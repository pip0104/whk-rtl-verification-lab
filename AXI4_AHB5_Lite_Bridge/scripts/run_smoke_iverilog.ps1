[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $projectRoot 'build\iverilog_smoke'
$environmentScript = Join-Path $OssCadRoot 'environment.ps1'
$iverilog = Join-Path $OssCadRoot 'bin\iverilog.exe'
$vvp = Join-Path $OssCadRoot 'bin\vvp.exe'

foreach ($requiredPath in @($environmentScript, $iverilog, $vvp)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required OSS CAD Suite file is missing: $requiredPath"
  }
}

# The suite environment supplies the required DLL search path for vvp.
. $environmentScript
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

Push-Location $buildDir
try {
  $sources = @(
    (Join-Path $projectRoot 'rtl\axi4_ahb5_lite_bridge_pkg.sv'),
    (Join-Path $projectRoot 'rtl\axi4_ahb5_lite_bridge.sv'),
    (Join-Path $projectRoot 'tb\ahb5_lite_memory_model.sv'),
    (Join-Path $projectRoot 'tb\tb_top_smoke.sv')
  )

  # Icarus does not implement the project's concurrent SVA checker fully, so
  # this portable smoke path intentionally excludes axi4_ahb5_lite_bridge_assert.sv.
  & $iverilog -g2012 -Wall -s tb_top_smoke -o smoke.vvp @sources 2>&1 |
    Tee-Object -FilePath 'compile.log'
  if ($LASTEXITCODE -ne 0) {
    throw "Icarus compile failed. See $buildDir\compile.log"
  }

  & $vvp 'smoke.vvp' 2>&1 | Tee-Object -FilePath 'simulate.log'
  if ($LASTEXITCODE -ne 0) {
    throw "Icarus simulation failed. See $buildDir\simulate.log"
  }

  if (-not (Select-String -LiteralPath 'simulate.log' -Pattern 'SMOKE_TEST_PASS' -Quiet)) {
    throw "Smoke test did not report PASS. See $buildDir\simulate.log"
  }

  Write-Host "PASS: Icarus smoke test completed."
  Write-Host "Waveform: $buildDir\smoke.vcd"
}
finally {
  Pop-Location
}
