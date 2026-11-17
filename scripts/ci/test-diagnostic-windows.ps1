$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'MSVC toolchain not found' }
$vcvars = Join-Path $installation 'VC\Auxiliary\Build\vcvarsall.bat'
$environment = cmd /c """$vcvars"" x86 >nul && set"
if ($LASTEXITCODE) { throw 'MSVC x86 initialization failed' }
foreach ($line in $environment) {
  if ($line -match '^(.*?)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
}
$root = (Get-Location).Path
$deps = Join-Path $root '.deps\exts-windows'
$python = Join-Path $deps '.venv-windows\Scripts\python.exe'
$build = Join-Path $root '.build\steam-debug'
New-Item -ItemType Directory -Force (Join-Path $build 'test-data') | Out-Null
Push-Location $build
try {
  & cl /nologo /std:c++14 /EHsc /W4 /D_CRT_SECURE_NO_WARNINGS "$root\diagnostics\steam_lifecycle_debug\tests.cpp" /Fe:tests.exe /link advapi32.lib
  if ($LASTEXITCODE) { throw 'Diagnostic fixture compilation failed' }
  & .\tests.exe (Join-Path $build 'test-data')
  if ($LASTEXITCODE) { throw 'Diagnostic fixture failed' }
  & $python "$root\configure.py" --sdks l4d2 --hl2sdk-root $deps --mms-path "$deps\mmsource-1.12" --sm-path "$deps\sourcemod-1.12" --enable-optimize --steam-lifecycle-debug
  if ($LASTEXITCODE) { throw 'Diagnostic configuration failed' }
  & $python -c 'import sys; from ambuild2.run import cli_run; sys.exit(cli_run())'
  if ($LASTEXITCODE) { throw 'Diagnostic build failed' }
} finally { Pop-Location }
