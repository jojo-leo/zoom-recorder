# User-facing notices: 12h balloon reminder and the 15-minute confirmation window.

function Format-MeetingNumber {
    param([Parameter(Mandatory, Position = 0)][string]$Number)
    switch ($Number.Length) {
        9 { '{0} {1} {2}' -f $Number.Substring(0, 3), $Number.Substring(3, 3), $Number.Substring(6) }
        10 { '{0} {1} {2}' -f $Number.Substring(0, 3), $Number.Substring(3, 3), $Number.Substring(6) }
        11 { '{0} {1} {2}' -f $Number.Substring(0, 3), $Number.Substring(3, 4), $Number.Substring(7) }
        default { $Number }
    }
}

function Format-MeetingTimes {
    param([Parameter(Mandatory, Position = 0)]$Meeting)
    @{
        Original = Format-OriginalTime $Meeting
        Perth    = '{0} (AWST)' -f (Get-MeetingPerthTime $Meeting).ToString('yyyy-MM-dd HH:mm')
    }
}

function Format-Countdown {
    param([Parameter(Mandatory, Position = 0)][int]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    '{0:00}:{1:00}' -f [math]::Floor($Seconds / 60), ($Seconds % 60)
}

function Get-ReminderText {
    param([Parameter(Mandatory, Position = 0)]$Meeting, [datetime]$Now = (Get-Date))
    $perth = Get-MeetingPerthTime $Meeting
    $days = ($perth.Date - $Now.Date).Days
    $day = switch ($days) { 0 { '今天' } 1 { '明天' } default { $perth.ToString('MM-dd') } }
    @(
        "$day $($perth.ToString('HH:mm')) 有会议需要录制"
        "会议：$($Meeting.name) ($($Meeting.meetingID))"
        "原定时间：$((Format-MeetingTimes $Meeting).Original)"
    ) -join "`n"
}

function Get-ConfirmBodyText {
    param([Parameter(Mandatory, Position = 0)]$Meeting)
    $times = Format-MeetingTimes $Meeting
    @(
        "会议原定时间: $($times.Original)"
        "珀斯时间: $($times.Perth)"
        "会议号: $(Format-MeetingNumber $Meeting.meetingID)"
        "会议名称: $($Meeting.name)"
        ''
        '重要提示：'
        '✓ 工具已为你临时关闭自动锁屏和睡眠'
        '✓ 请确保：不要手动按 Win+L 锁屏'
        '✓ 请确保：不要合上笔记本盖'
        '✓ 建议：接上电源'
    ) -join "`n"
}

function Show-ReminderBalloon {
    param([Parameter(Mandatory, Position = 0)]$Meeting)
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Icon = [System.Drawing.SystemIcons]::Information
    $icon.Text = 'ZoomRecorder'
    $icon.Visible = $true
    $entry = Get-EntryScriptPath
    $open = { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -STA -File `"$entry`" -Action UI" }.GetNewClosure()
    $icon.add_BalloonTipClicked($open)
    $icon.ShowBalloonTip(15000, 'Zoom 会议录制提醒', (Get-ReminderText $Meeting), [System.Windows.Forms.ToolTipIcon]::Info)
    $until = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $until) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    $icon.Dispose()
}

function Show-SessionConfirmDialog {
    param([Parameter(Mandatory, Position = 0)]$Meeting, [Parameter(Mandatory)][int]$TimeoutSeconds)
    Add-Type -AssemblyName PresentationFramework
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="即将开始录制 Zoom 会议" SizeToContent="WidthAndHeight" MinWidth="460"
        Topmost="True" ResizeMode="NoResize" WindowStyle="ToolWindow" WindowStartupLocation="CenterScreen"
        FontFamily="Microsoft YaHei UI" FontSize="14">
  <StackPanel Margin="24">
    <TextBlock Text="即将开始录制 Zoom 会议" FontSize="18" FontWeight="Bold" Margin="0,0,0,16"/>
    <TextBlock x:Name="Body" TextWrapping="Wrap" LineHeight="22"/>
    <TextBlock x:Name="Countdown" Margin="0,16,0,16" FontWeight="Bold" Foreground="#C62828"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="ConfirmBtn" Content="确认" Width="110" Height="32" Margin="0,0,12,0" IsDefault="True"/>
      <Button x:Name="CancelBtn" Content="取消录制" Width="110" Height="32"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $window.FindName('Body').Text = Get-ConfirmBodyText $Meeting
    $countdown = $window.FindName('Countdown')
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $state = @{ Result = 'Timeout' }

    $update = {
        $left = [int][math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        $countdown.Text = "录制将在 $(Format-Countdown $left) 后自动开始"
        if ($left -le 0) { $window.Close() }
    }.GetNewClosure()
    & $update

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [timespan]::FromSeconds(1)
    $timer.add_Tick($update)
    $window.FindName('ConfirmBtn').add_Click({ $state.Result = 'Confirm'; $window.Close() }.GetNewClosure())
    $window.FindName('CancelBtn').add_Click({ $state.Result = 'Cancel'; $window.Close() }.GetNewClosure())
    $window.add_Closed({ $timer.Stop() }.GetNewClosure())

    $timer.Start()
    [void]$window.ShowDialog()
    $state.Result
}
