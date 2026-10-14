`timescale 1ps/1ps
// TREX 68000 overclock bench: whole Nuked-MD board, BRAM work/Z80 RAM,
// cartridge ROM with SDRAM-like latency, the TREX clock generator and DTACK hold.
module tb;
	integer PERIOD = 0;   // +PERIOD= 68k clock period in clk_md cycles, 0 = stock
	integer ARB    = 0;   // +ARB=1: arbiter/IO chip follow the 68k clock
	integer HOLD   = 1;   // +HOLD=0: no DTACK hold for ROM data
	integer LAT    = 10;  // +LAT= ROM latency in clk_md cycles
	integer SLOW   = 0;   // +SLOW=1: Z80-area slowdown as in MegaDrive.sv
	integer TOGGLE = 0;
	integer SPRU   = 0;   // +SPRU=1: Sprite Limit Off
	initial begin
		if($value$plusargs("PERIOD=%d", PERIOD)) ;
		if($value$plusargs("ARB=%d", ARB)) ;
		if($value$plusargs("HOLD=%d", HOLD)) ;
		if($value$plusargs("LAT=%d", LAT)) ;
		if($value$plusargs("SLOW=%d", SLOW)) ;
		if($value$plusargs("TOGGLE=%d", TOGGLE)) ;
		if($value$plusargs("SPRU=%d", SPRU)) ;
	end

	// same Z80-area slowdown as MegaDrive.sv, and an optional stress toggle of the speed
	wire [22:0] m68k_addr;
	reg  [10:0] cpu_slow = 0;
	reg         tog = 0;
	integer     tcnt = 0;
	always @(posedge clk) begin
		if(SLOW != 0 && m68k_addr[22:16] == 7'b1010000) cpu_slow <= '1;
		else if(cpu_slow != 0) cpu_slow <= cpu_slow - 1'd1;
		tcnt <= tcnt + 1;
		if(TOGGLE != 0 && tcnt % TOGGLE == 0) tog <= ~tog;
	end
	wire [3:0] period_now = (cpu_slow != 0 || tog) ? 4'd0 : PERIOD[3:0];
	parameter MAXCYC  = 3000000;
	parameter DBG     = 0;

	reg clk = 0;
	always #4657 clk = ~clk; // ~107.4 MHz

	reg ext_reset = 1;
	integer cyc = 0;
	always @(posedge clk) begin cyc <= cyc + 1; if(cyc % 50000 == 0) $display("cyc %0d addr %06X", cyc, {cart_address,1'b0}); end
	initial begin
		repeat(2000) @(posedge clk);
		ext_reset = 0;
	end

	wire VCLK, ZCLK;
	wire cpu_clk, arb_clk, fast;

	m68k_clkgen clkgen
	(
		.clk(clk), .period(period_now), .run(1'b1),
		.VCLK(VCLK),
		.cpu_clk(cpu_clk), .arb_clk(arb_clk), .fast(fast)
	);

	wire [14:0] ram_68k_address; wire [1:0] ram_68k_byteena; wire [15:0] ram_68k_data; wire ram_68k_wren;
	reg  [15:0] ram_68k_o;
	wire [12:0] ram_z80_address; wire [7:0] ram_z80_data; wire ram_z80_wren;
	reg  [7:0]  ram_z80_o;

	reg [15:0] wram[0:32767];
	reg [7:0]  zram[0:8191];
	reg old_wren = 0;
	always @(posedge clk) begin
		old_wren <= ram_68k_wren;
		if(ram_68k_wren && first_wr < 0) first_wr = cyc;
		if(ram_68k_wren & ~old_wren & DBG) $display("W %04X %04X be=%b t=%0d", ram_68k_address, ram_68k_data, ram_68k_byteena, cyc);
		if(ram_68k_wren) begin
			if(ram_68k_byteena[1]) wram[ram_68k_address][15:8] <= ram_68k_data[15:8];
			if(ram_68k_byteena[0]) wram[ram_68k_address][7:0]  <= ram_68k_data[7:0];
		end
		ram_68k_o <= wram[ram_68k_address];
		if(ram_z80_wren) zram[ram_z80_address] <= ram_z80_data;
		ram_z80_o <= zram[ram_z80_address];
	end

	// cartridge: data register updates LAT cycles after the read starts, like the SDRAM path
	reg [15:0] rom[0:4095];
	initial begin
		string romfile;
		if(!$value$plusargs("ROM=%s", romfile)) romfile = "rom.hex";
		$readmemh(romfile, rom);
	end
	wire [22:0] cart_address;
	wire cart_cs, cart_oe;
	reg  [15:0] cart_data = 16'hFFFF;
	reg  rd_old = 0, ready = 0;
	integer wait_cnt = -1;
	wire rd = cart_oe & cart_cs;
	always @(posedge clk) begin
		rd_old <= rd;
		if(~rd) ready <= 0;
		if(rd & ~rd_old) wait_cnt <= LAT;
		else if(wait_cnt > 0) wait_cnt <= wait_cnt - 1;
		else if(wait_cnt == 0) begin
			cart_data <= rom[cart_address[11:0]];
			ready <= 1;
			wait_cnt <= -1;
		end
	end
	wire hold = (HOLD != 0) & fast & rd & ~ready;

	wire [15:0] m68k_bus_do; wire [7:0] z80_bus_do;
	wire [6:0] PA_o, PA_d, PB_o, PB_d, PC_o, PC_d;

	md_board md_board
	(
		.MCLK2(clk), .ext_reset(ext_reset), .reset_button(1'b0), .ext_vres(1'b0), .ext_zres(1'b0),
		.ram_68k_address(ram_68k_address), .ram_68k_byteena(ram_68k_byteena), .ram_68k_data(ram_68k_data),
		.ram_68k_wren(ram_68k_wren), .ram_68k_o(ram_68k_o),
		.ram_z80_address(ram_z80_address), .ram_z80_data(ram_z80_data), .ram_z80_wren(ram_z80_wren), .ram_z80_o(ram_z80_o),
		.M3(1'b1), .cart_data(cart_data), .cart_data_en(rd), .cart_address(cart_address), .cart_cs(cart_cs),
		.cart_oe(), .cart_lwr(), .cart_uwr(), .cart_time(), .cart_cas2(), .cart_data_wr(), .cart_dma(),
		.cart_m3_pause(1'b0), .ext_dtack(1'b0), .ext_dtack_hold(hold), .pal(1'b0), .jap(1'b0),
		.tmss_enable(1'b0), .tmss_data(16'h0), .tmss_address(),
		.m68k_addr(m68k_addr), .m68k_bus_do(m68k_bus_do), .m68k_di(m68k_bus_do),
		.z80_addr(), .z80_bus_do(z80_bus_do), .z80_di(z80_bus_do),
		.ext_VCLK_o(VCLK), .ext_ZCLK_o(ZCLK),
		.ext_VCLK_i(cpu_clk), .ext_ZCLK_i(ZCLK),
		.ext_VCLK_arb_i((ARB != 0) ? arb_clk : VCLK),
		.V_R(vr), .V_G(vg), .V_B(vb), .V_HS(), .V_VS(), .V_CS(),
		.A_L(), .A_R(), .A_L_2612(), .A_R_2612(), .MOL(), .MOR(), .MOL_2612(), .MOR_2612(), .PSG(), .DAC_ch_index(), .fm_sel23(),
		.PA_i(7'h7F), .PA_o(PA_o), .PA_d(PA_d), .PB_i(7'h7F), .PB_o(PB_o), .PB_d(PB_d), .PC_i(7'h7F), .PC_o(PC_o), .PC_d(PC_d),
		.vdp_hclk1(vhclk1), .vdp_intfield(), .vdp_de_h(vde_h), .vdp_de_v(vde_v), .vdp_m5(), .vdp_rs1(), .vdp_m2(), .vdp_lcb(), .vdp_psg_clk1(),
		.vdp_cramdot_dis(1'b1), .fm_clk1(), .vdp_hsync2(), .vdp_vsync2(), .ym2612_status_enable(1'b0),
		.dma_68k_req(1'b0), .dma_z80_req(1'b0), .dma_z80_ack(), .res_z80(), .vdp_dma_oe_early(cart_oe), .vdp_dma(), .spr_unlimited(SPRU != 0)
	);

	// results: work RAM $FF8000.. is word address 0x4000..
	integer i, fetches = 0, stale = 0, first_fetch = -1, first_wr = -1;
	reg [15:0] fin;
	always @(posedge clk) begin
		if(rd & ~rd_old) begin
			fetches = fetches + 1;
			if(first_fetch < 0) begin first_fetch = cyc; $display("first fetch at %0d", cyc); end
		end
		if(ram_68k_wren && (ram_68k_data == 16'h600D || ram_68k_data == 16'h0BAD) && ram_68k_byteena == 2'b11) begin
			fin = ram_68k_data;
			$display("RESULT period=%0d arb=%0d hold=%0d lat=%0d status=%s cycles=%0d fetches=%0d d2=%04X%04X d1=%04X%04X z80sum=%04X%04X vramsum=%04X%04X dmasum=%04X%04X vdp=%04X ram0=%04X%04X ram7=%04X%04X ramsum=%08X",
				PERIOD, ARB, HOLD, LAT, fin == 16'h600D ? "OK" : "TRAP", cyc - first_wr, fetches,
				wram[16'h6000], wram[16'h6001], wram[16'h6002], wram[16'h6003], wram[16'h6004], wram[16'h6005], wram[16'h6006], wram[16'h6007], wram[16'h600A], wram[16'h600B], wram[16'h6009],
				wram[16'h2000], wram[16'h2001], wram[16'h200E], wram[16'h200F], ramsum(0));
			$finish;
		end
		if(cyc == MAXCYC) begin
			$display("RESULT period=%0d arb=%0d hold=%0d lat=%0d status=TIMEOUT fetches=%0d addr=%06X", PERIOD, ARB, HOLD, LAT, fetches, {cart_address,1'b0});
			$finish;
		end
	end

	// +LINE=n: print active line n of frame 3 as runs of colours
	integer LINE = -1, frame = 0, aline = -1, apix = 0;
	integer LINE2 = -1;
	initial begin if($value$plusargs("LINE=%d", LINE)) ; if(!$value$plusargs("LINE2=%d", LINE2)) LINE2 = LINE; end
	wire [7:0] vr, vg, vb;
	wire vde_h, vde_v, vhclk1;
	reg  old_de_h = 0, old_de_v = 0, old_hclk1 = 0;
	reg  [23:0] run_c = 0;
	integer run_n = 0, run_x = 0;
	always @(posedge clk) if(LINE >= 0) begin
		old_de_h <= vde_h; old_de_v <= vde_v; old_hclk1 <= vhclk1;
		if(vde_v & ~old_de_v) begin frame = frame + 1; aline = -1; end
		if(vde_h & ~old_de_h & vde_v) begin aline = aline + 1; apix = 0; run_n = 0; end
		if(frame == 3 && aline >= LINE && aline <= LINE2 && vde_h && vhclk1 && !old_hclk1) begin
			if(run_n == 0) begin run_c = {vr,vg,vb}; run_x = apix; run_n = 1; end
			else if({vr,vg,vb} == run_c) run_n = run_n + 1;
			else begin
				$display("PIX x=%0d n=%0d rgb=%06X", run_x, run_n, run_c);
				run_c = {vr,vg,vb}; run_x = apix; run_n = 1;
			end
			apix = apix + 1;
		end
		if(frame == 3 && aline >= LINE && aline <= LINE2 && ~vde_h & old_de_h) begin
			$display("PIX x=%0d n=%0d rgb=%06X", run_x, run_n, run_c);
			$display("LINEDONE line=%0d pixels=%0d", aline, apix);
			if(aline == LINE2) $finish;
		end
	end

	// +PROBE=1: VDP sprite timing around the captured line
	integer PROBE = 0;
	initial if($value$plusargs("PROBE=%d", PROBE)) ;
	reg [9:0] old_y = 0;
	reg old_rd = 0, old_wr = 0, old_deh2 = 0;
	wire [9:0] p_y  = md_board.ym.vdp.w653;
	wire [5:0] p_ix = md_board.ym.vdp.w825;
	wire p_rd = md_board.ym.vdp.w823 & (p_ix < 40);
	wire p_wr = md_board.ym.vdp.w822 & md_board.ym.vdp.w817 & (p_ix < 40);
	always @(posedge clk) if(PROBE != 0 && frame == 3 && aline >= LINE - 2 && aline <= LINE) begin
		old_y <= p_y; old_rd <= p_rd; old_wr <= p_wr; old_deh2 <= vde_h;
		if(p_y != old_y) $display("PRB %0d line=%0d w653=%03X", cyc, aline, p_y);
		if(vde_h != old_deh2) $display("PRB %0d line=%0d de_h=%0d", cyc, aline, vde_h);
		if(cyc % 128 == 0) $display("PRB %0d line=%0d tick w821=%0d w823=%0d w822=%0d w817=%0d idx=%0d l475=%0d l474=%0d", cyc, aline, md_board.ym.vdp.w821, md_board.ym.vdp.w823, md_board.ym.vdp.w822, md_board.ym.vdp.w817, p_ix, md_board.ym.vdp.l475, md_board.ym.vdp.l474);
		if(p_rd != old_rd) $display("PRB %0d line=%0d disp_read=%0d idx=%0d", cyc, aline, p_rd, p_ix);
		if(p_wr != old_wr) $display("PRB %0d line=%0d spr_write=%0d idx=%0d", cyc, aline, p_wr, p_ix);
	end

	integer snoops = 0, lbw = 0;
	always @(posedge clk) begin
		if(md_board.vram_snoop_we) begin snoops = snoops + 1; if(PROBE == 2 && (snoops < 40 || (md_board.vram_snoop_addr[7:2] == 6'h3E && md_board.vram_snoop_addr[15:8] < 2))) $display("SNP %0d a=%04X d=%02X", cyc, md_board.vram_snoop_addr, md_board.vram_snoop_data); end
		if(md_board.spr_extra.lb_we) lbw = lbw + 1;
		if(PROBE != 0 && frame == 3 && aline >= LINE - 2 && aline <= LINE && md_board.spr_extra.start)
			$display("SPX %0d line=%0d y=%03X snoops=%0d lbw=%0d at=%02X h40=%0d state=%0d", cyc, aline, md_board.spr_line_y, snoops, lbw, md_board.spr_reg_at, md_board.spr_h40, md_board.spr_extra.state);
		if(PROBE != 0 && frame == 3 && aline >= LINE - 2 && aline <= LINE && md_board.spr_extra.state == 2 && md_board.spr_extra.cur < 3)
			$display("SPX %0d sat cur=%0d addr=%04X", cyc, md_board.spr_extra.cur, md_board.spr_extra.sat_addr);
		if(PROBE != 0 && frame == 3 && aline >= LINE - 2 && aline <= LINE && md_board.spr_extra.state == 3 && md_board.spr_extra.cur < 3)
			$display("SPX %0d word0=%08X ly=%03X yrow=%03X", cyc, md_board.spr_extra.sh_word, md_board.spr_extra.ly, md_board.spr_extra.y_row);
	end

	function [31:0] ramsum(input integer dummy);
		integer k; reg [31:0] s;
		begin
			s = 0;
			for(k = 0; k < 64; k = k + 1) s = {s[30:0], s[31]} ^ wram[16'h2000 + k];
			ramsum = s;
		end
	endfunction
endmodule
