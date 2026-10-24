# run_sta.ps1 - real static timing analysis with OpenSTA (built locally via MSYS2/UCRT64)
#
# Prerequisites on this machine (all already set up):
#   F:\EDA\OpenSTA-master\build\sta.exe                    OpenSTA built from source
#   F:\EDA\liberty\sky130_fd_sc_hd__tt_025C_1v80.lib       SkyWater SKY130 HD, tt corner
#   C:\msys64\ucrt64\bin                                   Tcl + MSYS2 runtime DLLs for sta.exe
#   build\asic_estimate\mapped.v                           gate-level netlist (run_asic_estimate.ps1)
#
# Outputs: build\sta\sta_report.log  (the run itself happens in an ASCII staging dir)
#
# This is a real STA run (NLDM liberty, propagated clock, SDC constraints), but note:
#   * no placement/CTS, no SPEF parasitics -> ideal or zero-interconnect unless annotated
#   * single corner (tt, 25C, 1.80V), no derates, no crosstalk
# so it is an optimistic signoff-style estimate, not a manufactured-silicon guarantee.
#
# WHY A STAGING DIR: sta.exe is an MSYS2-based executable. A working path containing
# non-ASCII characters (this repo lives under "总线验证") gets mangled, and backslashes
# in the script argument are eaten as escapes. So all inputs are copied to an
# ASCII-only staging directory and passed with forward slashes.

param(
  [string]$Sta     = 'F:\EDA\OpenSTA-master\build\sta.exe',
  [string]$Liberty = 'F:/EDA/liberty/sky130_fd_sc_hd__tt_025C_1v80.lib',
  [string]$Netlist = 'build/asic_estimate/mapped.v',
  [string]$Sdc     = 'constraints/bridge_100mhz.sdc',
  [string]$Top     = 'axi4_ahb5_lite_bridge',
  [string]$Stage   = 'F:\EDA\sta-work\bridge'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
if (-not (Test-Path $Sta))     { throw "OpenSTA not found: $Sta" }
if (-not (Test-Path $Netlist)) { throw "Mapped netlist not found: $Netlist (run scripts\run_asic_estimate.ps1 first)" }

$out = Join-Path $root 'build\sta'
New-Item -ItemType Directory -Force -Path $out | Out-Null

New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item (Join-Path $root $Netlist) (Join-Path $Stage 'mapped.v') -Force
Copy-Item (Join-Path $root $Sdc)     (Join-Path $Stage 'design.sdc') -Force
$stagePosix = ($Stage -replace '\\','/')
$tcl = Join-Path $Stage 'sta_run.tcl'

@"
read_liberty $Liberty
read_verilog $stagePosix/mapped.v
link_design $Top
read_sdc $stagePosix/design.sdc
report_units
report_checks -path_delay max -digits 3 -format full_clock_expanded
report_checks -path_delay min -digits 3
report_worst_slack -max
report_worst_slack -min
report_tns
report_wns
report_checks -unconstrained -path_delay max
"@ | Set-Content -Encoding ascii $tcl

# sta.exe needs the MSYS2 ucrt64 runtime (Tcl) on PATH.
$env:PATH = "C:\msys64\ucrt64\bin;$env:PATH"

Write-Host "=== OpenSTA run: $Top ==="
& $Sta -no_splash -no_init -exit "$stagePosix/sta_run.tcl" 2>&1 | Tee-Object -FilePath (Join-Path $out 'sta_report.log')
Write-Host "log: build\sta\sta_report.log"
