# Tray icon: shows session phase, lets the user open the UI, stop a recording, and see failure notices.

$script:TrayColors = @{ Idle = '#1E88E5'; Guarding = '#FBC02D'; Recording = '#E53935'; RecordingDim = '#7F1D1D' }

function New-DotIcon {
    param([Parameter(Mandatory, Position = 0)][string]$Color)
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($Color))
    $g.FillEllipse($brush, 1, 1, 14, 14)
    $brush.Dispose(); $g.Dispose()
    [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function Start-Tray {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $mutex = New-Object System.Threading.Mutex($false, 'Global\ZoomRecorder_Tray')
    if (-not $mutex.WaitOne(0)) { return }   # already running

    $ctx = @{
        Icons    = @{}
        Tray     = New-Object System.Windows.Forms.NotifyIcon
        Blink    = $false
        Showing  = $false
        Entry    = Get-EntryScriptPath
        LogDir   = Get-DefaultLogDir
    }
    foreach ($k in $script:TrayColors.Keys) { $ctx.Icons[$k] = New-DotIcon $script:TrayColors[$k] }

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $openItem = $menu.Items.Add('打开管理界面')
    $stopItem = $menu.Items.Add('立即停止当前录制')
    $logItem = $menu.Items.Add('查看日志文件夹')
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $exitItem = $menu.Items.Add('退出')
    $ctx.StopItem = $stopItem

    $openUi = { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -STA -File `"$($ctx.Entry)`" -Action UI" }
    $openItem.add_Click($openUi)
    $ctx.Tray.add_DoubleClick($openUi)
    $logItem.add_Click({
            if (-not (Test-Path $ctx.LogDir)) { New-Item -ItemType Directory -Path $ctx.LogDir -Force | Out-Null }
            Start-Process explorer.exe $ctx.LogDir
        })
    $stopItem.add_Click({
            $s = Get-SessionState
            if ($s.Phase -eq 'Idle') { return }
            $what = if ($s.Phase -eq 'Recording' -and $s.StartedAt) {
                "确定要停止当前录制吗？已录制 $([int]((Get-Date) - [datetime]$s.StartedAt).TotalMinutes) 分钟"
            } else { "确定要取消「$($s.Name)」的录制吗？" }
            if ([System.Windows.Forms.MessageBox]::Show($what, 'ZoomRecorder', 'YesNo', 'Question') -eq 'Yes') { Request-SessionStop }
        })
    $exitItem.add_Click({
            if ((Get-SessionState).Phase -ne 'Idle') {
                $answer = [System.Windows.Forms.MessageBox]::Show('当前有录制在进行。退出托盘不会停止录制，确定退出吗？', 'ZoomRecorder', 'YesNo', 'Warning')
                if ($answer -ne 'Yes') { return }
            }
            $ctx.Timer.Stop(); $ctx.Tray.Visible = $false; $ctx.Tray.Dispose()
            [System.Windows.Forms.Application]::ExitThread()
        })

    $ctx.Tray.ContextMenuStrip = $menu
    $ctx.Tray.Icon = $ctx.Icons.Idle
    $ctx.Tray.Text = 'ZoomRecorder · 空闲'
    $ctx.Tray.Visible = $true

    $ctx.Timer = New-Object System.Windows.Forms.Timer
    $ctx.Timer.Interval = 500
    $ctx.Timer.add_Tick({
            $s = Get-SessionState
            $ctx.Blink = -not $ctx.Blink
            $ctx.Tray.Icon = switch ($s.Phase) {
                'Recording' { if ($ctx.Blink) { $ctx.Icons.Recording } else { $ctx.Icons.RecordingDim } }
                'Guarding' { $ctx.Icons.Guarding }
                default { $ctx.Icons.Idle }
            }
            $ctx.Tray.Text = Format-TrayTooltip $s
            $ctx.StopItem.Enabled = $s.Phase -ne 'Idle'
            # Failure notices queued while the screen was locked are shown once the user is back.
            if (-not $ctx.Showing -and -not (Test-SessionLocked)) {
                $notices = @(Get-PendingNotices -Clear)
                if ($notices.Count) {
                    $ctx.Showing = $true
                    [void][System.Windows.Forms.MessageBox]::Show(($notices -join "`n`n"), 'ZoomRecorder 录制提醒', 'OK', 'Warning')
                    $ctx.Showing = $false
                }
            }
        })
    $ctx.Timer.Start()

    try { [System.Windows.Forms.Application]::Run() }
    finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
}
