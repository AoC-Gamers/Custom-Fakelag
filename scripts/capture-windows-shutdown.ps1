param(
 [Parameter(Mandatory)][string]$TrialState,
 [Parameter(Mandatory)][string]$PrivateDirectory,
 [switch]$TraceFirstChance,
 [string]$ContextSnapshot,
 [string]$Debugger = 'C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2611.4001.0_x64__8wekyb3d8bbwe\x86\cdb.exe'
)
$ErrorActionPreference = 'Stop'
$trial = Get-Content -LiteralPath $TrialState -Raw | ConvertFrom-Json
$process = Get-CimInstance Win32_Process -Filter "ProcessId=$($trial.server_pid)"
$expected = [IO.Path]::GetFullPath($trial.argv[0])
if (-not $process -or $process.ExecutablePath -ine $expected) { throw 'Owned server path mismatch' }
$created = ([DateTimeOffset]$process.CreationDate).ToUnixTimeSeconds()
if ($created -lt [Math]::Floor($trial.started) -or $created -gt [Math]::Ceiling($trial.started)+10) { throw 'Process creation does not match the trial launch window' }
$private = [IO.Path]::GetFullPath($PrivateDirectory)
if ($private -match '(?i)OneDrive' -or $private.StartsWith((Split-Path -Parent $PSScriptRoot), [StringComparison]::OrdinalIgnoreCase)) { throw 'Dumps must stay outside OneDrive and Git' }
if ($private -match '[;"\r\n\s]') { throw 'Use a private debugger path without whitespace or command delimiters' }
New-Item -ItemType Directory -Path $private -Force | Out-Null
$tag = "$($trial.row)_$($trial.scenario)_$($trial.repeat)_$($trial.server_pid)"
$script = Join-Path $private "$tag.cdb"
$log = Join-Path $private "$tag.debugger.log"
$dump = (Join-Path $private "$tag.dmp").Replace('\','/')
$firstDump = (Join-Path $private "$tag.first-chance.dmp").Replace('\','/')
if ((Test-Path -LiteralPath $script) -or (Test-Path -LiteralPath $dump)) { throw 'Never overwrite diagnostic evidence' }
# Symbol downloads and disassembly are done offline, after the owned child exits.
$symbols = Join-Path $private 'symbols'
New-Item -ItemType Directory -Path $symbols -Force | Out-Null
$capture = ".echo FINAL_SECOND_CHANCE;.dump /ma $dump;.exr -1;r;kv;~* kb;lm;gn"
$firstCapture = '.echo FIRST_CHANCE_AV;.if (@$t0 == 0) {.dump /ma ' + $firstDump + ';r @$t0=1;};.exr -1;r;kv;~* kb;gn'
$first = if ($TraceFirstChance) { '-c "' + $firstCapture + '" ' } else { '' }
$watch = @()
if ($ContextSnapshot) {
 $context = Get-Content -LiteralPath $ContextSnapshot -Raw | ConvertFrom-Json
 if ($context.server_pid -ne $trial.server_pid -or $context.server_sha256 -ne 'a93ec916a8f26fbea85688c321d2ba8dd346d435fab09a0b926dd950c2e1ea12') { throw 'Context does not match this owned server' }
 if (([DateTimeOffset]::UtcNow - [DateTimeOffset]$context.captured_utc).TotalSeconds -gt 30) { throw 'Capture a fresh context snapshot before watching it' }
 foreach ($offset in @(4,8)) {
  $field = $context.fields | Where-Object offset -eq $offset
  if (-not $field.object -or $field.vtable_location.module -ne 'steamclient.dll') { throw 'Expected a live Steam interface before installing the watch' }
  $address = '0x{0:x}' -f [long]$field.object
  $watch += ('ba w4 ' + $address + ' ".echo CONTEXT_OBJECT_' + $offset + '_WRITE;r;kv;gc"')
 }
 $address = '0x{0:x}' -f ([long]$context.context_address + 4)
 $watch += ('ba w4 ' + $address + ' ".echo CONTEXT_POINTER_WRITE;r;kv;gc"')
}
$commands = @(
 ".sympath $symbols",
 'r @$t0=0',
 'sxd av',
 "sxd ${first}-c2 `"$capture`" av",
 "sxd -c2 `"$capture`" 0xc0000409"
) + $watch + @(
 '.echo CAPTURE_READY',
 'g'
)
$commands | Set-Content -LiteralPath $script -Encoding ascii
$arguments = @('-G','-p',"$($trial.server_pid)",'-logo',$log,'-cf',$script)
$quoted = ($arguments | ForEach-Object { if($_.Contains('"')) { throw 'Invalid quote' }; '"'+$_+'"' }) -join ' '
$debug = Start-Process -FilePath $Debugger -ArgumentList $quoted -WindowStyle Hidden -PassThru
[ordered]@{server_pid=$trial.server_pid;debugger_pid=$debug.Id;debugger=$Debugger;commands=$script;log=$log;dump=$dump;first_chance_dump=if($TraceFirstChance){$firstDump}else{$null};note='Debugger exit is not the server exit. Trial collector retains the actual server handle. A first-chance dump is not proof of an unhandled final exception.'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $private "$tag.receipt.json")
