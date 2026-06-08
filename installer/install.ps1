# BagIdea Office - one-shot open-source installer.
#
# Installs every dependency (Git, Node LTS, Rust, Godot 4.6.3, Claude Code CLI),
# clones the public repo to %LOCALAPPDATA%\BagIdeaOffice\app, builds the Rust
# shell, brands the window icon, wires the `bagidea` command onto your PATH and
# drops a Start Menu shortcut. Safe to re-run - every step skips what's done and
# a re-run does a `git pull` instead of a fresh clone (your data is preserved).
#
#   irm https://raw.githubusercontent.com/bagidea/bagidea-office/main/installer/install.ps1 | iex
#
# Options (env or params):
#   -Repo   <url>   source repo            (default: the public BagIdea Office)
#   -Branch <name>  branch to install      (default: main)
param(
  [string]$Repo   = $(if ($env:BAGIDEA_REPO)   { $env:BAGIDEA_REPO }   else { "https://github.com/bagidea/bagidea-office.git" }),
  [string]$Branch = $(if ($env:BAGIDEA_BRANCH) { $env:BAGIDEA_BRANCH } else { "main" })
)
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$APPDIR = Join-Path $env:LOCALAPPDATA "BagIdeaOffice"
$APP    = Join-Path $APPDIR "app"
$GODOTV = "4.6.3"

