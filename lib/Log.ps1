# Per-session log files under Logs\. One file per recording attempt.

$script:LogEncoding = New-Object System.Text.UTF8Encoding $true
$script:LogRule = '=' * 40
$script:LogSubRule = '-' * 40

function Get-DefaultLogDir { Join-Path $script:Root 'Logs' }

function Format-OriginalTime {
    param([Parameter(Mandatory)]$Meeting)
    $t = [datetime]::ParseExact($Meeting.originalTime, $script:TimeFormat, [Globalization.CultureInfo]::InvariantCulture)
    '{0} {1}' -f $t.ToString('yyyy-MM-dd HH:mm'), $Meeting.originalTimeZone
}

function Add-LogText {
    param([string]$Path, [string]$Text)
    [IO.File]::AppendAllText($Path, $Text + "`r`n", $script:LogEncoding)
}

function New-SessionLog {
    param([Parameter(Mandatory, Position = 0)]$Meeting, [string]$LogDir = (Get-DefaultLogDir))
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $perth = Get-MeetingPerthTime $Meeting
    $safeName = $Meeting.name -replace '[^\p{L}\p{Nd}]', ''
    $path = Join-Path $LogDir ('{0}_{1}.log' -f $perth.ToString('yyyyMMdd_HHmmss'), $safeName)
    Add-LogText $path (@(
            $script:LogRule
            'Zoom 会议自动录制日志'
            $script:LogRule
            "会议名称: $($Meeting.name)"
            "会议号: $($Meeting.meetingID)"
            "原定时间: $(Format-OriginalTime $Meeting)"
            "珀斯时间: $($perth.ToString('yyyy-MM-dd HH:mm')) AWST"
            "最长时长: $($Meeting.maxDuration) 分钟"
            ''
            $script:LogSubRule
        ) -join "`r`n")
    $path
}

function Write-SessionLog {
    param([Parameter(Mandatory, Position = 0)][string]$Path, [Parameter(Mandatory, Position = 1)][string]$Message)
    $masked = $Message -replace 'pwd=[^&\s]*', 'pwd=***'
    Add-LogText $Path ('[{0}] {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $masked)
}

function Complete-SessionLog {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Path,
        [Parameter(Mandatory)][string]$Status,
        [timespan]$Duration = [timespan]::Zero,
        [string]$VideoPath
    )
    if (-not $VideoPath) { $VideoPath = '（无）' }
    Add-LogText $Path (@(
            ''
            $script:LogSubRule
            "录制时长: $([int][math]::Round($Duration.TotalMinutes)) 分钟"
            "EV 文件路径: $VideoPath"
            "状态: $Status"
            $script:LogRule
        ) -join "`r`n")
}
