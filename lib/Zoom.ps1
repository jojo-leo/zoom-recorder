# Zoom desktop client control: join via zoommtg://, classify windows, full screen, computer audio, captions.
# Window classes / titles below were chosen from known Zoom builds; calibrate against the real client
# (Get-TopWindows -ProcessName Zoom) if detection misbehaves after a Zoom update.

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$script:ZoomProcessName = 'Zoom'
$script:ZoomClasses = @{ Meeting = @('ConfMultiTabContentWndClass') }
$script:ZoomTitles = @{
    Meeting       = '^Zoom (Meeting|Webinar|会议|网络研讨会)'
    PasswordError = 'incorrect|wrong|invalid|错误|密码'
    Waiting       = 'waiting|等候|等待主持人'
}
$script:ZoomButtons = @{
    ComputerAudio = '^(Join with Computer Audio|Join Audio by Computer|使用电脑音频加入|使用电脑语音设备)'
    Captions      = '^(Show Captions|Captions|CC|Closed Caption|显示字幕|字幕)'
    CaptionsMenu  = '^(Show Captions|Show Subtitle|显示字幕)'
    CaptionsOn    = '^(Hide Captions|Hide Subtitle|隐藏字幕)'
}

function Get-ZoomJoinUrl {
    param([Parameter(Mandatory, Position = 0)][string]$MeetingID, [Parameter(Position = 1)][string]$Password)
    $url = "zoommtg://zoom.us/join?confno=$MeetingID"
    if ($Password) { $url += '&pwd=' + [uri]::EscapeDataString($Password) }
    $url
}

function Get-ZoomWindowState {
    param([Parameter(Position = 0)][object[]]$Windows = @())
    $visible = @($Windows | Where-Object { $_.Visible })
    if ($visible.Count -eq 0) { return 'None' }
    if ($visible | Where-Object { $script:ZoomClasses.Meeting -contains $_.ClassName -or $_.Title -match $script:ZoomTitles.Meeting }) { return 'Meeting' }
    if ($visible | Where-Object { $_.Title -match $script:ZoomTitles.PasswordError }) { return 'PasswordError' }
    if ($visible | Where-Object { $_.Title -match $script:ZoomTitles.Waiting }) { return 'Waiting' }
    'Other'
}

function Get-ZoomWindows { @(Get-TopWindows -ProcessName $script:ZoomProcessName) }

function Get-ZoomState { Get-ZoomWindowState (Get-ZoomWindows) }

function Get-ZoomMeetingWindow {
    Get-ZoomWindows | Where-Object { $_.Visible -and ($script:ZoomClasses.Meeting -contains $_.ClassName -or $_.Title -match $script:ZoomTitles.Meeting) } |
        Sort-Object { $_.Width * $_.Height } -Descending | Select-Object -First 1
}

function Start-ZoomJoin {
    param([Parameter(Mandatory)][string]$MeetingID, [string]$Password)
    Start-Process -FilePath (Get-ZoomJoinUrl $MeetingID $Password) | Out-Null
}

function Close-Zoom { Stop-Process -Name $script:ZoomProcessName -Force -ErrorAction SilentlyContinue }

function Test-ZoomFullScreen {
    $w = Get-ZoomMeetingWindow
    if (-not $w) { return $false }
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $w.Width -ge $screen.Width -and $w.Height -ge $screen.Height
}

function Set-ZoomFullScreen {
    $w = Get-ZoomMeetingWindow
    if (-not $w) { return $false }
    if (Test-ZoomFullScreen) { return $true }   # Alt+F toggles, so never press it when already full screen
    Set-ForegroundWindowSafe $w.Handle
    Start-Sleep -Milliseconds 500
    Send-KeyChord @('Menu', 'F')
    Start-Sleep -Seconds 2
    Test-ZoomFullScreen
}

# --- UI Automation helpers -------------------------------------------------

function Find-ZoomUiElement {
    param([Parameter(Mandatory)][string]$NamePattern, [IntPtr[]]$Handles = @(Get-ZoomWindows | Where-Object Visible | ForEach-Object Handle))
    $ae = [System.Windows.Automation.AutomationElement]
    foreach ($h in $Handles) {
        try { $root = $ae::FromHandle($h) } catch { continue }
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            $name = $el.Current.Name
            if ($name -and $name -match $NamePattern) { return $el }
        }
    }
    $null
}

function Invoke-UiElement {
    param([Parameter(Mandatory)]$Element)
    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) { $pattern.Invoke(); return $true }
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) { $pattern.Toggle(); return $true }
    $false
}

function Confirm-ZoomComputerAudio {
    $button = Find-ZoomUiElement -NamePattern $script:ZoomButtons.ComputerAudio
    if ($button) { [void](Invoke-UiElement $button); return $true }
    $false
}

function Test-ZoomCaptionsOn { [bool](Find-ZoomUiElement -NamePattern $script:ZoomButtons.CaptionsOn) }

function Enable-ZoomCaptions {
    if (Test-ZoomCaptionsOn) { return $true }
    $w = Get-ZoomMeetingWindow
    if (-not $w) { return $false }

    # 1. keyboard shortcut
    Set-ForegroundWindowSafe $w.Handle
    Send-KeyChord @('ControlKey', 'ShiftKey', 'C')
    Start-Sleep -Seconds 2
    if (Test-ZoomCaptionsOn) { return $true }

    # 2. toolbar button, then the "Show Captions" item of the menu it may open
    $button = Find-ZoomUiElement -NamePattern $script:ZoomButtons.Captions -Handles @($w.Handle)
    if ($button -and (Invoke-UiElement $button)) {
        Start-Sleep -Seconds 1
        $item = Find-ZoomUiElement -NamePattern $script:ZoomButtons.CaptionsMenu
        if ($item) { [void](Invoke-UiElement $item) }
        Start-Sleep -Seconds 1
        if (Test-ZoomCaptionsOn) { return $true }
    }
    $false
}
