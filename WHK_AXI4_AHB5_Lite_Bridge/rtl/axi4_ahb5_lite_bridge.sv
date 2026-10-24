`timescale 1ns/1ps

// Learning-oriented AXI4 Slave to AHB5-Lite Master bridge.
//
// Microarchitecture:
//   * A single command FIFO preserves the global arrival order of AW and AR.
//   * A write-data FIFO receives W independently from AW.
//   * The AHB backend issues only one active command/beat at any time.
//   * A whole write burst is buffered and prevalidated before any AHB write.
//   * Each AXI beat becomes a separate address/data-phase AHB SINGLE.
//
// The legal subset, error policy and response order are defined in
// docs/bridge_spec.md.  Keep this module and the specification synchronized.

module axi4_ahb5_lite_bridge #(
  parameter int ADDR_WIDTH      = 32,
  parameter int DATA_WIDTH      = 32,
  parameter int ID_WIDTH        = 4,
  parameter int FIFO_DEPTH      = 16,
  parameter int MAX_BURST_BEATS = FIFO_DEPTH,
  parameter logic [3:0] AHB_HPROT_DEFAULT = 4'b0011,
  parameter logic       AHB_HNONSEC_DEFAULT = 1'b0
) (
  input  logic                  clk,
  input  logic                  rst_n,

  // AXI4 Slave write-address channel.
  input  logic [ID_WIDTH-1:0]   s_awid,
  input  logic [ADDR_WIDTH-1:0] s_awaddr,
  input  logic [7:0]            s_awlen,
  input  logic [2:0]            s_awsize,
  input  logic [1:0]            s_awburst,
  input  logic                  s_awvalid,
  output logic                  s_awready,

  // AXI4 Slave write-data channel.
  input  logic [DATA_WIDTH-1:0] s_wdata,
  input  logic [DATA_WIDTH/8-1:0] s_wstrb,
  input  logic                  s_wlast,
  input  logic                  s_wvalid,
  output logic                  s_wready,

  // AXI4 Slave write-response channel.
  output logic [ID_WIDTH-1:0]   s_bid,
  output logic [1:0]            s_bresp,
  output logic                  s_bvalid,
  input  logic                  s_bready,

  // AXI4 Slave read-address channel.
  input  logic [ID_WIDTH-1:0]   s_arid,
  input  logic [ADDR_WIDTH-1:0] s_araddr,
  input  logic [7:0]            s_arlen,
  input  logic [2:0]            s_arsize,
  input  logic [1:0]            s_arburst,
  input  logic                  s_arvalid,
  output logic                  s_arready,

  // AXI4 Slave read-data channel.
  output logic [ID_WIDTH-1:0]   s_rid,
  output logic [DATA_WIDTH-1:0] s_rdata,
  output logic [1:0]            s_rresp,
  output logic                  s_rlast,
  output logic                  s_rvalid,
  input  logic                  s_rready,

  // AHB5-Lite Master interface. Optional AHB5 sideband signals are tied to
  // parameterized defaults; exclusive accesses are intentionally unsupported.
  output logic [ADDR_WIDTH-1:0] haddr,
  output logic                  hwrite,
  output logic [2:0]            hsize,
  output logic [2:0]            hburst,
  output logic [3:0]            hprot,
  output logic [1:0]            htrans,
  output logic                  hmastlock,
  output logic                  hnonsec,
  output logic [DATA_WIDTH-1:0] hwdata,
  input  logic [DATA_WIDTH-1:0] hrdata,
  input  logic                  hready,
  input  logic                  hresp
);

  import axi4_ahb5_lite_bridge_pkg::*;

  localparam int BYTE_LANES  = DATA_WIDTH / 8;
  localparam int PTR_W       = $clog2(FIFO_DEPTH);
  localparam int COUNT_W     = $clog2(FIFO_DEPTH + 1);
  localparam int MAX_AXSIZE  = $clog2(BYTE_LANES);

  typedef struct packed {
    logic                  is_write;
    logic [ID_WIDTH-1:0]   id;
    logic [ADDR_WIDTH-1:0] addr;
    logic [7:0]            len;
    logic [2:0]            size;
    logic [1:0]            burst;
    logic                  descriptor_illegal;
  } cmd_t;

  typedef struct packed {
    logic [DATA_WIDTH-1:0] data;
    logic [BYTE_LANES-1:0] strb;
    logic                  last;
  } wdata_t;

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_VALIDATE_CMD,
    ST_VALIDATE_WRITE,
    ST_PREPARE_BEAT,
    ST_AHB_ADDRESS,
    ST_AHB_WAIT,
    ST_INVALID_WRITE_DRAIN,
    ST_READ_RESPONSE,
    ST_WRITE_RESPONSE
  } state_t;

  state_t state_q;

  cmd_t   cmd_mem [0:FIFO_DEPTH-1];
  wdata_t wdata_mem [0:FIFO_DEPTH-1];
  logic [PTR_W-1:0] cmd_wr_ptr_q, cmd_rd_ptr_q;
  logic [PTR_W-1:0] wdata_wr_ptr_q, wdata_rd_ptr_q;
  logic [COUNT_W-1:0] cmd_count_q, wdata_count_q;

  cmd_t active_cmd_q;
  cmd_t cmd_head;
  wdata_t wdata_head;
  logic [7:0] active_beat_q;
  logic [7:0] validate_beat_q;
  logic [PTR_W-1:0] validate_ptr_q;
  wdata_t validation_wdata;
  logic [1:0] write_resp_q;
  logic [1:0] read_resp_q;
  logic [1:0] read_terminal_resp_q;
  logic [DATA_WIDTH-1:0] read_data_q;
  logic read_terminal_q;

  logic cmd_full, cmd_empty, wdata_full, wdata_empty;
  logic cmd_push_aw, cmd_push_ar, cmd_push, cmd_pop;
  logic wdata_push, wdata_pop;
  logic head_is_write;
  logic head_write_ready;
  logic active_last_beat;
  logic active_wdata_legal;
  logic [ADDR_WIDTH-1:0] active_addr;
  logic [BYTE_LANES-1:0] active_expected_strb;
  logic [BYTE_LANES-1:0] wdata_head_strb;
  logic wdata_head_last;

  // --------------------------------------------------------------------------
  // Functions shared by RTL and verification intent.
  // --------------------------------------------------------------------------

  function automatic logic descriptor_is_illegal(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [7:0]            len,
    input logic [2:0]            size,
    input logic [1:0]            burst
  );
    int unsigned step_bytes;
    int unsigned beats;
    longint unsigned last_byte;
    begin
      descriptor_is_illegal = 1'b0;
      beats = int'(len) + 1;
      step_bytes = 1 << size;

      if (beats > MAX_BURST_BEATS)
        descriptor_is_illegal = 1'b1;
      if (size > MAX_AXSIZE)
        descriptor_is_illegal = 1'b1;
      if ((addr & (step_bytes - 1)) != '0)
        descriptor_is_illegal = 1'b1;
      if (burst == 2'b11)
        descriptor_is_illegal = 1'b1;
      if ((burst == AXI_BURST_FIXED) && (beats > 16))
        descriptor_is_illegal = 1'b1;
      // INCR spans every beat; FIXED spans only one transfer; legal WRAP
      // blocks (at most 16*4 bytes) remain wholly inside their 4KB page.
      last_byte = addr;
      if (burst == AXI_BURST_INCR)
        last_byte = last_byte + beats * step_bytes - 1;
      else if (burst == AXI_BURST_FIXED)
        last_byte = last_byte + step_bytes - 1;
      if (((last_byte >> 12) != (addr >> 12)) ||
          ((ADDR_WIDTH < 64) && ((last_byte >> ADDR_WIDTH) != 0)))
        descriptor_is_illegal = 1'b1;
      if ((burst == AXI_BURST_WRAP) &&
          !((beats == 2) || (beats == 4) || (beats == 8) || (beats == 16)))
        descriptor_is_illegal = 1'b1;
    end
  endfunction

  function automatic logic [ADDR_WIDTH-1:0] burst_beat_addr(
    input cmd_t      command,
    input logic [7:0] beat
  );
    longint unsigned step_bytes;
    longint unsigned beats;
    longint unsigned wrap_bytes;
    longint unsigned lower_boundary;
    longint unsigned next_addr;
    begin
      step_bytes = 1 << command.size;
      beats = int'(command.len) + 1;
      if (command.burst == AXI_BURST_FIXED) begin
        burst_beat_addr = command.addr;
      end else if (command.burst == AXI_BURST_INCR) begin
        burst_beat_addr = command.addr + (beat * step_bytes);
      end else begin
        // WRAP range is a power of two in the supported subset. At most one
        // wrap can occur when calculating a beat inside one burst.
        wrap_bytes = beats * step_bytes;
        lower_boundary = command.addr & ~(wrap_bytes - 1);
        next_addr = command.addr + (beat * step_bytes);
        if (next_addr >= (lower_boundary + wrap_bytes))
          next_addr = next_addr - wrap_bytes;
        burst_beat_addr = next_addr[ADDR_WIDTH-1:0];
      end
    end
  endfunction

  function automatic logic [BYTE_LANES-1:0] expected_wstrb(
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [2:0]            size
  );
    int unsigned step_bytes;
    int unsigned lane;
    begin
      step_bytes = 1 << size;
      lane = addr % BYTE_LANES;
      expected_wstrb = ((1 << step_bytes) - 1) << lane;
    end
  endfunction

  function automatic logic [DATA_WIDTH-1:0] byte_mask_from_strb(
    input logic [BYTE_LANES-1:0] strb
  );
    logic [DATA_WIDTH-1:0] mask;
    begin
      mask = '0;
      for (int lane = 0; lane < BYTE_LANES; lane++)
        mask[(lane * 8) +: 8] = {8{strb[lane]}};
      byte_mask_from_strb = mask;
    end
  endfunction

  function automatic logic [2:0] ahb_burst_encoding(input cmd_t command);
    begin
      // A conservative non-pipelined master uses an independent SINGLE for
      // every AXI beat. AXI addressing is preserved by burst_beat_addr.
      ahb_burst_encoding = AHB_BURST_SINGLE;
    end
  endfunction

  // --------------------------------------------------------------------------
  // FIFO and handshake bookkeeping.
  // --------------------------------------------------------------------------

  assign cmd_full    = (cmd_count_q == FIFO_DEPTH);
  assign cmd_empty   = (cmd_count_q == '0);
  assign wdata_full  = (wdata_count_q == FIFO_DEPTH);
  assign wdata_empty = (wdata_count_q == '0);

  // Give AW priority over AR when the single command FIFO has one free slot.
  // This guarantees that at most one command enters the FIFO per cycle.
  always_comb begin
    s_awready = rst_n && !cmd_full;
    s_arready = rst_n && !cmd_full && !s_awvalid;
    s_wready  = rst_n && !wdata_full;
  end

  always_comb begin
    validation_wdata = wdata_mem[validate_ptr_q];
  end

  assign cmd_push_aw = s_awvalid && s_awready;
  assign cmd_push_ar = s_arvalid && s_arready;
  assign cmd_push    = cmd_push_aw || cmd_push_ar;
  assign wdata_push  = s_wvalid && s_wready;

  // A read is immediately executable. A write waits until all of its W beats
  // have arrived so every WSTRB/WLAST can be checked before any AHB side effect.
  always_comb begin
    cmd_head = '0;
    head_is_write = 1'b0;
    head_write_ready = 1'b0;
    if (!cmd_empty) begin
      cmd_head = cmd_mem[cmd_rd_ptr_q];
      head_is_write = cmd_head.is_write;
      if (cmd_head.is_write)
        // A structurally illegal descriptor (for example, a burst longer
        // than the configured FIFO) must enter the reject-and-drain path
        // immediately.  Waiting for the whole burst here would deadlock an
        // oversized write because it can never fit in the W FIFO at once.
        head_write_ready = cmd_head.descriptor_illegal ||
                           (int'(wdata_count_q) >= (int'(cmd_head.len) + 1));
    end
  end

  // Keep unpacked-memory member selects in procedural logic. This avoids an
  // Icarus elaboration defect while preserving the combinational intent.
  always_comb begin
    wdata_head = '0;
    wdata_head_strb = '0;
    wdata_head_last = 1'b0;
    if (!wdata_empty) begin
      wdata_head = wdata_mem[wdata_rd_ptr_q];
      wdata_head_strb = wdata_head.strb;
      wdata_head_last = wdata_head.last;
    end
  end

  assign cmd_pop = (state_q == ST_IDLE) && !cmd_empty &&
                    (!head_is_write || head_write_ready);

  assign active_last_beat = (active_beat_q == active_cmd_q.len);
  assign active_addr = burst_beat_addr(active_cmd_q, active_beat_q);
  assign active_expected_strb = expected_wstrb(active_addr, active_cmd_q.size);
  assign active_wdata_legal = !wdata_empty &&
                               (wdata_head_strb == active_expected_strb) &&
                               (wdata_head_last == active_last_beat);

  // A W entry is consumed only after an AHB write completes or while rejecting
  // a write transaction. Thus the data remains stable during HREADY wait states.
  assign wdata_pop = ((state_q == ST_AHB_WAIT) && hready && active_cmd_q.is_write) ||
                     ((state_q == ST_INVALID_WRITE_DRAIN) && !wdata_empty);

  // --------------------------------------------------------------------------
  // Sequential state, FIFOs and response payloads.
  // --------------------------------------------------------------------------

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state_q              <= ST_IDLE;
      cmd_wr_ptr_q         <= '0;
      cmd_rd_ptr_q         <= '0;
      cmd_count_q          <= '0;
      wdata_wr_ptr_q       <= '0;
      wdata_rd_ptr_q       <= '0;
      wdata_count_q        <= '0;
      active_cmd_q         <= '0;
      active_beat_q        <= '0;
      validate_beat_q      <= '0;
      validate_ptr_q       <= '0;
      write_resp_q         <= AXI_RESP_OKAY;
      read_resp_q          <= AXI_RESP_OKAY;
      read_terminal_resp_q <= AXI_RESP_OKAY;
      read_data_q          <= '0;
      read_terminal_q      <= 1'b0;
    end else begin
      // Command FIFO write side. AW and AR are intentionally mutually
      // exclusive through READY generation above.
      if (cmd_push_aw) begin
        // Whole packed-structure writes avoid tool-specific limitations on
        // unpacked-memory member selections while keeping the field layout.
        cmd_mem[cmd_wr_ptr_q] <= {
          1'b1, s_awid, s_awaddr, s_awlen, s_awsize, s_awburst,
          descriptor_is_illegal(s_awaddr, s_awlen, s_awsize, s_awburst)
        };
        cmd_wr_ptr_q <= cmd_wr_ptr_q + 1'b1;
      end else if (cmd_push_ar) begin
        cmd_mem[cmd_wr_ptr_q] <= {
          1'b0, s_arid, s_araddr, s_arlen, s_arsize, s_arburst,
          descriptor_is_illegal(s_araddr, s_arlen, s_arsize, s_arburst)
        };
        cmd_wr_ptr_q <= cmd_wr_ptr_q + 1'b1;
      end
      if (cmd_pop)
        cmd_rd_ptr_q <= cmd_rd_ptr_q + 1'b1;
      case ({cmd_push, cmd_pop})
        2'b10: cmd_count_q <= cmd_count_q + 1'b1;
        2'b01: cmd_count_q <= cmd_count_q - 1'b1;
        default: cmd_count_q <= cmd_count_q;
      endcase

      // Write-data FIFO.
      if (wdata_push) begin
        wdata_mem[wdata_wr_ptr_q] <= {s_wdata, s_wstrb, s_wlast};
        wdata_wr_ptr_q <= wdata_wr_ptr_q + 1'b1;
      end
      if (wdata_pop)
        wdata_rd_ptr_q <= wdata_rd_ptr_q + 1'b1;
      case ({wdata_push, wdata_pop})
        2'b10: wdata_count_q <= wdata_count_q + 1'b1;
        2'b01: wdata_count_q <= wdata_count_q - 1'b1;
        default: wdata_count_q <= wdata_count_q;
      endcase

      case (state_q)
        ST_IDLE: begin
          if (cmd_pop) begin
            active_cmd_q    <= cmd_head;
            active_beat_q   <= '0;
            read_terminal_q <= 1'b0;
            write_resp_q    <= AXI_RESP_OKAY;
            state_q         <= ST_VALIDATE_CMD;
          end
        end

        ST_VALIDATE_CMD: begin
          if (active_cmd_q.descriptor_illegal) begin
            if (active_cmd_q.is_write) begin
              write_resp_q <= AXI_RESP_DECERR;
              state_q      <= ST_INVALID_WRITE_DRAIN;
            end else begin
              read_data_q          <= '0;
              read_resp_q          <= AXI_RESP_DECERR;
              read_terminal_resp_q <= AXI_RESP_DECERR;
              read_terminal_q      <= 1'b1;
              state_q              <= ST_READ_RESPONSE;
            end
          end else if (active_cmd_q.is_write) begin
            // All W beats are buffered before command selection. Walk them
            // without popping: a malformed LAST/strobe at ANY position must
            // be rejected before the first externally visible AHB write.
            validate_beat_q <= '0;
            validate_ptr_q <= wdata_rd_ptr_q;
            state_q <= ST_VALIDATE_WRITE;
          end else begin
            state_q <= ST_PREPARE_BEAT;
          end
        end

        ST_VALIDATE_WRITE: begin
          if ((validation_wdata.strb != expected_wstrb(
                burst_beat_addr(active_cmd_q, validate_beat_q), active_cmd_q.size)) ||
              (validation_wdata.last != (validate_beat_q == active_cmd_q.len))) begin
            write_resp_q <= AXI_RESP_DECERR;
            state_q <= ST_INVALID_WRITE_DRAIN;
          end else if (validate_beat_q == active_cmd_q.len) begin
            state_q <= ST_PREPARE_BEAT;
          end else begin
            validate_beat_q <= validate_beat_q + 1'b1;
            validate_ptr_q <= validate_ptr_q + 1'b1;
          end
        end

        ST_PREPARE_BEAT: begin
          // Validate WSTRB and WLAST before any AHB control is asserted.
          if (active_cmd_q.is_write && !active_wdata_legal) begin
            write_resp_q <= AXI_RESP_DECERR;
            state_q      <= ST_INVALID_WRITE_DRAIN;
          end else begin
            state_q <= ST_AHB_ADDRESS;
          end
        end

        ST_AHB_ADDRESS: begin
          if (hready)
            state_q <= ST_AHB_WAIT;
        end

        ST_AHB_WAIT: begin
          if (hready) begin
            if (active_cmd_q.is_write) begin
              if (hresp) begin
                write_resp_q <= AXI_RESP_SLVERR;
                if (active_last_beat)
                  state_q <= ST_WRITE_RESPONSE;
                else begin
                  active_beat_q <= active_beat_q + 1'b1;
                  state_q       <= ST_INVALID_WRITE_DRAIN;
                end
              end else if (active_last_beat) begin
                write_resp_q <= AXI_RESP_OKAY;
                state_q      <= ST_WRITE_RESPONSE;
              end else begin
                active_beat_q <= active_beat_q + 1'b1;
                state_q       <= ST_PREPARE_BEAT;
              end
            end else begin
              if (hresp) begin
                read_data_q          <= '0;
                read_resp_q          <= AXI_RESP_SLVERR;
                read_terminal_resp_q <= AXI_RESP_SLVERR;
                read_terminal_q      <= 1'b1;
              end else begin
                read_data_q <= hrdata & byte_mask_from_strb(active_expected_strb);
                read_resp_q <= AXI_RESP_OKAY;
              end
              state_q <= ST_READ_RESPONSE;
            end
          end
        end

        ST_INVALID_WRITE_DRAIN: begin
          // For a malformed descriptor, W data may arrive after the command
          // has already been rejected.  Consume only real entries and wait
          // without advancing when the FIFO is temporarily empty.
          if (!wdata_empty) begin
            if (active_last_beat) begin
              state_q <= ST_WRITE_RESPONSE;
            end else begin
              active_beat_q <= active_beat_q + 1'b1;
            end
          end
        end

        ST_READ_RESPONSE: begin
          if (s_rready) begin
            if (active_last_beat) begin
              state_q <= ST_IDLE;
            end else begin
              active_beat_q <= active_beat_q + 1'b1;
              if (read_terminal_q) begin
                read_data_q <= '0;
                read_resp_q <= read_terminal_resp_q;
                state_q     <= ST_READ_RESPONSE;
              end else begin
                state_q <= ST_PREPARE_BEAT;
              end
            end
          end
        end

        ST_WRITE_RESPONSE: begin
          if (s_bready)
            state_q <= ST_IDLE;
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // Combinational interface outputs.
  // --------------------------------------------------------------------------

  always_comb begin
    s_bid    = active_cmd_q.id;
    s_bresp  = write_resp_q;
    s_bvalid = (state_q == ST_WRITE_RESPONSE);

    s_rid    = active_cmd_q.id;
    s_rdata  = read_data_q;
    s_rresp  = read_resp_q;
    s_rlast  = active_last_beat;
    s_rvalid = (state_q == ST_READ_RESPONSE);

    haddr      = active_addr;
    hwrite     = active_cmd_q.is_write;
    hsize      = active_cmd_q.size;
    hburst     = ahb_burst_encoding(active_cmd_q);
    hprot      = AHB_HPROT_DEFAULT;
    hmastlock  = 1'b0;
    hnonsec    = AHB_HNONSEC_DEFAULT;
    hwdata     = '0;
    htrans     = AHB_TRANS_IDLE;

    if (active_cmd_q.is_write && !wdata_empty)
      hwdata = wdata_head.data & byte_mask_from_strb(active_expected_strb);

    // Address acceptance is distinct from subsequent data completion. During
    // the data phase offer IDLE as the next address, keeping write data at the
    // FIFO head until HREADY completes this phase (including two-cycle ERROR).
    if (state_q == ST_AHB_ADDRESS)
      htrans = AHB_TRANS_NONSEQ;
  end

  // These are elaboration-time contract checks, not protocol assertions.
  initial begin
    if ((ADDR_WIDTH != 32) || (DATA_WIDTH != 32))
      $fatal(1, "The verified interface contract requires 32-bit address/data");
    if (DATA_WIDTH % 8 != 0)
      $fatal(1, "DATA_WIDTH must be a whole number of bytes");
    if ((FIFO_DEPTH < 8) || (FIFO_DEPTH > 128) || ((FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0))
      $fatal(1, "FIFO_DEPTH must be a power of two from 8 through 128");
    if ((MAX_BURST_BEATS < 2) || (MAX_BURST_BEATS > FIFO_DEPTH))
      $fatal(1, "MAX_BURST_BEATS must be from 2 through FIFO_DEPTH");
    if (ADDR_WIDTH > 64)
      $fatal(1, "Learning implementation supports ADDR_WIDTH up to 64");
  end

endmodule
