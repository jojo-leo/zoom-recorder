# Rewrites every .ps1/.psm1 under -Path as UTF-8 with BOM so Windows PowerShell 5.1
# reads non-ASCII text correctly regardless of the system ANSI code page.
param([string]$Path = (Split-Path $PSScriptRoot -Parent))

$utf8Bom = New-Object System.Text.UTF8Encoding $true
Get-ChildItem -Path $Path -Recurse -Include *.ps1, *.psm1 -File | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return }
    $text = (New-Object System.Text.UTF8Encoding $false).GetString($bytes)
    [System.IO.File]::WriteAllText($_.FullName, $text, $utf8Bom)
}
