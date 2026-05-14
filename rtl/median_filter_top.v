//
// 中值滤波顶层：连接 APB 接口、像素时钟域与外部存储器
//
module median_filter_top (
	input             pclk,
	input             prstn,
	/////////////
	input             clk,
	input             rstn,
	/// apb in/out signals
	input      [ 7:0] paddr,
	input      [31:0] pwdata,
	input             penable,
	input             pwrite,
	input             psel,
	output     [31:0] prdata,
	//////
	output            int_out,
	/////////////
	output            mem_csn,
	output     [ 7:0] mem_wen, // byte select
	output     [20:0] mem_adr,
	output     [63:0] mem_do,
	input      [63:0] mem_di
);
	// TODO: 实现 APB 接口与中值滤波核心逻辑

endmodule
