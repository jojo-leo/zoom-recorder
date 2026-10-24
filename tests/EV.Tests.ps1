Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

Describe 'Find-EVRecording' {
    $dir = Join-Path $TestDrive 'v'
    New-Item $dir -ItemType Directory | Out-Null
    $old = New-Item (Join-Path $dir 'old.mp4') -ItemType File
    $old.LastWriteTime = [datetime]'2026-01-01'
    New-Item (Join-Path $dir 'new.mp4') -ItemType File | Out-Null
    New-Item (Join-Path $dir 'notes.txt') -ItemType File | Out-Null

    It '返回开始后的最新 mp4' { Split-Path (Find-EVRecording -Since (Get-Date).AddMinutes(-1) -Dir $dir) -Leaf | Should Be 'new.mp4' }
    It '没有则 null' { Find-EVRecording -Since (Get-Date).AddMinutes(5) -Dir $dir | Should Be $null }
    It '目录不存在则 null' { Find-EVRecording -Since (Get-Date) -Dir (Join-Path $TestDrive 'nope') | Should Be $null }
}

Describe 'EV 热键不激活窗口' {
    Mock Send-KeyChord {} -ModuleName RecorderCore
    Mock Set-ForegroundWindowSafe {} -ModuleName RecorderCore

    It 'Ctrl+F1 开始' {
        Start-EVRecording
        Assert-MockCalled Send-KeyChord -ModuleName RecorderCore -Times 1 -Exactly -Scope It -ParameterFilter { ($Chord -join '+') -eq 'ControlKey+F1' }
        Assert-MockCalled Set-ForegroundWindowSafe -ModuleName RecorderCore -Times 0 -Exactly -Scope It
    }
    It 'Ctrl+F2 停止' {
        Stop-EVRecording
        Assert-MockCalled Send-KeyChord -ModuleName RecorderCore -Times 1 -Exactly -Scope It -ParameterFilter { ($Chord -join '+') -eq 'ControlKey+F2' }
    }
}

Describe 'Start-EV' {
    It 'EV 已在运行时不重复启动' {
        Mock Test-EVRunning { $true } -ModuleName RecorderCore
        Mock Start-Process {} -ModuleName RecorderCore
        Start-EV | Should Be $true
        Assert-MockCalled Start-Process -ModuleName RecorderCore -Times 0 -Exactly -Scope It
    }
    It '可执行文件不存在返回 false' {
        Mock Test-EVRunning { $false } -ModuleName RecorderCore
        Mock Test-Path { $false } -ModuleName RecorderCore
        Mock Start-Process {} -ModuleName RecorderCore
        Start-EV | Should Be $false
        Assert-MockCalled Start-Process -ModuleName RecorderCore -Times 0 -Exactly -Scope It
    }
}
