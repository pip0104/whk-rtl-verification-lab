`timescale 1ns/1ps

module tb_cocotb_spi;
  reg         pclk = 1'b0;
  reg         presetn = 1'b0;
  reg  [31:0] paddr = 32'h0;
  reg         psel = 1'b0;
  reg         penable = 1'b0;
  reg         pwrite = 1'b0;
  reg  [31:0] pwdata = 32'h0;
  wire [31:0] prdata;
  wire        pready;
  wire        pslverr;
  wire        spi_sclk;
  wire        spi_mosi;
  reg         spi_miso = 1'b0;
  wire        spi_cs_n;
  wire        irq;

  apb3_spi_master dut (.*);
  always #5 pclk = ~pclk;
endmodule
