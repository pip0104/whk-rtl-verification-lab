`timescale 1ns/1ps

// Fast non-UVM regression gate. It verifies APB setup/access timing, all four
// CPOL/CPHA modes, MSB/LSB bit order, programmable divider, RX data, IRQ W1C,
// and continuous CS hold/release. UVM retains these tests as its smoke layer.
module tb_top_smoke;
  reg         pclk;
  reg         presetn;
  reg  [31:0] paddr;
  reg         psel;
  reg         penable;
  reg         pwrite;
  reg  [31:0] pwdata;
  wire [31:0] prdata;
  wire        pready;
  wire        pslverr;
  wire        spi_sclk;
  wire        spi_mosi;
  reg         spi_miso;
  wire        spi_cs_n;
  wire        irq;

  reg         slave_cpol;
  reg         slave_cpha;
  reg         slave_lsb_first;
  integer     slave_bits;
  reg  [31:0] slave_response;
  reg  [31:0] slave_received;
  reg         slave_active;
  integer     slave_sample_count;
  integer     edge_count;
  time        edge_times [0:31];

  apb3_spi_master dut (.*);

  always #5 pclk = ~pclk;

  function automatic response_bit;
    input [31:0] value;
    input integer index;
    input integer bits;
    input         lsb_first;
    begin
      response_bit = lsb_first ? value[index] : value[bits - 1 - index];
    end
  endfunction

  // A compact SPI slave model. It launches MISO on the edge opposite the
  // master sample edge and records every sampled MOSI bit independently of
  // the DUT's internal shift register.
  always @(negedge spi_cs_n) begin
    slave_active = 1'b1;
    slave_sample_count = 0;
    slave_received = 32'h0000_0000;
    if (!slave_cpha)
      spi_miso = response_bit(slave_response, 0, slave_bits, slave_lsb_first);
    else
      spi_miso = 1'b0;
  end

  // Keep the slave active through the delta cycle in which the final SCLK
  // trailing edge and CS deassertion are both scheduled by the DUT.
  always @(posedge spi_cs_n) begin
    #1 slave_active = 1'b0;
  end

  always @(spi_sclk) begin
    if (slave_active) begin
      if (spi_sclk != slave_cpol) begin
        // Leading edge. CPHA=1 slave launches MISO here.
        if (slave_cpha && (slave_sample_count < slave_bits))
          spi_miso = response_bit(slave_response, slave_sample_count,
                                  slave_bits, slave_lsb_first);
      end
      else begin
        // Trailing edge. CPHA=0 launches the next MISO bit here.
        if (!slave_cpha && (slave_sample_count < slave_bits))
          spi_miso = response_bit(slave_response, slave_sample_count,
                                  slave_bits, slave_lsb_first);
      end

      // The master samples MOSI on leading edge for CPHA=0 and trailing edge
      // for CPHA=1. Store bits in their logical, not wire-order, positions.
      if (((!slave_cpha) && (spi_sclk != slave_cpol)) ||
          (slave_cpha && (spi_sclk == slave_cpol))) begin
        if (slave_sample_count < slave_bits) begin
          if (slave_lsb_first)
            slave_received[slave_sample_count] = spi_mosi;
          else
            slave_received[slave_bits - 1 - slave_sample_count] = spi_mosi;
          slave_sample_count = slave_sample_count + 1;
        end
      end
    end
  end

  always @(spi_sclk) begin
    if (slave_active && (edge_count < 32)) begin
      edge_times[edge_count] = $time;
      edge_count = edge_count + 1;
    end
  end

  task automatic apb_write;
    input [31:0] addr;
    input [31:0] data;
    begin
      @(negedge pclk);
      paddr   = addr;
      pwdata  = data;
      pwrite  = 1'b1;
      psel    = 1'b1;
      penable = 1'b0;
      @(negedge pclk);
      penable = 1'b1;
      @(posedge pclk);
      if (!pready || pslverr)
        $fatal(1, "APB write failed addr=%h", addr);
      @(negedge pclk);
      psel    = 1'b0;
      penable = 1'b0;
      pwrite  = 1'b0;
      paddr   = 32'h0;
      pwdata  = 32'h0;
    end
  endtask

  task automatic apb_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
      @(negedge pclk);
      paddr   = addr;
      pwrite  = 1'b0;
      psel    = 1'b1;
      penable = 1'b0;
      @(negedge pclk);
      penable = 1'b1;
      @(posedge pclk);
      if (!pready || pslverr)
        $fatal(1, "APB read failed addr=%h", addr);
      data = prdata;
      @(negedge pclk);
      psel    = 1'b0;
      penable = 1'b0;
      paddr   = 32'h0;
    end
  endtask

  task automatic wait_for_frame;
    begin
      wait (dut.busy == 1'b1);
      wait (dut.busy == 1'b0);
      @(posedge pclk);
    end
  endtask

  task automatic run_mode_case;
    input mode_cpol;
    input mode_cpha;
    input mode_lsb;
    input [31:0] tx_word;
    input [31:0] expected_rx;
    reg [31:0]   status;
    reg [31:0]   rx_word;
    reg [31:0]   ctrl_word;
    integer      edge_index;
    begin
      slave_cpol      = mode_cpol;
      slave_cpha      = mode_cpha;
      slave_lsb_first = mode_lsb;
      slave_bits      = 8;
      slave_response  = expected_rx;
      edge_count      = 0;

      // divider=1 means each half SCLK phase lasts two PCLK cycles.
      // Program CPOL/CPHA before asserting START. This establishes the idle
      // level while CS is inactive and prevents a mode-change transition from
      // being mistaken for the first SPI clock edge.
      ctrl_word = 32'h0000_0700 | {29'd0, mode_cpol, 2'b00} |
                  {28'd0, mode_cpha, 3'b000} | {26'd0, mode_lsb, 5'b00000} |
                  32'h0000_0001; // ENABLE, no START
      apb_write(32'h00, ctrl_word);
      apb_write(32'h04, 32'd1);
      apb_write(32'h08, tx_word);
      ctrl_word = ctrl_word | 32'h0000_0002; // START command
      apb_write(32'h00, ctrl_word);
      wait_for_frame();

      if (slave_received[7:0] !== tx_word[7:0])
        $fatal(1, "SPI mode %0d%0d lsb=%0d MOSI mismatch got=%h exp=%h",
               mode_cpol, mode_cpha, mode_lsb, slave_received[7:0], tx_word[7:0]);
      apb_read(32'h0c, rx_word);
      if (rx_word[7:0] !== expected_rx[7:0])
        $fatal(1, "SPI mode %0d%0d lsb=%0d MISO mismatch got=%h exp=%h",
               mode_cpol, mode_cpha, mode_lsb, rx_word[7:0], expected_rx[7:0]);
      apb_read(32'h10, status);
      if (status[2] !== 1'b0 || status[0] !== 1'b0 || status[3] !== 1'b0)
        $fatal(1, "Status did not return idle after single frame: %h", status);
      if (edge_count !== 16)
        $fatal(1, "Expected 16 SCLK edges, observed %0d", edge_count);
      for (edge_index = 1; edge_index < edge_count; edge_index = edge_index + 1)
        if ((edge_times[edge_index] - edge_times[edge_index-1]) !== 20)
          $fatal(1, "SCLK divider mismatch: edge delta=%0t",
                 edge_times[edge_index] - edge_times[edge_index-1]);
    end
  endtask

  reg [31:0] status_word;
  reg [31:0] irq_word;
  initial begin
    pclk             = 1'b0;
    presetn          = 1'b0;
    paddr            = 32'h0;
    psel             = 1'b0;
    penable          = 1'b0;
    pwrite           = 1'b0;
    pwdata           = 32'h0;
    spi_miso         = 1'b0;
    slave_cpol       = 1'b0;
    slave_cpha       = 1'b0;
    slave_lsb_first  = 1'b0;
    slave_bits       = 8;
    slave_response   = 32'h0;
    slave_received   = 32'h0;
    slave_active     = 1'b0;
    slave_sample_count = 0;
    edge_count       = 0;

    $dumpfile("smoke.vcd");
    $dumpvars(0, tb_top_smoke);

    repeat (3) @(posedge pclk);
    @(negedge pclk);
    presetn = 1'b1;

    // The four SPI modes plus an LSB-first instance.
    run_mode_case(1'b0, 1'b0, 1'b0, 32'h0000_003c, 32'h0000_00a6);
    run_mode_case(1'b0, 1'b1, 1'b0, 32'h0000_0096, 32'h0000_005a);
    run_mode_case(1'b1, 1'b0, 1'b0, 32'h0000_0069, 32'h0000_003c);
    run_mode_case(1'b1, 1'b1, 1'b0, 32'h0000_00a5, 32'h0000_0096);
    run_mode_case(1'b0, 1'b0, 1'b1, 32'h0000_00d2, 32'h0000_004b);

    // Continuous frame: CS stays asserted after completion until RELEASE.
    slave_cpol = 1'b0;
    slave_cpha = 1'b0;
    slave_lsb_first = 1'b0;
    slave_bits = 8;
    slave_response = 32'h0000_0033;
    apb_write(32'h08, 32'h0000_0055);
    apb_write(32'h00, 32'h0000_0713); // enable,start,continuous, 8 bits
    wait_for_frame();
    if (spi_cs_n !== 1'b0)
      $fatal(1, "Continuous frame deasserted CS too early");
    apb_read(32'h0c, irq_word);
    if (irq_word[7:0] !== 8'h33)
      $fatal(1, "Continuous-frame RX mismatch");
    apb_write(32'h00, 32'h0001_0711); // enable,continuous,CS_RELEASE, no START
    @(posedge pclk);
    if (spi_cs_n !== 1'b1)
      $fatal(1, "CS_RELEASE did not deassert CS");

    // DONE/RX_AVAIL are sticky and W1C. Verify maskable IRQ operation.
    apb_write(32'h14, 32'h0000_0003);
    apb_read(32'h18, irq_word);
    if ((irq_word & 32'h0000_0003) != 32'h0000_0003 || irq !== 1'b1)
      $fatal(1, "Expected DONE/RX interrupts after transfer, got status=%h irq=%b", irq_word, irq);
    apb_write(32'h18, 32'h0000_0003);
    @(posedge pclk);
    if (irq !== 1'b0)
      $fatal(1, "W1C did not clear IRQ");

    $display("SMOKE_TEST_PASS: APB3 SPI modes, bit order, IRQ and CS hold passed");
    #20;
    $finish;
  end

  initial begin
    repeat (2500) @(posedge pclk);
    $fatal(1, "SMOKE_TEST_TIMEOUT");
  end
endmodule
