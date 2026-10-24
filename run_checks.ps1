[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite',
  [string]$Python = 'python',
  [ValidateSet('all','spi','bridge')][string]$Project = 'all',
  [switch]$Formal
)
$ErrorActionPreference = 'Stop'
$environmentScript = Join-Path $OssCadRoot 'environment.ps1'
if (Test-Path -LiteralPath $environmentScript) { . $environmentScript }
$arguments = @((Join-Path $PSScriptRoot 'scripts\verify.py'), '--project', $Project)
if ($Formal) { $arguments += '--formal' }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw 'Verification failed; inspect results/verification_summary.json.' }
