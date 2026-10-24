# Zoom desktop client control: join via zoommtg://, classify windows, full screen.
# Captions, computer audio and skipping the join preview come from Zoom's own settings (see README):
# Zoom exposes no toolbar buttons to UI Automation, so they cannot be clicked from here.
# Window classes / titles below were chosen from known Zoom builds; calibrate against the real client
# (Get-TopWindows -ProcessName Zoom) if detection misbehaves after a Zoom update.

$script:ZoomProcessName = 'Zoom'
$script:ZoomClasses = @{ Meeting = @('ConfMultiTabContentWndClass') }
$script:ZoomTitles = @{
    Meeting       = '^Zoom (Meeting|Webinar|会议|网络研讨会)'
    PasswordError = 'incorrect|wrong|invalid|错误|密码'
    Waiting       = 'waiting|等候|等待主持人'
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
    # Alt+F toggles, so check before every press. Focus can take a moment to land, hence the retries.
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $w = Get-ZoomMeetingWindow
        if (-not $w) { return $false }
        if (Test-ZoomFullScreen) { return $true }
        Set-ForegroundWindowSafe $w.Handle
        Start-Sleep -Milliseconds 800
        Send-KeyChord @('Menu', 'F')
        for ($i = 0; $i -lt 8 -and -not (Test-ZoomFullScreen); $i++) { Start-Sleep -Milliseconds 500 }
    }
    Test-ZoomFullScreen
}
