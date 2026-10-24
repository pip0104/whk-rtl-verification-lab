`ifndef AXI4_AHB5_LITE_BRIDGE_PKG_SV
`define AXI4_AHB5_LITE_BRIDGE_PKG_SV

package axi4_ahb5_lite_bridge_pkg;

  // AXI4 burst encodings.
  localparam logic [1:0] AXI_BURST_FIXED = 2'b00;
  localparam logic [1:0] AXI_BURST_INCR  = 2'b01;
  localparam logic [1:0] AXI_BURST_WRAP  = 2'b10;

  // AXI4 response encodings.
  localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
  localparam logic [1:0] AXI_RESP_DECERR = 2'b11;

  // AHB-Lite transfer encodings.
  localparam logic [1:0] AHB_TRANS_IDLE   = 2'b00;
  localparam logic [1:0] AHB_TRANS_NONSEQ = 2'b10;
  localparam logic [1:0] AHB_TRANS_SEQ    = 2'b11;

  // AHB-Lite burst encodings.
  localparam logic [2:0] AHB_BURST_SINGLE = 3'b000;
  localparam logic [2:0] AHB_BURST_INCR   = 3'b001;
  localparam logic [2:0] AHB_BURST_WRAP4  = 3'b010;
  localparam logic [2:0] AHB_BURST_INCR4  = 3'b011;
  localparam logic [2:0] AHB_BURST_WRAP8  = 3'b100;
  localparam logic [2:0] AHB_BURST_INCR8  = 3'b101;
  localparam logic [2:0] AHB_BURST_WRAP16 = 3'b110;
  localparam logic [2:0] AHB_BURST_INCR16 = 3'b111;

endpackage

`endif
