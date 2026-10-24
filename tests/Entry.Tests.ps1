Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

Describe 'Get-RunCommand' {
    It '托盘开机命令' { Get-RunCommand Tray | Should Match '^powershell\.exe -NoProfile -WindowStyle Hidden -STA -File ".+\\ZoomRecorder\.ps1" -Action Tray$' }
    It '不使用 Bypass' { Get-RunCommand Tray | Should Not Match 'Bypass' }
}

Describe 'Invoke-Notify12h' {
    Mock Show-ReminderBalloon { $global:ZrBalloon++ } -ModuleName RecorderCore
    It 'pending 会议显示提醒' {
        $global:ZrBalloon = 0
        Mock Get-Meeting { [pscustomobject]@{ id = 'x'; status = 'pending' } } -ModuleName RecorderCore
        Invoke-Notify12h 'x'
        $global:ZrBalloon | Should Be 1
    }
}

Describe 'Invoke-Notify12h 跳过' {
    Mock Show-ReminderBalloon { $global:ZrBalloon++ } -ModuleName RecorderCore
    It '已完成/已取消/不存在的会议不提醒' {
        $global:ZrBalloon = 0
        $global:ZrMeeting = [pscustomobject]@{ id = 'x'; status = 'cancelled' }
        Mock Get-Meeting { $global:ZrMeeting } -ModuleName RecorderCore
        Invoke-Notify12h 'x'
        $global:ZrMeeting = $null
        Invoke-Notify12h 'x'
        $global:ZrBalloon | Should Be 0
    }
}

Describe 'Get-MeetingsToReschedule' {
    It '只重新注册未过期的 pending 会议' {
        $now = [datetime]'2026-10-24 12:00'
        $mk = { param($t, $s) $m = New-MeetingObject -Name n -MeetingID '123456789' -Password '' -OriginalTime $t -TimeZone 'UTC' -MaxDuration 60; $m.status = $s; $m }
        $list = @((& $mk ([datetime]'2026-10-25 00:00') 'pending'), (& $mk ([datetime]'2026-10-20 00:00') 'pending'), (& $mk ([datetime]'2026-10-26 00:00') 'completed'))
        $r = @(Get-MeetingsToReschedule -Meetings $list -Now $now)
        $r.Count | Should Be 1
        $r[0].perthTime | Should Be '2026-10-25T08:00:00'
    }
}

Describe 'Install-ZoomRecorder' {
    Mock New-Item {} -ModuleName RecorderCore
    Mock Set-ItemProperty { $global:ZrRunValue = $Value } -ModuleName RecorderCore
    Mock Register-MeetingTasks { $global:ZrRegistered++ } -ModuleName RecorderCore
    Mock Get-Meetings {
        $a = New-MeetingObject -Name a -MeetingID '123456789' -Password '' -OriginalTime ((Get-Date).AddDays(2)) -TimeZone 'UTC' -MaxDuration 60
        $b = New-MeetingObject -Name b -MeetingID '123456789' -Password '' -OriginalTime ((Get-Date).AddDays(-2)) -TimeZone 'UTC' -MaxDuration 60
        $a, $b
    } -ModuleName RecorderCore
    It '写开机启动项并重新注册未来的会议' {
        $global:ZrRegistered = 0
        Install-ZoomRecorder | Should Be 1
        $global:ZrRunValue | Should Be (Get-RunCommand Tray)
        $global:ZrRegistered | Should Be 1
    }
}

Describe 'Test-TrayShouldExit（随录制启动的托盘）' {
    $now = [datetime]'2026-10-29 05:00:00'
    It '录制中不退出' { Test-TrayShouldExit -Phase Recording -NoticeCount 0 -IdleSince $null -Now $now | Should Be $false }
    It '有未显示的失败提醒不退出' { Test-TrayShouldExit -Phase Idle -NoticeCount 1 -IdleSince $now.AddMinutes(-5) -Now $now | Should Be $false }
    It '刚变空闲不退出（给会话写状态留时间）' { Test-TrayShouldExit -Phase Idle -NoticeCount 0 -IdleSince $now.AddSeconds(-5) -Now $now | Should Be $false }
    It '空闲超过 15 秒且无提醒 → 退出' { Test-TrayShouldExit -Phase Idle -NoticeCount 0 -IdleSince $now.AddSeconds(-16) -Now $now | Should Be $true }
}

Describe 'Get-TrayLaunchArguments' {
    It '自动退出模式' { Get-TrayLaunchArguments | Should Match '-Action Tray -AutoExit$' }
}

Describe 'Format-TrayTooltip' {
    It '空闲' { Format-TrayTooltip ([pscustomobject]@{ Phase = 'Idle' }) | Should Be 'ZoomRecorder · 空闲' }
    It '值守' { Format-TrayTooltip ([pscustomobject]@{ Phase = 'Guarding'; Name = 'S' }) | Should Be 'ZoomRecorder · 值守中 · S' }
    It '录制中带分钟数' {
        Format-TrayTooltip ([pscustomobject]@{ Phase = 'Recording'; Name = 'S'; StartedAt = '2026-10-29T03:15:00' }) -Now ([datetime]'2026-10-29 03:52') | Should Be 'ZoomRecorder · 录制中 · S · 37 分钟'
    }
    It '不超过 63 字符（NotifyIcon 限制）' {
        (Format-TrayTooltip ([pscustomobject]@{ Phase = 'Guarding'; Name = ('x' * 100) })).Length | Should Not BeGreaterThan 63
    }
}
