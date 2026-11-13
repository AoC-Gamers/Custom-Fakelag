param(
  [Parameter(Mandatory)][string]$Python,
  [Parameter(Mandatory)][string]$Srcds,
  [Parameter(Mandatory)][string]$Game,
  [Parameter(Mandatory)][string]$Commands,
  [Parameter(Mandatory)][string]$Output,
  [string]$Ip = '192.168.1.87'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$Srcds = (Resolve-Path -LiteralPath $Srcds).Path
$Game = (Resolve-Path -LiteralPath $Game).Path
if (-not (Test-Path -LiteralPath (Join-Path $Game '.custom-fakelag-isolated'))) { throw 'Private gamedir marker required' }
if (Get-Process srcds -ErrorAction SilentlyContinue) { throw 'Stop the previous dedicated test process first' }
if ((Test-Path -LiteralPath $Commands) -and ([string](Get-Content -LiteralPath $Commands -Raw)).Trim()) { throw 'Use an empty command file' }
$runtime = Join-Path (Split-Path -Parent $Srcds) 'bin\steamclient.dll'
if (-not (Test-Path -LiteralPath $runtime)) { throw 'Missing official dedicated Steam runtime' }
$registry = 'HKCU:\Software\Valve\Steam\ActiveProcess'
$original = (Get-ItemProperty -LiteralPath $registry -Name SteamClientDll).SteamClientDll
function Quote-Argument([string]$Value) {
  if ($Value.Contains('"')) { throw 'Quotes are not valid in these path arguments' }
  return '"' + $Value + '"'
}
$arguments = @((Join-Path $root 'tests\windows_load_order_session.py'), '--srcds', $Srcds,
              '--game', $Game, '--commands', $Commands, '--output', $Output, '--ip', $Ip)
$line = ($arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
$loaded = $null; $server = $null
try {
  # steam_api.dll consults this value even when local redistributables exist.
  # Restore the original immediately after observing the dedicated DLL load.
  # Do not start/restart the desktop client during this short selection window.
  Set-ItemProperty -LiteralPath $registry -Name SteamClientDll -Value $runtime
  $driver = Start-Process -FilePath $Python -ArgumentList $line -WorkingDirectory $root -WindowStyle Hidden `
    -RedirectStandardOutput "$Output.stdout" -RedirectStandardError "$Output.stderr" -PassThru
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 300
    $server = Get-Process srcds -ErrorAction SilentlyContinue
    if ($server) {
      $loaded = $server.Modules | Where-Object ModuleName -eq 'steamclient.dll' | Select-Object -First 1 -ExpandProperty FileName
      if ($loaded) { break }
    }
  }
} finally {
  Set-ItemProperty -LiteralPath $registry -Name SteamClientDll -Value $original
}
$receipt = [ordered]@{driver_pid=$driver.Id; server_pid=$server.Id; original=$original; selected=$runtime;
  loaded=$loaded; restored=(Get-ItemProperty -LiteralPath $registry -Name SteamClientDll).SteamClientDll;
  runtime_sha256=(Get-FileHash -LiteralPath $runtime).Hash; time=(Get-Date).ToString('o')}
$receipt | ConvertTo-Json | Set-Content -LiteralPath "$Output.launch.json"
if ($loaded -ne $runtime -or $receipt.restored -ne $original) { throw 'Dedicated runtime selection or restoration failed; inspect the receipt' }
$receipt | ConvertTo-Json
