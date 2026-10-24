[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite',
  [string]$PythonExe = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$environmentScript = Join-Path $OssCadRoot 'environment.ps1'
$python = Join-Path $projectRoot '.venv_cocotb\Scripts\python.exe'
if ($PythonExe) { $python = $PythonExe }
$runner = Join-Path $projectRoot 'tests\cocotb\run_bridge_regression.py'

foreach ($requiredPath in @($environmentScript, $python, $runner)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required free-toolchain file is missing: $requiredPath"
  }
}

. $environmentScript
& $python $runner
if ($LASTEXITCODE -ne 0) {
  throw 'Portable bridge regression failed.'
}

$coverage = Join-Path $projectRoot 'results\functional_coverage.json'
if (-not (Test-Path -LiteralPath $coverage -PathType Leaf)) {
  throw "Regression completed without coverage report: $coverage"
}

$junit = Join-Path $projectRoot 'results\bridge_regression.xml'
if (-not (Test-Path -LiteralPath $junit -PathType Leaf)) {
  throw "Regression completed without JUnit result: $junit"
}
[xml]$resultXml = Get-Content -LiteralPath $junit -Raw
$suites = @($resultXml.testsuites.testsuite)
if ($suites.Count -eq 0) { throw "No cocotb test suites. See $junit" }
foreach ($suite in $suites) {
  if ([int]$suite.failures -ne 0 -or [int]$suite.errors -ne 0 -or [int]$suite.tests -lt 1) {
    throw "cocotb reported failures/errors. See $junit"
  }
}

Write-Host 'PASS: AXI4-to-AHB5-Lite portable regression completed.'
Write-Host "Functional coverage: $coverage"
