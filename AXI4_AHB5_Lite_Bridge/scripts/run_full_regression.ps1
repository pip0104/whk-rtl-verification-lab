[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite',
  [string]$PythonExe = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$resultsDir = Join-Path $projectRoot 'results'
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null

$steps = @(
  'run_reference_model_tests.ps1',
  'run_smoke_iverilog.ps1',
  'run_parameter_sweep_iverilog.ps1',
  'run_bridge_regression.ps1'
)

$log = Join-Path $resultsDir 'full_regression.log'
Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
foreach ($step in $steps) {
  "`n===== $step =====" | Tee-Object -FilePath $log -Append
  $stepArgs = @{ OssCadRoot = $OssCadRoot }
  if ($PythonExe -and $step -in @('run_reference_model_tests.ps1','run_bridge_regression.ps1')) {
    $stepArgs.PythonExe = $PythonExe
  }
  & (Join-Path $PSScriptRoot $step) @stepArgs 2>&1 |
    Tee-Object -FilePath $log -Append
  if ($LASTEXITCODE -ne 0) {
    throw "Regression step failed: $step. See $log"
  }
}

Write-Host "PASS: full portable regression completed. Log: $log"
