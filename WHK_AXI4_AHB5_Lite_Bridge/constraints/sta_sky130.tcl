# sta_sky130.tcl - static timing analysis TEMPLATE
#
# STATUS: this exact flow HAS been executed on this machine, but through
# scripts/run_sta.ps1, which stages the inputs into an ASCII-only directory and runs
# a locally built OpenSTA (MSYS2/UCRT64). This .tcl file is kept as the portable
# template for OpenSTA on Linux/macOS. See docs/performance_notes.md for results:
#   @100 MHz setup slack -3.39 ns (violated); Fmax ~74.6 MHz (period 13.4 ns).
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

set liberty  "/path/to/sky130_fd_sc_hd__tt_025C_1v80.lib"
set netlist  "build/asic_estimate/mapped.v"
set top      "axi4_ahb5_lite_bridge"

read_liberty $liberty
read_verilog $netlist
link_design $top

# Constraint intent from the verification environment: single 100 MHz clock.
read_sdc constraints/bridge_100mhz.sdc

report_clock_properties
report_units

# Setup (max) and hold (min) analysis
report_checks -path_delay max -digits 3 -format full_clock_expanded -fields {slew cap input_pin}
report_checks -path_delay min -digits 3

# Summary numbers: worst negative slack and total negative slack give the Fmax headroom.
report_worst_slack -max
report_worst_slack -min
report_tns
report_wns

# Anything unconstrained means the SDC is incomplete; fix that before quoting numbers.
report_checks -unconstrained -path_delay max

# For an Fmax number, re-run with progressively shorter periods, e.g.:
#   set period 9.0   ;# 111 MHz
#   create_clock -name clk -period $period [get_ports clk]
# and find the shortest period where report_worst_slack -max >= 0.
