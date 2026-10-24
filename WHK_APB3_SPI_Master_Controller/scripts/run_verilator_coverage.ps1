[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite',
  [string]$MsysRoot = 'C:\msys64'
)

$ErrorActionPreference = 'Stop'
function ConvertTo-MsysPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  $fullPath = [IO.Path]::GetFullPath($Path)
  if ($fullPath.Length -lt 4 -or $fullPath[1] -ne ':' -or $fullPath[2] -ne '\') {
    throw "Not a drive-rooted Windows path: $fullPath"
  }
  $drive = $fullPath.Substring(0, 1).ToLowerInvariant()
  $rest = $fullPath.Substring(3).Replace('\', '/')
  return "/$drive/$rest"
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$environmentScript = Join-Path $OssCadRoot 'environment.ps1'
$verilator = Join-Path $OssCadRoot 'bin\verilator_bin.exe'
$coverageTool = Join-Path $OssCadRoot 'bin\verilator_coverage_bin_dbg.exe'
$verilatorRoot = Join-Path $OssCadRoot 'share\verilator'
$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
$python = 'C:\Users\Pip\Documents\总线验证\AXI4_AHB5_Lite_Bridge\.venv_cocotb\Scripts\python.exe'
$buildDir = Join-Path $projectRoot 'build\verilator_smoke_coverage'
$objectDir = Join-Path $buildDir 'obj_dir'
$resultsDir = Join-Path $projectRoot 'results'
foreach ($path in @($environmentScript, $verilator, $coverageTool, $bash, $python, (Join-Path $MsysRoot 'usr\bin\make.exe'), (Join-Path $MsysRoot 'ucrt64\bin\g++.exe'))) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing coverage prerequisite: $path" }
}
. $environmentScript
$env:VERILATOR_ROOT = $verilatorRoot
New-Item -ItemType Directory -Force -Path $buildDir, $resultsDir | Out-Null
$sources = @((Join-Path $projectRoot 'rtl\apb3_spi_master.sv'), (Join-Path $projectRoot 'tb\tb_top_smoke.sv'))
& $verilator --cc --main --exe --timing --trace --coverage --coverage-line --coverage-toggle -Wno-fatal --top-module tb_top_smoke --Mdir $objectDir @sources
if ($LASTEXITCODE -ne 0) { throw 'Verilator elaboration failed.' }
$msysObjectDir = ConvertTo-MsysPath $objectDir
$msysVerilatorRoot = ConvertTo-MsysPath $verilatorRoot
$msysPython = ConvertTo-MsysPath $python
$bashCommand = @('export PATH=/ucrt64/bin:/usr/bin:$PATH', "cd '$msysObjectDir'", "make -B -f Vtb_top_smoke.mk -j 2 PYTHON3=$msysPython USER_CPPFLAGS=-D_GLIBCXX_USE_CXX11_ABI=0 VERILATOR_ROOT=$msysVerilatorRoot", './Vtb_top_smoke') -join '; '
& $bash -lc $bashCommand
if ($LASTEXITCODE -ne 0) { throw 'MSYS2 build or Verilator simulation failed.' }
$coverageDat = Join-Path $objectDir 'coverage.dat'
if (-not (Test-Path -LiteralPath $coverageDat -PathType Leaf)) { throw 'Verilator did not produce coverage.dat.' }
Push-Location $buildDir
try {
  & $coverageTool --report summary,hier 'obj_dir/coverage.dat' 2>&1 | Tee-Object -FilePath (Join-Path $resultsDir 'verilator_code_coverage_summary.txt')
  if ($LASTEXITCODE -ne 0) { throw 'Coverage summary failed.' }
  & $coverageTool --write-info (Join-Path $resultsDir 'verilator_code_coverage.info') 'obj_dir/coverage.dat'
  if ($LASTEXITCODE -ne 0) { throw 'LCOV export failed.' }
}
finally { Pop-Location }
Write-Host "PASS: Verilator smoke coverage completed. Database: $coverageDat"
