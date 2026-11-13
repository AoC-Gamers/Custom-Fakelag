param([Parameter(Mandatory=$true)][string]$EnginePath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$deps = if ($env:DEPS_DIR) { $env:DEPS_DIR } else { Join-Path $root '.deps\exts-windows' }
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$vcvars = $env:VCVARSALL_PATH
if (-not $vcvars) {
  $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  $vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvarsall.bat'
}
$environment = cmd /c """$vcvars"" x86 >nul && set"
if ($LASTEXITCODE) { throw 'Could not initialize MSVC x86' }
foreach ($line in $environment) {
  if ($line -match '^(.*?)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
}
$sdk = Join-Path $deps 'hl2sdk-l4d2'
$build = Join-Path $root '.build\windows-sdk-contract'
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
  $instrumentation = @()
  if ($env:CUSTOM_FAKELAG_ASAN -eq '1') { $instrumentation += '/fsanitize=address' }
  & cl @instrumentation /Zi /nologo /std:c++17 /EHsc /W4 /DWIN32 /DCOMPILER_MSVC /DCOMPILER_MSVC32 /D_CRT_SECURE_NO_WARNINGS `
    /I "$sdk\public" /I "$sdk\public\tier1" /I "$sdk\public\tier0" /I "$sdk\public\mathlib" `
    "$root\tests\windows_sdk_contract.cpp" "$root\extension\network\L4D2PacketAdapter.cpp" `
    /Fe:windows_sdk_contract.exe /link "$sdk\lib\public\tier1.lib" "$sdk\lib\public\tier0.lib" `
    "$sdk\lib\public\vstdlib.lib" advapi32.lib ws2_32.lib
  if ($LASTEXITCODE) { throw "SDK contract compilation failed: $LASTEXITCODE" }
  $env:PATH = (Split-Path -Parent ([IO.Path]::GetFullPath($EnginePath))) + ';' + $env:PATH
  & .\windows_sdk_contract.exe ([IO.Path]::GetFullPath($EnginePath))
  if ($LASTEXITCODE) { throw "SDK contract tests failed: $LASTEXITCODE" }
} finally { Pop-Location }

