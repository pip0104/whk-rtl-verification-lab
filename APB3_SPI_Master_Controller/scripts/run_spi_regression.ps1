[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite',
  [string]$Python = 'C:\Users\Pip\Documents\总线验证\AXI4_AHB5_Lite_Bridge\.venv_cocotb\Scripts\python.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$environmentScript = Join-Path $OssCadRoot 'environment.ps1'
$runner = Join-Path $projectRoot 'tests\cocotb\run_spi_regression.py'
$resultsDir = Join-Path $projectRoot 'results'
foreach ($path in @($environmentScript, $Python, $runner)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing regression prerequisite: $path" }
}
. $environmentScript
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
Push-Location (Join-Path $projectRoot 'tests\cocotb')
try {
  & $Python $runner 2>&1 | Tee-Object -FilePath (Join-Path $resultsDir 'cocotb_regression.log')
  if ($LASTEXITCODE -ne 0) { throw 'cocotb runner failed.' }
}
finally { Pop-Location }

$junit = Join-Path $resultsDir 'spi_regression.xml'
$coverage = Join-Path $resultsDir 'functional_coverage.json'
if (-not (Test-Path -LiteralPath $junit -PathType Leaf) -or -not (Test-Path -LiteralPath $coverage -PathType Leaf)) {
  throw 'cocotb run did not generate JUnit and functional-coverage outputs.'
}
[xml]$xml = Get-Content -LiteralPath $junit -Raw
$suite = $xml.testsuites.testsuite
if ([int]$suite.tests -lt 1 -or [int]$suite.failures -ne 0 -or [int]$suite.errors -ne 0) {
  throw "cocotb reported failures. See $junit"
}
$cov = Get-Content -LiteralPath $coverage -Raw | ConvertFrom-Json
if ($cov.hit_bins -ne $cov.required_bins) { throw 'Required functional-coverage bins were not all hit.' }
Write-Host "PASS: cocotb APB3-SPI regression completed; bins=$($cov.hit_bins)/$($cov.required_bins)."
