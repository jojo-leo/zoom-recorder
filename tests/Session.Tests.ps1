Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

# Mock bodies run in module scope, so shared test state lives in $global:Zr.
function Reset-Zr([hashtable]$Overrides = @{}) {
    $m = New-MeetingObject -Name 'S' -MeetingID '123456789' -Password 'p' -OriginalTime ([datetime]'2026-10-29 03:15') -TimeZone 'Asia/Shanghai' -MaxDuration 60
    $global:Zr = @{
        Meeting = $m; Clock = [datetime]'2026-10-29 03:00'; Calls = New-Object System.Collections.ArrayList
        Logs = New-Object System.Collections.ArrayList; Notices = New-Object System.Collections.ArrayList
        Dialog = 'Confirm'; Locked = $false; EvStarts = $true; Join = 'Meeting'; FullScreen = $true; Watch = 'MeetingEnded'
        Statuses = New-Object System.Collections.ArrayList
    }
    foreach ($k in $Overrides.Keys) { $global:Zr[$k] = $Overrides[$k] }
}
function Get-ZrCalls([string[]]$Names) { ($global:Zr.Calls | Where-Object { $Names -contains $_ }) -join ',' }

$track = 'Start-EV', 'Start-ZoomJoin', 'Set-ZoomFullScreen', 'Start-EVRecording', 'Stop-EVRecording'

