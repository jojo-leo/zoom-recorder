Import-Module "$PSScriptRoot\..\RecorderCore.psm1" -Force

Describe 'Win32' {
    It '能枚举到 explorer 窗口' { @(Get-TopWindows -ProcessName explorer).Count | Should BeGreaterThan 0 }
    It '窗口对象字段齐全' {
        $w = @(Get-TopWindows -ProcessName explorer)[0]
        $w.Handle | Should Not Be ([IntPtr]::Zero)
        $w.ProcessId | Should BeGreaterThan 0
        ($w.PSObject.Properties.Name -join ',') | Should Be 'Handle,Title,ClassName,ProcessId,Visible,Width,Height'
    }
    It '当前未锁屏' { Test-SessionLocked | Should Be $false }
    It 'KeepAwake 可调用' { { Enable-KeepAwake; Disable-KeepAwake } | Should Not Throw }
    It '键名转换' { Get-VirtualKeyCode 'ControlKey' | Should Be 0x11; Get-VirtualKeyCode 'F1' | Should Be 0x70; Get-VirtualKeyCode 'Menu' | Should Be 0x12 }
    It '未知键名报错' { { Get-VirtualKeyCode 'NoSuchKey' } | Should Throw }
    It '截图生成文件' { $p = Join-Path $TestDrive 's.png'; Save-Screenshot $p; Test-Path $p | Should Be $true }
}
