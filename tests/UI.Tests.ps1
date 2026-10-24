# Drives the real WPF windows: raises button clicks and records which dialogs open.
# Same module scope as production (RecorderUI.ps1 only imports the module and calls Show-MainWindow).
Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

Describe 'RecorderUI 按钮' {
    if (-not [System.Windows.Application]::Current) {
        $app = New-Object System.Windows.Application
        $app.ShutdownMode = 'OnExplicitShutdown'
    }
    Mock Get-Meetings { @() } -ModuleName RecorderCore

    # Close every dialog that opens on top of the main window and remember its title.
    $global:ZrOpened = New-Object System.Collections.ArrayList
    $closer = New-Object System.Windows.Threading.DispatcherTimer
    $closer.Interval = [timespan]::FromMilliseconds(300)
    $closer.add_Tick({
            foreach ($win in @([System.Windows.Application]::Current.Windows)) {
                if ($win.Title -ne 'ZoomRecorder - 会议管理') { [void]$global:ZrOpened.Add($win.Title); $win.Close() }
            }
        })

    It '点击"添加"会打开添加会议对话框' {
        $global:ZrOpened.Clear()
        $w = New-MainWindow
        $w.Show()
        $closer.Start()
        try {
            $w.FindName('AddBtn').RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        } finally { $closer.Stop(); $w.Close() }
        ($global:ZrOpened -join ',') | Should Be '添加会议'
    }
}
