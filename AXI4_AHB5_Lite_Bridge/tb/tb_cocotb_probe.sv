`timescale 1ns/1ps

// Minimal top-level used only to verify the local cocotb + Icarus setup.
// It intentionally does not instantiate project RTL or replace the smoke TB.
module tb_cocotb_probe;
  logic clk = 1'b0;

  always #5 clk = ~clk;
endmodule
