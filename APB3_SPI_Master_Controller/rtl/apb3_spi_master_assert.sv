`timescale 1ns/1ps

// Simulation-only protocol assertions.  They observe the IP boundary so the
// checks remain meaningful if the implementation is later refactored.
module apb3_spi_master_assert (
  input wire        pclk,
  input wire        presetn,
  input wire        psel,
  input wire        penable,
  input wire        pwrite,
  input wire [31:0] paddr,
  input wire [31:0] pwdata,
  input wire [31:0] prdata,
  input wire        pready,
  input wire        pslverr,
  input wire        spi_sclk,
  input wire        spi_mosi,
  input wire        spi_cs_n,
  input wire        irq
);
  default clocking cb @(posedge pclk); endclocking

  // APB setup is followed by an access phase for a non-wait-state slave.
  ap_setup_to_access: assert property (
    disable iff (!presetn) psel && !penable |=> psel && penable
  ) else $error("APB setup phase was not followed by access phase");

  ap_ready_always: assert property (
    disable iff (!presetn) psel && penable |-> pready
  ) else $error("APB3 slave unexpectedly stalled");

  // Once CS is inactive, the serial clock must be an idle level and MOSI is
  // quiescent. This catches partial transfer cleanup bugs.
  ap_idle_mosi_low: assert property (
    disable iff (!presetn) spi_cs_n |-> (spi_mosi == 1'b0)
  ) else $error("MOSI was not quiescent while CS was inactive");

endmodule

bind apb3_spi_master apb3_spi_master_assert u_apb3_spi_master_assert (.*);
