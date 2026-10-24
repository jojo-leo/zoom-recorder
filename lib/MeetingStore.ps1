# Meetings.json persistence, input validation and overlap detection.

$script:TimeFormat = 'yyyy-MM-ddTHH:mm:ss'
$script:ActiveStatuses = @('pending', 'guarding', 'recording')

function Get-DefaultMeetingPath { Join-Path $script:Root 'Meetings.json' }

function New-MeetingObject {
    param(
        [string]$Name,
        [Parameter(Mandatory)][string]$MeetingID,
        [string]$Password,
        [Parameter(Mandatory)][datetime]$OriginalTime,
        [Parameter(Mandatory)][string]$TimeZone,
        [int]$MaxDuration = 120
    )
    $number = $MeetingID -replace '[\s-]', ''
    $perth = ConvertTo-PerthTime -OriginalTime $OriginalTime -TimeZone $TimeZone
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = "Meeting_$number" }
    [pscustomobject]@{
        id               = '{0}_{1}' -f $perth.ToString('yyyyMMddHHmmss'), $number
        name             = $Name.Trim()
        meetingID        = $number
        password         = [string]$Password
        originalTime     = $OriginalTime.ToString($script:TimeFormat)
        originalTimeZone = $TimeZone
        perthTime        = $perth.ToString($script:TimeFormat)
        maxDuration      = $MaxDuration
        status           = 'pending'
        createdAt        = (Get-Date).ToString($script:TimeFormat)
    }
}

function Get-MeetingPerthTime {
    param([Parameter(Mandatory)]$Meeting)
    [datetime]::ParseExact($Meeting.perthTime, $script:TimeFormat, [Globalization.CultureInfo]::InvariantCulture)
}

function Test-MeetingInput {
    param([Parameter(Mandatory)]$Meeting, [datetime]$Now = (Get-Date))
    $errors = @()
    if ($Meeting.meetingID -notmatch '^\d{9,11}$') { $errors += '会议号必须是 9-11 位数字' }
    if ((Get-MeetingPerthTime $Meeting) -le $Now) { $errors += '会议时间已过' }
    if ($Meeting.maxDuration -lt 1 -or $Meeting.maxDuration -gt 600) { $errors += '最长时长需在 1-600 分钟' }
    $errors
}

function Find-MeetingConflict {
    param([Parameter(Mandatory)]$Meeting, [object[]]$Existing = @())
    $start = Get-MeetingPerthTime $Meeting
    $end = $start.AddMinutes($Meeting.maxDuration)
    foreach ($other in $Existing) {
        if ($other.id -eq $Meeting.id -or $other.status -notin $script:ActiveStatuses) { continue }
        $oStart = Get-MeetingPerthTime $other
        $oEnd = $oStart.AddMinutes($other.maxDuration)
        if ($start -lt $oEnd -and $oStart -lt $end) { $other }
    }
}

function Get-Meetings {
    param([string]$Path = (Get-DefaultMeetingPath))
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $text = [IO.File]::ReadAllText($Path)
    try { $data = $text | ConvertFrom-Json }
    catch { throw "Meetings.json 已损坏，请检查或从备份恢复: $Path" }
    if ($null -eq $data -or $null -eq $data.meetings) { throw "Meetings.json 已损坏（缺少 meetings 字段）: $Path" }
    @($data.meetings)
}

function Get-Meeting {
    param([Parameter(Mandatory, Position = 0)][string]$Id, [string]$Path = (Get-DefaultMeetingPath))
    Get-Meetings -Path $Path | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Write-MeetingsFile {
    param([object[]]$Meetings, [string]$Path)
    $json = ConvertTo-Json -InputObject ([pscustomobject]@{ meetings = @($Meetings) }) -Depth 5
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
    Protect-UserOnlyFile $tmp
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# The file holds meeting passwords: current user + SYSTEM only, no inherited entries.
# Applied to the temp file on every write because the atomic move replaces the target's ACL.
function Protect-UserOnlyFile {
    param([Parameter(Mandatory, Position = 0)][string]$Path)
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in [Security.Principal.WindowsIdentity]::GetCurrent().User, (New-Object Security.Principal.SecurityIdentifier 'S-1-5-18')) {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'Allow')))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Save-Meeting {
    param([Parameter(Mandatory, Position = 0)]$Meeting, [string]$Path = (Get-DefaultMeetingPath))
    $others = @(Get-Meetings -Path $Path | Where-Object { $_.id -ne $Meeting.id })
    Write-MeetingsFile -Meetings ($others + $Meeting) -Path $Path
}

function Remove-Meeting {
    param([Parameter(Mandatory, Position = 0)][string]$Id, [string]$Path = (Get-DefaultMeetingPath))
    Write-MeetingsFile -Meetings @(Get-Meetings -Path $Path | Where-Object { $_.id -ne $Id }) -Path $Path
}

function Set-MeetingStatus {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Id,
        [Parameter(Mandatory, Position = 1)][ValidateSet('pending', 'guarding', 'recording', 'completed', 'failed', 'cancelled')][string]$Status,
        [string]$Path = (Get-DefaultMeetingPath)
    )
    $all = @(Get-Meetings -Path $Path)
    $target = $all | Where-Object { $_.id -eq $Id }
    if (-not $target) { return }
    $target.status = $Status
    Write-MeetingsFile -Meetings $all -Path $Path
}
