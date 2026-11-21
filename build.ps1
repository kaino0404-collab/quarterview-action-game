# 쿼터뷰액션.exe 만들기: *.lua 를 묶어서 love.exe 뒤에 붙이고 필요한 dll 을 복사한다
# 사용: powershell -ExecutionPolicy Bypass -File build.ps1
# 게임이 켜져 있으면 exe 를 덮어쓸 수 없으므로 "쿼터뷰액션_새버전.exe" 로 따로 만든다 (언제든 바로 빌드)
$ErrorActionPreference = "Stop"
$src  = $PSScriptRoot
$dst  = Join-Path $src "실행파일"
$love = "C:\Program Files\LOVE"
$name = "쿼터뷰액션"
New-Item -ItemType Directory -Force $dst | Out-Null

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $env:TEMP "quarterview_build.love"
if (Test-Path $zip) { Remove-Item $zip -Force }
$fs = [System.IO.File]::Open($zip, [System.IO.FileMode]::Create)
$arc = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
function AddFile($path, $entry) {
  # 압축 안 경로는 반드시 / 로 (LÖVE 가 \ 경로를 못 찾는다)
  [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($arc, $path, $entry.Replace("\", "/")) | Out-Null
}
Get-ChildItem $src -Filter *.lua -File | ForEach-Object { AddFile $_.FullName $_.Name }
$arc.Dispose(); $fs.Dispose()
$bytes = [IO.File]::ReadAllBytes((Join-Path $love "love.exe")) + [IO.File]::ReadAllBytes($zip)

$main = Join-Path $dst "$name.exe"
$alt  = Join-Path $dst ($name + "_새버전.exe")
$running = Get-Process -Name $name -ErrorAction SilentlyContinue
$out = $main
if ($running) { $out = $alt }
else {
  try { [IO.File]::WriteAllBytes($main, $bytes) } catch { $out = $alt }
}
if ($out -eq $alt) { [IO.File]::WriteAllBytes($alt, $bytes) }
elseif (Test-Path $alt) { Remove-Item $alt -Force -ErrorAction SilentlyContinue }   # 예전 새버전은 정리

# dll: 없을 때만 복사 (게임이 켜져 있으면 잠겨 있으니 건너뜀)
Get-ChildItem $love -Filter *.dll | ForEach-Object {
  $t = Join-Path $dst $_.Name
  if (-not (Test-Path $t)) { Copy-Item $_.FullName $t }
}
if (-not (Test-Path (Join-Path $dst "license.txt"))) { Copy-Item (Join-Path $love "license.txt") $dst }

if ($out -eq $alt) { Write-Output "게임이 켜져 있어서 새 버전을 따로 만듦 → $alt" }
else { Write-Output "$name.exe 만듦 → $dst" }