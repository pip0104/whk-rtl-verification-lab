`timescale 1ns/1ps

// Reusable, zero-wait-state AHB5-Lite memory model for directed bring-up.
// The UVM phase will wrap the same semantics in an AHB Slave Agent and add
// configurable wait/error injection. This small model keeps the first RTL
// smoke test self-contained.

module ahb5_lite_memory_model #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int MEM_BYTES  = 4096
) (
  input  logic clk,
  input  logic rst_n,
  input  logic [ADDR_WIDTH-1:0] haddr,
  input  logic hwrite,
  input  logic [2:0] hsize,
  input  logic [2:0] hburst,
  input  logic [3:0] hprot,
  input  logic [1:0] htrans,
  input  logic hmastlock,
  input  logic hnonsec,
  input  logic [DATA_WIDTH-1:0] hwdata,
  output logic [DATA_WIDTH-1:0] hrdata,
  output logic hready,
  output logic hresp
);

  localparam int BYTE_LANES = DATA_WIDTH / 8;
  localparam int ADDR_LSB   = $clog2(BYTE_LANES);
  localparam int MEM_WORDS  = MEM_BYTES / BYTE_LANES;
  localparam int INDEX_W    = $clog2(MEM_WORDS);

  logic [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];
  logic [INDEX_W-1:0] word_index;
  logic [BYTE_LANES-1:0] byte_enable;
  logic data_valid_q = 1'b0;
  logic data_write_q;
  logic [ADDR_WIDTH-1:0] data_addr_q;
  logic [2:0] data_size_q;

  function automatic logic [BYTE_LANES-1:0] hsize_byte_enable(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [2:0] size
  );
    int unsigned transfer_bytes;
    int unsigned lane;
    begin
      transfer_bytes = 1 << size;
      lane = addr % BYTE_LANES;
      hsize_byte_enable = ((1 << transfer_bytes) - 1) << lane;
    end
  endfunction

  assign word_index  = data_addr_q[ADDR_LSB +: INDEX_W];
  assign byte_enable = hsize_byte_enable(data_addr_q, data_size_q);
  assign hready      = 1'b1;
  assign hresp       = 1'b0;
  assign hrdata      = data_valid_q ? mem[word_index] : '0;

  // Use always rather than always_ff: this verification memory is also
  // initialized and accessed through backdoor helper routines.
  always @(posedge clk) begin
    if (!rst_n) begin
      data_valid_q <= 1'b0;
    end else if (hready) begin
      // HWDATA belongs to the PREVIOUS accepted address/control, even when
      // the currently offered address is IDLE or a different transaction.
      if (data_valid_q && data_write_q && !hresp) begin
        for (int lane = 0; lane < BYTE_LANES; lane++) begin
          if (byte_enable[lane])
            mem[word_index][lane*8 +: 8] <= hwdata[lane*8 +: 8];
        end
      end
      data_valid_q <= htrans[1];
      data_addr_q <= haddr;
      data_write_q <= hwrite;
      data_size_q <= hsize;
    end
  end

  // Backdoor helpers become useful when the UVM scoreboarding layer is added.
  task automatic backdoor_write(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [DATA_WIDTH-1:0] data
  );
    mem[addr[ADDR_LSB +: INDEX_W]] = data;
  endtask

  function automatic logic [DATA_WIDTH-1:0] backdoor_read(
    input logic [ADDR_WIDTH-1:0] addr
  );
    return mem[addr[ADDR_LSB +: INDEX_W]];
  endfunction

  initial begin
    if ((MEM_BYTES % BYTE_LANES) != 0)
      $fatal(1, "MEM_BYTES must be an integer number of DATA_WIDTH words");
    if ((MEM_WORDS & (MEM_WORDS - 1)) != 0)
      $fatal(1, "MEM_WORDS must be a power of two in this learning model");
    for (int word = 0; word < MEM_WORDS; word++)
      mem[word] = '0;
  end

endmodule
