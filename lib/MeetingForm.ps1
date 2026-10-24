# Glue between the management UI form and the store/scheduler. Kept out of RecorderUI.ps1 so it is testable.

$script:StatusLabels = [ordered]@{
    pending = '待录制'; guarding = '值守中'; recording = '录制中'
    completed = '已完成'; failed = '失败'; cancelled = '已取消'
}

function Get-StatusLabel {
    param([Parameter(Position = 0)][string]$Status)
    if ($script:StatusLabels.Contains([string]$Status)) { $script:StatusLabels[$Status] } else { $Status }
}

function Save-MeetingFromForm {
    param(
        [Parameter(Mandatory, Position = 0)][hashtable]$Form,
        $Existing,
        [datetime]$Now = (Get-Date),
        [switch]$Force
    )
    $result = @{ Ok = $false; Errors = @(); Conflicts = @(); Meeting = $null }

    $time = [datetime]::MinValue
    if (-not $Form.Date) { $result.Errors += '请选择日期' }
    if (-not [datetime]::TryParseExact([string]$Form.Time, 'H:mm', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$time)) {
        $result.Errors += '时间格式应为 HH:mm（例如 15:00）'
    }
    $duration = 0
    if (-not [int]::TryParse([string]$Form.MaxDuration, [ref]$duration)) { $result.Errors += '最长时长需为整数分钟' }
    if ($result.Errors.Count) { return $result }

    $original = ([datetime]$Form.Date).Date.Add($time.TimeOfDay)
    try {
        $meeting = New-MeetingObject -Name $Form.Name -MeetingID ([string]$Form.MeetingID) -Password $Form.Password `
            -OriginalTime $original -TimeZone $Form.TimeZone -MaxDuration $duration
    } catch {
        $result.Errors += $_.Exception.Message
        return $result
    }
    $result.Meeting = $meeting
    $result.Errors = @(Test-MeetingInput $meeting -Now $Now)
    if ($result.Errors.Count) { return $result }

    $others = @(Get-Meetings | Where-Object { -not $Existing -or $_.id -ne $Existing.id })
    $result.Conflicts = @(Find-MeetingConflict $meeting -Existing $others)
    if ($result.Conflicts.Count -and -not $Force) { return $result }

    if ($Existing -and $Existing.id -ne $meeting.id) {
        Unregister-MeetingTasks $Existing.id
        Remove-Meeting $Existing.id
    }
    Save-Meeting $meeting
    Register-MeetingTasks $meeting
    $result.Ok = $true
    $result
}

function Remove-MeetingWithTasks {
    param([Parameter(Mandatory, Position = 0)][string]$Id)
    Unregister-MeetingTasks $Id
    Remove-Meeting $Id
}
