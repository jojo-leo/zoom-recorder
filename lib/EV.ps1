# EV 录屏 control. Recording area (full screen) and audio (system only) are preset in EV itself;
# Ctrl+F1 / Ctrl+F2 are EV's global hotkeys, so the EV window is never brought to the front.

$script:EvExe = 'C:\Program Files (x86)\EVCapture\EVCapture.exe'
$script:EvProcessName = 'EVCapture'
$script:EvVideoDir = 'D:\EV录屏文件'

function Test-EVRunning { [bool](Get-Process -Name $script:EvProcessName -ErrorAction SilentlyContinue) }

function Start-EV {
    if (Test-EVRunning) { return $true }
    if (-not (Test-Path -LiteralPath $script:EvExe)) { return $false }
    Start-Process -FilePath $script:EvExe | Out-Null
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        if (Test-EVRunning) { Start-Sleep -Seconds 5; return $true }
    }
    $false
}

function Start-EVRecording { Send-KeyChord @('ControlKey', 'F1') }

function Stop-EVRecording { Send-KeyChord @('ControlKey', 'F2') }

function Close-EV { Stop-Process -Name $script:EvProcessName -Force -ErrorAction SilentlyContinue }

function Find-EVRecording {
    param([Parameter(Mandatory)][datetime]$Since, [string]$Dir = $script:EvVideoDir)
    if (-not (Test-Path -LiteralPath $Dir)) { return $null }
    $file = Get-ChildItem -LiteralPath $Dir -Filter *.mp4 -File |
        Where-Object { $_.LastWriteTime -ge $Since } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($file) { $file.FullName } else { $null }
}
