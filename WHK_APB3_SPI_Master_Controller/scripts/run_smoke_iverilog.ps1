[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$environmentScript = Join-Path $OssCadRoot 'environment.ps1'
$iverilog = Join-Path $OssCadRoot 'bin\iverilog.exe'
$vvp = Join-Path $OssCadRoot 'bin\vvp.exe'
$buildDir = Join-Path $projectRoot 'build\iverilog_smoke'
foreach ($path in @($environmentScript, $iverilog, $vvp)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing toolchain file: $path" }
}
. $environmentScript
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
Push-Location $buildDir
try {
  $sources = @(
    (Join-Path $projectRoot 'rtl\apb3_spi_master.sv'),
    (Join-Path $projectRoot 'tb\tb_top_smoke.sv')
  )
  & $iverilog -g2012 -Wall -s tb_top_smoke -o smoke.vvp @sources 2>&1 |
    Tee-Object -FilePath 'compile.log'
  if ($LASTEXITCODE -ne 0) { throw 'Icarus compilation failed.' }
  & $vvp smoke.vvp 2>&1 | Tee-Object -FilePath 'simulate.log'
  if ($LASTEXITCODE -ne 0) { throw 'Icarus smoke simulation failed.' }
  if (-not (Select-String -LiteralPath 'simulate.log' -Pattern 'SMOKE_TEST_PASS' -Quiet)) {
    throw 'Smoke simulation did not report PASS.'
  }
}
finally { Pop-Location }
Write-Host "PASS: Icarus smoke completed. Waveform: $buildDir\smoke.vcd"
