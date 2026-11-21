# 쿼터뷰액션.exe 만들기: *.lua 를 묶어서 love.exe 뒤에 붙이고 필요한 dll 을 복사한다
# 사용: powershell -ExecutionPolicy Bypass -File build.ps1
# 게임이 켜져 있으면 강제로 끄고 빌드한다 (유저 요청: 새버전 파일 따로 만들지 말 것)
$ErrorActionPreference = "Stop"
$src  = $PSScriptRoot
$dst  = Join-Path $src "실행파일"
$love = "C:\Program Files\LOVE"
$name = "쿼터뷰액션"
New-Item -ItemType Directory -Force $dst | Out-Null

# 켜져 있는 게임(예전 _새버전 포함)을 강제로 끈다
$procs = @(Get-Process -Name $name, ($name + "_새버전") -ErrorAction SilentlyContinue)
if ($procs.Count -gt 0) {
  $procs | Stop-Process -Force
  $procs | ForEach-Object { try { $_.WaitForExit(3000) | Out-Null } catch {} }
  Start-Sleep -Milliseconds 300
  Write-Output "켜져 있던 게임을 강제로 껐음"
}

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

# 파일 잠금이 늦게 풀릴 수 있어서 몇 번 다시 시도
$main = Join-Path $dst "$name.exe"
$ok = $false
for ($i = 0; $i -lt 10 -and -not $ok; $i++) {
  try { [IO.File]::WriteAllBytes($main, $bytes); $ok = $true } catch { Start-Sleep -Milliseconds 300 }
}
if (-not $ok) { Write-Output "실패: $main 을 쓸 수 없음"; exit 1 }
$alt = Join-Path $dst ($name + "_새버전.exe")
if (Test-Path $alt) { Remove-Item $alt -Force -ErrorAction SilentlyContinue }   # 예전 방식의 새버전 파일 정리

Get-ChildItem $love -Filter *.dll | Copy-Item -Destination $dst -Force
Copy-Item (Join-Path $love "license.txt") $dst -Force
Write-Output "$name.exe 만듦 → $dst"