# Runs Pester (3.4) on the given test file(s) or the whole tests folder; exits non-zero on failure.
param([string[]]$Path = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tests'))

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
& (Join-Path $PSScriptRoot 'Add-Bom.ps1')
Import-Module Pester -RequiredVersion 3.4.0
$result = Invoke-Pester -Script $Path -PassThru -Quiet
foreach ($t in $result.TestResult | Where-Object { -not $_.Passed }) {
    Write-Output "FAIL: $($t.Describe) > $($t.Name)`n      $($t.FailureMessage)"
}
Write-Output "Passed: $($result.PassedCount)  Failed: $($result.FailedCount)"
exit $result.FailedCount
