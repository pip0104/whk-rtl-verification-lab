[CmdletBinding()]
param(
  [string]$OssCadRoot = 'F:\EDA\oss-cad-suite',
  [string]$MsysRoot = 'C:\msys64'
)

$ErrorActionPreference = 'Stop'

function ConvertTo-MsysPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $fullPath = [IO.Path]::GetFullPath($Path)
  if ($fullPath -notmatch '^(?<drive>[A-Za-z]):\\(?<rest>.*)$') {
    throw "Cannot convert this path to an MSYS path: $fullPath"
  }
  return ('/' + $Matches.drive.ToLowerInvariant() + '/' + ($Matches.rest -replace '\\', '/'))
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$environmentScript = Join-Path $OssCadRoot 'environment.ps1'
$verilator = Join-Path $OssCadRoot 'bin\verilator_bin.exe'
$coverageTool = Join-Path $OssCadRoot 'bin\verilator_coverage_bin_dbg.exe'
$verilatorRootWin = Join-Path $OssCadRoot 'share\verilator'
$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
$python = Join-Path $projectRoot '.venv_cocotb\Scripts\python.exe'
$buildDir = Join-Path $projectRoot 'build\verilator_smoke_coverage'
$objectDir = Join-Path $buildDir 'obj_dir'
$resultsDir = Join-Path $projectRoot 'results'
$summary = Join-Path $resultsDir 'verilator_code_coverage_summary.txt'
$lcovInfo = Join-Path $resultsDir 'verilator_code_coverage.info'

foreach ($requiredPath in @(
  $environmentScript,
  $verilator,
  $coverageTool,
  $bash,
  (Join-Path $MsysRoot 'usr\bin\make.exe'),
  (Join-Path $MsysRoot 'ucrt64\bin\g++.exe'),
  $python
)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Required free coverage-toolchain file is missing: $requiredPath"
  }
}

. $environmentScript
$env:VERILATOR_ROOT = $verilatorRootWin
New-Item -ItemType Directory -Force -Path $buildDir, $resultsDir | Out-Null

$sources = @(
  (Join-Path $projectRoot 'rtl\axi4_ahb5_lite_bridge_pkg.sv'),
  (Join-Path $projectRoot 'rtl\axi4_ahb5_lite_bridge.sv'),
  (Join-Path $projectRoot 'tb\ahb5_lite_memory_model.sv'),
  (Join-Path $projectRoot 'tb\tb_top_smoke.sv')
)

# --cc + --main deliberately separates Verilator elaboration from the free
# MSYS2 C++ build.  Unlike --binary, this does not expect a commercial tool or
# a Perl wrapper on Windows.
& $verilator --cc --main --exe --timing --trace --coverage --coverage-line `
  --coverage-toggle -Wno-fatal --top-module tb_top_smoke --Mdir $objectDir `
  @sources
if ($LASTEXITCODE -ne 0) {
  throw 'Verilator elaboration failed; no code-coverage data was generated.'
}

$msysObjectDir = ConvertTo-MsysPath $objectDir
$msysPython = ConvertTo-MsysPath $python
$msysVerilatorRoot = ConvertTo-MsysPath $verilatorRootWin
$bashCommand = @(
  'export PATH=/ucrt64/bin:/usr/bin:$PATH',
  "cd '$msysObjectDir'",
  "make -B -f Vtb_top_smoke.mk -j 2 PYTHON3=$msysPython USER_CPPFLAGS=-D_GLIBCXX_USE_CXX11_ABI=0 VERILATOR_ROOT=$msysVerilatorRoot",
  './Vtb_top_smoke'
) -join '; '

& $bash -lc $bashCommand
if ($LASTEXITCODE -ne 0) {
  throw 'Free MSYS2 build or Verilator smoke simulation failed.'
}

$coverageDat = Join-Path $objectDir 'coverage.dat'
if (-not (Test-Path -LiteralPath $coverageDat -PathType Leaf)) {
  throw "Verilator did not produce a coverage database: $coverageDat"
}

# Run from the coverage build root so the relative RTL paths recorded by
# Verilator resolve correctly during source annotation.
Push-Location $buildDir
try {
  & $coverageTool --report summary,hier 'obj_dir/coverage.dat' 2>&1 |
    Tee-Object -FilePath $summary
  if ($LASTEXITCODE -ne 0) {
    throw 'Verilator coverage summary generation failed.'
  }

  & $coverageTool --write-info $lcovInfo 'obj_dir/coverage.dat'
  if ($LASTEXITCODE -ne 0) {
    throw 'Verilator LCOV export failed.'
  }

  # The Windows Verilator coverage annotator currently cannot reopen a source
  # path containing Chinese characters (it percent-encodes the path).  The
  # database, summary and LCOV export above are valid; skip only the optional
  # annotated-copy convenience output in such workspaces.
  if ($projectRoot -notmatch '[^\x00-\x7F]') {
    $annotationDir = Join-Path $buildDir 'coverage_annotated'
    New-Item -ItemType Directory -Force -Path $annotationDir | Out-Null
    & $coverageTool --annotate 'coverage_annotated' 'obj_dir/coverage.dat' 2>&1 |
      Tee-Object -FilePath (Join-Path $resultsDir 'verilator_code_coverage_annotation.log')
    if ($LASTEXITCODE -ne 0) {
      Write-Warning 'Coverage annotation was unavailable; summary and LCOV export remain valid.'
    }
  }
  else {
    Write-Warning 'Skipping optional annotated sources because this workspace path contains non-ASCII characters.'
  }
}
finally {
  Pop-Location
}

Write-Host 'PASS: free Verilator code-coverage smoke completed.'
Write-Host "Coverage database: $coverageDat"
Write-Host "Coverage summary: $summary"
Write-Host "LCOV export: $lcovInfo"
if ($projectRoot -notmatch '[^\x00-\x7F]') {
  Write-Host "Annotated sources: $buildDir\coverage_annotated"
}
