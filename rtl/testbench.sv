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

	// Testbench init mode and image size
	localparam bit INIT_MODE_RAW = 1'b1; // 0 = RGB888, 1 = RAW16
	localparam int IMG_WIDTH  = 480;
	localparam int IMG_HEIGHT = 640;
	localparam int INIT_BASE_ADDR = 32'h0000_0000; // byte address for SRAM init start
	localparam int OUT_BASE_ADDR  = 32'h0040_0000; // byte address for SRAM output start

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

`ifndef _USE_TSMC_MODEL_
	// SRAM init mode: 0 = RGB888 (RRGGBB), 1 = RAW16 (HHLL, little-endian bytes)
	localparam int IMG_PIXELS = IMG_WIDTH * IMG_HEIGHT;
	localparam int BYTES_PER_PIXEL = INIT_MODE_RAW ? 2 : 3;

	string  img_file_rgb;
	string  img_file_raw;
	string  img_file;
	integer img_fh;
	integer img_r;
	integer pixel_index;
	integer byte_addr;
	reg [23:0] rgb_hex;
	reg [15:0] raw_hex;
	reg [ 7:0] red_byte;
	reg [ 7:0] green_byte;
	reg [ 7:0] blue_byte;
	string  out_file;

	task automatic write_sram_byte(input integer addr, input [7:0] data);
		integer word_addr;
		integer byte_lane;
		begin
			word_addr = addr >> 3;
			byte_lane = addr & 7;
			u_mem.mem[word_addr][byte_lane*8 +: 8] = data;
		end
	endtask

	task automatic read_sram_byte(input integer addr, output [7:0] data);
		integer word_addr;
		integer byte_lane;
		begin
			word_addr = addr >> 3;
			byte_lane = addr & 7;
			data = u_mem.mem[word_addr][byte_lane*8 +: 8];
		end
	endtask

	task automatic dump_output_to_file;
		integer out_fh;
		integer i;
		integer addr;
		reg [7:0] b0;
		reg [7:0] b1;
		reg [15:0] raw_out;
		begin
			out_fh = $fopen(out_file, "w");
			if (out_fh == 0) begin
				$display("ERROR: could not open output file %s", out_file);
			end else begin
				for (i = 0; i < IMG_PIXELS; i = i + 1) begin
					addr = OUT_BASE_ADDR + (i * (INIT_MODE_RAW ? 2 : 1));
					if (INIT_MODE_RAW) begin
						read_sram_byte(addr + 0, b0);
						read_sram_byte(addr + 1, b1);
						raw_out = {b1, b0};
						$fwrite(out_fh, "%04x\n", raw_out);
					end else begin
						read_sram_byte(addr, b0);
						$fwrite(out_fh, "%02x\n", b0);
					end
				end
				$fclose(out_fh);
				$display("Dumped %0d pixels to %s", IMG_PIXELS, out_file);
			end
		end
	endtask

	initial begin
		img_file_rgb = "matlab/bmp.txt";
		img_file_raw = "matlab/raw16.txt";
		img_file = INIT_MODE_RAW ? img_file_raw : img_file_rgb;
		if ($value$plusargs("IMG_FILE=%s", img_file)) begin
		end
		out_file = "rtl/output";
		if ($value$plusargs("OUT_FILE=%s", out_file)) begin
		end

		img_fh = $fopen(img_file, "r");
		if (img_fh == 0) begin
			$display("ERROR: could not open image file %s", img_file);
		end else begin
			pixel_index = 0;
			while (!$feof(img_fh) && (pixel_index < IMG_PIXELS)) begin
				if (INIT_MODE_RAW) begin
					img_r = $fscanf(img_fh, "%h\n", raw_hex);
					if (img_r == 1) begin
						byte_addr  = INIT_BASE_ADDR + (pixel_index * BYTES_PER_PIXEL);
						write_sram_byte(byte_addr + 0, raw_hex[7:0]);
						write_sram_byte(byte_addr + 1, raw_hex[15:8]);
						pixel_index = pixel_index + 1;
					end
				end else begin
					img_r = $fscanf(img_fh, "%h\n", rgb_hex);
					if (img_r == 1) begin
						red_byte   = rgb_hex[23:16];
						green_byte = rgb_hex[15:8];
						blue_byte  = rgb_hex[7:0];
						byte_addr  = INIT_BASE_ADDR + (pixel_index * BYTES_PER_PIXEL);
						write_sram_byte(byte_addr + 0, red_byte);
						write_sram_byte(byte_addr + 1, green_byte);
						write_sram_byte(byte_addr + 2, blue_byte);
						pixel_index = pixel_index + 1;
					end
				end
			end
			$fclose(img_fh);
			$display("Loaded %0d pixels into SRAM from %s", pixel_index, img_file);
		end
	end
`endif
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
			testbench.u0_apb_host_driver.write_apb(REG_FRAME_WIDTH, IMG_WIDTH);
			testbench.u0_apb_host_driver.write_apb(REG_FRAME_HEIGHT, IMG_HEIGHT);
			testbench.u0_apb_host_driver.write_apb(REG_BASE_FRAME_IN, INIT_BASE_ADDR);
			testbench.u0_apb_host_driver.write_apb(REG_BASE_FRAME_OUT, OUT_BASE_ADDR);
			testbench.u0_apb_host_driver.write_apb(REG_INT_ENABLE, 32'h1); // enable interrupt
			/////////////
			testbench.u0_apb_host_driver.write_apb(REG_SYS_CTRL, INIT_MODE_RAW ? 32'h03 : 32'h01); // start + pixel_size
			$display("frame start!");
		end
		/////////////
		wait (int_out == 1);
		dump_output_to_file();
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
