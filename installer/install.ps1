# BagIdea Office — installer (closed-source friendly).
# Installs from a RELEASE ZIP — no source repo access, no Rust build needed
# (the shell binary is bundled). Get the zip from a URL you control or a
# local file; the office app + deps land in %LOCALAPPDATA%\BagIdeaOffice.
#
#   # from a hosted zip:
#   $env:BAGIDEA_RELEASE_URL = "https://your-host/BagIdeaOffice-latest.zip"
#   irm https://your-host/install.ps1 | iex
#
#   # from a local zip the owner sent you:
#   .\install.ps1 -Zip .\BagIdeaOffice-latest.zip
param([string]$Zip = $env:BAGIDEA_RELEASE_URL)
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$APPDIR = Join-Path $env:LOCALAPPDATA "BagIdeaOffice"
$APP    = Join-Path $APPDIR "app"
$GODOTV = "4.6.3"

function Step($n, $m) { Write-Host ""; Write-Host "  [$n] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "      + $m" -ForegroundColor Green }
function Skip($m) { Write-Host "      - $m" -ForegroundColor DarkGray }
function Warn($m) { Write-Host "      ! $m" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Cyan
Write-Host "   BagIdea Office — INSTALLER" -ForegroundColor Cyan
Write-Host "  ===========================================" -ForegroundColor Cyan

if (-not $Zip) {
  Warn "ไม่พบ release zip — ระบุด้วย -Zip <path|url> หรือตั้ง `$env:BAGIDEA_RELEASE_URL"
  Warn "ขอไฟล์ติดตั้งจากผู้พัฒนา (โปรเจคนี้เป็น private)"
  exit 1
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Warn "ไม่พบ winget — ติดตั้ง 'App Installer' จาก Microsoft Store ก่อน"; exit 1
}

# ---- deps (no Rust — the shell binary ships in the zip) ----------------------
Step 1 "Node.js LTS"
if (Get-Command node -ErrorAction SilentlyContinue) { Skip "มีอยู่แล้ว ($(node --version))" }
else { winget install --id OpenJS.NodeJS.LTS -e --silent --accept-package-agreements --accept-source-agreements; Ok "ติดตั้งแล้ว" }

Step 2 "Claude Code CLI (สมองของ agents)"
if (Get-Command claude -ErrorAction SilentlyContinue) { Skip "มีอยู่แล้ว" }
else { npm install -g @anthropic-ai/claude-code; Ok "ติดตั้งแล้ว — login ครั้งแรกด้วยคำสั่ง: claude" }

Step 3 "Godot $GODOTV (ตัว render โลกออฟฟิศ)"
$gdir = Join-Path $APPDIR "tools\godot"
$gexe = Join-Path $gdir "Godot_v$GODOTV-stable_win64.exe"
if (Test-Path $gexe) { Skip "มีอยู่แล้ว" }
else {
  New-Item -ItemType Directory -Force $gdir | Out-Null
  $z = Join-Path $env:TEMP "godot.zip"
  Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/$GODOTV-stable/Godot_v$GODOTV-stable_win64.exe.zip" -OutFile $z
  Expand-Archive -Path $z -DestinationPath $gdir -Force; Remove-Item $z
  if (Test-Path $gexe) { Ok "ติดตั้งแล้ว" } else { Warn "แตก zip แล้วไม่พบ exe" }
}
[Environment]::SetEnvironmentVariable("BAGIDEA_GODOT", $gexe, "User")

# ---- the app (from the release zip) ------------------------------------------
Step 4 "ติดตั้งตัวโปรแกรม (จาก release zip)"
$tmp = Join-Path $env:TEMP "bagidea_dl.zip"
if ($Zip -match '^https?://') {
  Write-Host "      ดาวน์โหลด..." -ForegroundColor DarkGray
  Invoke-WebRequest -Uri $Zip -OutFile $tmp; $src = $tmp
} elseif (Test-Path $Zip) { $src = (Resolve-Path $Zip).Path }
else { Warn "ไม่พบไฟล์ zip: $Zip"; exit 1 }

# Preserve user data across re-installs (registry/sessions/projects/keys/etc).
$backup = Join-Path $env:TEMP "bagidea_userdata"
if (Test-Path $APP) {
  if (Test-Path $backup) { Remove-Item -Recurse -Force $backup }
  New-Item -ItemType Directory -Force $backup | Out-Null
  foreach ($f in @("daemon\registry.json","daemon\sessions.json","daemon\projects.json",
      "daemon\jobs.json","daemon\calendar.json","daemon\notes.json","daemon\layout.json","daemon\stats.json")) {
    $p = Join-Path $APP $f; if (Test-Path $p) { Copy-Item $p (Join-Path $backup (Split-Path $f -Leaf)) -Force }
  }
  if (Test-Path (Join-Path $APP "daemon\i18n")) { Copy-Item (Join-Path $APP "daemon\i18n") (Join-Path $backup "i18n") -Recurse -Force }
  Remove-Item -Recurse -Force $APP
}
New-Item -ItemType Directory -Force $APP | Out-Null
Expand-Archive -Path $src -DestinationPath $APP -Force
if (Test-Path $backup) {
  Get-ChildItem $backup -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $APP ("daemon\" + $_.Name)) -Force }
  if (Test-Path (Join-Path $backup "i18n")) { Copy-Item (Join-Path $backup "i18n") (Join-Path $APP "daemon\i18n") -Recurse -Force }
  Ok "กู้คืนข้อมูลผู้ใช้เดิมแล้ว"
}
Ok "ติดตั้งที่ $APP"

Step 5 "ทำ exe แบรนด์ (icon BAG IDEA — ไม่ให้เห็น Godot)"
$bindir = Join-Path $APP "godot\bin"
$branded = Join-Path $bindir "BagIdeaOffice.exe"
$ico = Join-Path $APP "godot\assets\brand\logo.ico"
if ((Test-Path $gexe) -and (Test-Path $ico)) {
  New-Item -ItemType Directory -Force $bindir | Out-Null
  $rcedit = Join-Path $env:TEMP "rcedit-x64.exe"
  if (-not (Test-Path $rcedit)) {
    try { Invoke-WebRequest -Uri "https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe" -OutFile $rcedit } catch {}
  }
  Copy-Item $gexe $branded -Force
  if (Test-Path $rcedit) {
    & $rcedit $branded --set-icon $ico --set-version-string "FileDescription" "BagIdea Office" --set-version-string "ProductName" "BagIdea Office" 2>$null
    Ok "ทำ exe แบรนด์แล้ว — taskbar เป็น BAG IDEA ตั้งแต่เปิด"
  } else { Warn "ดาวน์โหลด rcedit ไม่ได้ — จะใช้ icon Godot ปกติ" }
} else { Skip "ข้าม (ไม่พบ Godot หรือ logo.ico)" }

# ---- hook paths: the permission/notify hooks use absolute paths --------------
Step 6 "ตั้งค่า hooks ให้ตรงเครื่องนี้"
foreach ($cfg in @("$APP\.claude\settings.json", "$APP\workspace\.claude\settings.json")) {
  if (Test-Path $cfg) {
    $txt = Get-Content $cfg -Raw
    $txt = [regex]::Replace($txt, '"command":\s*"[^"]*?([\w-]+\.ps1)"', { param($m)
      '"command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"' +
      ($APP -replace '\\','\\') + '\\daemon\\' + $m.Groups[1].Value + '\""' })
    Set-Content $cfg $txt -Encoding utf8
  }
}
Ok "hooks ชี้มาที่ตำแหน่งติดตั้งแล้ว"

# ---- CLI on PATH + Start Menu shortcut ---------------------------------------
Step 7 "คำสั่ง bagidea + shortcut"
$exe = Join-Path $APP "shell\target\release\bagidea-office-shell.exe"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$APP*") {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$APP", "User"); Ok "เพิ่ม bagidea เข้า PATH แล้ว (เปิดเทอร์มินัลใหม่)" }
else { Skip "อยู่ใน PATH แล้ว" }
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut([IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs\BagIdea Office.lnk"))
$lnk.TargetPath = $exe; $lnk.WorkingDirectory = Split-Path $exe; $lnk.Save()
Ok "สร้าง Start Menu shortcut แล้ว"

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "   ติดตั้งเสร็จแล้ว!" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "   ครั้งแรก: เปิดเทอร์มินัลใหม่ รัน  claude  เพื่อ login Claude" -ForegroundColor Yellow
Write-Host "   จากนั้น:  bagidea start   (หรือ Start Menu > BagIdea Office)" -ForegroundColor Cyan
Write-Host ""
$go = Read-Host "  เปิดโปรแกรมเลยไหม? (y/n)"
if ($go -eq "y" -and (Test-Path $exe)) { Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) }
