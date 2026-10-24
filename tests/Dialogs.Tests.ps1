Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

Describe 'Dialog 文本' {
    $m = New-MeetingObject -Name 'Weekly Seminar' -MeetingID '123456789' -Password '' -OriginalTime ([datetime]'2026-10-28 15:15') -TimeZone 'America/New_York' -MaxDuration 120

    It '两种时间' {
        $t = Format-MeetingTimes $m
        $t.Original | Should Be '2026-10-28 15:15 America/New_York'
        $t.Perth | Should Be '2026-10-29 03:15 (AWST)'
    }
    It '提醒文本：明天' {
        $s = Get-ReminderText $m -Now ([datetime]'2026-10-28 15:15')
        $s | Should Match '明天 03:15 有会议需要录制'
        $s | Should Match 'Weekly Seminar \(123456789\)'
        $s | Should Match '原定时间：2026-10-28 15:15 America/New_York'
    }
    It '提醒文本：今天' { Get-ReminderText $m -Now ([datetime]'2026-10-29 01:00') | Should Match '今天 03:15' }
    It '提醒文本：更远日期' { Get-ReminderText $m -Now ([datetime]'2026-10-26 10:00') | Should Match '10-29 03:15' }
    It '会议号分组' { Format-MeetingNumber '123456789' | Should Be '123 456 789'; Format-MeetingNumber '12345678901' | Should Be '123 4567 8901' }
    It '倒计时格式' { Format-Countdown 905 | Should Be '15:05'; Format-Countdown 0 | Should Be '00:00' }
    It '确认窗正文' {
        $b = Get-ConfirmBodyText $m
        $b | Should Match '会议原定时间: 2026-10-28 15:15 America/New_York'
        $b | Should Match '珀斯时间: 2026-10-29 03:15 \(AWST\)'
        $b | Should Match '会议号: 123 456 789'
        $b | Should Match '不要合上笔记本盖'
    }
}
