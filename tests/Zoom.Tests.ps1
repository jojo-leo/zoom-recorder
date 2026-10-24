Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

function W($t, $c, $v = $true) { [pscustomobject]@{ Title = $t; ClassName = $c; Visible = $v; Handle = [IntPtr]1; ProcessId = 1; Width = 800; Height = 600 } }

Describe 'Get-ZoomJoinUrl' {
    It '无密码' { Get-ZoomJoinUrl '123456789' '' | Should Be 'zoommtg://zoom.us/join?confno=123456789' }
    It '密码转义' { Get-ZoomJoinUrl '123456789' 'a b&c' | Should Be 'zoommtg://zoom.us/join?confno=123456789&pwd=a%20b%26c' }
}

Describe 'Get-ZoomWindowState' {
    It '会议窗口（类名）' { Get-ZoomWindowState @((W 'Zoom' 'ZPPTMainFrmWndClassEx'), (W 'Zoom' 'ConfMultiTabContentWndClass')) | Should Be 'Meeting' }
    It '会议窗口（中文标题）' { Get-ZoomWindowState @((W 'Zoom 会议' 'x')) | Should Be 'Meeting' }
    It '会议窗口（英文标题）' { Get-ZoomWindowState @((W 'Zoom Meeting' 'x')) | Should Be 'Meeting' }
    It '网络研讨会' { Get-ZoomWindowState @((W 'Zoom Webinar' 'x')) | Should Be 'Meeting' }
    It '密码错误' { Get-ZoomWindowState @((W 'Incorrect meeting passcode' 'x')) | Should Be 'PasswordError' }
    It '密码错误（中文）' { Get-ZoomWindowState @((W '会议密码错误' 'x')) | Should Be 'PasswordError' }
    It '等候室' { Get-ZoomWindowState @((W 'Waiting for Host' 'x')) | Should Be 'Waiting' }
    It '等候室（中文）' { Get-ZoomWindowState @((W '请等待主持人开始会议' 'x')) | Should Be 'Waiting' }
    It '只有主界面' { Get-ZoomWindowState @((W 'Zoom Workplace' 'ZPPTMainFrmWndClassEx')) | Should Be 'Other' }
    It '不可见窗口忽略' { Get-ZoomWindowState @((W 'Zoom Meeting' 'ConfMultiTabContentWndClass' $false)) | Should Be 'None' }
    It '无窗口' { Get-ZoomWindowState @() | Should Be 'None' }
    It '会议窗口优先于密码提示' { Get-ZoomWindowState @((W '密码' 'x'), (W 'Zoom Meeting' 'ConfMultiTabContentWndClass')) | Should Be 'Meeting' }
}

Describe 'Start-ZoomJoin' {
    It '以 zoommtg URL 启动' {
        Mock Start-Process {} -ModuleName RecorderCore
        Start-ZoomJoin -MeetingID '123456789' -Password 'p'
        Assert-MockCalled Start-Process -ModuleName RecorderCore -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'zoommtg://zoom.us/join?confno=123456789&pwd=p' }
    }
}
