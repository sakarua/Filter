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
	localparam bit INIT_MODE_RAW = 1'b0; // 0 = RGB888, 1 = RAW16
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
	wire        int_out;
	wire        mem_csn;
	wire [ 7:0] mem_wen; // byte select
	wire [20:0] mem_adr;
	wire [63:0] mem_do;
	wire [63:0] mem_di;
	integer     sram_write_cycles;
	integer     sram_write_bytes;
	integer     sram_lane_idx;
	integer     active_write_bytes;

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

	always @(posedge pixel_clk or negedge pixel_rstn) begin
		if (!pixel_rstn) begin
			sram_write_cycles <= 0;
			sram_write_bytes  <= 0;
		end else if (!mem_csn && (mem_wen != 8'hff)) begin
			active_write_bytes = 0;
			for (sram_lane_idx = 0; sram_lane_idx < 8; sram_lane_idx = sram_lane_idx + 1) begin
				if (!mem_wen[sram_lane_idx])
					active_write_bytes = active_write_bytes + 1;
			end
			sram_write_cycles <= sram_write_cycles + 1;
			sram_write_bytes  <= sram_write_bytes + active_write_bytes;
		end
	end

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
	localparam int IMG_PIXELS = IMG_WIDTH * IMG_HEIGHT;
	localparam int BYTES_PER_PIXEL = INIT_MODE_RAW ? 2 : 3;

	string  img_file_rgb;
	string  img_file_raw;
	string  img_file;
	integer img_fh;
	integer img_r;
	integer raw_b0;
	integer raw_b1;
	integer bmp_sig0;
	integer bmp_sig1;
	integer bmp_file_size;
	integer bmp_data_offset;
	integer bmp_info_size;
	integer bmp_width;
	integer bmp_height_signed;
	integer bmp_height;
	integer bmp_planes;
	integer bmp_bpp;
	integer bmp_compression;
	integer bmp_row_size;
	integer bmp_row;
	integer bmp_col;
	integer bmp_file_row;
	integer bmp_row_offset;
	integer load_width;
	integer load_height;
	integer pixel_count;
	integer top_down;
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

	task automatic read_u16_le(input integer fh, output integer value);
		integer b0;
		integer b1;
		begin
			b0 = $fgetc(fh);
			b1 = $fgetc(fh);
			if ((b0 < 0) || (b1 < 0))
				value = -1;
			else
				value = (b0 & 8'hff) | ((b1 & 8'hff) << 8);
		end
	endtask

	task automatic read_u32_le(input integer fh, output integer value);
		integer b0;
		integer b1;
		integer b2;
		integer b3;
		begin
			b0 = $fgetc(fh);
			b1 = $fgetc(fh);
			b2 = $fgetc(fh);
			b3 = $fgetc(fh);
			if ((b0 < 0) || (b1 < 0) || (b2 < 0) || (b3 < 0))
				value = -1;
			else
				value = (b0 & 8'hff) | ((b1 & 8'hff) << 8) | ((b2 & 8'hff) << 16) | ((b3 & 8'hff) << 24);
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
		img_file_rgb = "matlab/test_img.bmp";
		img_file_raw = "matlab/test_img.raw";
		img_file = INIT_MODE_RAW ? img_file_raw : img_file_rgb;
		if ($value$plusargs("IMG_FILE=%s", img_file)) begin
		end
		out_file = "rtl/output";
		if ($value$plusargs("OUT_FILE=%s", out_file)) begin
		end

		$display("[%0t] SRAM init start: file=%s, mode=%s, size=%0dx%0d, base=0x%08h",
				 $time, img_file, INIT_MODE_RAW ? "RAW16" : "RGB888", IMG_WIDTH, IMG_HEIGHT, INIT_BASE_ADDR);
		if (INIT_MODE_RAW)
			img_fh = $fopen(img_file, "rb");
		else
			img_fh = $fopen(img_file, "rb");
		if (img_fh == 0) begin
			$display("ERROR: could not open image file %s", img_file);
		end else begin
			pixel_index = 0;
			if (INIT_MODE_RAW) begin
				while (!$feof(img_fh) && (pixel_index < IMG_PIXELS)) begin
					raw_b0 = $fgetc(img_fh);
					raw_b1 = $fgetc(img_fh);
					if ((raw_b0 != -1) && (raw_b1 != -1)) begin
						raw_hex = {raw_b1[7:0], raw_b0[7:0]};
						byte_addr  = INIT_BASE_ADDR + (pixel_index * BYTES_PER_PIXEL);
						write_sram_byte(byte_addr + 0, raw_hex[7:0]);
						write_sram_byte(byte_addr + 1, raw_hex[15:8]);
						pixel_index = pixel_index + 1;
					end else begin
						pixel_index = IMG_PIXELS;
					end
				end
			end else begin
				bmp_sig0 = $fgetc(img_fh);
				bmp_sig1 = $fgetc(img_fh);
				read_u32_le(img_fh, bmp_file_size);
				read_u16_le(img_fh, img_r);
				read_u16_le(img_fh, img_r);
				read_u32_le(img_fh, bmp_data_offset);
				read_u32_le(img_fh, bmp_info_size);
				read_u32_le(img_fh, bmp_width);
				read_u32_le(img_fh, bmp_height_signed);
				read_u16_le(img_fh, bmp_planes);
				read_u16_le(img_fh, bmp_bpp);
				read_u32_le(img_fh, bmp_compression);
				if ((bmp_sig0 != "B") || (bmp_sig1 != "M")) begin
					$display("ERROR: invalid BMP signature in %s", img_file);
				end else if ((bmp_bpp != 24) || (bmp_compression != 0)) begin
					$display("ERROR: unsupported BMP format: bpp=%0d, compression=%0d", bmp_bpp, bmp_compression);
				end else begin
					top_down = 0;
					if (bmp_height_signed < 0) begin
						top_down = 1;
						bmp_height = -bmp_height_signed;
					end else begin
						bmp_height = bmp_height_signed;
					end
					bmp_row_size = ((bmp_width * 3) + 3) & ~3;
					load_width  = (bmp_width  < IMG_WIDTH)  ? bmp_width  : IMG_WIDTH;
					load_height = (bmp_height < IMG_HEIGHT) ? bmp_height : IMG_HEIGHT;
					if ((bmp_width != IMG_WIDTH) || (bmp_height != IMG_HEIGHT)) begin
						$display("WARNING: BMP size %0dx%0d differs from IMG %0dx%0d, loading %0dx%0d",
								 bmp_width, bmp_height, IMG_WIDTH, IMG_HEIGHT, load_width, load_height);
					end
					for (bmp_row = 0; bmp_row < load_height; bmp_row = bmp_row + 1) begin
						bmp_file_row = top_down ? bmp_row : (bmp_height - 1 - bmp_row);
						bmp_row_offset = bmp_data_offset + (bmp_file_row * bmp_row_size);
						img_r = $fseek(img_fh, bmp_row_offset, 0);
						for (bmp_col = 0; bmp_col < load_width; bmp_col = bmp_col + 1) begin
							blue_byte  = $fgetc(img_fh);
							green_byte = $fgetc(img_fh);
							red_byte   = $fgetc(img_fh);
							if ((blue_byte < 0) || (green_byte < 0) || (red_byte < 0)) begin
								bmp_col = load_width;
								bmp_row = load_height;
							end else begin
								pixel_index = (bmp_row * IMG_WIDTH) + bmp_col;
								byte_addr  = INIT_BASE_ADDR + (pixel_index * BYTES_PER_PIXEL);
								write_sram_byte(byte_addr + 0, red_byte);
								write_sram_byte(byte_addr + 1, green_byte);
								write_sram_byte(byte_addr + 2, blue_byte);
							end
						end
					end
					pixel_index = load_width * load_height;
				end
			end
			$fclose(img_fh);
			if (pixel_index == IMG_PIXELS)
				$display("[%0t] SRAM init success: loaded %0d pixels (%0d bytes) from %s",
						 $time, pixel_index, pixel_index * BYTES_PER_PIXEL, img_file);
			else
				$display("[%0t] WARNING: SRAM init loaded only %0d/%0d pixels from %s",
						 $time, pixel_index, IMG_PIXELS, img_file);
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
			$display("[%0t] APB config start", $time);
			testbench.u0_apb_host_driver.write_apb(REG_FRAME_WIDTH, IMG_WIDTH);
			testbench.u0_apb_host_driver.write_apb(REG_FRAME_HEIGHT, IMG_HEIGHT);
			testbench.u0_apb_host_driver.write_apb(REG_BASE_FRAME_IN, INIT_BASE_ADDR);
			testbench.u0_apb_host_driver.write_apb(REG_BASE_FRAME_OUT, OUT_BASE_ADDR);
			testbench.u0_apb_host_driver.write_apb(REG_INT_ENABLE, 32'h1); // enable interrupt
			/////////////
			testbench.u0_apb_host_driver.write_apb(REG_SYS_CTRL, INIT_MODE_RAW ? 32'h03 : 32'h01); // start + pixel_size
			$display("[%0t] Frame start issued", $time);
		end
		/////////////
		wait (int_out == 1);
		$display("[%0t] SRAM writeback done: write_cycles=%0d, write_bytes=%0d",
				 $time, sram_write_cycles, sram_write_bytes);
		dump_output_to_file;
		#5ms;
		$finish;
	end

	initial begin
		#20ms;
		$display("[%0t] ERROR: simulation timeout", $time);
		$finish;
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
