# BagIdea Office — Wallpaper mode PoC helper.
#
# Re-parents a running Godot window into the desktop's WorkerW layer so it
# renders BEHIND desktop icons (same technique as Wallpaper Engine).
#
# Usage:
#   .\wallpaper.ps1 -Attach -ProcessId <pid>   # embed the window as wallpaper
#   .\wallpaper.ps1 -Detach                    # kill Godot + restore wallpaper
param(
    [switch]$Attach,
    [switch]$Detach,
    [int]$ProcessId = 0
)

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class WallpaperHelper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindow(string cls, string win);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string win);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, UIntPtr wParam,
        IntPtr lParam, uint flags, uint timeout, out UIntPtr result);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetParent(IntPtr child, IntPtr parent);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hgt, bool repaint);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, string vparam, uint init);

    // Find (or spawn) the WorkerW layer that sits between the wallpaper and
    // the icon list (SHELLDLL_DefView).
    public static IntPtr FindWorkerW() {
        IntPtr progman = FindWindow("Progman", null);
        UIntPtr res;
        // Undocumented message: asks Progman to spawn a WorkerW behind the icons.
        SendMessageTimeout(progman, 0x052C, UIntPtr.Zero, IntPtr.Zero, 0x0, 1000, out res);

        IntPtr workerw = IntPtr.Zero;
        EnumWindows(delegate(IntPtr top, IntPtr lp) {
            IntPtr shell = FindWindowEx(top, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (shell != IntPtr.Zero) {
                // Classic layout: the WorkerW we want is the top-level sibling
                // right after the window hosting the icons.
                workerw = FindWindowEx(IntPtr.Zero, top, "WorkerW", null);
            }
            return true;
        }, IntPtr.Zero);

        if (workerw == IntPtr.Zero) {
            // Win11 24H2+ layout: icons host and WorkerW live under Progman itself.
            workerw = FindWindowEx(progman, IntPtr.Zero, "WorkerW", null);
            if (workerw == IntPtr.Zero) workerw = progman;
        }
        return workerw;
    }

    public static void RefreshWallpaper() {
        // Re-applies the user's wallpaper so no black WorkerW residue is left.
        SystemParametersInfo(0x0014 /*SPI_SETDESKWALLPAPER*/, 0, null, 0x03);
    }
}
"@

if ($Detach) {
    Get-Process | Where-Object { $_.Name -like "Godot*" } | Stop-Process -Force
    [WallpaperHelper]::RefreshWallpaper()
    Write-Output "detached: godot stopped, wallpaper refreshed"
    exit 0
}

if (-not $Attach) { Write-Output "specify -Attach -ProcessId <pid> or -Detach"; exit 1 }

$proc = Get-Process -Id $ProcessId -ErrorAction Stop

# Wait for the game window to exist.
$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 50; $i++) {
    $proc.Refresh()
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 200
}
if ($hwnd -eq [IntPtr]::Zero) { Write-Error "godot window not found"; exit 1 }

$workerw = [WallpaperHelper]::FindWorkerW()
if ($workerw -eq [IntPtr]::Zero) { Write-Error "WorkerW not found"; exit 1 }

$null = [WallpaperHelper]::SetParent($hwnd, $workerw)
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$null = [WallpaperHelper]::MoveWindow($hwnd, 0, 0, $b.Width, $b.Height, $true)

Write-Output ("attached: hwnd=0x{0:X} -> workerw=0x{1:X} ({2}x{3})" -f $hwnd.ToInt64(), $workerw.ToInt64(), $b.Width, $b.Height)
