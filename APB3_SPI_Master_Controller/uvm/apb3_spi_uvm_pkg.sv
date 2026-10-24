package apb3_spi_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam bit [31:0] CTRL       = 32'h00;
  localparam bit [31:0] CLKDIV     = 32'h04;
  localparam bit [31:0] TXDATA     = 32'h08;
  localparam bit [31:0] RXDATA     = 32'h0c;
  localparam bit [31:0] STATUS     = 32'h10;
  localparam bit [31:0] IRQ_ENABLE = 32'h14;
  localparam bit [31:0] IRQ_STATUS = 32'h18;

  typedef enum bit {APB_READ, APB_WRITE} apb_direction_e;

  class apb3_item extends uvm_sequence_item;
    rand apb_direction_e direction;
    rand bit [31:0] addr;
    rand bit [31:0] wdata;
    bit [31:0] rdata;
    bit        slverr;

    `uvm_object_utils_begin(apb3_item)
      `uvm_field_enum(apb_direction_e, direction, UVM_DEFAULT)
      `uvm_field_int(addr, UVM_DEFAULT)
      `uvm_field_int(wdata, UVM_DEFAULT)
      `uvm_field_int(rdata, UVM_DEFAULT)
      `uvm_field_int(slverr, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "apb3_item"); super.new(name); endfunction
  endclass

  // Raw SPI observation is kept separate from APB programming. The scoreboard
  // joins them using the APB-visible CTRL/TXDATA/START history, not DUT state.
  class spi_observed_frame extends uvm_sequence_item;
    bit raw_sclk[$];
    bit raw_mosi[$];
    bit raw_miso[$];
    time start_time;
    time end_time;

    `uvm_object_utils(spi_observed_frame)
    function new(string name = "spi_observed_frame"); super.new(name); endfunction
  endclass

  class spi_expected_frame extends uvm_object;
    bit cpol;
    bit cpha;
    bit lsb_first;
    bit continuous;
    bit [5:0] bits;
    bit [15:0] divider;
    bit [31:0] tx_data;
    bit [31:0] expected_rx;
    bit expected_rx_valid;

    `uvm_object_utils_begin(spi_expected_frame)
      `uvm_field_int(cpol, UVM_DEFAULT)
      `uvm_field_int(cpha, UVM_DEFAULT)
      `uvm_field_int(lsb_first, UVM_DEFAULT)
      `uvm_field_int(continuous, UVM_DEFAULT)
      `uvm_field_int(bits, UVM_DEFAULT)
      `uvm_field_int(divider, UVM_DEFAULT)
      `uvm_field_int(tx_data, UVM_DEFAULT)
      `uvm_field_int(expected_rx, UVM_DEFAULT)
      `uvm_field_int(expected_rx_valid, UVM_DEFAULT)
    `uvm_object_utils_end
    function new(string name = "spi_expected_frame"); super.new(name); endfunction

    function bit tx_bit(int unsigned index);
      return lsb_first ? tx_data[index] : tx_data[bits - 1 - index];
    endfunction
  endclass

  class apb3_sequencer extends uvm_sequencer #(apb3_item);
    `uvm_component_utils(apb3_sequencer)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass

  class apb3_driver extends uvm_driver #(apb3_item);
    `uvm_component_utils(apb3_driver)
    virtual apb3_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual apb3_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "apb3_driver requires virtual apb3_if")
    endfunction

    task run_phase(uvm_phase phase);
      apb3_item req;
      vif.psel <= 0; vif.penable <= 0; vif.pwrite <= 0;
      vif.paddr <= '0; vif.pwdata <= '0;
      forever begin
        seq_item_port.get_next_item(req);
        drive_one(req);
        seq_item_port.item_done();
      end
    endtask

    task drive_one(apb3_item tr);
      @(vif.master_cb);
      vif.master_cb.paddr   <= tr.addr;
      vif.master_cb.pwdata  <= tr.wdata;
      vif.master_cb.pwrite  <= (tr.direction == APB_WRITE);
      vif.master_cb.psel    <= 1'b1;
      vif.master_cb.penable <= 1'b0;
      @(vif.master_cb);
      vif.master_cb.penable <= 1'b1;
      do @(vif.master_cb); while (!vif.master_cb.pready);
      tr.rdata  = vif.master_cb.prdata;
      tr.slverr = vif.master_cb.pslverr;
      vif.master_cb.psel    <= 1'b0;
      vif.master_cb.penable <= 1'b0;
      vif.master_cb.pwrite  <= 1'b0;
    endtask
  endclass

  class apb3_monitor extends uvm_component;
    `uvm_component_utils(apb3_monitor)
    virtual apb3_if vif;
    uvm_analysis_port #(apb3_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent); ap = new("ap", this);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual apb3_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "apb3_monitor requires virtual apb3_if")
    endfunction
    task run_phase(uvm_phase phase);
      apb3_item tr;
      forever begin
        @(posedge vif.pclk);
        if (vif.psel && vif.penable && vif.pready) begin
          tr = apb3_item::type_id::create("tr");
          tr.direction = vif.pwrite ? APB_WRITE : APB_READ;
          tr.addr      = vif.paddr;
          tr.wdata     = vif.pwdata;
          tr.rdata     = vif.prdata;
          tr.slverr    = vif.pslverr;
          ap.write(tr);
        end
      end
    endtask
  endclass

  class apb3_agent extends uvm_agent;
    `uvm_component_utils(apb3_agent)
    apb3_sequencer sqr;
    apb3_driver    drv;
    apb3_monitor   mon;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon = apb3_monitor::type_id::create("mon", this);
      if (is_active == UVM_ACTIVE) begin
        sqr = apb3_sequencer::type_id::create("sqr", this);
        drv = apb3_driver::type_id::create("drv", this);
      end
    endfunction
    function void connect_phase(uvm_phase phase);
      if (is_active == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  class spi_monitor extends uvm_component;
    `uvm_component_utils(spi_monitor)
    virtual spi_if vif;
    uvm_analysis_port #(spi_observed_frame) ap;
    function new(string name, uvm_component parent);
      super.new(name, parent); ap = new("ap", this);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual spi_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "spi_monitor requires virtual spi_if")
    endfunction
    task run_phase(uvm_phase phase);
      spi_observed_frame frame;
      forever begin
        @(negedge vif.cs_n);
        frame = spi_observed_frame::type_id::create("frame");
        frame.start_time = $time;
        while (!vif.cs_n) begin
          @(vif.sclk);
          frame.raw_sclk.push_back(vif.sclk);
          frame.raw_mosi.push_back(vif.mosi);
          frame.raw_miso.push_back(vif.miso);
        end
        frame.end_time = $time;
        ap.write(frame);
      end
    endtask
  endclass

  `uvm_analysis_imp_decl(_apb)
  `uvm_analysis_imp_decl(_spi)

  class apb3_spi_scoreboard extends uvm_component;
    `uvm_component_utils(apb3_spi_scoreboard)
    uvm_analysis_imp_apb #(apb3_item, apb3_spi_scoreboard) apb_imp;
    uvm_analysis_imp_spi #(spi_observed_frame, apb3_spi_scoreboard) spi_imp;
    uvm_analysis_port #(spi_expected_frame) expected_ap;
    spi_expected_frame expected_q[$];
    bit [31:0] ctrl_shadow;
    bit [15:0] clkdiv_shadow;
    bit [31:0] tx_shadow;
    int unsigned compared_frames;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      apb_imp = new("apb_imp", this);
      spi_imp = new("spi_imp", this);
      expected_ap = new("expected_ap", this);
    endfunction

    function void write_apb(apb3_item tr);
      spi_expected_frame exp;
      if (tr.direction != APB_WRITE || tr.slverr) return;
      case (tr.addr)
        CTRL: begin
          ctrl_shadow = tr.wdata & 32'hfffe_dffd; // commands/reserved bits are not state
          if (tr.wdata[1] && tr.wdata[0]) begin
            exp = spi_expected_frame::type_id::create("expected");
            exp.cpol       = tr.wdata[2];
            exp.cpha       = tr.wdata[3];
            exp.continuous = tr.wdata[4];
            exp.lsb_first  = tr.wdata[5];
            exp.bits       = tr.wdata[12:8] + 1;
            exp.divider    = clkdiv_shadow;
            exp.tx_data    = tx_shadow;
            expected_q.push_back(exp);
            expected_ap.write(exp);
          end
        end
        CLKDIV: clkdiv_shadow = tr.wdata[15:0];
        TXDATA: tx_shadow = tr.wdata;
        default: ;
      endcase
    endfunction

    function void write_spi(spi_observed_frame actual);
      spi_expected_frame exp;
      int unsigned bit_no;
      int unsigned edge_no;
      if (expected_q.size() == 0) begin
        `uvm_error("SPI_SB", "Observed a CS-framed transfer without APB START")
        return;
      end
      exp = expected_q.pop_front();
      if (actual.raw_sclk.size() != 2 * exp.bits)
        `uvm_error("SPI_SB", $sformatf("SCLK edge count got %0d expected %0d",
                                        actual.raw_sclk.size(), 2 * exp.bits))
      for (bit_no = 0; bit_no < exp.bits; bit_no++) begin
        edge_no = 2 * bit_no + (exp.cpha ? 1 : 0);
        if (edge_no >= actual.raw_mosi.size()) break;
        if (actual.raw_mosi[edge_no] !== exp.tx_bit(bit_no))
          `uvm_error("SPI_SB", $sformatf("MOSI bit %0d got %b expected %b",
                                          bit_no, actual.raw_mosi[edge_no], exp.tx_bit(bit_no)))
      end
      compared_frames++;
    endfunction
  endclass

  class spi_coverage extends uvm_subscriber #(spi_expected_frame);
    `uvm_component_utils(spi_coverage)
    bit cp_cpol, cp_cpha, cp_lsb, cp_cont;
    bit [5:0] cp_bits;
    bit [15:0] cp_divider;
    covergroup spi_cg;
      option.per_instance = 1;
      cpol_cp: coverpoint cp_cpol;
      cpha_cp: coverpoint cp_cpha;
      mode_cp: cross cpol_cp, cpha_cp;
      lsb_cp: coverpoint cp_lsb;
      cont_cp: coverpoint cp_cont;
      bits_cp: coverpoint cp_bits { bins b1={1}; bins b8={8}; bins b16={16}; bins b32={32}; bins other={[2:7], [9:15], [17:31]}; }
      divider_cp: coverpoint cp_divider { bins min={0}; bins low={[1:3]}; bins mid={[4:31]}; bins high={[32:16'hffff]}; }
      config_cross: cross mode_cp, lsb_cp, cont_cp;
    endgroup
    function new(string name, uvm_component parent);
      super.new(name, parent); spi_cg = new;
    endfunction
    function void write(spi_expected_frame frame);
      cp_cpol = frame.cpol; cp_cpha = frame.cpha; cp_lsb = frame.lsb_first;
      cp_cont = frame.continuous; cp_bits = frame.bits; cp_divider = frame.divider;
      spi_cg.sample();
    endfunction
  endclass

  class apb3_spi_env extends uvm_env;
    `uvm_component_utils(apb3_spi_env)
    apb3_agent           apb_agent;
    spi_monitor          spi_mon;
    apb3_spi_scoreboard  sb;
    spi_coverage         cov;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      apb_agent = apb3_agent::type_id::create("apb_agent", this);
      spi_mon   = spi_monitor::type_id::create("spi_mon", this);
      sb        = apb3_spi_scoreboard::type_id::create("sb", this);
      cov       = spi_coverage::type_id::create("cov", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      apb_agent.mon.ap.connect(sb.apb_imp);
      spi_mon.ap.connect(sb.spi_imp);
      sb.expected_ap.connect(cov.analysis_export);
    endfunction
  endclass

  class spi_program_frame_seq extends uvm_sequence #(apb3_item);
    `uvm_object_utils(spi_program_frame_seq)
    rand bit cpol, cpha, lsb_first, continuous;
    rand bit [5:0] bits;
    rand bit [15:0] divider;
    rand bit [31:0] tx_data;
    constraint legal_c { bits inside {[1:32]}; }
    function new(string name = "spi_program_frame_seq"); super.new(name); endfunction

    task write_reg(bit [31:0] addr, bit [31:0] data);
      apb3_item tr = apb3_item::type_id::create("tr");
      start_item(tr); tr.direction = APB_WRITE; tr.addr = addr; tr.wdata = data; finish_item(tr);
      if (tr.slverr) `uvm_error("APB_SEQ", $sformatf("APB error writing %h", addr))
    endtask
    task body();
      bit [31:0] ctrl;
      ctrl = 32'h1 | (cpol << 2) | (cpha << 3) | (continuous << 4) |
             (lsb_first << 5) | ((bits - 1) << 8);
      // Static control is written before START so CPOL settles while CS is high.
      write_reg(CTRL, ctrl);
      write_reg(CLKDIV, divider);
      write_reg(TXDATA, tx_data);
      write_reg(CTRL, ctrl | 32'h2);
    endtask
  endclass

  class apb3_spi_base_test extends uvm_test;
    `uvm_component_utils(apb3_spi_base_test)
    apb3_spi_env env;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase); env = apb3_spi_env::type_id::create("env", this);
    endfunction
  endclass
endpackage
