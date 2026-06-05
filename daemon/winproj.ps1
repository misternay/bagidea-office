# Project window manager — tmux-style background sessions on Windows.
# Project terminals are `conhost cmd /k "title BAGIDEA_PROJ_<id> && …"`.
# The console HWND may be owned by the cmd, its conhost parent, or a child
# (claude retitles and respawns things) — so we match the window against the
# WHOLE process family of the marker cmd: parent + all descendants.
#   sweep        -> "<id> <visible01>" per live project window
#   hide <id>    -> hide the window (claude keeps running)
#   show <id>    -> bring the same window back (resume)
#   stop <id>    -> kill the whole family for real
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
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
"@

# One process snapshot for everything.
$all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, CommandLine
$kids = @{}
foreach ($p in $all) {
  $pp = [string]$p.ParentProcessId
  if (-not $kids.ContainsKey($pp)) { $kids[$pp] = @() }
  $kids[$pp] += $p.ProcessId
}

# Collect every top-level window once: pid -> best candidate. Processes
# (conhost, claude, node) also own invisible helper windows — a REAL
# console (class ConsoleWindowClass) outranks everything, then visible,
# then titled.
$script:winByPid = @{}
$cb = [WU+EnumProc]{ param($h, $l)
  $o = [uint32]0
  [void][WU]::GetWindowThreadProcessId($h, [ref]$o)
  $k = [string]$o
  $vis = [WU]::IsWindowVisible($h)
  $sb = New-Object System.Text.StringBuilder 64
  [void][WU]::GetClassName($h, $sb, 64)
  $score = 0
  if ($sb.ToString() -eq "ConsoleWindowClass") { $score += 4 }
  if ($vis) { $score += 2 }
  if ([WU]::GetWindowTextLength($h) -gt 0) { $score += 1 }
  if (-not $script:winByPid.ContainsKey($k) -or $score -gt $script:winByPid[$k].score) {
    $script:winByPid[$k] = @{ h = $h; vis = $vis; score = $score }
  }
  return $true
}
[void][WU]::EnumWindows($cb, [IntPtr]::Zero)

# The real session hosts: the powershell (or legacy cmd /k) carrying our
# marker — the transient `cmd /c start …` launcher also contains the
# marker, so cmd.exe only counts with /k.
$hosts = $all | Where-Object {
  $_.CommandLine -match "BAGIDEA_PROJ_([\w-]+)" -and (
    $_.Name -eq "powershell.exe" -or
    ($_.Name -eq "cmd.exe" -and $_.CommandLine -match "/k"))
}

foreach ($p in $hosts) {
  if ($p.CommandLine -notmatch 'BAGIDEA_PROJ_([\w-]+)') { continue }
  $projId = $Matches[1]

  # Family = parent (conhost) + the cmd + every descendant (claude, node…).
  $family = New-Object System.Collections.Generic.List[string]
  if ($p.ParentProcessId) { $family.Add([string]$p.ParentProcessId) }
  $queue = @([string]$p.ProcessId)
  while ($queue.Count -gt 0) {
    $cur = $queue[0]; $queue = $queue[1..$queue.Count]
    $family.Add($cur)
    if ($kids.ContainsKey($cur)) { $queue += ($kids[$cur] | ForEach-Object { [string]$_ }) }
  }

  # Best-scored window across the whole family (never the first ghost).
  $win = $null
  foreach ($f in $family) {
    if ($script:winByPid.ContainsKey($f)) {
      $cand = $script:winByPid[$f]
      if (-not $win -or $cand.score -gt $win.score) { $win = $cand }
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
          [void][WU]::ShowWindow($win.h, 5)   # SW_SHOW
          [void][WU]::ShowWindow($win.h, 9)   # SW_RESTORE (un-minimize too)
          [void][WU]::BringWindowToTop($win.h)
          [void][WU]::SetForegroundWindow($win.h)
        }
      }
      "stop" { taskkill /PID $p.ProcessId /T /F | Out-Null }
    }
  }
}
