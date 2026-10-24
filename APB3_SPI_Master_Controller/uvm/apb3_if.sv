interface apb3_if(input logic pclk);
  logic        presetn;
  logic [31:0] paddr;
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;

  clocking master_cb @(posedge pclk);
    default input #1step output #1step;
    output paddr, psel, penable, pwrite, pwdata;
    input prdata, pready, pslverr;
  endclocking
endinterface
