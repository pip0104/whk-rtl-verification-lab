`timescale 1ns/1ps
module tb_top_uvm;
  import uvm_pkg::*;
  import apb3_spi_uvm_pkg::*;
  logic pclk = 1'b0;
  always #5 pclk = ~pclk;

  apb3_if apb(pclk);
  spi_if  spi();
  wire irq;

  apb3_spi_master dut (
    .pclk(pclk), .presetn(apb.presetn),
    .paddr(apb.paddr), .psel(apb.psel), .penable(apb.penable),
    .pwrite(apb.pwrite), .pwdata(apb.pwdata), .prdata(apb.prdata),
    .pready(apb.pready), .pslverr(apb.pslverr),
    .spi_sclk(spi.sclk), .spi_mosi(spi.mosi), .spi_miso(spi.miso),
    .spi_cs_n(spi.cs_n), .irq(irq)
  );

  initial begin
    apb.presetn = 0;
    apb.psel = 0; apb.penable = 0; apb.pwrite = 0;
    apb.paddr = '0; apb.pwdata = '0; spi.miso = 0;
    repeat (3) @(posedge pclk);
    apb.presetn = 1;
  end

  initial begin
    uvm_config_db#(virtual apb3_if)::set(null, "uvm_test_top.env.apb_agent.*", "vif", apb);
    uvm_config_db#(virtual spi_if)::set(null, "uvm_test_top.env.spi_mon", "vif", spi);
    run_test();
  end
endmodule
