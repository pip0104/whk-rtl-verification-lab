# bridge_100mhz.sdc
# Timing-constraint DRAFT for the verification-environment assumption:
# single clock domain, 10 ns period = 100 MHz.
#
# This file states the design's CLOCK INTENT. It is NOT a signoff constraint:
# this repo has no standard-cell library, no synthesis and no STA signoff flow,
# so this file alone cannot produce an Fmax number.
# A real Fmax needs: Liberty library + synthesis + static timing analysis.
#
# Evidence:
#   docs/bridge_spec.md section 2.1  -> AXI and AHB share one clk; rst_n is a
#                                       synchronous active-low reset
#   tb/tb_cocotb_bridge.sv line 74   -> "forever #5 clk = ~clk" (5 ns half period)

# ---------------------------------------------------------------- clock
create_clock -name clk -period 10.000 [get_ports clk]

# Clock uncertainty: budget for jitter and clock-tree skew (conservative, study use).
set_clock_uncertainty -setup 0.150 [get_clocks clk]
set_clock_uncertainty -hold  0.050 [get_clocks clk]

# ---------------------------------------------------------------- IO (placeholders)
# Kept COMMENTED OUT on purpose:
#   * the values are placeholders until the board/top-level environment is known, and
#   * "remove_from_collection" is a PrimeTime-only command that OpenSTA does not
#     implement, so a collection-based expression would fail in the open-source flow.
# Enable the per-tool version below once real numbers exist.
#
# PrimeTime style:
#   set_input_delay  -clock clk -max 2.000 [remove_from_collection [all_inputs] [get_ports clk]]
#   set_output_delay -clock clk -max 2.000 [all_outputs]
#
# Portable / OpenSTA style (explicit port names, AXI + AHB sides):
#   set_input_delay  -clock clk -max 2.000 [get_ports {rst_n awvalid wvalid bready arvalid rready hready hresp hrdata[*]}]
#   set_output_delay -clock clk -max 2.000 [get_ports {awready wready bvalid rvalid haddr[*] htrans[*] hsize[*] hwrite hsel hwdata[*]}]
#   set_load 0.050 [get_ports {awready wready bvalid rvalid haddr[*] hwdata[*]}]

# ---------------------------------------------------------------- reset
# The spec requires rst_n to be a SYNCHRONOUS active-low reset, therefore it is
# deliberately NOT declared as a false path; it stays timed as a synchronous path
# (only the input delay above applies to it).

# ---------------------------------------------------------------- clock domains
# AXI and AHB share the same clk, so there are no cross-domain paths and no
# set_clock_groups is needed.
#
# For a future FIFO_DEPTH sweep, create one scenario per parameter value, e.g.
#   set_parameter -name FIFO_DEPTH 8
#   set_parameter -name FIFO_DEPTH 128
# and store one report per scenario (not implemented in this repo yet).
#
# Analysis intent for the open-source STA flow: ideal clock network (no CTS exists yet),
# so internal register-to-register paths are what an Fmax number should be read from.
