# sta_sky130.tcl - static timing analysis TEMPLATE
#
# STATUS: this exact flow HAS been executed on this machine, but through
# scripts/run_sta.ps1, which stages the inputs into an ASCII-only directory and runs
# a locally built OpenSTA (MSYS2/UCRT64). This .tcl file is kept as the portable
# template for OpenSTA on Linux/macOS. See docs/performance_notes.md for results:
#   @100 MHz setup slack +4.54 ns (met); Fmax ~182 MHz (period 5.5 ns).
#
# Why it is needed: yosys/abc only MAPS to standard cells and does not report a
# critical-path delay, so an ASIC Fmax number can only come from a real STA run.
#
# Prerequisites on the Linux/WSL machine:
#   1) OpenSTA built from source (https://github.com/parallaxsw/OpenSTA)
#   2) the sky130 Liberty file (copy F:\EDA\liberty\sky130_fd_sc_hd__tt_025C_1v80.lib)
#   3) the mapped gate-level netlist produced by scripts/run_asic_estimate.ps1
#      (build/asic_estimate/mapped.v)
#
# Usage:
#   sta -no_init -exit constraints/sta_sky130.tcl
#
# NOTE on SCLK: the SDC declares spi_sclk as a generated clock (divide_by 2, the
# CLKDIV=0 worst case). For other divider settings create additional scenarios,
#   CLKDIV=1 -> -divide_by 4,  CLKDIV=4 -> -divide_by 10
# and report each one separately.

set liberty  "/path/to/sky130_fd_sc_hd__tt_025C_1v80.lib"
set netlist  "build/asic_estimate/mapped.v"
set top      "apb3_spi_master"

read_liberty $liberty
read_verilog $netlist
link_design $top

# Constraint intent from the verification environment: PCLK 100 MHz, SCLK from CLKDIV.
read_sdc constraints/spi_100mhz.sdc

report_clock_properties
report_units

report_checks -path_delay max -digits 3 -format full_clock_expanded -fields {slew cap input_pin}
report_checks -path_delay min -digits 3

report_worst_slack -max
report_worst_slack -min
report_tns
report_wns

report_checks -unconstrained -path_delay max
