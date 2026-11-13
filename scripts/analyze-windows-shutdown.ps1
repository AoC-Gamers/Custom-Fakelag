param(
 [Parameter(Mandatory)][string]$Dump,
 [string]$Debugger = 'C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2611.4001.0_x64__8wekyb3d8bbwe\x86\cdb.exe'
)
$ErrorActionPreference = 'Stop'
$dumpPath = (Resolve-Path -LiteralPath $Dump).Path
if ($dumpPath -match '(?i)OneDrive') { throw 'Dump must remain private' }
$folder = Split-Path -Parent $dumpPath
$commands = $dumpPath + '.analysis.cdb'
$log = $dumpPath + '.analysis.log'
if (Test-Path -LiteralPath $log) { throw 'Never overwrite analysis evidence' }
$symbols = Join-Path $folder 'symbols'
# Separate command lines let disassembly of an invalid instruction address fail
# without preventing the remaining offline analysis or debugger exit.
@(
 ".sympath srv*$symbols*https://msdl.microsoft.com/download/symbols;srv*$symbols*https://sourcemod.net/symbols",
 '.exr -1', '.ecxr', 'r', 'kv', '~* kb', 'lmv', 'u @eip-20 L30', '!analyze -v', 'q'
) | Set-Content -LiteralPath $commands -Encoding ascii
$arguments = @('-z',$dumpPath,'-logo',$log,'-cf',$commands)
$quoted = ($arguments | ForEach-Object { if($_.Contains('"')) { throw 'Invalid quote' }; '"'+$_+'"' }) -join ' '
$analysis = Start-Process -FilePath $Debugger -ArgumentList $quoted -WindowStyle Hidden -PassThru
[ordered]@{analysis_pid=$analysis.Id;commands=$commands;log=$log;dump_sha256=(Get-FileHash -LiteralPath $dumpPath -Algorithm SHA256).Hash.ToLowerInvariant();note='Offline dump analysis; no live process is resumed or terminated.'} | ConvertTo-Json
