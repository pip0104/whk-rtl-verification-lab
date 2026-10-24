# run_synth_timing.ps1
# Open-source synthesis + timing estimate using oss-cad-suite:
#   1) yosys synthesis (resource stats, then mapped to iCE40 LUT/DFF/BRAM)
#   2) nextpnr-ice40 place & route + static timing -> Fmax estimate on that FPGA
#
# IMPORTANT: the result is an FPGA (iCE40 HX8K) estimate, NOT an ASIC signoff frequency.
# This repo has no standard-cell library and no commercial synthesis/STA tool.
#
# Requires: yosys.exe and nextpnr-ice40.exe from F:\EDA\oss-cad-suite\bin
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads a .ps1 without BOM as
# ANSI, and non-ASCII comment bytes can swallow the following line break.

$ErrorActionPreference = 'Stop'
# nextpnr returns a non-zero exit code when the --freq target is not met.
# That is an expected, informational outcome here, not a script failure.
$PSNativeCommandUseErrorActionPreference = $false
$root = Split-Path -Parent $PSScriptRoot
$oss  = 'F:\EDA\oss-cad-suite\bin'
$lib  = 'F:\EDA\oss-cad-suite\lib'
if (-not (Test-Path (Join-Path $oss 'yosys.exe'))) { throw "oss-cad-suite not found: $oss" }
# lib must be on PATH too, otherwise yosys/nextpnr exit with 0xC0000135 (STATUS_DLL_NOT_FOUND).
$env:PATH = "$oss;$lib;$env:PATH"

$out  = Join-Path $root 'build\synth'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$ys = Join-Path $out 'synth.ys'
@"
# Read RTL with the slang SystemVerilog frontend; the SVA assertion file is
# intentionally excluded, same as the Icarus flow.
read_slang rtl/apb3_spi_master.sv
hierarchy -check -top apb3_spi_master
# Synthesize/map to iCE40 primitives and emit the JSON nextpnr needs
synth_ice40 -top apb3_spi_master -json build/synth/spi_ice40.json
# Post-mapping resource stats (LUT / DFF / BRAM)
stat
"@ | Set-Content -Encoding ascii $ys

Write-Host '=== 1/2 yosys synthesis ==='
Set-Location $root
& yosys -s $ys -l (Join-Path $out 'yosys_synth.log')
if (-not (Test-Path (Join-Path $out 'spi_ice40.json'))) { throw 'yosys did not emit JSON; see build\synth\yosys_synth.log' }
Write-Host 'yosys done: build\synth\yosys_synth.log'
Get-Content (Join-Path $out 'yosys_synth.log') | Select-String -Pattern 'Number of cells|DFF|LUT|BRAM|SB_' | Select-Object -Last 12 | ForEach-Object { $_.Line.Trim() }

Write-Host '=== 2/2 nextpnr place & route + timing ==='
& nextpnr-ice40 --hx8k --package ct256 --json (Join-Path $out 'spi_ice40.json') --freq 100 --seed 1 --pcf-allow-unconstrained --log (Join-Path $out 'nextpnr_ice40.log') --report (Join-Path $out 'nextpnr_ice40_timing.json')
$rc = $LASTEXITCODE
if ($rc -ne 0) { Write-Host "NOTE: nextpnr exited $rc because the 100 MHz target was not met; the Max frequency printed above is the achieved FPGA estimate." }
Write-Host 'nextpnr done: build\synth\nextpnr_ice40.log'
Get-Content (Join-Path $out 'nextpnr_ice40.log') | Select-String -Pattern 'Max frequency|Device utilisation|ICESTORM_LC|Warning' | Select-Object -Last 14 | ForEach-Object { $_.Line.Trim() }
