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
$hl2sdkDir = if ($env:HL2SDK_DIR) { $env:HL2SDK_DIR } else { Join-Path $depsDir "hl2sdk-l4d2" }
$sourcemodDir = if ($env:SOURCEMOD_DIR) { $env:SOURCEMOD_DIR } else { Join-Path $depsDir "sourcemod-1.12" }
$mmsourceDir = if ($env:MMSOURCE_DIR) { $env:MMSOURCE_DIR } else { Join-Path $depsDir "mmsource-1.12" }
$ambuildDir = if ($env:AMBUILD_DIR) { $env:AMBUILD_DIR } else { Join-Path $depsDir "ambuild" }
$venvDir = if ($env:VENV_DIR) { $env:VENV_DIR } else { Join-Path $depsDir ".venv-windows" }

function Clone-OrUpdate {
  param(
    [string]$RepoUrl,
    [string]$RepoDir,
    [string]$Branch
  )

  if (Test-Path (Join-Path $RepoDir ".git")) {
    git -C $RepoDir fetch --all --tags --prune
    git -C $RepoDir checkout $Branch
    git -C $RepoDir pull --ff-only
    return
  }

  git clone --branch $Branch --single-branch $RepoUrl $RepoDir
}

function Sync-SubmodulesIfPresent {
  param([string]$RepoDir)

  if (-not (Test-Path (Join-Path $RepoDir ".gitmodules"))) {
    return
  }

  git -C $RepoDir submodule sync --recursive
  git -C $RepoDir submodule update --init --recursive
}

New-Item -ItemType Directory -Force $depsDir | Out-Null

Clone-OrUpdate "https://github.com/alliedmodders/hl2sdk.git" $hl2sdkDir "l4d2"
Clone-OrUpdate "https://github.com/alliedmodders/sourcemod.git" $sourcemodDir "1.12-dev"
Clone-OrUpdate "https://github.com/alliedmodders/metamod-source.git" $mmsourceDir "1.12-dev"
Clone-OrUpdate "https://github.com/alliedmodders/ambuild.git" $ambuildDir "master"

Sync-SubmodulesIfPresent $sourcemodDir
Sync-SubmodulesIfPresent $mmsourceDir

if (-not (Test-Path $venvDir)) {
  python -m venv $venvDir
}

$venvPython = Join-Path $venvDir "Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
  throw "Missing Python in venv: $venvPython"
}

& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install $ambuildDir

Write-Host "Dependencies ready."
Write-Host "ROOT_DIR=$root"
Write-Host "DEPS_DIR=$depsDir"
Write-Host "HL2SDK_DIR=$hl2sdkDir"
Write-Host "SOURCEMOD_DIR=$sourcemodDir"
Write-Host "MMSOURCE_DIR=$mmsourceDir"
Write-Host "AMBUILD_DIR=$ambuildDir"
Write-Host "VENV_DIR=$venvDir"