Describe 'Invoke-RecordingSession' {
    Mock Get-Now { $global:Zr.Clock } -ModuleName RecorderCore
    Mock Wait-Seconds { $global:Zr.Clock = $global:Zr.Clock.AddSeconds($Seconds) } -ModuleName RecorderCore
    Mock Get-Meeting { $global:Zr.Meeting } -ModuleName RecorderCore
    Mock Set-MeetingStatus { [void]$global:Zr.Statuses.Add($Status); $global:Zr.Meeting.status = $Status } -ModuleName RecorderCore
    Mock New-SessionLog { 'TestDrive:\s.log' } -ModuleName RecorderCore
    Mock Write-SessionLog { [void]$global:Zr.Logs.Add($Message) } -ModuleName RecorderCore
    Mock Complete-SessionLog { [void]$global:Zr.Logs.Add("STATUS:$Status") } -ModuleName RecorderCore
    Mock Enable-KeepAwake { [void]$global:Zr.Calls.Add('Enable-KeepAwake') } -ModuleName RecorderCore
    Mock Disable-KeepAwake { [void]$global:Zr.Calls.Add('Disable-KeepAwake') } -ModuleName RecorderCore
    Mock Show-SessionConfirmDialog { [void]$global:Zr.Calls.Add('Dialog'); $global:Zr.Dialog } -ModuleName RecorderCore
    Mock Unregister-MeetingTasks { [void]$global:Zr.Calls.Add('Unregister-MeetingTasks') } -ModuleName RecorderCore
    Mock Test-SessionLocked { $global:Zr.Locked } -ModuleName RecorderCore
    Mock Start-EV { [void]$global:Zr.Calls.Add('Start-EV'); $global:Zr.EvStarts } -ModuleName RecorderCore
    Mock Start-ZoomJoin { [void]$global:Zr.Calls.Add('Start-ZoomJoin'); $global:Zr.JoinedAt = $global:Zr.Clock } -ModuleName RecorderCore
    Mock Wait-ForZoomMeeting { $global:Zr.Join } -ModuleName RecorderCore
    Mock Set-ZoomFullScreen { [void]$global:Zr.Calls.Add('Set-ZoomFullScreen'); $global:Zr.FullScreen } -ModuleName RecorderCore
    Mock Start-EVRecording { [void]$global:Zr.Calls.Add('Start-EVRecording') } -ModuleName RecorderCore
    Mock Stop-EVRecording { [void]$global:Zr.Calls.Add('Stop-EVRecording') } -ModuleName RecorderCore
    Mock Watch-Recording { $global:Zr.Watch } -ModuleName RecorderCore
    Mock Close-Zoom {} -ModuleName RecorderCore
    Mock Close-EV {} -ModuleName RecorderCore
    Mock Find-EVRecording { 'D:\v.mp4' } -ModuleName RecorderCore
    Mock Wait-EVFileSettled {} -ModuleName RecorderCore
    Mock Save-Screenshot { [void]$global:Zr.Calls.Add('Save-Screenshot') } -ModuleName RecorderCore
    Mock Add-PendingNotice { [void]$global:Zr.Notices.Add($Message) } -ModuleName RecorderCore
    Mock Get-StateDir { 'TestDrive:\state' } -ModuleName RecorderCore

    It '正常流程 → completed，顺序为 EV 启动→入会→全屏→字幕→开始录制' {
        Reset-Zr
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Should Be 'completed'
        Get-ZrCalls $track | Should Be 'Start-EV,Start-ZoomJoin,Set-ZoomFullScreen,Start-EVRecording,Stop-EVRecording'
        ($global:Zr.Statuses -join ',') | Should Be 'guarding,recording,completed'
    }
    It '等到会议开始才入会' {
        Reset-Zr
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Out-Null
        $global:Zr.JoinedAt | Should Be ([datetime]'2026-10-29 03:15')
    }
    It '用户取消 → cancelled，删除任务，不启动 EV' {
        Reset-Zr @{ Dialog = 'Cancel' }
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Should Be 'cancelled'
        Get-ZrCalls 'Unregister-MeetingTasks', 'Start-EV' | Should Be 'Unregister-MeetingTasks'
    }
    It '锁屏 → failed "系统已锁屏"，不启动 EV，写 pending notice' {
        Reset-Zr @{ Locked = $true }
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Should Be 'failed'
        Get-ZrCalls $track | Should Be ''
        ($global:Zr.Logs -join '|') | Should Match '系统已锁屏'
        ($global:Zr.Notices -join '|') | Should Match '系统已锁屏'
    }
    It 'EV 启动失败 → failed，不入会' {
        Reset-Zr @{ EvStarts = $false }
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Should Be 'failed'
        Get-ZrCalls 'Start-ZoomJoin' | Should Be ''
    }
    It '密码错误 → failed，截图，不调用 Start-EVRecording' {
        Reset-Zr @{ Join = 'PasswordError' }
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Should Be 'failed'
        Get-ZrCalls 'Save-Screenshot', 'Start-EVRecording' | Should Be 'Save-Screenshot'
        ($global:Zr.Logs -join '|') | Should Match '入会失败：密码错误'
    }
    It 'Zoom 未响应 → failed "Zoom 未响应"' {
        Reset-Zr @{ Join = 'NoResponse' }
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Should Be 'failed'
        ($global:Zr.Logs -join '|') | Should Match 'Zoom 未响应'
    }
    It '全屏失败仍然录制 → completed，日志含警告' {
        Reset-Zr @{ FullScreen = $false }
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Should Be 'completed'
        ($global:Zr.Logs -join '|') | Should Match '未能确认全屏'
        Get-ZrCalls 'Start-EVRecording' | Should Be 'Start-EVRecording'
    }
    It '不再尝试点击字幕/音频按钮（Zoom 不暴露按钮，改由 Zoom 设置控制）' {
        (Get-Command Enable-ZoomCaptions, Confirm-ZoomComputerAudio -ErrorAction SilentlyContinue).Count | Should Be 0
    }
    It '录制中锁屏 → failed + notice "录制中断"' {
        Reset-Zr @{ Watch = 'Locked' }
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Should Be 'failed'
        ($global:Zr.Notices -join '|') | Should Match '录制中断'
    }
    It 'EV 崩溃 → failed，不再发 Ctrl+F2' {
        Reset-Zr @{ Watch = 'EVCrashed' }
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Should Be 'failed'
        Get-ZrCalls 'Stop-EVRecording' | Should Be ''
    }
    It 'status 非 pending → Skipped，不弹窗' {
        Reset-Zr
        $global:Zr.Meeting.status = 'completed'
        Invoke-RecordingSession -Id $global:Zr.Meeting.id | Should Be 'Skipped'
        Get-ZrCalls 'Dialog', 'Enable-KeepAwake' | Should Be ''
    }
    It '会议不存在 → Skipped' {
        Reset-Zr @{ Meeting = $null }
        Invoke-RecordingSession -Id 'nope' | Should Be 'Skipped'
    }
    It '-Unattended 不弹确认窗' {
        Reset-Zr
        Invoke-RecordingSession -Id $global:Zr.Meeting.id -Unattended | Should Be 'completed'
        Get-ZrCalls 'Dialog' | Should Be ''
    }
    It '错过整场会议（唤醒太晚）→ failed，不入会' {
        Reset-Zr @{ Clock = [datetime]'2026-10-29 04:20' }
        Invoke-RecordingSession -Id $global:Zr.Meeting.id -Unattended | Should Be 'failed'
        Get-ZrCalls 'Start-EV' | Should Be ''
    }
    It '任何路径都会调用 Disable-KeepAwake' {
        foreach ($o in @(@{}, @{ Dialog = 'Cancel' }, @{ Locked = $true }, @{ Join = 'PasswordError' })) {
            Reset-Zr $o
            Invoke-RecordingSession -Id $global:Zr.Meeting.id | Out-Null
            Get-ZrCalls 'Disable-KeepAwake' | Should Be 'Disable-KeepAwake'
        }
    }
}

