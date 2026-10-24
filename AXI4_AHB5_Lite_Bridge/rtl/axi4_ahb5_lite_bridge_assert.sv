`timescale 1ns/1ps

// Protocol-facing assertions for axi4_ahb5_lite_bridge.
// Compile this file in simulation only.  The assertions deliberately observe
// module ports instead of RTL internals so that they check externally visible
// protocol rules and remain useful after microarchitecture refactoring.

module axi4_ahb5_lite_bridge_assert #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int ID_WIDTH   = 4
) (
  input logic clk,
  input logic rst_n,

  input logic [ID_WIDTH-1:0] s_awid,
  input logic [ADDR_WIDTH-1:0] s_awaddr,
  input logic [7:0] s_awlen,
  input logic [2:0] s_awsize,
  input logic [1:0] s_awburst,
  input logic s_awvalid,
  input logic s_awready,

  input logic [DATA_WIDTH-1:0] s_wdata,
  input logic [DATA_WIDTH/8-1:0] s_wstrb,
  input logic s_wlast,
  input logic s_wvalid,
  input logic s_wready,

  input logic [ID_WIDTH-1:0] s_bid,
  input logic [1:0] s_bresp,
  input logic s_bvalid,
  input logic s_bready,

  input logic [ID_WIDTH-1:0] s_arid,
  input logic [ADDR_WIDTH-1:0] s_araddr,
  input logic [7:0] s_arlen,
  input logic [2:0] s_arsize,
  input logic [1:0] s_arburst,
  input logic s_arvalid,
  input logic s_arready,

  input logic [ID_WIDTH-1:0] s_rid,
  input logic [DATA_WIDTH-1:0] s_rdata,
  input logic [1:0] s_rresp,
  input logic s_rlast,
  input logic s_rvalid,
  input logic s_rready,

  input logic [ADDR_WIDTH-1:0] haddr,
  input logic hwrite,
  input logic [2:0] hsize,
  input logic [2:0] hburst,
  input logic [3:0] hprot,
  input logic [1:0] htrans,
  input logic hmastlock,
  input logic hnonsec,
  input logic [DATA_WIDTH-1:0] hwdata,
  input logic [DATA_WIDTH-1:0] hrdata,
  input logic hready,
  input logic hresp
);

  default clocking cb @(posedge clk); endclocking

  // AXI source-side payloads must remain stable while the bridge applies
  // backpressure. This catches both a bad driver and a bad READY policy.
  ap_aw_stable_when_stalled: assert property (
    disable iff (!rst_n) s_awvalid && !s_awready |=> s_awvalid &&
      $stable({s_awid, s_awaddr, s_awlen, s_awsize, s_awburst})
  ) else $error("AXI AW payload changed while stalled");

  ap_w_stable_when_stalled: assert property (
    disable iff (!rst_n) s_wvalid && !s_wready |=> s_wvalid && $stable({s_wdata, s_wstrb, s_wlast})
  ) else $error("AXI W payload changed while stalled");

  ap_ar_stable_when_stalled: assert property (
    disable iff (!rst_n) s_arvalid && !s_arready |=> s_arvalid &&
      $stable({s_arid, s_araddr, s_arlen, s_arsize, s_arburst})
  ) else $error("AXI AR payload changed while stalled");

  // AXI response producer side must hold the response through downstream
  // backpressure. These two properties directly protect B and R correctness.
  ap_b_stable_when_stalled: assert property (
    disable iff (!rst_n) s_bvalid && !s_bready |=> s_bvalid && $stable({s_bid, s_bresp})
  ) else $error("AXI B response changed while stalled");

  ap_r_stable_when_stalled: assert property (
    disable iff (!rst_n) s_rvalid && !s_rready |=> s_rvalid &&
      $stable({s_rid, s_rdata, s_rresp, s_rlast})
  ) else $error("AXI R response changed while stalled");

  // While the AHB slave inserts a wait state, the bridge keeps this active
  // transfer unchanged. htrans[1] identifies NONSEQ or SEQ transfers.
  ap_ahb_stable_when_waiting: assert property (
    disable iff (!rst_n) htrans[1] && !hready |=> htrans[1] &&
      $stable({haddr, hwrite, hsize, hburst, hprot, htrans, hmastlock, hnonsec, hwdata})
  ) else $error("AHB control/data changed while HREADY was low");

  // Reset is intentionally strict in this learning design: no AXI handshake
  // or stale response remains one clock after reset has been sampled.
  ap_reset_quiet: assert property (
    !rst_n |=> (!s_bvalid && !s_rvalid)
  ) else $error("Bridge exposed AXI activity during reset");

endmodule

// Wildcard port connection is intentional: assertion port names mirror the
// bridge top-level exactly. Parameters are passed explicitly for elaboration.
bind axi4_ahb5_lite_bridge axi4_ahb5_lite_bridge_assert #(
  .ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .ID_WIDTH(ID_WIDTH)
) u_axi4_ahb5_lite_bridge_assert (.*);
