// TREX: "Sprite Limit Off" helper renderer for the Nuked-MD VDP.
//
// The VDP still draws every line as usual. This module draws the same line
// again from a shadow copy of VRAM, with no sprites-per-line or
// pixels-per-line limit, into a small line buffer of its own. The VDP's sprite
// line buffer readout then uses these pixels wherever the VDP itself has no
// sprite pixel, so sprites the VDP had to drop show up, while everything the
// VDP did draw (and its priority, shadow/highlight and collision handling)
// is untouched.
//
// Shadow VRAM is written from the VRAM chip interface, so it sees every write
// (CPU, DMA fill/copy, 68k DMA). From simulation, the chip address of VDP
// byte address A is {A[9:2], A[15:10], A[1], ~A[0]}.
//
// Line buffer entries use the VDP format: 8 pixels per entry, pixel n (0 =
// leftmost) in bits [7n+6:7n] = {index[3:0], palette[1:0], priority}.

module md_spr_extra
(
	input             clk,         // MCLK2

	// VRAM chip write snoop
	input             vram_we,
	input      [15:0] vram_addr,   // chip address {row, col}
	input       [7:0] vram_data,

	// VDP state
	input       [7:0] reg_at,      // sprite attribute table base (reg 5)
	input             h40,
	input             im2,         // interlace mode 2 (double height cells)
	input       [9:0] line_y,      // sprite Y the VDP compares against (w653)
	input             disp,        // VDP is reading its line buffer for display (w823)

	// VDP line buffer readout
	input       [5:0] rd_idx,
	output reg [55:0] rd_data,
	output reg  [7:0] rd_valid     // per pixel: helper has a pixel here
);

///////////////////////////////////////////////////////////////////
// shadow VRAM: 16K x 32, byte lane = VDP address bits [1:0]

wire [13:0] sh_waddr = {vram_addr[7:2], vram_addr[15:8]};
wire  [1:0] sh_lane  = {vram_addr[1], ~vram_addr[0]};

reg  [13:0] sh_raddr;
reg   [7:0] sh_q[4];

genvar gl;
generate
	for(gl = 0; gl < 4; gl = gl + 1) begin : shadow
		reg [7:0] mem[16384];
		always @(posedge clk) begin
			if(vram_we && sh_lane == gl) mem[sh_waddr] <= vram_data;
			sh_q[gl] <= mem[sh_raddr];
		end
	end
endgenerate

// byte at VDP address A[1:0]=0 is the most significant (68000 order)
wire [31:0] sh_word = {sh_q[0], sh_q[1], sh_q[2], sh_q[3]};

///////////////////////////////////////////////////////////////////
// Timing (from simulation of the Nuked VDP): line_y changes once per line,
// just before the VDP ends its display readout. The VDP searches sprites for
// line_y during the next display period and draws that line into its buffer
// in the following HBlank, so the line_y set at one change is displayed in
// the second display period after it. Three banks: one displayed, one ready,
// one being drawn.

reg  [1:0] rbank = 0;         // bank being drawn
reg  [1:0] last_bank = 0, prev_bank = 0;
reg  [1:0] dbank = 0;         // bank being displayed
reg [319:0] occ[3];           // pixel present

reg  [9:0] line_y_old;
reg        disp_old;
wire       start = (line_y != line_y_old);
wire [1:0] nbank = (rbank == 2) ? 2'd0 : rbank + 1'd1;

always @(posedge clk) begin
	line_y_old <= line_y;
	disp_old   <= disp;
	if(start) begin
		rbank  <= nbank;
		prev_bank <= last_bank;
		last_bank   <= nbank;
	end
	if(disp & ~disp_old) dbank <= prev_bank;
end

reg        lb_we;
reg  [1:0] lb_wbank;
reg  [5:0] lb_widx;
reg  [2:0] lb_wlane;
reg  [6:0] lb_wdata;

reg  [6:0] lb_q[8];
reg  [5:0] rd_idx_r;
reg  [1:0] rd_bank_r;

genvar gp;
generate
	for(gp = 0; gp < 8; gp = gp + 1) begin : lanes
		reg [6:0] mem[256];
		always @(posedge clk) begin
			if(lb_we && lb_wlane == gp) mem[{lb_wbank, lb_widx}] <= lb_wdata;
			lb_q[gp] <= mem[{dbank, rd_idx}];
		end
	end
endgenerate

always @(posedge clk) begin
	rd_idx_r  <= rd_idx;
	rd_bank_r <= dbank;
end

integer k;
always @(*) begin
	for(k = 0; k < 8; k = k + 1) begin
		rd_valid[k] = (rd_idx_r < 6'd40) && occ[rd_bank_r][{rd_idx_r, 3'b000} + k];
		rd_data[k*7 +: 7] = rd_valid[k] ? lb_q[k] : 7'h00;
	end
end

///////////////////////////////////////////////////////////////////
// renderer

localparam S_IDLE = 0, S_SAT0 = 1, S_SAT0W = 2, S_SAT0D = 3, S_SAT1W = 4, S_SAT1D = 5,
           S_CELL = 6, S_CELLW = 7, S_CELLD = 8, S_PIX = 9, S_NEXT = 10;

reg  [3:0] state = S_IDLE;
reg  [6:0] cur;            // sprite number
reg  [6:0] cnt;            // sprites visited
reg  [6:0] link;
reg  [1:0] hs, vs;
reg  [5:0] row;            // pixel row inside the sprite (up to 4 cells x 16)
reg  [1:0] col;            // cell column being drawn
reg [15:0] pat;
reg  [9:0] sx;             // screen x of the current cell (signed 10 bit)
reg        nonzero_x;      // a sprite with X != 0 was seen on this line
reg [31:0] pix;            // cell pixels, next pixel in [31:28] (hflip applied on load)
reg  [2:0] pn;
reg  [9:0] px;             // screen x of the pixel being written (= sx + pn, registered for timing)
reg  [9:0] ly;

