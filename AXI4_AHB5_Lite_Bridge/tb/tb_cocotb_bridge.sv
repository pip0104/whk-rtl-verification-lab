`timescale 1ns/1ps

// Simulation top used by the portable cocotb regression.
//
// The AHB slave is deliberately driven from Python rather than instantiated
// here.  That lets the test environment inject HREADY stalls and HRESP errors
// while observing every bridge-issued AHB beat.  The RTL itself is exactly the
// same DUT used by the directed smoke test.
module tb_cocotb_bridge;
  localparam int ADDR_WIDTH = 32;
  localparam int DATA_WIDTH = 32;
  localparam int ID_WIDTH   = 4;

  logic clk;
  logic rst_n;

  logic [ID_WIDTH-1:0]   s_awid;
  logic [ADDR_WIDTH-1:0] s_awaddr;
  logic [7:0]            s_awlen;
  logic [2:0]            s_awsize;
  logic [1:0]            s_awburst;
  logic                  s_awvalid;
  logic                  s_awready;

  logic [DATA_WIDTH-1:0]   s_wdata;
  logic [DATA_WIDTH/8-1:0] s_wstrb;
  logic                    s_wlast;
  logic                    s_wvalid;
  logic                    s_wready;

  logic [ID_WIDTH-1:0] s_bid;
  logic [1:0]          s_bresp;
  logic                s_bvalid;
  logic                s_bready;

  logic [ID_WIDTH-1:0]   s_arid;
  logic [ADDR_WIDTH-1:0] s_araddr;
  logic [7:0]            s_arlen;
  logic [2:0]            s_arsize;
  logic [1:0]            s_arburst;
  logic                  s_arvalid;
  logic                  s_arready;

  logic [ID_WIDTH-1:0]   s_rid;
  logic [DATA_WIDTH-1:0] s_rdata;
  logic [1:0]            s_rresp;
  logic                  s_rlast;
  logic                  s_rvalid;
  logic                  s_rready;

  logic [ADDR_WIDTH-1:0] haddr;
  logic                  hwrite;
  logic [2:0]            hsize;
  logic [2:0]            hburst;
  logic [3:0]            hprot;
  logic [1:0]            htrans;
  logic                  hmastlock;
  logic                  hnonsec;
  logic [DATA_WIDTH-1:0] hwdata;
  logic [DATA_WIDTH-1:0] hrdata;
  logic                  hready;
  logic                  hresp;

  axi4_ahb5_lite_bridge #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH(ID_WIDTH),
    .FIFO_DEPTH(16),
    .MAX_BURST_BEATS(16)
  ) dut (.*);

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    $dumpfile("bridge_regression.vcd");
    $dumpvars(0, tb_cocotb_bridge);
  end
endmodule
