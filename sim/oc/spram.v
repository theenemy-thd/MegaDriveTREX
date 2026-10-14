// sim model of bram.vhd spram: registered address, unregistered output
module spram #(parameter AW=8, DW=8)
(
	input clock,
	input [AW-1:0] address,
	input [DW-1:0] data,
	input wren,
	input [DW/8-1:0] byteena,
	output [DW-1:0] q
);
reg [DW-1:0] mem[0:(1<<AW)-1];
reg [AW-1:0] a;
integer i;
initial for(i=0;i<(1<<AW);i=i+1) mem[i]=0;
always @(posedge clock) begin
	a <= address;
	if(wren) for(i=0;i<DW/8;i=i+1) if(byteena[i]) mem[address][i*8+:8] <= data[i*8+:8];
end
assign q = mem[a];
endmodule
