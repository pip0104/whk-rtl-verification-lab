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
$runner = Join-Path $projectRoot 'tests\cocotb\run_environment_probe.py'

foreach ($requiredPath in @($environmentScript, $python, $runner)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required free-toolchain file is missing: $requiredPath"
  }
}

. $environmentScript
& $python $runner
if ($LASTEXITCODE -ne 0) {
  throw 'cocotb/Icarus environment probe failed.'
}

Write-Host 'PASS: cocotb communicated with Icarus through VPI.'
