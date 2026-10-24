[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $projectRoot 'build\iverilog_parameter_sweep'
$environmentScript = Join-Path $OssCadRoot 'environment.ps1'
$iverilog = Join-Path $OssCadRoot 'bin\iverilog.exe'
$vvp = Join-Path $OssCadRoot 'bin\vvp.exe'

foreach ($requiredPath in @($environmentScript, $iverilog, $vvp)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required OSS CAD Suite file is missing: $requiredPath"
  }
}

. $environmentScript
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
Push-Location $buildDir
try {
  $sources = @(
    (Join-Path $projectRoot 'rtl\axi4_ahb5_lite_bridge_pkg.sv'),
    (Join-Path $projectRoot 'rtl\axi4_ahb5_lite_bridge.sv'),
    (Join-Path $projectRoot 'tb\tb_parameter_sweep.sv')
  )
  & $iverilog -g2012 -Wall -s tb_parameter_sweep -o parameter_sweep.vvp @sources 2>&1 |
    Tee-Object -FilePath 'compile.log'
  if ($LASTEXITCODE -ne 0) { throw "Parameter sweep compile failed. See $buildDir\compile.log" }
  & $vvp parameter_sweep.vvp 2>&1 | Tee-Object -FilePath 'simulate.log'
  if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath simulate.log -Pattern 'PARAMETER_SWEEP_PASS' -Quiet)) {
    throw "Parameter sweep simulation failed. See $buildDir\simulate.log"
  }
  Write-Host 'PASS: all advertised FIFO depths elaborated.'
}
finally {
  Pop-Location
}
