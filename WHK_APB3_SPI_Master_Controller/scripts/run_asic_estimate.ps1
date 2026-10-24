# run_asic_estimate.ps1
# Open-source ASIC area/delay ESTIMATE using yosys + ABC + an open Liberty library.
#
# What this does:
#   pass 1: generic synthesis + area-oriented mapping (ABC reports real cell area and delay)
#   pass 2: delay-driven mapping toward a 100 MHz target (ABC -D 10000 ps)
#
# IMPORTANT BOUNDARIES - this is NOT signoff:
#   * ideal interconnect: no floorplan, no placement, no CTS, no wire-load model
#   * no clock-tree latency/skew, no derates, no crosstalk, no multi-corner
#   * FIFO/register arrays stay as flops (a real ASIC would use SRAM macros)
# Because of ideal interconnect the delay is OPTIMISTIC compared with a real P&R result.
#
# Libraries (open source, downloaded to a machine-local cache, not into this repo):
#   F:\EDA\liberty\sky130_fd_sc_hd__tt_025C_1v80.lib      (SkyWater SKY130 HD, tt corner)
#   F:\EDA\liberty\NangateOpenCellLibrary_typical.lib     (Nangate45, educational)

param(
  [string]$Liberty = 'F:\EDA\liberty\sky130_fd_sc_hd__tt_025C_1v80.lib'
)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot
$oss     = 'F:\EDA\oss-cad-suite\bin'
$libdir  = 'F:\EDA\oss-cad-suite\lib'
if (-not (Test-Path $Liberty)) { throw "Liberty not found: $Liberty" }
$env:PATH = "$oss;$libdir;$env:PATH"

$out = Join-Path $root 'build\asic_estimate'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$libTag   = [IO.Path]::GetFileNameWithoutExtension($Liberty)
$areaLog  = Join-Path $out "area_$libTag.log"
$fastLog  = Join-Path $out "target100mhz_$libTag.log"

$ysArea = Join-Path $out 'asic_area.ys'
@"
read_slang rtl/apb3_spi_master.sv
hierarchy -check -top apb3_spi_master
synth -top apb3_spi_master -flatten
dfflibmap -liberty $Liberty
abc -liberty $Liberty
write_verilog -noattr build/asic_estimate/mapped.v
stat
"@ | Set-Content -Encoding ascii $ysArea

$ysFast = Join-Path $out 'asic_target100mhz.ys'
@"
read_slang rtl/apb3_spi_master.sv
hierarchy -check -top apb3_spi_master
synth -top apb3_spi_master -flatten
dfflibmap -liberty $Liberty
abc -liberty $Liberty -D 10000
write_verilog -noattr build/asic_estimate/mapped.v
stat
"@ | Set-Content -Encoding ascii $ysFast

Set-Location $root

Write-Host "=== pass 1: area-oriented mapping ($libTag) ==="
& yosys -s $ysArea -l $areaLog
Get-Content $areaLog | Select-String -Pattern 'Delay =|Area =|Chip area|Number of cells|Number of wires' | ForEach-Object { $_.Line.Trim() } | Select-Object -Last 10

Write-Host "=== pass 2: delay-driven mapping to 100 MHz ($libTag) ==="
& yosys -s $ysFast -l $fastLog
Get-Content $fastLog | Select-String -Pattern 'Delay =|Area =|Chip area|Number of cells' | ForEach-Object { $_.Line.Trim() } | Select-Object -Last 10

Write-Host "logs: build\asic_estimate\"