Describe 'Watch-Recording' {
    Mock Get-Now { $global:Zr.Clock } -ModuleName RecorderCore
    Mock Wait-Seconds { $global:Zr.Clock = $global:Zr.Clock.AddSeconds($Seconds) } -ModuleName RecorderCore
    Mock Test-StopRequested { $global:Zr.Stop } -ModuleName RecorderCore
    Mock Test-SessionLocked { $global:Zr.Locked } -ModuleName RecorderCore
    Mock Test-EVRunning { $global:Zr.Ev } -ModuleName RecorderCore
    # Zoom state script: function of elapsed seconds since start
    Mock Get-ZoomState { & $global:Zr.ZoomAt ($global:Zr.Clock - $global:Zr.Start).TotalSeconds } -ModuleName RecorderCore

    function Start-Watch([hashtable]$o) {
        $global:Zr = @{ Clock = [datetime]'2026-10-29 03:15'; Start = [datetime]'2026-10-29 03:15'; Stop = $false; Locked = $false; Ev = $true; ZoomAt = { 'Meeting' } }
        foreach ($k in $o.Keys) { $global:Zr[$k] = $o[$k] }
        Watch-Recording -StartedAt $global:Zr.Start -MaxMinutes 60
    }

    It 'Zoom 窗口短暂消失后恢复 → 不结束' {
        Start-Watch @{ ZoomAt = { param($s) if ($s -ge 600 -and $s -lt 605) { 'Other' } else { 'Meeting' } } } | Should Be 'MaxDuration'
    }
    It 'Zoom 窗口消失 10 秒后仍不在 → MeetingEnded（约在消失后 15 秒内）' {
        Start-Watch @{ ZoomAt = { param($s) if ($s -ge 600) { 'None' } else { 'Meeting' } } } | Should Be 'MeetingEnded'
        ($global:Zr.Clock - $global:Zr.Start).TotalSeconds | Should BeLessThan 620
    }
    It '达到最长时长 → MaxDuration' {
        Start-Watch @{} | Should Be 'MaxDuration'
        ($global:Zr.Clock - $global:Zr.Start).TotalMinutes | Should Be 60
    }
    It 'stop.request → UserStop' { Start-Watch @{ Stop = $true } | Should Be 'UserStop' }
    It '锁屏 → Locked' { Start-Watch @{ Locked = $true } | Should Be 'Locked' }
    It 'EV 退出 → EVCrashed' { Start-Watch @{ Ev = $false } | Should Be 'EVCrashed' }
}

Describe 'Wait-ForZoomMeeting' {
    Mock Get-Now { $global:Zr.Clock } -ModuleName RecorderCore
    Mock Wait-Seconds { $global:Zr.Clock = $global:Zr.Clock.AddSeconds($Seconds) } -ModuleName RecorderCore
    Mock Test-StopRequested { $false } -ModuleName RecorderCore
    Mock Get-ZoomState { & $global:Zr.ZoomAt ($global:Zr.Clock - $global:Zr.Start).TotalSeconds } -ModuleName RecorderCore

    function Start-Wait($zoomAt) {
        $global:Zr = @{ Clock = [datetime]'2026-10-29 03:15'; Start = [datetime]'2026-10-29 03:15'; ZoomAt = $zoomAt }
        Wait-ForZoomMeeting -TimeoutMinutes 30
    }

    It '会议窗口出现 → Meeting' { Start-Wait { param($s) if ($s -ge 8) { 'Meeting' } else { 'None' } } | Should Be 'Meeting' }
    It '30 秒内无任何 Zoom 窗口 → NoResponse' { Start-Wait { 'None' } | Should Be 'NoResponse'; ($global:Zr.Clock - $global:Zr.Start).TotalSeconds | Should BeLessThan 35 }
    It '等候室持续 → 30 分钟后 Timeout' { Start-Wait { 'Waiting' } | Should Be 'Timeout'; ($global:Zr.Clock - $global:Zr.Start).TotalMinutes | Should Not BeLessThan 30 }
    It '主持人 20 分钟后开会 → Meeting' { Start-Wait { param($s) if ($s -ge 1200) { 'Meeting' } else { 'Waiting' } } | Should Be 'Meeting' }
    It '密码错误 → PasswordError' { Start-Wait { param($s) if ($s -ge 4) { 'PasswordError' } else { 'Other' } } | Should Be 'PasswordError' }
}

Describe 'Session 状态文件' {
    Mock Get-StateDir { Join-Path $TestDrive 'state' } -ModuleName RecorderCore
    It '默认 Idle' { (Get-SessionState).Phase | Should Be 'Idle' }
    It '写入并读回' { Set-SessionState -Id 'x' -Name 'S' -Phase Recording -StartedAt ([datetime]'2026-10-29 03:15'); (Get-SessionState).Phase | Should Be 'Recording'; (Get-SessionState).Name | Should Be 'S' }
    It '停止请求' { Test-StopRequested | Should Be $false; Request-SessionStop; Test-StopRequested | Should Be $true; Clear-StopRequest; Test-StopRequested | Should Be $false }
    It '待显示通知' { Add-PendingNotice 'a'; Add-PendingNotice 'b'; (Get-PendingNotices -Clear) -join ',' | Should Be 'a,b'; @(Get-PendingNotices).Count | Should Be 0 }
}
