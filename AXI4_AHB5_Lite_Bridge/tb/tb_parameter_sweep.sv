`timescale 1ns/1ps

// Elaboration contract test for every supported FIFO depth.  Functional
// behavior is covered by tb_cocotb_bridge; this test prevents a later edit
// from silently breaking one of the advertised parameter values.
module bridge_parameter_probe #(
  parameter int FIFO_DEPTH = 8
);
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [3:0] s_awid, s_arid;
  logic [31:0] s_awaddr, s_wdata, s_araddr;
  logic [7:0] s_awlen, s_arlen;
  logic [2:0] s_awsize, s_arsize;
  logic [1:0] s_awburst, s_arburst;
  logic s_awvalid, s_awready, s_wlast, s_wvalid, s_wready, s_arvalid, s_arready;
  logic [3:0] s_wstrb;
  logic [3:0] s_bid, s_rid;
  logic [1:0] s_bresp, s_rresp;
  logic s_bvalid, s_bready;
  logic [31:0] s_rdata;
  logic s_rlast, s_rvalid, s_rready;
  logic [31:0] haddr;
  logic hwrite;
  logic [2:0] hsize, hburst;
  logic [3:0] hprot;
  logic [1:0] htrans;
  logic hmastlock, hnonsec;
  logic [31:0] hwdata;
  logic [31:0] hrdata = '0;
  logic hready = 1'b1;
  logic hresp = 1'b0;

  axi4_ahb5_lite_bridge #(
    .FIFO_DEPTH(FIFO_DEPTH),
    .MAX_BURST_BEATS(FIFO_DEPTH)
  ) dut (.*);

  initial begin
    s_awid = '0; s_awaddr = '0; s_awlen = '0; s_awsize = '0;
    s_awburst = '0; s_awvalid = 1'b0; s_wdata = '0; s_wstrb = '0;
    s_wlast = 1'b0; s_wvalid = 1'b0; s_bready = 1'b0;
    s_arid = '0; s_araddr = '0; s_arlen = '0; s_arsize = '0;
    s_arburst = '0; s_arvalid = 1'b0; s_rready = 1'b0;
  end
endmodule

module tb_parameter_sweep;
  bridge_parameter_probe #(.FIFO_DEPTH(8))   depth_8();
  bridge_parameter_probe #(.FIFO_DEPTH(16))  depth_16();
  bridge_parameter_probe #(.FIFO_DEPTH(32))  depth_32();
  bridge_parameter_probe #(.FIFO_DEPTH(64))  depth_64();
  bridge_parameter_probe #(.FIFO_DEPTH(128)) depth_128();

  initial begin
    #1;
    $display("PARAMETER_SWEEP_PASS: FIFO_DEPTH=8/16/32/64/128 elaborated");
    $finish;
  end
endmodule
