# Opens the ZoomRecorder meeting management window. The window itself is lib\UI.ps1.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -STA -File `"$PSCommandPath`""
    return
}
Import-Module (Join-Path $PSScriptRoot 'RecorderCore.psm1') -Force
Show-MainWindow