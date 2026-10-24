[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite',
  [string]$PythonExe = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$python = Join-Path $OssCadRoot 'lib\python3.exe'
if ($PythonExe) { $python = $PythonExe }
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
  throw "OSS CAD Suite Python is missing: $python"
}

Push-Location $projectRoot
try {
  & $python 'tools\test_reference_model.py'
  if ($LASTEXITCODE -ne 0) {
    throw 'Reference-model tests failed.'
  }
}
finally {
  Pop-Location
}
