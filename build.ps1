# 악귀사냥꾼.exe 만들기: main.lua, conf.lua 를 묶어서 love.exe 뒤에 붙이고 필요한 dll 을 복사한다
# 사용: powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = "Stop"
$src  = $PSScriptRoot
$dst  = Join-Path $src "실행파일"
$love = "C:\Program Files\LOVE"
$name = "쿼터뷰액션"
if (Get-Process -Name $name -ErrorAction SilentlyContinue) { Write-Output "$name.exe 실행 중 - 창을 닫고 다시 실행하세요"; exit 1 }
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
[IO.File]::WriteAllBytes((Join-Path $dst "$name.exe"), $bytes)
Get-ChildItem $love -Filter *.dll | Copy-Item -Destination $dst -Force
Copy-Item (Join-Path $love "license.txt") $dst -Force
Write-Output "$name.exe 만듦 → $dst"
