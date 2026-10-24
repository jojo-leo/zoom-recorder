Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

Describe 'SessionLog' {
    $m = New-MeetingObject -Name 'Weekly Seminar!' -MeetingID '123456789' -Password 'abc' -OriginalTime ([datetime]'2026-10-28 15:15') -TimeZone 'America/New_York' -MaxDuration 120
    $log = New-SessionLog $m -LogDir (Join-Path $TestDrive 'Logs')

    It '文件名去掉符号' { Split-Path $log -Leaf | Should Be '20261029_031500_WeeklySeminar.log' }
    It '中文会议名保留' {
        $c = New-MeetingObject -Name '组会 #3' -MeetingID '123456789' -Password '' -OriginalTime ([datetime]'2026-10-28 15:15') -TimeZone 'America/New_York' -MaxDuration 60
        Split-Path (New-SessionLog $c -LogDir (Join-Path $TestDrive 'Logs2')) -Leaf | Should Be '20261029_031500_组会3.log'
    }
    It '头部含两种时间' {
        $t = [IO.File]::ReadAllText($log)
        $t | Should Match '2026-10-28 15:15 America/New_York'
        $t | Should Match '2026-10-29 03:15 AWST'
        $t | Should Match '最长时长: 120 分钟'
    }
    It '带时间戳追加' { Write-SessionLog $log '进入值守模式'; [IO.File]::ReadAllText($log) | Should Match '\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] 进入值守模式' }
    It '密码脱敏' {
        Write-SessionLog $log '入会: zoommtg://zoom.us/join?confno=1&pwd=abc'
        $t = [IO.File]::ReadAllText($log)
        $t | Should Not Match 'pwd=abc'
        $t | Should Match 'pwd=\*\*\*'
    }
    It '尾部' {
        Complete-SessionLog $log -Status '成功' -Duration ([timespan]::FromMinutes(97)) -VideoPath 'D:\x.mp4'
        $t = [IO.File]::ReadAllText($log)
        $t | Should Match '录制时长: 97 分钟'
        $t | Should Match 'EV 文件路径: D:\\x.mp4'
        $t | Should Match '状态: 成功'
    }
}
