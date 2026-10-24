`timescale 1ns/1ps

// Non-UVM smoke test. It exists for first RTL bring-up; later UVM tests must
// retain these scenarios as the quickest regression gate.

module tb_top_smoke;
  localparam int ADDR_WIDTH = 32;
  localparam int DATA_WIDTH = 32;
  localparam int ID_WIDTH   = 4;

  logic clk;
  logic rst_n;

  logic [ID_WIDTH-1:0] s_awid;
  logic [ADDR_WIDTH-1:0] s_awaddr;
  logic [7:0] s_awlen;
  logic [2:0] s_awsize;
  logic [1:0] s_awburst;
  logic s_awvalid, s_awready;

  logic [DATA_WIDTH-1:0] s_wdata;
  logic [DATA_WIDTH/8-1:0] s_wstrb;
  logic s_wlast, s_wvalid, s_wready;

  logic [ID_WIDTH-1:0] s_bid;
  logic [1:0] s_bresp;
  logic s_bvalid, s_bready;

  logic [ID_WIDTH-1:0] s_arid;
  logic [ADDR_WIDTH-1:0] s_araddr;
  logic [7:0] s_arlen;
  logic [2:0] s_arsize;
  logic [1:0] s_arburst;
  logic s_arvalid, s_arready;

  logic [ID_WIDTH-1:0] s_rid;
  logic [DATA_WIDTH-1:0] s_rdata;
  logic [1:0] s_rresp;
  logic s_rlast, s_rvalid, s_rready;

  logic [ADDR_WIDTH-1:0] haddr;
  logic hwrite;
  logic [2:0] hsize, hburst;
  logic [3:0] hprot;
  logic [1:0] htrans;
  logic hmastlock, hnonsec;
  logic [DATA_WIDTH-1:0] hwdata, hrdata;
  logic hready, hresp;

  axi4_ahb5_lite_bridge #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH(ID_WIDTH),
    .FIFO_DEPTH(8),
    .MAX_BURST_BEATS(8)
  ) dut (.*);

  ahb5_lite_memory_model #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .MEM_BYTES(4096)
  ) ahb_mem (.*);

  always #5 clk = ~clk;

  // VCD is portable: Verdi can open it and no proprietary PLI setup is needed.
  initial begin
    $dumpfile("smoke.vcd");
    $dumpvars(0, tb_top_smoke);
  end

  task automatic send_aw(
    input logic [ID_WIDTH-1:0] id,
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [7:0] len,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    begin
      @(negedge clk);
      s_awid = id;
      s_awaddr = addr;
      s_awlen = len;
      s_awsize = size;
      s_awburst = burst;
      s_awvalid = 1'b1;
      do @(posedge clk); while (!s_awready);
      @(negedge clk);
      s_awvalid = 1'b0;
    end
  endtask

  task automatic send_w(
    input logic [DATA_WIDTH-1:0] data,
    input logic [DATA_WIDTH/8-1:0] strb,
    input logic last
  );
    begin
      @(negedge clk);
      s_wdata = data;
      s_wstrb = strb;
      s_wlast = last;
      s_wvalid = 1'b1;
      do @(posedge clk); while (!s_wready);
      @(negedge clk);
      s_wvalid = 1'b0;
    end
  endtask

  task automatic wait_b(
    input logic [ID_WIDTH-1:0] expected_id,
    input logic [1:0] expected_resp
  );
    begin
      do @(posedge clk); while (!s_bvalid);
      if ((s_bid !== expected_id) || (s_bresp !== expected_resp))
        $fatal(1, "B mismatch: id=%0h resp=%0h expected id=%0h resp=%0h",
               s_bid, s_bresp, expected_id, expected_resp);
    end
  endtask

  task automatic send_ar(
    input logic [ID_WIDTH-1:0] id,
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [7:0] len,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    begin
      @(negedge clk);
      s_arid = id;
      s_araddr = addr;
      s_arlen = len;
      s_arsize = size;
      s_arburst = burst;
      s_arvalid = 1'b1;
      do @(posedge clk); while (!s_arready);
      @(negedge clk);
      s_arvalid = 1'b0;
    end
  endtask

  task automatic wait_r(
    input logic [ID_WIDTH-1:0] expected_id,
    input logic [DATA_WIDTH-1:0] expected_data,
    input logic [1:0] expected_resp,
    input logic expected_last
  );
    begin
      do @(posedge clk); while (!s_rvalid);
      if ((s_rid !== expected_id) || (s_rdata !== expected_data) ||
          (s_rresp !== expected_resp) || (s_rlast !== expected_last))
        $fatal(1, "R mismatch: id=%0h data=%0h resp=%0h last=%0b; expected id=%0h data=%0h resp=%0h last=%0b",
               s_rid, s_rdata, s_rresp, s_rlast,
               expected_id, expected_data, expected_resp, expected_last);
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    s_awid = '0;
    s_awaddr = '0;
    s_awlen = '0;
    s_awsize = '0;
    s_awburst = '0;
    s_awvalid = 1'b0;
    s_wdata = '0;
    s_wstrb = '0;
    s_wlast = 1'b0;
    s_wvalid = 1'b0;
    s_bready = 1'b1;
    s_arid = '0;
    s_araddr = '0;
    s_arlen = '0;
    s_arsize = '0;
    s_arburst = '0;
    s_arvalid = 1'b0;
    s_rready = 1'b1;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // 32-bit single write/read.
    send_aw(4'h1, 32'h0000_0020, 8'd0, 3'd2, 2'b01);
    send_w(32'hDEAD_BEEF, 4'b1111, 1'b1);
    wait_b(4'h1, 2'b00);

    send_ar(4'h2, 32'h0000_0020, 8'd0, 3'd2, 2'b01);
    wait_r(4'h2, 32'hDEAD_BEEF, 2'b00, 1'b1);

    // 8-bit narrow write/read on byte lane 2 of the same 32-bit word.
    send_aw(4'h3, 32'h0000_0022, 8'd0, 3'd0, 2'b01);
    send_w(32'h00AA_0000, 4'b0100, 1'b1);
    wait_b(4'h3, 2'b00);

    send_ar(4'h4, 32'h0000_0022, 8'd0, 3'd0, 2'b01);
    wait_r(4'h4, 32'h00AA_0000, 2'b00, 1'b1);

    $display("SMOKE_TEST_PASS: single full-width and narrow transfers passed");
    #10;
    $finish;
  end

  initial begin
    repeat (300) @(posedge clk);
    $fatal(1, "SMOKE_TEST_TIMEOUT");
  end

endmodule
