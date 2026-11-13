param(
 [Parameter(Mandatory)][ValidateSet('A','B','C','D','E','F','G')][string]$Row,
 [Parameter(Mandatory)][ValidateSet('connected','detached','idle')][string]$Scenario,
 [Parameter(Mandatory)][int]$Repeat,
 [string]$Python = 'C:\Users\israe\AppData\Local\mise\installs\python\3.12.13\python.exe',
 [string]$PrivateRoot = 'C:\Users\israe\Documents\Codex\2026-11-13\tene\work\windows-srcds',
 [string]$DataRoot = 'C:\Users\israe\Documents\Codex\2026-11-13\tene\work\shutdown-private\trials',
 [string]$Runtime = 'D:\SteamLibrary\steamapps\common\Left 4 Dead 2 Dedicated Server\bin\steamclient.dll'
)
$ErrorActionPreference = 'Stop'
if (Get-Process srcds -ErrorAction SilentlyContinue) { throw 'A dedicated server is still active' }
if (-not (Test-Path -LiteralPath (Join-Path $PrivateRoot 'left4dead2\.custom-fakelag-isolated'))) { throw 'Private marker missing' }
$repo = Split-Path -Parent $PSScriptRoot
$name = "${Row}_${Scenario}_${Repeat}"
$commands = Join-Path $DataRoot "$name.commands"
$output = Join-Path $DataRoot "$name.jsonl"
if ((Test-Path -LiteralPath $commands) -or (Test-Path -LiteralPath $output)) { throw 'Use a new trial id; never overwrite evidence' }
New-Item -ItemType Directory -Force $DataRoot | Out-Null
$parts = @((Join-Path $repo 'tests\windows_shutdown_trial.py'), '--root', $PrivateRoot,
 '--runtime', $Runtime, '--row', $Row, '--scenario', $Scenario, '--repeat', "$Repeat",
 '--commands', $commands, '--output', $output)
$line = ($parts | ForEach-Object { if ($_.Contains('"')) { throw 'Invalid quote in argument' }; '"'+$_+'"' }) -join ' '
$driver = Start-Process -FilePath $Python -ArgumentList $line -WorkingDirectory $repo -WindowStyle Hidden `
 -RedirectStandardOutput (Join-Path $DataRoot "$name.stdout") -RedirectStandardError (Join-Path $DataRoot "$name.stderr") -PassThru
[ordered]@{trial=$name;collector_pid=$driver.Id;commands=$commands;state=(Join-Path $DataRoot "$name.state.json")} | ConvertTo-Json