// pixel write, split over two clocks for timing: S_PIX checks the occupancy flag,
// the next clock sets it and writes the line buffer. Consecutive S_PIX clocks always
// have different px, and a later sprite reaches the same px at least 3 clocks later.
reg        pw_go;
reg  [1:0] pw_bank;
reg  [8:0] pw_px;
reg  [6:0] pw_data;

wire [6:0] max_spr = h40 ? 7'd80 : 7'd64;
wire [9:0] width   = h40 ? 10'd320 : 10'd256;

// SAT entry n: VDP byte address sat_base + 8n
wire [15:0] sat_base = {(h40 ? {reg_at[6:1], 1'b0} : reg_at[6:0]), 9'h000};
wire [15:0] sat_addr = sat_base + {cur, 3'b000};

// word0 = {Y[15:0], size, link}, word1 = {pattern, X}
wire  [9:0] y_pos  = im2 ? sh_word[25:16] : {1'b0, sh_word[24:16]};
wire  [9:0] y_row  = im2 ? (ly - y_pos) : ((ly - y_pos) & 10'h1FF);
wire  [1:0] w_vs   = sh_word[9:8];
wire  [6:0] height = im2 ? ({w_vs, 4'h0} + 7'd16) : ({1'b0, w_vs, 3'h0} + 7'd8);

// cell address for column col, current row
wire  [1:0] c_col   = pat[11] ? (hs - col) : col;                  // hflip
wire  [5:0] c_row   = pat[12] ? ((im2 ? {vs, 4'hF} : {1'b0, vs, 3'h7}) - row) : row; // vflip
wire  [1:0] c_cell  = im2 ? c_row[5:4] : c_row[4:3];
wire  [3:0] c_line  = im2 ? c_row[3:0] : {1'b0, c_row[2:0]};
wire [10:0] c_tile  = pat[10:0] + c_col * (vs + 1'd1) + c_cell;
wire [15:0] c_addr  = im2 ? {c_tile[9:0], c_line, 2'b00} : {c_tile, c_line[2:0], 2'b00};

// pixel being written
wire [3:0] pv     = pix[31:28];
wire [31:0] sh_word_hf = {sh_word[3:0],   sh_word[7:4],   sh_word[11:8],  sh_word[15:12],
                          sh_word[19:16], sh_word[23:20], sh_word[27:24], sh_word[31:28]};

always @(posedge clk) begin
	lb_we <= 0;
	pw_go <= 0;

	case(state)
		S_IDLE: ;

		S_SAT0: begin
				sh_raddr <= sat_addr[15:2];
				state <= S_SAT0W;
			end

		S_SAT0W: state <= S_SAT0D;

		S_SAT0D: begin
				link <= sh_word[6:0];
				hs   <= sh_word[11:10];
				vs   <= sh_word[9:8];
				row  <= y_row[5:0];
				if(y_row < height) begin
					sh_raddr <= sh_raddr + 1'd1;
					state <= S_SAT1W;
				end
				else state <= S_NEXT;
			end

		S_SAT1W: state <= S_SAT1D;

		S_SAT1D: begin
				pat <= sh_word[31:16];
				sx  <= {1'b0, sh_word[8:0]} - 10'd128;
				col <= 0;
				if(sh_word[8:0] == 0) begin
					// X = 0 masks the rest of the line once another sprite was found
					if(nonzero_x) state <= S_IDLE;
					else state <= S_NEXT;
				end
				else begin
					nonzero_x <= 1;
					state <= S_CELL;
				end
			end

		S_CELL: begin
				sh_raddr <= c_addr[15:2];
				state <= S_CELLW;
			end

		S_CELLW: state <= S_CELLD;

		S_CELLD: begin
				pix <= pat[11] ? sh_word_hf : sh_word;
				pn <= 0;
				px <= sx;
				state <= S_PIX;
			end

		S_PIX: begin
				pw_go   <= pv != 0 && !px[9] && px < width && !occ[rbank][px];
				pw_bank <= rbank;
				pw_px   <= px[8:0];
				pw_data <= {pv, pat[14:13], pat[15]};
				pix <= {pix[27:0], 4'h0};
				pn <= pn + 1'd1;
				px <= px + 1'd1;
				if(pn == 7) begin
					sx <= sx + 10'd8;
					col <= col + 1'd1;
					state <= (col == hs) ? S_NEXT : S_CELL;
				end
			end

		S_NEXT: begin
				cur <= link;
				cnt <= cnt + 1'd1;
				if(link == 0 || link >= max_spr || cnt + 1'd1 >= max_spr) state <= S_IDLE;
				else state <= S_SAT0;
			end
	endcase

	// a new line starts the renderer (and stops one that did not finish)
	if(start) begin
		ly <= line_y;
		cur <= 0;
		cnt <= 0;
		nonzero_x <= 0;
		occ[nbank] <= '0;
		pw_go <= 0;
		state <= S_SAT0;
	end

	// second half of the pixel write (a pixel decided before a new line still lands
	// in its own bank)
	if(pw_go) begin
		occ[pw_bank][pw_px] <= 1;
		lb_we    <= 1;
		lb_wbank <= pw_bank;
		lb_widx  <= pw_px[8:3];
		lb_wlane <= pw_px[2:0];
		lb_wdata <= pw_data;
	end
end

endmodule
