# Thin P/Invoke layer: keyboard input, window enumeration/activation, keep-awake, lock detection, screenshots.

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

if (-not ('ZR.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace ZR {
    public class WinInfo {
        public IntPtr Handle; public string Title; public string ClassName;
        public int ProcessId; public bool Visible; public int Width; public int Height;
    }

    public static class Native {
        [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
        delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);
        [DllImport("user32.dll", SetLastError = true)] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
        [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder info, int len, out int needed);

        public static List<WinInfo> GetTopWindows() {
            var list = new List<WinInfo>();
            EnumWindows((h, l) => {
                var title = new StringBuilder(512); GetWindowText(h, title, title.Capacity);
                var cls = new StringBuilder(256); GetClassName(h, cls, cls.Capacity);
                int pid; GetWindowThreadProcessId(h, out pid);
                RECT r; GetWindowRect(h, out r);
                list.Add(new WinInfo { Handle = h, Title = title.ToString(), ClassName = cls.ToString(), ProcessId = pid,
                    Visible = IsWindowVisible(h), Width = r.Right - r.Left, Height = r.Bottom - r.Top });
                return true;
            }, IntPtr.Zero);
            return list;
        }

        // The interactive desktop is "Default" while the user is logged in; it switches to "Winlogon" when locked.
        public static bool IsSessionLocked() {
            IntPtr desk = OpenInputDesktop(0, false, 0x0100 /* DESKTOP_SWITCHDESKTOP */);
            if (desk == IntPtr.Zero) return true;
            try {
                var name = new StringBuilder(256); int needed;
                if (!GetUserObjectInformation(desk, 2 /* UOI_NAME */, name, name.Capacity * 2, out needed)) return false;
                return !string.Equals(name.ToString(), "Default", StringComparison.OrdinalIgnoreCase);
            } finally { CloseDesktop(desk); }
        }
    }
}
'@
}

# Physical pixels everywhere, so window sizes compare correctly with screen bounds on scaled displays.
[void][ZR.Native]::SetProcessDPIAware()

$script:ES_CONTINUOUS = [uint32]'0x80000000'
$script:ES_SYSTEM_REQUIRED = [uint32]1
$script:ES_DISPLAY_REQUIRED = [uint32]2

function Get-VirtualKeyCode {
    param([Parameter(Mandatory, Position = 0)][string]$Name)
    if (-not [Enum]::IsDefined([System.Windows.Forms.Keys], $Name)) { throw "未知键名: $Name" }
    [int][System.Windows.Forms.Keys]::$Name
}

function Send-KeyChord {
    param([Parameter(Mandatory, Position = 0)][string[]]$Chord)
    $codes = @($Chord | ForEach-Object { [byte](Get-VirtualKeyCode $_) })
    foreach ($vk in $codes) { [ZR.Native]::keybd_event($vk, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 30 }
    [array]::Reverse($codes)
    foreach ($vk in $codes) { [ZR.Native]::keybd_event($vk, 0, 2 <# KEYUP #>, [UIntPtr]::Zero); Start-Sleep -Milliseconds 30 }
}

function Get-TopWindows {
    param([string]$ProcessName)
    $all = [ZR.Native]::GetTopWindows()
    if ($ProcessName) {
        $ids = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | ForEach-Object Id)
        $all = $all | Where-Object { $ids -contains $_.ProcessId }
    }
    foreach ($w in $all) {
        [pscustomobject][ordered]@{
            Handle = $w.Handle; Title = $w.Title; ClassName = $w.ClassName; ProcessId = $w.ProcessId
            Visible = $w.Visible; Width = $w.Width; Height = $w.Height
        }
    }
}

function Set-ForegroundWindowSafe {
    param([Parameter(Mandatory, Position = 0)][IntPtr]$Handle)
    if ([ZR.Native]::IsIconic($Handle)) { [void][ZR.Native]::ShowWindow($Handle, 9 <# SW_RESTORE #>) }
    # Windows only lets a process take the foreground right after keyboard input; a bare Alt tap satisfies that.
    Send-KeyChord 'Menu'
    [void][ZR.Native]::SetForegroundWindow($Handle)
}

function Enable-KeepAwake {
    [void][ZR.Native]::SetThreadExecutionState($script:ES_CONTINUOUS -bor $script:ES_SYSTEM_REQUIRED -bor $script:ES_DISPLAY_REQUIRED)
}

function Disable-KeepAwake { [void][ZR.Native]::SetThreadExecutionState($script:ES_CONTINUOUS) }

function Test-SessionLocked { [ZR.Native]::IsSessionLocked() }

function Save-Screenshot {
    param([Parameter(Mandatory, Position = 0)][string]$Path)
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $g.Dispose()
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bmp.Dispose() }
}
