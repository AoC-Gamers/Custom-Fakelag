param(
 [Parameter(Mandatory)][string]$PrivateDirectory,
 [string]$Python = 'C:\Users\israe\AppData\Local\mise\installs\python\3.12.13\python.exe',
 [string]$VcVars = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$private = [IO.Path]::GetFullPath($PrivateDirectory)
if ($private -match '(?i)OneDrive' -or $private.StartsWith($repo,[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture outputs must stay outside Git and OneDrive' }
if (Test-Path -LiteralPath $private) { throw 'Use a new output directory; never overwrite test evidence' }
foreach($value in @($private,$repo,$VcVars)) {
 if($value -match '[%!&|<>^"\r\n]') { throw 'Command delimiters are not accepted in fixture paths' }
}
New-Item -ItemType Directory -Path $private | Out-Null
$source = Join-Path $repo 'tests\ShutdownExitDetachFixture.cpp'
$dll = Join-Path $private 'ExitDetach.dll'
$exe = Join-Path $private 'ExitDetach.exe'
$build = Join-Path $private 'build.cmd'
@(
 "@call `"$VcVars`" x86 >nul",
 '@if errorlevel 1 exit /b 1',
 "@cl /nologo /LD /O2 /MT /Fo`"$private\dll.obj`" `"$source`" /link /OUT:`"$dll`" /IMPLIB:`"$private\fixture.lib`"",
 '@if errorlevel 1 exit /b 1',
 "@cl /nologo /O2 /MT /DEXIT_DETACH_EXE /Fo`"$private\exe.obj`" `"$source`" /link /OUT:`"$exe`""
) | Set-Content -LiteralPath $build -Encoding ascii
& cmd.exe /c $build
if($LASTEXITCODE -ne 0) { throw 'Fixture compilation failed' }
& $Python (Join-Path $repo 'tests\test_windows_shutdown_collection.py') $exe $dll
if($LASTEXITCODE -ne 0) { throw 'Collection regression failed' }
