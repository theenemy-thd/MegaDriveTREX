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
	integer PSGS   = 0;   // +PSGS=1: stock-speed window after PSG writes
	initial begin
		if($value$plusargs("PERIOD=%d", PERIOD)) ;
		if($value$plusargs("ARB=%d", ARB)) ;
		if($value$plusargs("HOLD=%d", HOLD)) ;
		if($value$plusargs("LAT=%d", LAT)) ;
		if($value$plusargs("SLOW=%d", SLOW)) ;
		if($value$plusargs("TOGGLE=%d", TOGGLE)) ;
		if($value$plusargs("SPRU=%d", SPRU)) ;
		if($value$plusargs("PSGS=%d", PSGS)) ;
	end

	// same Z80-area slowdown as MegaDrive.sv, and an optional stress toggle of the speed
	wire [22:0] m68k_addr;
	reg  [10:0] cpu_slow = 0;
	reg         tog = 0;
	integer     tcnt = 0;
	always @(posedge clk) begin
		if((SLOW != 0 && m68k_addr[22:16] == 7'b1010000) || (DMAS == 4 && m68k_addr[22:20] == 3'b110) || (DMAS == 6 && m68k_addr[22:20] == 3'b110 && m68k_addr[2:1] == 2'b01) || (PSGS != 0 && m68k_addr[22:20] == 3'b110 && m68k_addr[3:2] == 2'b10)) cpu_slow <= '1;
		else if(cpu_slow != 0) cpu_slow <= cpu_slow - 1'd1;
		tcnt <= tcnt + 1;
		if(TOGGLE != 0 && tcnt % TOGGLE == 0) tog <= ~tog;
	end
	integer DMAS = 0;   // +DMAS=1: stock speed while the VDP owns the 68k bus (vdp_dma), 2: while BR is asserted
	initial if($value$plusargs("DMAS=%d", DMAS)) ;
	wire vdp_dma;
	wire dma_slow = (DMAS == 1 && vdp_dma) || (DMAS == 2 && !md_board.BR) || (DMAS == 3 && (vdp_dma || !md_board.BR || !md_board.BGACK));
	wire [3:0] period_now = (cpu_slow != 0 || tog || dma_slow) ? 4'd0 : PERIOD[3:0];
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

	// +GAME=1: run a real cartridge (rom_game.hex, up to 8MB, SSF mapper at $A130F3-$A130FF)
	integer GAME = 0, FRAMES = 0, START1 = -1, START2 = -1;
	reg [15:0] game[0:4194303];
	reg [3:0]  ssf_bank[0:7];
	initial begin
		integer b;
		for(b = 0; b < 8; b = b + 1) ssf_bank[b] = b;
		if($value$plusargs("GAME=%d", GAME)) ;
		if($value$plusargs("FRAMES=%d", FRAMES)) ;
		if($value$plusargs("START1=%d", START1)) ;
		if($value$plusargs("START2=%d", START2)) ;
		if(GAME != 0) $readmemh("rom_game.hex", game);
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
			cart_data <= (GAME != 0) ? game[{ssf_bank[cart_address[20:18]], cart_address[17:0]}] : rom[cart_address[11:0]];
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
		.cart_oe(), .cart_lwr(cart_lwr), .cart_uwr(), .cart_time(), .cart_cas2(), .cart_data_wr(cart_data_wr), .cart_dma(),
		.cart_m3_pause(1'b0), .ext_dtack(1'b0), .ext_dtack_hold(hold), .pal(1'b0), .jap(1'b0),
		.tmss_enable(1'b0), .tmss_data(16'h0), .tmss_address(),
		.m68k_addr(m68k_addr), .m68k_bus_do(m68k_bus_do), .m68k_di(m68k_bus_do),
		.z80_addr(), .z80_bus_do(z80_bus_do), .z80_di(z80_bus_do),
		.ext_VCLK_o(VCLK), .ext_ZCLK_o(ZCLK),
		.ext_VCLK_i(cpu_clk), .ext_ZCLK_i(ZCLK),
		.ext_VCLK_arb_i((ARB != 0) ? arb_clk : VCLK),
		.V_R(vr), .V_G(vg), .V_B(vb), .V_HS(), .V_VS(), .V_CS(),
		.A_L(), .A_R(), .A_L_2612(aL), .A_R_2612(aR), .MOL(), .MOR(), .MOL_2612(), .MOR_2612(), .PSG(),  .DAC_ch_index(), .fm_sel23(),
		.PA_i(pad_a), .PA_o(PA_o), .PA_d(PA_d), .PB_i(7'h7F), .PB_o(PB_o), .PB_d(PB_d), .PC_i(7'h7F), .PC_o(PC_o), .PC_d(PC_d),
		.vdp_hclk1(vhclk1), .vdp_intfield(), .vdp_de_h(vde_h), .vdp_de_v(vde_v), .vdp_m5(), .vdp_rs1(), .vdp_m2(), .vdp_lcb(), .vdp_psg_clk1(),
		.vdp_cramdot_dis(1'b1), .fm_clk1(), .vdp_hsync2(), .vdp_vsync2(vvs), .ym2612_status_enable(1'b0),
		.dma_68k_req(1'b0), .dma_z80_req(1'b0), .dma_z80_ack(), .res_z80(), .vdp_dma_oe_early(cart_oe), .vdp_dma(vdp_dma), .spr_unlimited(SPRU != 0)
	);

	// results: work RAM $FF8000.. is word address 0x4000..
	integer i, fetches = 0, stale = 0, first_fetch = -1, first_wr = -1;
	reg [15:0] fin;
	always @(posedge clk) begin
		if(rd & ~rd_old) begin
			fetches = fetches + 1;
			if(first_fetch < 0) begin first_fetch = cyc; $display("first fetch at %0d", cyc); end
		end
		if(ram_68k_wren && ram_68k_address == 15'h6010 && (ram_68k_data == 16'h600D || ram_68k_data == 16'h0BAD) && ram_68k_byteena == 2'b11) begin
			fin = ram_68k_data;
			$display("PSGVOL %h %h %h %h tone %h %h %h noise %h", md_board.ym.vdp.l655, md_board.ym.vdp.l656, md_board.ym.vdp.l657, md_board.ym.vdp.l658, md_board.ym.vdp.l659, md_board.ym.vdp.l660, md_board.ym.vdp.l661, md_board.ym.vdp.l662);
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

	// +VLOG=1: log every VRAM chip write (address, data) as it settles
	integer VLOG = 0, vfd = 0;
	reg vwe_old = 0; reg [15:0] va_old; reg [7:0] vd_old;
	initial if($value$plusargs("VLOG=%d", VLOG)) vfd = $fopen("vlog.txt", "w");
	always @(posedge clk) if(VLOG != 0) begin
		vwe_old <= md_board.vram_snoop_we; va_old <= md_board.vram_snoop_addr; vd_old <= md_board.vram_snoop_data;
		if(vwe_old & ~md_board.vram_snoop_we) $fdisplay(vfd, "%04X %02X", va_old, vd_old);
	end

	// +PROBE=3: bus state every 20000 cycles after reset (hang hunting)
	always @(posedge clk) if(PROBE == 3 && cyc > 1300000 && cyc % 20000 == 0)
		$display("BUS %0d AS=%b DTACK=%b BR=%b BG=%b BGACK=%b ZBR=%b ZBAK=%b ZRES=%b MREQ=%b ZA=%04X VA=%06X WAIT=%b RW=%b", cyc,
			md_board.AS, md_board.DTACK, md_board.BR, md_board.BG, md_board.BGACK, md_board.ZBR, md_board.ZBAK, md_board.ZRES,
			md_board.MREQ, md_board.ZA, {md_board.VA,1'b0}, md_board.WAIT, md_board.RW);

	wire cart_lwr; wire [15:0] cart_data_wr;
	wire [17:0] aL, aR;
	wire vvs;

	// SSF mapper writes
	reg old_lwr = 0;
	always @(posedge clk) begin
		old_lwr <= cart_lwr;
		if(GAME != 0 && cart_lwr && !old_lwr && {cart_address, 1'b0} >= 24'hA130F2 && {cart_address, 1'b0} <= 24'hA130FE)
			ssf_bank[cart_address[2:0]] <= cart_data_wr[3:0];
	end

	// pad 1: Start held for 10 frames from frame START1 and START2
	integer gframe = 0;
	wire th = PA_d[6] ? 1'b1 : PA_o[6];
	wire start_dn = (START1 >= 0 && gframe >= START1 && gframe < START1 + 10) || (START2 >= 0 && gframe >= START2 && gframe < START2 + 10);
	wire [6:0] pad_a = th ? 7'h7F : {1'b0, ~start_dn, 1'b1, 2'b00, 2'b11};

	// frame counter, YM2612 write log and audio dump (one stereo sample every 2048 clocks, 52.4 kHz)
	integer yfd = 0, afd = 0;
	reg old_vs = 1, old_ymwr = 0;
	reg [9:0] ylast = 0;
	initial if(GAME != 0) begin yfd = $fopen("ymlog.txt", "w"); afd = $fopen("audio.raw", "wb"); end
	always @(posedge clk) if(GAME != 0) begin
		old_vs <= vvs;
		if(old_vs & ~vvs) begin
			gframe = gframe + 1;
			$fdisplay(yfd, "F %0d", gframe);
			if(gframe % 30 == 0) $display("frame %0d cyc %0d", gframe, cyc);
			if(FRAMES != 0 && gframe >= FRAMES) $finish;
		end
		old_ymwr <= ~md_board.ym.fm_cs & ~md_board.ym.ZWR_i;
		if(~md_board.ym.fm_cs & ~md_board.ym.ZWR_i) ylast <= {md_board.ym.ZA_i[1:0], md_board.ym.ZD_i};
		if(old_ymwr & ~(~md_board.ym.fm_cs & ~md_board.ym.ZWR_i))
			$fdisplay(yfd, "W %0d %02X", ylast[9:8], ylast[7:0]);
		if(cyc % 2048 == 0) begin
			$fwrite(afd, "%c%c%c%c", aL[9:2], aL[17:10], aR[9:2], aR[17:10]);
		end
	end

	// +SNAP=n: write every n-th frame as snap_<frame>.ppm (active area)
	integer SNAP = 0, sfd = 0, sx = 0, sy = -1;
	initial if($value$plusargs("SNAP=%d", SNAP)) ;
	reg s_deh = 0, s_dev = 0, s_hclk = 0;
	always @(posedge clk) if(GAME != 0 && SNAP != 0) begin
		s_deh <= vde_h; s_dev <= vde_v; s_hclk <= vhclk1;
		if(vde_v & ~s_dev) begin
			sy = -1;
			if(gframe % SNAP == 0) begin
				string fn;
				fn = $sformatf("snap_%0d.ppm", gframe);
				sfd = $fopen(fn, "wb");
				$fwrite(sfd, "P6%c320 224%c255%c", 8'd10, 8'd10, 8'd10);
			end
			else sfd = 0;
		end
		if(~vde_v & s_dev & sfd != 0) begin $fclose(sfd); sfd = 0; end
		if(vde_h & ~s_deh & vde_v) begin sy = sy + 1; sx = 0; end
		if(sfd != 0 && vde_h && vde_v && vhclk1 && !s_hclk && sx < 320 && sy < 224) begin
			$fwrite(sfd, "%c%c%c", vr, vg, vb);
			sx = sx + 1;
		end
	end

	// +PROBE=4: PSG write strobes
	reg old_w111 = 0;
	always @(posedge clk) if(PROBE == 4) begin
		old_w111 <= md_board.ym.vdp.w111;
		if(md_board.ym.vdp.w111 != old_w111) $display("PSGW %0d w111=%b data=%02X fast=%b slow=%0d l635=%b t43=%b", cyc, md_board.ym.vdp.w111, md_board.ym.vdp.io_data[7:0], fast, cpu_slow, md_board.ym.vdp.l635, md_board.ym.vdp.t43);
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
