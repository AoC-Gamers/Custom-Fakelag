Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $Root ".build\tests-windows"
$TestSource = Join-Path $Root "tests\custom_fakelag_tests.cpp"
$LagSystemSource = Join-Path $Root "extension\network\LagSystem.cpp"
$TestExe = Join-Path $BuildDir "custom_fakelag_tests.exe"

function Find-VsWhere {
    $candidates = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe",
        "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Find-VcVarsAll {
    if ($env:VCVARSALL_PATH -and (Test-Path $env:VCVARSALL_PATH)) {
        return $env:VCVARSALL_PATH
    }

    $vswhere = Find-VsWhere
    if ($vswhere) {
        $installationPath = & $vswhere -latest -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installationPath) {
            $vcvarsall = Join-Path $installationPath "VC\Auxiliary\Build\vcvarsall.bat"
            if (Test-Path $vcvarsall) {
                return $vcvarsall
            }
        }
    }

    return $null
}

function Import-VcVarsEnvironment {
    param([string]$VcVarsAllPath)

    $cmdOutput = cmd /c """$VcVarsAllPath"" x86 >nul && set"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to initialize MSVC environment via $VcVarsAllPath"
    }

    foreach ($line in $cmdOutput) {
        if ($line -notmatch "^(.*?)=(.*)$") {
            continue
        }
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$IncludeArgs = @(
    "/I", (Join-Path $Root "extension"),
    "/I", (Join-Path $Root ".deps\hl2sdk-l4d2\public"),
    "/I", (Join-Path $Root ".deps\hl2sdk-l4d2\public\tier1"),
    "/I", (Join-Path $Root ".deps\sourcemod-1.12\public\amtl"),
    "/I", (Join-Path $Root ".deps\sourcemod-1.12\public")
)

$cl = Get-Command cl.exe -ErrorAction SilentlyContinue
if (-not $cl) {
    $vcvarsall = Find-VcVarsAll
    if (-not $vcvarsall) {
        throw "MSVC x86 toolchain was not found. Install Visual Studio Build Tools with C++ x86/x64 support or set VCVARSALL_PATH."
    }

    Import-VcVarsEnvironment $vcvarsall
}

& cl /std:c++17 /EHsc /nologo /W3 /Od /Zi /DUNIT_TEST /Fe:$TestExe $TestSource $LagSystemSource @IncludeArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to compile tests."
}

& $TestExe
if ($LASTEXITCODE -ne 0) {
    throw "Tests failed."
}

Write-Host "Tests passed."
