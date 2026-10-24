[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite',
  [string]$Python = 'C:\Users\Pip\Documents\总线验证\AXI4_AHB5_Lite_Bridge\.venv_cocotb\Scripts\python.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$resultsDir = Join-Path $projectRoot 'results'
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$log = Join-Path $resultsDir 'full_regression.log'
Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
foreach ($script in @('run_reference_model_tests.ps1', 'run_smoke_iverilog.ps1', 'run_spi_regression.ps1')) {
  "`n===== $script =====" | Tee-Object -FilePath $log -Append
  if ($script -eq 'run_reference_model_tests.ps1') {
    & (Join-Path $PSScriptRoot $script) -Python $Python 2>&1 | Tee-Object -FilePath $log -Append
  }
  elseif ($script -eq 'run_smoke_iverilog.ps1') {
    & (Join-Path $PSScriptRoot $script) -OssCadRoot $OssCadRoot 2>&1 | Tee-Object -FilePath $log -Append
  }
  else {
    & (Join-Path $PSScriptRoot $script) -OssCadRoot $OssCadRoot -Python $Python 2>&1 |
      Tee-Object -FilePath $log -Append
  }
  if ($LASTEXITCODE -ne 0) { throw "Regression step failed: $script" }
}
Write-Host "PASS: full APB3-SPI regression completed. Log: $log"
