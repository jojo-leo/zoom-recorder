# ZoomRecorder entry point. Scheduled tasks and the autostart entry all call this script with -Action.
#   Tray       tray icon (autostart)
#   UI         meeting management window
#   Notify12h  12-hour reminder balloon               (scheduled task)
#   Session    confirm -> keep awake -> record -> stop (scheduled task; -Unattended for the wake fallback)
#   Install    autostart + re-register tasks + start tray
#   Uninstall  remove autostart and all ZoomRecorder_* tasks (meeting data and logs are kept)
param(
    [ValidateSet('Tray', 'UI', 'Notify12h', 'Session', 'Install', 'Uninstall')][string]$Action = 'Tray',
    [string]$Id,
    [switch]$Unattended,
    [switch]$AutoExit
)

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $argList = "-NoProfile -WindowStyle Hidden -STA -File `"$PSCommandPath`" -Action $Action"
    if ($Id) { $argList += " -Id $Id" }
    if ($Unattended) { $argList += ' -Unattended' }
    if ($AutoExit) { $argList += ' -AutoExit' }
    Start-Process powershell.exe -ArgumentList $argList
    return
}

Import-Module (Join-Path $PSScriptRoot 'RecorderCore.psm1') -Force

switch ($Action) {
    'Tray' { Start-Tray -AutoExit:$AutoExit }
    'UI' { & (Join-Path $PSScriptRoot 'RecorderUI.ps1') }
    'Notify12h' { Invoke-Notify12h $Id }
    'Session' { [void](Invoke-RecordingSession -Id $Id -Unattended:$Unattended) }
    'Install' {
        $count = Install-ZoomRecorder
        Write-Output "已安装：开机自启已设置，重新注册了 $count 场会议的定时任务。"
        Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -STA -File `"$PSCommandPath`" -Action Tray"
    }
    'Uninstall' {
        Uninstall-ZoomRecorder
        Write-Output '已卸载：开机自启和定时任务已删除（会议数据和日志保留）。'
    }
}
