$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'MSVC toolchain not found' }
$vcvars = Join-Path $installation 'VC\Auxiliary\Build\vcvarsall.bat'
$python = (Get-Command python.exe -ErrorAction Stop).Source
$temporary = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$private = Join-Path $temporary ('shutdown-collection-' + [guid]::NewGuid())
pwsh -NoProfile -File scripts/ci/test-windows-shutdown-collection.ps1 -PrivateDirectory $private -Python $python -VcVars $vcvars
