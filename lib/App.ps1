# Entry-point helpers: autostart, install/uninstall, 12h reminder, tray text.

$script:RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:RunValueName = 'ZoomRecorder'

function Get-RunCommand {
    param([Parameter(Mandatory, Position = 0)][ValidateSet('Tray', 'UI')][string]$Action)
    'powershell.exe -NoProfile -WindowStyle Hidden -STA -File "{0}" -Action {1}' -f (Get-EntryScriptPath), $Action
}

function Invoke-Notify12h {
    param([Parameter(Mandatory, Position = 0)][string]$Id)
    $meeting = Get-Meeting $Id
    if ($meeting -and $meeting.status -eq 'pending') { Show-ReminderBalloon $meeting }
}

function Get-MeetingsToReschedule {
    param([object[]]$Meetings = @(Get-Meetings), [datetime]$Now = (Get-Date))
    $Meetings | Where-Object { $_.status -eq 'pending' -and (Get-MeetingPerthTime $_).AddMinutes($_.maxDuration) -gt $Now }
}

function Install-ZoomRecorder {
    foreach ($dir in 'Logs', 'state') { New-Item -ItemType Directory -Path (Join-Path $script:Root $dir) -Force | Out-Null }
    Set-ItemProperty -Path $script:RunKey -Name $script:RunValueName -Value (Get-RunCommand Tray)
    $count = 0
    foreach ($m in @(Get-MeetingsToReschedule)) { Register-MeetingTasks $m; $count++ }
    $count
}

function Uninstall-ZoomRecorder {
    Remove-ItemProperty -Path $script:RunKey -Name $script:RunValueName -ErrorAction SilentlyContinue
    Unregister-AllRecorderTasks
}

# --- tray started on demand by a recording session (no autostart needed) ---
$script:TrayMutexName = 'Global\ZoomRecorder_Tray'
$script:TrayIdleGraceSeconds = 15

function Get-TrayLaunchArguments {
    '-NoProfile -WindowStyle Hidden -STA -File "{0}" -Action Tray -AutoExit' -f (Get-EntryScriptPath)
}

function Start-TrayIfNeeded {
    $existing = $null
    if ([System.Threading.Mutex]::TryOpenExisting($script:TrayMutexName, [ref]$existing)) { $existing.Dispose(); return }
    Start-Process powershell.exe -ArgumentList (Get-TrayLaunchArguments) | Out-Null
}

function Test-TrayShouldExit {
    # An on-demand tray stays while a session runs or a failure notice is unread, then leaves.
    param([string]$Phase, [int]$NoticeCount, $IdleSince, [datetime]$Now = (Get-Date))
    if ($Phase -ne 'Idle' -or $NoticeCount -gt 0 -or -not $IdleSince) { return $false }
    ($Now - [datetime]$IdleSince).TotalSeconds -ge $script:TrayIdleGraceSeconds
}

function Format-TrayTooltip {
    param([Parameter(Mandatory, Position = 0)]$State, [datetime]$Now = (Get-Date))
    $text = switch ($State.Phase) {
        'Guarding' { "ZoomRecorder · 值守中 · $($State.Name)" }
        'Recording' {
            $minutes = 0
            if ($State.StartedAt) { $minutes = [int][math]::Floor(($Now - [datetime]$State.StartedAt).TotalMinutes) }
            "ZoomRecorder · 录制中 · $($State.Name) · $minutes 分钟"
        }
        default { 'ZoomRecorder · 空闲' }
    }
    if ($text.Length -gt 63) { $text = $text.Substring(0, 62) + '…' }
    $text
}
