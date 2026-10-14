// TREX: 68000 clock generator for the Nuked-MD board (release 20260603 clocking).
// Period 0 passes the stock VCLK through exactly as the stock core does
// (VCLK & vclk_en, combinational). Any other value makes a clock of that many
// clk_md cycles (low phase first) from a register. Speed changes happen only
// while both clocks are low: stock -> fast right after VCLK falls, fast ->
// stock by holding the clock low until VCLK falls, so the CPU never sees a
// short phase.

module m68k_clkgen
(
	input            clk,          // clk_md (MCLK2)
	input      [3:0] period,       // 0 = stock
	input            run,          // 0 = freeze the CPU clock (low) at its next falling edge
	input            VCLK,         // stock VCLK from the board

	output           cpu_clk,      // gated clock for the 68000
	output           arb_clk,      // ungated clock for the arbiter / I/O chip
	output           fast          // 1 while not on the stock clock
);

localparam STOCK = 2'd0, FAST = 2'd1, HOLD = 2'd2;

reg  [1:0] src = STOCK;
reg  [3:0] per = 0;
reg  [3:0] cnt = 0;
reg        fclk = 0;         // generated clock (FAST), 0 in HOLD
reg        vclk_en = 0, fclk_en = 0;
reg        old_vclk = 0;

wire [3:0] lowlen = per - per[3:1];
wire [3:0] cnt_n  = (cnt == per - 1'd1) ? 4'd0 : cnt + 1'd1;
wire       vfall  = old_vclk & ~VCLK;          // VCLK fell last clock (it is low now)
wire       ffall  = fclk & ~(cnt_n >= lowlen); // generated clock falls this clock

assign fast    = (src != STOCK);
assign cpu_clk = fast ? (fclk & fclk_en) : (VCLK & vclk_en);
assign arb_clk = fast ? fclk : VCLK;

always @(posedge clk) begin
	old_vclk <= VCLK;
	if(vfall) vclk_en <= run;

	case(src)
		STOCK:
			if(vfall && period) begin
				src <= FAST;
				per <= period;
				cnt <= 0;
				fclk <= 0;
				fclk_en <= vclk_en;
			end

		FAST: begin
			cnt  <= cnt_n;
			fclk <= (cnt_n >= lowlen);
			if(ffall) begin
				fclk_en <= run;
				if(period != per) begin
					cnt <= 0;
					if(period) per <= period;
					else src <= HOLD;
				end
			end
		end

		default: begin
			fclk <= 0;
			if(vfall) begin
				src <= STOCK;
				vclk_en <= fclk_en & run;
			end
		end
	endcase
end

endmodule
