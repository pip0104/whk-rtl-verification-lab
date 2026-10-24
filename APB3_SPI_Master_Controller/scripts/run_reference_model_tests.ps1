[CmdletBinding()]
param(
  [string]$Python = 'C:\Users\Pip\Documents\总线验证\AXI4_AHB5_Lite_Bridge\.venv_cocotb\Scripts\python.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
  throw "Python with cocotb dependencies was not found: $Python"
}
Push-Location (Join-Path $projectRoot 'tools')
try {
  & $Python -m unittest -v test_reference_model.py
  if ($LASTEXITCODE -ne 0) { throw 'Reference-model unit tests failed.' }
}
finally { Pop-Location }
Write-Host 'PASS: SPI reference-model unit tests completed.'
