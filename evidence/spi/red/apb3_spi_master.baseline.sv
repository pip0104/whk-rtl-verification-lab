`timescale 1ns/1ps

// APB3-programmable, single-chip-select SPI master.
//
// The controller deliberately keeps the data path small: TXDATA and RXDATA
// are one-entry registers.  CONTINUOUS therefore means that CS remains
// asserted between explicitly started frames; firmware must read RXDATA and
// issue the next START.  This makes every received frame observable instead
// of silently overwriting it in a hidden streaming FIFO.
module apb3_spi_master #(
  parameter integer ADDR_WIDTH = 32,
  parameter integer DATA_WIDTH = 32
) (
  input  wire                  pclk,
  input  wire                  presetn,

  // AMBA APB3 slave interface.
  input  wire [ADDR_WIDTH-1:0] paddr,
  input  wire                  psel,
  input  wire                  penable,
  input  wire                  pwrite,
  input  wire [DATA_WIDTH-1:0] pwdata,
  output reg  [DATA_WIDTH-1:0] prdata,
  output wire                  pready,
  output wire                  pslverr,

  // Standard four-wire SPI master interface.
  output reg                   spi_sclk,
  output reg                   spi_mosi,
  input  wire                  spi_miso,
  output reg                   spi_cs_n,
  output wire                  irq
);

  localparam [5:0] ADDR_CTRL       = 6'h00;
  localparam [5:0] ADDR_CLKDIV     = 6'h04;
  localparam [5:0] ADDR_TXDATA     = 6'h08;
  localparam [5:0] ADDR_RXDATA     = 6'h0c;
  localparam [5:0] ADDR_STATUS     = 6'h10;
  localparam [5:0] ADDR_IRQ_ENABLE = 6'h14;
  localparam [5:0] ADDR_IRQ_STATUS = 6'h18;

  // CTRL fields:
  //  [0] enable; [1] START (write-one command); [2] CPOL; [3] CPHA;
  //  [4] CONTINUOUS CS hold; [5] LSB_FIRST; [13:8] BITS_MINUS_1;
  //  [16] CS_RELEASE (write-one command when idle).
  reg [31:0] ctrl_reg;
  reg [15:0] clkdiv_reg;
  reg [31:0] tx_data;
  reg [31:0] rx_data;
  reg [3:0]  irq_enable;
  reg [3:0]  irq_status;
  reg        tx_valid;
  reg        rx_valid;
  reg        busy;

  // Transaction-latched configuration.  Writes to CTRL/CLKDIV while BUSY
  // only affect a later frame, which prevents a half-frame protocol change.
  reg        cpol_latched;
  reg        cpha_latched;
  reg        cont_latched;
  reg        lsb_latched;
  reg [5:0]  word_bits;
  reg [15:0] half_count;
  reg [5:0]  bit_index;
  reg        last_sample_pending;
  reg [31:0] tx_shift;
  reg [31:0] rx_shift;

  wire apb_access = psel && penable;
  wire apb_write  = apb_access && pwrite;
  wire apb_read   = apb_access && !pwrite;
  wire [5:0] reg_addr = paddr[5:0];
  wire addr_hi_zero = (paddr[ADDR_WIDTH-1:6] == {ADDR_WIDTH-6{1'b0}});
  wire valid_addr = addr_hi_zero && ((reg_addr == ADDR_CTRL) ||
                                     (reg_addr == ADDR_CLKDIV) ||
                                     (reg_addr == ADDR_TXDATA) ||
                                     (reg_addr == ADDR_RXDATA) ||
                                     (reg_addr == ADDR_STATUS) ||
                                     (reg_addr == ADDR_IRQ_ENABLE) ||
                                     (reg_addr == ADDR_IRQ_STATUS));

  assign pready  = 1'b1;  // no APB wait states
  assign pslverr = apb_access && !valid_addr;
  assign irq     = |(irq_enable & irq_status);

  function automatic select_tx_bit;
    input [31:0] value;
    input [5:0]  index;
    input [5:0]  bits;
    input        lsb_first;
    integer      position;
    begin
      if (lsb_first) begin
        select_tx_bit = value[index[4:0]];
      end
      else begin
        position = {26'd0, bits} - 1 - {26'd0, index};
        select_tx_bit = value[position];
      end
    end
  endfunction

  function automatic [31:0] insert_rx_bit;
    input [31:0] value;
    input [5:0]  index;
    input [5:0]  bits;
    input        lsb_first;
    input        sampled_bit;
    integer      position;
    reg [31:0]   result;
    begin
      result = value;
      if (lsb_first)
        result[index[4:0]] = sampled_bit;
      else begin
        position = {26'd0, bits} - 1 - {26'd0, index};
        result[position] = sampled_bit;
      end
      insert_rx_bit = result;
    end
  endfunction

  always @* begin
    prdata = 32'h0000_0000;
    if (valid_addr) begin
      case (reg_addr)
        ADDR_CTRL:       prdata = ctrl_reg;
        ADDR_CLKDIV:     prdata = {16'h0000, clkdiv_reg};
        ADDR_TXDATA:     prdata = tx_data;
        ADDR_RXDATA:     prdata = rx_data;
        ADDR_STATUS:     prdata = {25'h0000000,
                                   irq_status[3], irq_status[2],
                                   ctrl_reg[0], !spi_cs_n,
                                   rx_valid, !tx_valid, busy};
        ADDR_IRQ_ENABLE: prdata = {28'h0000000, irq_enable};
        ADDR_IRQ_STATUS: prdata = {28'h0000000, irq_status};
        default:         prdata = 32'h0000_0000;
      endcase
    end
  end

  always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      ctrl_reg            <= 32'h0000_0700; // 8 bits, disabled, mode 0
      clkdiv_reg          <= 16'd0;
      tx_data             <= 32'h0000_0000;
      rx_data             <= 32'h0000_0000;
      irq_enable          <= 4'h0;
      irq_status          <= 4'h0;
      tx_valid            <= 1'b0;
      rx_valid            <= 1'b0;
      busy                <= 1'b0;
      cpol_latched        <= 1'b0;
      cpha_latched        <= 1'b0;
      cont_latched        <= 1'b0;
      lsb_latched         <= 1'b0;
      word_bits           <= 6'd8;
      half_count          <= 16'd0;
      bit_index           <= 6'd0;
      last_sample_pending <= 1'b0;
      tx_shift            <= 32'h0000_0000;
      rx_shift            <= 32'h0000_0000;
      spi_sclk            <= 1'b0;
      spi_mosi            <= 1'b0;
      spi_cs_n            <= 1'b1;
    end
    else begin
      // APB software side effects.
      if (apb_write && valid_addr) begin
        case (reg_addr)
          ADDR_CTRL: begin
            // START and CS_RELEASE are commands, not stored state.
            ctrl_reg <= {pwdata[31:17], 1'b0, pwdata[15:14], 1'b0,
                         pwdata[12:2], 1'b0, pwdata[0]};

            // Releasing an already held continuous transaction is safe only
            // between frames. A busy transfer is never truncated by RELEASE.
            if (pwdata[16] && !busy) begin
              spi_cs_n <= 1'b1;
              spi_sclk <= pwdata[2];
              spi_mosi <= 1'b0;
            end

            // START consumes the one-entry TX buffer and atomically latches
            // all waveform-defining settings from this APB write.
            if (pwdata[1] && pwdata[0] && !busy && tx_valid) begin
              busy                <= 1'b1;
              cpol_latched        <= pwdata[2];
              cpha_latched        <= pwdata[3];
              cont_latched        <= pwdata[4];
              lsb_latched         <= pwdata[5];
              word_bits           <= {1'b0, pwdata[12:8]} + 6'd1;
              half_count          <= 16'd0;
              bit_index           <= 6'd0;
              last_sample_pending <= 1'b0;
              tx_shift            <= tx_data;
              rx_shift            <= 32'h0000_0000;
              tx_valid            <= 1'b0;
              spi_cs_n            <= 1'b0;
              spi_sclk            <= pwdata[2];
              spi_mosi            <= pwdata[3] ? 1'b0 :
                                      select_tx_bit(tx_data, 6'd0,
                                                    {1'b0, pwdata[12:8]} + 6'd1,
                                                    pwdata[5]);
            end
          end
          ADDR_CLKDIV: begin
            clkdiv_reg <= pwdata[15:0];
          end
          ADDR_TXDATA: begin
            // A second unconsumed write is reported instead of overwriting
            // data whose ordering software may still depend on.
            if (!tx_valid) begin
              tx_data  <= pwdata;
              tx_valid <= 1'b1;
            end
            else begin
              irq_status[2] <= 1'b1; // TX overrun
            end
          end
          ADDR_IRQ_ENABLE: begin
            irq_enable <= pwdata[3:0];
          end
          ADDR_IRQ_STATUS: begin
            irq_status <= irq_status & ~pwdata[3:0]; // W1C
          end
          default: begin end
        endcase
      end

      // Reading RXDATA acknowledges the data-valid level. The corresponding
      // sticky interrupt remains W1C so polling and interrupts compose cleanly.
      if (apb_read && valid_addr && (reg_addr == ADDR_RXDATA)) begin
        rx_valid <= 1'b0;
      end

      // Disabling the block aborts an in-flight frame at a PCLK boundary.
      // The sticky ABORT bit makes this observable to software.
      if (!ctrl_reg[0] && busy) begin
        busy                <= 1'b0;
        half_count          <= 16'd0;
        bit_index           <= 6'd0;
        last_sample_pending <= 1'b0;
        spi_cs_n            <= 1'b1;
        spi_sclk            <= ctrl_reg[2];
        spi_mosi            <= 1'b0;
        irq_status[3]       <= 1'b1;
      end
      else if (busy) begin
        if (half_count == clkdiv_reg) begin
          half_count <= 16'd0;
          if (spi_sclk == cpol_latched) begin
            // Leading edge: CPHA=0 samples MISO; CPHA=1 launches MOSI.
            spi_sclk <= ~spi_sclk;
            if (cpha_latched) begin
              spi_mosi <= select_tx_bit(tx_shift, bit_index, word_bits,
                                        lsb_latched);
            end
            else begin
              rx_shift <= insert_rx_bit(rx_shift, bit_index, word_bits,
                                        lsb_latched, spi_miso);
              if (bit_index == (word_bits - 1'b1))
                last_sample_pending <= 1'b1;
            end
          end
          else begin
            // Trailing edge: CPHA=0 launches next MOSI / completes; CPHA=1
            // samples MISO and completes immediately on the final bit.
            spi_sclk <= ~spi_sclk;
            if (cpha_latched) begin
              rx_shift <= insert_rx_bit(rx_shift, bit_index, word_bits,
                                        lsb_latched, spi_miso);
              if (bit_index == (word_bits - 1'b1)) begin
                if (!rx_valid) begin
                  rx_data       <= insert_rx_bit(rx_shift, bit_index, word_bits,
                                                  lsb_latched, spi_miso);
                  rx_valid      <= 1'b1;
                  irq_status[1] <= 1'b1;
                end
                else begin
                  irq_status[2] <= 1'b1; // unread RXDATA would be overwritten
                end
                busy          <= 1'b0;
                irq_status[0] <= 1'b1;
                if (!cont_latched)
                  spi_cs_n <= 1'b1;
              end
              else begin
                bit_index <= bit_index + 1'b1;
              end
            end
            else if (last_sample_pending) begin
              // The last CPHA=0 sample happened on the preceding leading edge;
              // finish only after returning SCLK to its idle polarity.
              last_sample_pending <= 1'b0;
              if (!rx_valid) begin
                rx_data       <= rx_shift;
                rx_valid      <= 1'b1;
                irq_status[1] <= 1'b1;
              end
              else begin
                irq_status[2] <= 1'b1;
              end
              busy          <= 1'b0;
              irq_status[0] <= 1'b1;
              if (!cont_latched)
                spi_cs_n <= 1'b1;
            end
            else begin
              bit_index <= bit_index + 1'b1;
              spi_mosi  <= select_tx_bit(tx_shift, bit_index + 1'b1,
                                         word_bits, lsb_latched);
            end
          end
        end
        else begin
          half_count <= half_count + 1'b1;
        end
      end
      else begin
        // In normal idle state SCLK tracks the currently programmed CPOL. It
        // remains at the latched CPOL while CS is held for continuous frames.
        half_count <= 16'd0;
        // Do not let the idle cleanup in this same PCLK overwrite the first
        // CPHA=0 MOSI bit that a valid APB START has just installed.
        if (spi_cs_n && !(apb_write && valid_addr && (reg_addr == ADDR_CTRL) &&
                          pwdata[1] && pwdata[0] && tx_valid)) begin
          spi_sclk <= ctrl_reg[2];
          spi_mosi <= 1'b0;
        end
      end
    end
  end

endmodule