function Step($n, $m) { Write-Host ""; Write-Host "  [$n] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "      + $m" -ForegroundColor Green }
function Skip($m) { Write-Host "      - $m" -ForegroundColor DarkGray }
function Warn($m) { Write-Host "      ! $m" -ForegroundColor Yellow }
function Have($c) { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Cyan
Write-Host "   BagIdea Office - INSTALLER (open source)" -ForegroundColor Cyan
Write-Host "  ===========================================" -ForegroundColor Cyan

if (-not (Have "winget")) {
  Warn "winget not found - install 'App Installer' from the Microsoft Store first."; exit 1
}
function Winget($id) { winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements | Out-Null }

# ---- dependencies ------------------------------------------------------------
Step 1 "Git"
if (Have "git") { Skip "already installed ($((git --version)))" }
else { Winget "Git.Git"; Ok "installed" }

Step 2 "Node.js LTS"
if (Have "node") { Skip "already installed ($(node --version))" }
else { Winget "OpenJS.NodeJS.LTS"; Ok "installed" }

Step 3 "Rust toolchain (to build the desktop shell)"
$cargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
if (Have "cargo") { Skip "already installed ($(cargo --version))"; $cargo = "cargo" }
elseif (Test-Path $cargo) { Skip "already installed" }
else {
  Winget "Rustlang.Rustup"
  $rustup = Join-Path $env:USERPROFILE ".cargo\bin\rustup.exe"
  if (Test-Path $rustup) { & $rustup default stable | Out-Null; Ok "installed" }
  else { Warn "Rustup install may need a new terminal; re-run this script after." }
}
# make cargo callable in THIS session
$env:Path = "$env:Path;$(Join-Path $env:USERPROFILE '.cargo\bin')"

Step 4 "Godot $GODOTV (renders the office world)"
$gdir = Join-Path $APPDIR "tools\godot"
$gexe = Join-Path $gdir "Godot_v$GODOTV-stable_win64.exe"
if (Test-Path $gexe) { Skip "already installed" }
else {
  New-Item -ItemType Directory -Force $gdir | Out-Null
  $z = Join-Path $env:TEMP "godot.zip"
  Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/$GODOTV-stable/Godot_v$GODOTV-stable_win64.exe.zip" -OutFile $z
  Expand-Archive -Path $z -DestinationPath $gdir -Force; Remove-Item $z
  if (Test-Path $gexe) { Ok "installed" } else { Warn "extracted but exe not found" }
}
[Environment]::SetEnvironmentVariable("BAGIDEA_GODOT", $gexe, "User")
$env:BAGIDEA_GODOT = $gexe

Step 5 "Claude Code CLI (the brain of every agent)"
if (Have "claude") { Skip "already installed" }
else { npm install -g @anthropic-ai/claude-code | Out-Null; Ok "installed - log in later by running: claude" }

# ---- the app: clone (or pull) ------------------------------------------------
Step 6 "Get the app -> $APP"
New-Item -ItemType Directory -Force $APPDIR | Out-Null
if (Test-Path (Join-Path $APP ".git")) {
  Push-Location $APP
  git fetch --depth 1 origin $Branch 2>$null
  git reset --hard "origin/$Branch" 2>$null
  Pop-Location
  Ok "updated existing clone (git pull) - your data is untouched"
} elseif (Test-Path $APP) {
  # an old non-git install: keep user data, replace the rest with a clone.
  $backup = Join-Path $env:TEMP "bagidea_userdata"
  if (Test-Path $backup) { Remove-Item -Recurse -Force $backup }
  New-Item -ItemType Directory -Force $backup | Out-Null
  foreach ($f in @("registry.json","sessions.json","projects.json","jobs.json",
      "calendar.json","notes.json","layout.json","stats.json","proposals.json")) {
    $p = Join-Path $APP "daemon\$f"; if (Test-Path $p) { Copy-Item $p (Join-Path $backup $f) -Force }
  }
  if (Test-Path (Join-Path $APP "daemon\i18n")) { Copy-Item (Join-Path $APP "daemon\i18n") (Join-Path $backup "i18n") -Recurse -Force }
  Remove-Item -Recurse -Force $APP
  git clone --depth 1 --branch $Branch $Repo $APP
  Get-ChildItem $backup -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $APP ("daemon\" + $_.Name)) -Force }
  if (Test-Path (Join-Path $backup "i18n")) { Copy-Item (Join-Path $backup "i18n") (Join-Path $APP "daemon\i18n") -Recurse -Force }
  Ok "cloned + restored your previous data"
} else {
  git clone --depth 1 --branch $Branch $Repo $APP
  Ok "cloned to $APP"
}

# ---- build the Rust shell ----------------------------------------------------
Step 7 "Build the desktop shell"
$exe = Join-Path $APP "shell\target\release\bagidea-office-shell.exe"
Push-Location (Join-Path $APP "shell")
& $cargo build --release
Pop-Location
if (Test-Path $exe) { Ok "built -> $exe" }
else {
  Warn "build failed. The Rust MSVC toolchain needs the C++ build tools (linker)."
  Warn "Install them, then re-run this script:"
  Warn "  winget install Microsoft.VisualStudio.2022.BuildTools --override `"--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended`""
}

# ---- branded window/taskbar icon (BAG IDEA, never a Godot icon) --------------
Step 8 "Brand the window icon"
$bindir  = Join-Path $APP "godot\bin"
$branded = Join-Path $bindir "BagIdeaOffice.exe"
$ico     = Join-Path $APP "godot\assets\brand\logo.ico"
if ((Test-Path $gexe) -and (Test-Path $ico)) {
  New-Item -ItemType Directory -Force $bindir | Out-Null
  $rcedit = Join-Path $env:TEMP "rcedit-x64.exe"
  if (-not (Test-Path $rcedit)) {
    try { Invoke-WebRequest -Uri "https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe" -OutFile $rcedit } catch {}
  }
  Copy-Item $gexe $branded -Force
  if (Test-Path $rcedit) {
    & $rcedit $branded --set-icon $ico --set-version-string "FileDescription" "BagIdea Office" --set-version-string "ProductName" "BagIdea Office" 2>$null
    Ok "branded exe ready - the taskbar shows BAG IDEA from launch"
  } else { Warn "couldn't fetch rcedit - the default Godot icon will be used" }
} else { Skip "skipped (Godot or logo.ico missing)" }

# ---- hook paths: the permission/notify hooks use absolute paths --------------
Step 9 "Point the Claude hooks at this install"
foreach ($cfg in @("$APP\.claude\settings.json", "$APP\workspace\.claude\settings.json")) {
  if (Test-Path $cfg) {
    $txt = Get-Content $cfg -Raw
    $txt = [regex]::Replace($txt, '"command":\s*"[^"]*?([\w-]+\.ps1)"', { param($m)
      '"command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"' +
      ($APP -replace '\\','\\') + '\\daemon\\' + $m.Groups[1].Value + '\""' })
    Set-Content $cfg $txt -Encoding utf8
  }
}
Ok "hooks now resolve to the install path"

# ---- CLI on PATH + Start Menu shortcut ---------------------------------------
Step 10 "Add 'bagidea' to PATH + Start Menu shortcut"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$APP*") {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$APP", "User"); Ok "added bagidea to PATH (open a new terminal)" }
else { Skip "already on PATH" }
if (Test-Path $exe) {
  $ws = New-Object -ComObject WScript.Shell
  $lnk = $ws.CreateShortcut([IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs\BagIdea Office.lnk"))
  $lnk.TargetPath = $exe; $lnk.WorkingDirectory = Split-Path $exe; $lnk.Save()
  Ok "created Start Menu shortcut"
}

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "   Done!" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "   First time: open a NEW terminal and run  claude  to log in." -ForegroundColor Yellow
Write-Host "   Then:       bagidea start    (or Start Menu > BagIdea Office)" -ForegroundColor Cyan
Write-Host ""
if (Test-Path $exe) {
  $go = Read-Host "  Launch it now? (y/n)"
  if ($go -eq "y") { Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) }
}
