module spi_formal;
  (* gclk *) reg pclk;
  (* anyseq *) reg presetn;
  (* anyseq *) reg [31:0] paddr;
  (* anyseq *) reg psel, penable, pwrite;
  (* anyseq *) reg [31:0] pwdata;
  (* anyseq *) reg spi_miso;
  wire [31:0] prdata;
  wire pready, pslverr, spi_sclk, spi_mosi, spi_cs_n, irq;
  apb3_spi_master dut(.*);
  reg past_valid = 0;
  always @(posedge pclk) begin
    past_valid <= 1;
    if (!past_valid) begin
      assume(!presetn);
      assume(!psel && !penable);
    end
    // Legal APB: one SETUP then ACCESS; DUT has no wait states.
    assume(!penable || psel);
    if (past_valid && presetn) begin
      if ($past(presetn && psel && !penable)) begin
        assume(psel && penable);
        assume(paddr == $past(paddr));
        assume(pwrite == $past(pwrite));
        assume(pwdata == $past(pwdata));
      end
      if (penable) assume($past(presetn && psel && !penable));
      if ($past(presetn && penable)) assume(!penable);
    end
  end
endmodule
