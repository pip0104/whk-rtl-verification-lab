// Included in the DUT scope. Independent reference divider captures START.
reg f_past_valid = 0;
reg [15:0] f_start_div;
reg f_busy_write_seen;
wire f_start = apb_write && valid_addr && reg_addr == ADDR_CTRL &&
               pwdata[1] && pwdata[0] && !busy && tx_valid;
wire f_div_write = apb_write && valid_addr && reg_addr == ADDR_CLKDIV;
always @(posedge pclk) begin
  f_past_valid <= 1;
  if (!presetn) begin
    f_start_div <= 0;
    f_busy_write_seen <= 0;
  end else begin
    if (f_start) begin
      f_start_div <= clkdiv_reg;
      f_busy_write_seen <= 0;
    end
    if (busy && f_div_write && pwdata[15:0] != f_start_div)
      f_busy_write_seen <= 1;
  end
  if (f_past_valid) begin
`ifdef P_RESET
    if (!$past(presetn)) begin
      reset_busy: assert(!busy);
      reset_pins: assert(spi_cs_n && !spi_sclk && !spi_mosi);
      reset_rx: assert(!rx_valid && rx_data == 0);
      reset_count: assert(half_count == 0);
    end
    apb_ready: assert(pready);
    apb_error: assert(pslverr == (apb_access && !valid_addr));
`endif
    if (presetn && $past(presetn)) begin
`ifdef P_CONFIG
      if (busy && $past(busy)) begin
        config_hold: assert({cpol_latched,cpha_latched,cont_latched,lsb_latched,word_bits}
                          == $past({cpol_latched,cpha_latched,cont_latched,lsb_latched,word_bits}));
        reference_hold: assert(f_start_div == $past(f_start_div));
      end
      if ($past(f_start)) begin
        config_capture: assert({cpol_latched,cpha_latched,cont_latched,lsb_latched}
                              == $past({pwdata[2],pwdata[3],pwdata[4],pwdata[5]}));
        bits_capture: assert(word_bits == {1'b0,$past(pwdata[12:8])} + 6'd1);
      end
`endif
`ifdef P_TIMING
      if (busy) begin
        count_bound: assert(half_count <= f_start_div);
`ifndef BASELINE
        implementation_capture: assert(clkdiv_latched == f_start_div);
`endif
      end
      if ($past(busy && ctrl_reg[0])) begin
        if ($past(half_count) == $past(f_start_div)) begin
          edge_due: assert(spi_sclk != $past(spi_sclk));
          edge_clear: assert(half_count == 0);
        end else begin
          edge_not_due: assert(spi_sclk == $past(spi_sclk));
          count_step: assert(half_count == $past(half_count) + 16'd1);
        end
      end
`endif
`ifdef P_RX
      if ($past(rx_valid)) begin
        unread_data_hold: assert(rx_data == $past(rx_data));
      end
      if ($past(rx_valid && !(apb_read && valid_addr && reg_addr == ADDR_RXDATA))) begin
        unread_valid_hold: assert(rx_valid);
      end
`endif
`ifdef P_COVER
      cover_start: cover(busy && $past(f_start));
      cover_busy_reprogram: cover(busy && f_busy_write_seen);
      cover_finish_after_reprogram: cover(!busy && $past(busy) &&
                                         $past(ctrl_reg[0]) && f_busy_write_seen &&
                                         irq_status[0] && !irq_status[3]);
`endif
    end
  end
end
