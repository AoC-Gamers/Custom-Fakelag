$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

function Import-DotEnv {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return
  }

  foreach ($line in Get-Content $Path) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) {
      continue
    }
    if ($trimmed -notmatch "^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$") {
      continue
    }

    $name = $matches[1]
    $value = $matches[2].Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    if (-not [System.Environment]::GetEnvironmentVariable($name, "Process")) {
      [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
  }
}

Import-DotEnv (Join-Path $root ".env")

$depsDir = if ($env:DEPS_DIR) { $env:DEPS_DIR } else { Join-Path $root ".deps" }
$buildDir = if ($env:BUILD_DIR) { $env:BUILD_DIR } else { Join-Path $root ".build\windows-l4d2" }
$hl2sdkDir = if ($env:HL2SDK_DIR) { $env:HL2SDK_DIR } else { Join-Path $depsDir "hl2sdk-l4d2" }
$sourcemodDir = if ($env:SOURCEMOD_DIR) { $env:SOURCEMOD_DIR } else { Join-Path $depsDir "sourcemod-1.12" }
$mmsourceDir = if ($env:MMSOURCE_DIR) { $env:MMSOURCE_DIR } else { Join-Path $depsDir "mmsource-1.12" }
$venvDir = if ($env:VENV_DIR) { $env:VENV_DIR } else { Join-Path $depsDir ".venv-windows" }
$configureScript = if ($env:CONFIGURE_SCRIPT) { $env:CONFIGURE_SCRIPT } else { Join-Path $root "configure.py" }
$manifestPath = if ($env:MANIFEST_PATH) { $env:MANIFEST_PATH } else { Join-Path $root "plugin-package-map.json" }

$venvPython = Join-Path $venvDir "Scripts\python.exe"
$venvAmbuild = Join-Path $venvDir "Scripts\ambuild.exe"

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

  $searchRoots = @(
    "C:\Program Files\Microsoft Visual Studio",
    "C:\Program Files (x86)\Microsoft Visual Studio"
  )
  foreach ($root in $searchRoots) {
    if (-not (Test-Path $root)) {
      continue
    }
    $vcvarsall = Get-ChildItem $root -Recurse -Filter vcvarsall.bat -ErrorAction SilentlyContinue |
      Select-Object -First 1 -ExpandProperty FullName
    if ($vcvarsall) {
      return $vcvarsall
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

foreach ($requiredDir in @($hl2sdkDir, $sourcemodDir, $mmsourceDir)) {
  if (-not (Test-Path $requiredDir)) {
    throw "Missing required directory: $requiredDir"
  }
}

if (-not (Test-Path $venvPython)) {
  throw "Missing Python venv at $venvDir. Run scripts/fetch-windows-deps.ps1 first."
}

if (-not (Test-Path $venvAmbuild)) {
  throw "Missing AMBuild in $venvDir. Run scripts/fetch-windows-deps.ps1 first."
}

$buildExtensionsJson = & $venvPython -c "import json,sys; m=json.load(open(sys.argv[1], encoding='utf-8')); [print(f'{bucket}|{ext}') for bucket, extensions in m.get('build', {}).get('extensions', {}).items() for ext in extensions]" $manifestPath
$buildExtensionRecords = @($buildExtensionsJson | Where-Object { $_ })

if ($buildExtensionRecords.Count -ne 1) {
  throw "Expected exactly one extension in build.extensions, found $($buildExtensionRecords.Count)."
}

$extensionBucket, $extensionStem = $buildExtensionRecords[0].Split("|", 2)

$cl = Get-Command cl.exe -ErrorAction SilentlyContinue
if (-not $cl) {
  $vcvarsall = Find-VcVarsAll
  if (-not $vcvarsall) {
    throw "MSVC x86 toolchain was not found. Install Visual Studio Build Tools with C++ x86/x64 support or set VCVARSALL_PATH."
  }

  Import-VcVarsEnvironment $vcvarsall
  $cl = Get-Command cl.exe -ErrorAction SilentlyContinue
  if (-not $cl) {
    throw "MSVC environment was initialized from $vcvarsall, but cl.exe is still unavailable."
  }
}

Remove-Item -Recurse -Force $buildDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $buildDir | Out-Null

Push-Location $buildDir
try {
  & $venvPython $configureScript `
    --sdks l4d2 `
    --hl2sdk-root $depsDir `
    --mms-path $mmsourceDir `
    --sm-path $sourcemodDir `
    --enable-optimize

  if (-not (Test-Path ".\.ambuild2\vars")) {
    throw "AMBuild configure did not produce .ambuild2\vars."
  }

  & $venvAmbuild
}
finally {
  Pop-Location
}

$packageDir = Join-Path $buildDir "package\addons\sourcemod\extensions"
$extBin = Get-ChildItem $packageDir -Filter "$extensionStem.ext*.dll" | Select-Object -First 1 -ExpandProperty FullName
if (-not $extBin) {
  throw "Build completed but no $extensionStem extension binary was found in $packageDir."
}

$canonicalExtDir = if ($extensionBucket -eq "root") { $packageDir } else { Join-Path $packageDir $extensionBucket }
New-Item -ItemType Directory -Force $canonicalExtDir | Out-Null
$canonicalExtBin = Join-Path $canonicalExtDir "$extensionStem.ext.dll"
if ($extBin -ne $canonicalExtBin) {
  Move-Item $extBin $canonicalExtBin -Force
  $extBin = $canonicalExtBin
}

Write-Host "Build complete."
Write-Host "BUILD_DIR=$buildDir"
Write-Host "EXTENSION=$extBin"
