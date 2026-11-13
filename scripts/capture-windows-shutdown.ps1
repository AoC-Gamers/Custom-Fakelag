param(
 [Parameter(Mandatory)][string]$TrialState,
 [Parameter(Mandatory)][string]$PrivateDirectory,
 [string]$Debugger = 'C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2611.4001.0_x64__8wekyb3d8bbwe\x86\cdb.exe'
)
$ErrorActionPreference = 'Stop'
$trial = Get-Content -LiteralPath $TrialState -Raw | ConvertFrom-Json
$process = Get-CimInstance Win32_Process -Filter "ProcessId=$($trial.server_pid)"
$expected = [IO.Path]::GetFullPath($trial.argv[0])
if (-not $process -or $process.ExecutablePath -ine $expected) { throw 'Owned server path mismatch' }
$created = ([DateTimeOffset]$process.CreationDate).ToUnixTimeSeconds()
if ($created -lt [Math]::Floor($trial.started)) { throw 'Process predates trial receipt' }
$private = [IO.Path]::GetFullPath($PrivateDirectory)
if ($private -match '(?i)OneDrive' -or $private.StartsWith((Split-Path -Parent $PSScriptRoot), [StringComparison]::OrdinalIgnoreCase)) { throw 'Dumps must stay outside OneDrive and Git' }
New-Item -ItemType Directory -Path $private -Force | Out-Null
$tag = "$($trial.row)_$($trial.scenario)_$($trial.repeat)_$($trial.server_pid)"
$script = Join-Path $private "$tag.cdb"
$log = Join-Path $private "$tag.debugger.log"
$dump = (Join-Path $private "$tag.dmp").Replace('\','/')
if ((Test-Path -LiteralPath $script) -or (Test-Path -LiteralPath $dump)) { throw 'Never overwrite diagnostic evidence' }
# Symbol downloads and disassembly are done offline, after the owned child exits.
$symbols = Join-Path $private 'symbols'
$capture = ".echo FINAL_SECOND_CHANCE;.dump /ma $dump;.exr -1;r;kv;~* kb;lm;gn"
@(
 ".sympath $symbols",
 'sxd av',
 "sxd -c2 `"$capture`" av",
 "sxd -c2 `"$capture`" 0xc0000409",
 '.echo CAPTURE_READY',
 'g'
) | Set-Content -LiteralPath $script -Encoding ascii
$arguments = @('-G','-p',"$($trial.server_pid)",'-logo',$log,'-cf',$script)
$quoted = ($arguments | ForEach-Object { if($_.Contains('"')) { throw 'Invalid quote' }; '"'+$_+'"' }) -join ' '
$debug = Start-Process -FilePath $Debugger -ArgumentList $quoted -WindowStyle Hidden -PassThru
[ordered]@{server_pid=$trial.server_pid;debugger_pid=$debug.Id;debugger=$Debugger;commands=$script;log=$log;dump=$dump;note='Debugger exit is not the server exit. Trial collector retains the actual server handle.'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $private "$tag.receipt.json")
