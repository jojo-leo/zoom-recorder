# ZoomRecorder core module: loads every lib\*.ps1 into one module scope.
$script:Root = $PSScriptRoot

Get-ChildItem -Path (Join-Path $PSScriptRoot 'lib') -Filter *.ps1 | Sort-Object Name | ForEach-Object { . $_.FullName }

Export-ModuleMember -Function * -Variable TimeZoneMap
