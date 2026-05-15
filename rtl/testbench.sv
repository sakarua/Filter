//
`timescale 1ns/10ps

module testbench;
	localparam PCLK_HALF_PERIOD   = 5; // 100MHz
	localparam PIXCLK_HALF_PERIOD = 2; // 250MHz

	localparam REG_SYS_CTRL        = 8'h00;
	localparam REG_FRAME_WIDTH     = 8'h04;
	localparam REG_FRAME_HEIGHT    = 8'h08;
	localparam REG_BASE_FRAME_IN   = 8'h0c;
	localparam REG_BASE_FRAME_OUT  = 8'h10;
	localparam REG_FRAME_NUMBER    = 8'h14;
	localparam REG_FRAME_CYCLE     = 8'h18;
	localparam REG_FRAME_CYCLE_SUM = 8'h1c;
	localparam REG_INT_STATUS      = 8'h20;
	localparam REG_INT_ENABLE      = 8'h24;

	/////////
	reg pclk;
	reg prstn;
	/////////////
	reg pixel_clk;
	reg pixel_rstn;
	/// apb in/out signals
	wire [31:0] paddr;
	wire [31:0] pwdata;
	wire        penable;
	wire        pwrite;
	wire        psel;
	wire [31:0] prdata;
	//////
	wire        mem_csn;
	wire [ 7:0] mem_wen; // byte select
	wire [20:0] mem_adr;
	wire [63:0] mem_do;
	wire [63:0] mem_di;

	initial begin
		pclk       = 1'b0;
		prstn      = 1'b0;
		pixel_clk  = 1'b0;
		pixel_rstn = 1'b0;
		#1us;
		prstn = 1'b1;
		#1us;
		pixel_rstn = 1'b1;
	end

	always #(PCLK_HALF_PERIOD  ) pclk      = ~pclk;
	always #(PIXCLK_HALF_PERIOD) pixel_clk = ~pixel_clk;

	// 顶层实例
	median_filter_top u0_ss_top (
		.pclk    (pclk),
		.prstn   (prstn),
		///////
		.clk     (pixel_clk),
		.rstn    (pixel_rstn),
		/// apb in/out signals
		.paddr   (paddr[7:0]),
		.pwdata  (pwdata),
		.penable (penable),
		.pwrite  (pwrite),
		.psel    (psel),
		.prdata  (prdata),
		//////
		.int_out (int_out),
		/////////////
		.mem_csn (mem_csn),
		.mem_wen (mem_wen), // byte select
		.mem_adr (mem_adr),
		.mem_do  (mem_do),
		.mem_di  (mem_di)
	);

	// SRAM 仿真模型
	sram_2Mx64 u_mem (
		.clk  (pixel_clk),
		.csn  (mem_csn),
		.adr  (mem_adr),
		.wen  (mem_wen),
		.din  (mem_do),
		.dout (mem_di)
	);

	reg  pready;
	wire reg_wr = penable & psel & pwrite;
	wire reg_rd = ~penable & psel & ~pwrite;

	always @(posedge pclk or negedge prstn) begin
		if (~prstn) begin
			pready <= 1'b0;
		end else begin
			if (pready)
				pready <= 1'b0;
			else if (reg_wr | reg_rd)
				pready <= 1'b1;
		end
	end

	// APB 主机驱动
	apb_host_driver u0_apb_host_driver (
		.pclk    (pclk),
		.presetn (prstn),
		//////
		.paddr   (paddr),
		.pwdata  (pwdata),
		.penable (penable),
		.pwrite  (pwrite),
		.psel    (psel),
		//////
		.prdata  (prdata),
		.pready  (pready)
	);

	reg [1:0]  sys_mode;
	reg [31:0] ir_period;

	// 通过 APB 配置寄存器
	initial begin
		wait (prstn == 1);
		begin
			repeat (100) @(posedge pclk);
			testbench.u0_apb_host_driver.write_apb(REG_FRAME_WIDTH, 32'd480);
			testbench.u0_apb_host_driver.write_apb(REG_FRAME_HEIGHT, 32'd640);
			testbench.u0_apb_host_driver.write_apb(REG_BASE_FRAME_IN, 32'h0000_0000);
			testbench.u0_apb_host_driver.write_apb(REG_BASE_FRAME_OUT, 32'h0040_0000);
			testbench.u0_apb_host_driver.write_apb(REG_INT_ENABLE, 32'h1); // enable interrupt
			/////////////
			testbench.u0_apb_host_driver.write_apb(REG_SYS_CTRL, 32'h01); // enable median filter
			$display("frame start!");
		end
		/////////////
		wait (int_out == 1);
		#5ms;
		$finish(2);
	end

	initial begin
		#20ms;
		$finish(2);
	end

	//`define FSDB_DUMP
`ifdef FSDB_DUMP
	initial begin
		$fsdbAutoSwitchDumpfile(512, "dump.fsdb", 4, "dump.log");
		$fsdbDumpvars(0, testbench);

		$fsdbDumpon;
		//#10 $fsdbDumpoff;
	end
`endif

endmodule
