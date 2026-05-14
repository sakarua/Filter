module sram_2Mx64 #(
	parameter DW = 64,
	parameter BW = 8,
	parameter AW = 21,
	parameter DEPTH = 2097152
) (
	input              clk,
	input              csn,
	input  [AW-1:0]     adr,
	input  [BW-1:0]     wen,
	input  [DW-1:0]     din,
	output [DW-1:0]     dout
);
`ifdef _USE_TSMC_MODEL_
	// TODO: 例化具体的 TSMC memory 模型
`else
	// 通用单端口同步 RAM 模型
	reg [DW-1:0] mem [DEPTH-1:0];
	reg [AW-1:0] addr_reg;
	integer i;

	assign dout = mem[addr_reg];

	always @(posedge clk) begin
		if (~csn)
			addr_reg <= adr;
	end

	always @(posedge clk) begin
		if (~csn) begin
			for (i = 0; i < BW; i = i + 1)
				if (~wen[i])
					{mem[adr][i*8+7], mem[adr][i*8+6], mem[adr][i*8+5], mem[adr][i*8+4],
					 mem[adr][i*8+3], mem[adr][i*8+2], mem[adr][i*8+1], mem[adr][i*8]} <=
					{din[i*8+7], din[i*8+6], din[i*8+5], din[i*8+4],
					 din[i*8+3], din[i*8+2], din[i*8+1], din[i*8]};
		end
	end
`endif

endmodule

