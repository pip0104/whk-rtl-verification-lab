# run_synth_timing.ps1
# Open-source synthesis + timing estimate using oss-cad-suite:
#   1) yosys synthesis, mapped to ECP5 primitives (LUT/DFF/BRAM)
#   2) nextpnr-ecp5 place & route + static timing -> Fmax estimate on that FPGA
#
# IMPORTANT: the result is an FPGA (ECP5-45K) estimate, NOT an ASIC signoff frequency.
# This repo has no standard-cell library and no commercial synthesis/STA tool.
#
# Why ECP5 and not iCE40: this bridge exposes ~305 IO bits. The iCE40 HX8K packages
# have at most ~206 IO pads, so nextpnr-ice40 fails with "SB_IO: 305/206 (148%)".
# That is a pin-count limit, not a logic-capacity problem (LC usage was 961/7680 = 12%).
# ECP5-45K in CABGA381 has enough pads and room for the same netlist.
#
# Requires: yosys.exe and nextpnr-ecp5.exe from F:\EDA\oss-cad-suite\bin
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
# Read RTL with the slang SystemVerilog frontend (full SV: packages, import, structs).
# The SVA assertion file is intentionally excluded, same as the Icarus flow.
# If read_slang is unavailable in your yosys build, the fallback is
#   read_verilog -sv rtl/axi4_ahb5_lite_bridge_pkg.sv
#   read_verilog -sv rtl/axi4_ahb5_lite_bridge.sv
# but note that yosys's built-in parser rejects a module-scope "import pkg::*" in this design.
read_slang rtl/axi4_ahb5_lite_bridge_pkg.sv rtl/axi4_ahb5_lite_bridge.sv
hierarchy -check -top axi4_ahb5_lite_bridge
# Synthesize/map to ECP5 primitives and emit the JSON nextpnr needs
synth_ecp5 -top axi4_ahb5_lite_bridge -json build/synth/bridge_ecp5.json
# Post-mapping resource stats
stat
"@ | Set-Content -Encoding ascii $ys

Write-Host '=== 1/2 yosys synthesis ==='
Set-Location $root
& yosys -s $ys -l (Join-Path $out 'yosys_synth.log')
if (-not (Test-Path (Join-Path $out 'bridge_ecp5.json'))) { throw 'yosys did not emit JSON; see build\synth\yosys_synth.log' }
Write-Host 'yosys done: build\synth\yosys_synth.log'
Get-Content (Join-Path $out 'yosys_synth.log') | Select-String -Pattern 'Number of cells|DFF|LUT|BRAM|SB_' | Select-Object -Last 12 | ForEach-Object { $_.Line.Trim() }

Write-Host '=== 2/2 nextpnr place & route + timing ==='
# NOTE: ECP5 uses --lpf-allow-unconstrained (the iCE40 flag is --pcf-allow-unconstrained).
# LFE5U-45F in CABGA381 has only 245 IO pads and cannot host this design's 305 IO bits
# (TRELLIS_IO 305/245 = 124%). LFE5U-85F in CABGA554 provides 365 pads, so it fits at 83%.
& nextpnr-ecp5 --85k --package CABGA554 --json (Join-Path $out 'bridge_ecp5.json') --freq 100 --seed 1 --lpf-allow-unconstrained --log (Join-Path $out 'nextpnr_ecp5.log') --report (Join-Path $out 'nextpnr_ecp5_timing.json')
$rc = $LASTEXITCODE
if ($rc -ne 0) { Write-Host "NOTE: nextpnr exited $rc because the 100 MHz target was not met; the Max frequency printed above is the achieved FPGA estimate." }
Write-Host 'nextpnr done: build\synth\nextpnr_ecp5.log'
Get-Content (Join-Path $out 'nextpnr_ecp5.log') | Select-String -Pattern 'Max frequency|Device utilisation|TRELLIS_COMB|TRELLIS_FF|TRELLIS_RAM|Warning' | Select-Object -Last 16 | ForEach-Object { $_.Line.Trim() }
