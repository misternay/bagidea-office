# Project window manager — tmux-style background sessions on Windows.
# Hosts are powershell processes whose command line carries the comment
# marker `#BAGIDEA_PROJ_<id>` (the strict # form: diagnostic shells that
# merely mention the word can never match).
#
# Window resolution — SAFETY FIRST. Windows Terminal runs every window in
# ONE shared process, so process-walking can land on the USER'S own
# terminal. Therefore:
#   1) prefer a window whose TITLE contains BAGIDEA_PROJ_<id>
#      (we spawn WT tabs with --suppressApplicationTitle, locking it)
#   2) else a classic ConsoleWindowClass window owned by the host family
#   3) a CASCADIA window WITHOUT the title marker is NEVER touched.
#   sweep | hide <id> | show <id> | stop <id>
param([string]$Action = "sweep", [string]$Id = "")

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WU {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
}
"@

# One process snapshot: child map for descendant walks.
$all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, CommandLine, ExecutablePath

# killdir <path>: reap processes anchored INSIDE a project folder (dev
# servers agents left behind, stray claude runs) so disk-delete can win.
# Match = command line or exe path contains the folder path. NEVER touch
# WindowsTerminal/explorer (shared hosts) or this very script's process —
# its own command line contains the path argument.
if ($Action -eq "killdir") {
  $needle = $Id.Trim().ToLower()
  if ($needle.Length -lt 8) { exit }   # refuse vague paths outright
  foreach ($p in $all) {
    if ($p.ProcessId -eq $PID) { continue }
    if ($p.Name -in @("WindowsTerminal.exe", "explorer.exe", "svchost.exe")) { continue }
    $cl = ([string]$p.CommandLine).ToLower()
    $ep = ([string]$p.ExecutablePath).ToLower()
    if ($cl.Contains($needle) -or ($ep -and $ep.Contains($needle))) {
      taskkill /PID $p.ProcessId /T /F | Out-Null
      Write-Output "killed $($p.ProcessId) $($p.Name)"
    }
  }
  exit
}

$kids = @{}
foreach ($p in $all) {
  $pp = [string]$p.ParentProcessId
  if (-not $kids.ContainsKey($pp)) { $kids[$pp] = @() }
  $kids[$pp] += $p.ProcessId
}

# Collect ALL top-level windows once.
$script:wins = @()
$cb = [WU+EnumProc]{ param($h, $l)
  $o = [uint32]0
  [void][WU]::GetWindowThreadProcessId($h, [ref]$o)
  $sbC = New-Object System.Text.StringBuilder 64
  [void][WU]::GetClassName($h, $sbC, 64)
  $sbT = New-Object System.Text.StringBuilder 256
  [void][WU]::GetWindowText($h, $sbT, 256)
  $script:wins += @{ h = $h; pid2 = [string]$o; vis = [WU]::IsWindowVisible($h)
    cls = $sbC.ToString(); title = $sbT.ToString() }
  return $true
}
[void][WU]::EnumWindows($cb, [IntPtr]::Zero)

# Session hosts: powershell with the strict comment marker.
$hosts = $all | Where-Object {
  $_.Name -eq "powershell.exe" -and $_.CommandLine -match "#BAGIDEA_PROJ_([\w-]+)"
}

foreach ($p in $hosts) {
  if ($p.CommandLine -notmatch '#BAGIDEA_PROJ_([\w-]+)') { continue }
  $projId = $Matches[1]

  # 1) Title-locked window (Windows Terminal path) — globally unique.
  $win = $null
  foreach ($w in $script:wins) {
    if ($w.title -match "BAGIDEA_PROJ_$projId") { $win = $w; break }
  }

  # 2) Classic console owned by the host family (conhost fallback path).
  if (-not $win) {
    $family = New-Object System.Collections.Generic.List[string]
    if ($p.ParentProcessId) { $family.Add([string]$p.ParentProcessId) }
    $queue = @([string]$p.ProcessId)
    while ($queue.Count -gt 0) {
      $cur = $queue[0]; $queue = $queue[1..$queue.Count]
      $family.Add($cur)
      if ($kids.ContainsKey($cur)) { $queue += ($kids[$cur] | ForEach-Object { [string]$_ }) }
    }
    foreach ($w in $script:wins) {
      if ($w.cls -eq "ConsoleWindowClass" -and $family.Contains($w.pid2)) { $win = $w; break }
    }
  }

  if ($Action -eq "sweep") {
    $vis = 0
    if ($win -and $win.vis) { $vis = 1 }
    Write-Output "$projId $vis"
  } elseif ($projId -eq $Id) {
    switch ($Action) {
      "hide" { if ($win) { [void][WU]::ShowWindow($win.h, 0) } }
      "show" {
        if ($win) {
          [void][WU]::ShowWindow($win.h, 5)
          [void][WU]::ShowWindow($win.h, 9)
          [void][WU]::BringWindowToTop($win.h)
          [void][WU]::SetForegroundWindow($win.h)
        }
      }
      "stop" {
        # Close the WINDOW itself (WM_CLOSE) — killing only the shell process
        # left the Windows Terminal window lingering, so the project looked
        # "still open" and any click re-detected it as active. This is OUR
        # dedicated `-w new` window (title-locked), so closing it is safe.
        if ($win) { [void][WU]::PostMessage($win.h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
        taskkill /PID $p.ProcessId /T /F | Out-Null
      }
    }
  }
}
