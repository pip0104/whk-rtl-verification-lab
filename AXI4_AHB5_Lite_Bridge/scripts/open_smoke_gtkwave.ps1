[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$gtkwave = Join-Path $OssCadRoot 'bin\gtkwave.exe'
$waveform = Join-Path $projectRoot 'build\iverilog_smoke\smoke.vcd'

if (-not (Test-Path -LiteralPath $gtkwave -PathType Leaf)) {
  throw "GTKWave is missing: $gtkwave"
}
if (-not (Test-Path -LiteralPath $waveform -PathType Leaf)) {
  throw "Waveform does not exist: $waveform. Run scripts\run_smoke_iverilog.ps1 first."
}

& $gtkwave $waveform
