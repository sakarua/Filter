//
// Median filter top: APB registers, SRAM access, unpack, grayscale,
// 3x3 window generation, median filtering and SRAM write-back.
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

localparam FORMAT_RGB888_BYTES = 2'd3;
localparam FORMAT_RAW16_BYTES  = 2'd2;

localparam ST_IDLE       = 4'd0;
localparam ST_READ0_ADDR = 4'd1;
localparam ST_READ0_WAIT = 4'd2;
localparam ST_CAP0       = 4'd3;
localparam ST_READ1_ADDR = 4'd4;
localparam ST_READ1_WAIT = 4'd5;
localparam ST_CAP1       = 4'd6;
localparam ST_UNPACK     = 4'd7;
localparam ST_WRITE      = 4'd8;
localparam ST_DRAIN      = 4'd9;
localparam ST_WRITE2     = 4'd10;

wire        frame_start_pclk;
reg         frame_start_meta;
reg         frame_start_sync;
reg         frame_start_sync_d;
wire        frame_start;
wire        pixel_size;
wire [31:0] baseImageI;
wire [31:0] baseImageO;
wire [15:0] frame_width;
wire [15:0] frame_height;
reg         frame_done;
reg  [31:0] frame_number;
reg  [31:0] frame_cycle_cur;
reg  [31:0] frame_cycle_sum;

filter_apb_if u_filter_apb_if (
	.pclk            (pclk),
	.prstn           (prstn),
	.paddr           (paddr),
	.pwdata          (pwdata),
	.penable         (penable),
	.pwrite          (pwrite),
	.psel            (psel),
	.prdata          (prdata),
	.frame_start     (frame_start_pclk),
	.frame_done      (frame_done),
	.frame_number    (frame_number),
	.frame_cycle_cur (frame_cycle_cur),
	.frame_cycle_sum (frame_cycle_sum),
	.baseImageI      (baseImageI),
	.baseImageO      (baseImageO),
	.frame_width     (frame_width),
	.frame_height    (frame_height),
	.pixel_size      (pixel_size),//输入信号格式选择：0=RGB888, 1=RAW16
	.int_out         (int_out)
);

always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		frame_start_meta   <= 1'b0;
		frame_start_sync   <= 1'b0;
		frame_start_sync_d <= 1'b0;
	end else begin
		frame_start_meta   <= frame_start_pclk;
		frame_start_sync   <= frame_start_meta;
		frame_start_sync_d <= frame_start_sync;
	end
end
assign frame_start = frame_start_sync & ~frame_start_sync_d;//检测上升沿

reg  [3:0]  state;
reg  [31:0] input_byte_addr;
reg  [31:0] pixel_count;
reg  [31:0] total_pixels;
reg  [ 4:0] drain_count;
wire [1:0]  bytes_per_pixel = pixel_size ? FORMAT_RAW16_BYTES : FORMAT_RGB888_BYTES;
wire [23:0] read_byte_addr  = input_byte_addr[23:0];
wire [20:0] read_word_addr  = read_byte_addr[23:3]; //用于访问SRAM的地址，单位是64-bit word
wire [7:0] unpack_red;
wire [7:0] unpack_green;
wire [7:0] unpack_blue;
wire [15:0] unpack_raw_gray;
wire       unpack_valid = (state == ST_UNPACK);

pixel_unpacker u_pixel_unpacker (
	.clk           (clk),
	.rst_n         (rstn),
	.capture_word0 (state == ST_CAP0),
	.capture_word1 (state == ST_CAP1),
	.format_raw16 (pixel_size),
	.mem_di       (mem_di),
	.byte_offset  (read_byte_addr[2:0]), //word内的字节偏移
	.red          (unpack_red),
	.green        (unpack_green),
	.blue         (unpack_blue),
	.raw_gray     (unpack_raw_gray)
);

wire [7:0] rgb_y;
wire [7:0] rgb_cb;
wire [7:0] rgb_cr;

RGB2YCbCr u_rgb2ycbcr (
	.clk   (clk),
	.rst_n (rstn),
	.red   (unpack_red),
	.green (unpack_green),
	.blue  (unpack_blue),
	.y     (rgb_y),
	.cb    (rgb_cb),
	.cr    (rgb_cr)
);

reg [2:0] rgb_valid_pipe;

always @(posedge clk or negedge rstn) begin
	if (!rstn)
		rgb_valid_pipe <= 3'b0;
	else
		rgb_valid_pipe <= {rgb_valid_pipe[1:0], unpack_valid & ~pixel_size};
end

wire        gray_valid = pixel_size ? unpack_valid : rgb_valid_pipe[2];
wire [15:0] gray_data  = pixel_size ? unpack_raw_gray : {8'd0, rgb_y};

wire        window_valid;
wire [31:0] window_center_index;
wire [15:0] data11;
wire [15:0] data12;
wire [15:0] data13;
wire [15:0] data21;
wire [15:0] data22;
wire [15:0] data23;
wire [15:0] data31;
wire [15:0] data32;
wire [15:0] data33;

pixel_matrix_3x3 #(.DATA_WIDTH(16)) u_pixel_matrix_3x3 (
	.clk          (clk),
	.rst_n        (rstn),
	.frame_start  (frame_start),
	.pixel_valid  (gray_valid),
	.pixel_data   (gray_data),
	.frame_width  (frame_width),
	.window_valid (window_valid),
	.center_index (window_center_index),
	.data11       (data11),
	.data12       (data12),
	.data13       (data13),
	.data21       (data21),
	.data22       (data22),
	.data23       (data23),
	.data31       (data31),
	.data32       (data32),
	.data33       (data33)
);

wire [15:0] filter_data;

median_filter_3x3 #(.DATA_WIDTH(16)) u_median_filter_3x3 (
	.clk         (clk),
	.rst_n       (rstn),
	.data11      (data11),
	.data12      (data12),
	.data13      (data13),
	.data21      (data21),
	.data22      (data22),
	.data23      (data23),
	.data31      (data31),
	.data32      (data32),
	.data33      (data33),
	.target_data (filter_data)
);

reg  [2:0]  filter_valid_pipe;
reg  [31:0] center_index_d0;
reg  [31:0] center_index_d1;
reg  [31:0] center_index_d2;
reg         write_pending;
reg  [31:0] write_byte_addr;
reg  [15:0] write_data;

always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		filter_valid_pipe <= 3'b0;
		center_index_d0   <= 32'd0;
		center_index_d1   <= 32'd0;
		center_index_d2   <= 32'd0;
		write_pending     <= 1'b0;
		write_byte_addr   <= 32'd0;
		write_data        <= 16'd0;
	end else begin
		filter_valid_pipe <= {filter_valid_pipe[1:0], window_valid};
		center_index_d0   <= window_center_index;
		center_index_d1   <= center_index_d0;
		center_index_d2   <= center_index_d1;

		if (filter_valid_pipe[2]) begin
			write_pending   <= 1'b1;
			write_byte_addr <= baseImageO + (pixel_size ? {center_index_d2[30:0], 1'b0} : center_index_d2);
			write_data      <= filter_data;
		end else if (state == ST_WRITE) begin
			write_pending <= 1'b0;
		end
	end
end

wire [2:0] write_lane = write_byte_addr[2:0];
wire       write_cross_word = pixel_size & (write_lane == 3'd7);
wire [7:0] write_mask = (state == ST_WRITE2) ? 8'hfe :
						write_cross_word ? ~(8'b0000_0001 << write_lane) :
						pixel_size ? ~((8'b0000_0001 << write_lane) | (8'b0000_0010 << write_lane)) :
						~(8'b0000_0001 << write_lane);
wire [63:0] write_word = (state == ST_WRITE2) ? {56'd0, write_data[15:8]} :
						 write_cross_word ? ({56'd0, write_data[7:0]} << {write_lane, 3'b000}) :
						 pixel_size ? ({48'd0, write_data} << {write_lane, 3'b000}) :
						 ({56'd0, write_data[7:0]} << {write_lane, 3'b000});

assign mem_csn = ~((state == ST_READ0_ADDR) || (state == ST_READ1_ADDR) || (state == ST_WRITE) || (state == ST_WRITE2));
assign mem_wen = ((state == ST_WRITE) || (state == ST_WRITE2)) ? write_mask : 8'hff;
assign mem_adr = (state == ST_WRITE) ? write_byte_addr[23:3] :
				 (state == ST_WRITE2) ? (write_byte_addr[23:3] + 21'd1) :
				 (state == ST_READ1_ADDR) ? (read_word_addr + 21'd1) : read_word_addr;
assign mem_do  = ((state == ST_WRITE) || (state == ST_WRITE2)) ? write_word : 64'd0;

always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		state           <= ST_IDLE;
		input_byte_addr <= 32'd0;
		pixel_count     <= 32'd0;
		total_pixels    <= 32'd0;
		drain_count     <= 5'd0;
		frame_done      <= 1'b0;
		frame_number    <= 32'd0;
		frame_cycle_cur <= 32'd0;
		frame_cycle_sum <= 32'd0;
	end else begin
		frame_done <= 1'b0;

		if (state != ST_IDLE)
			frame_cycle_cur <= frame_cycle_cur + 32'd1;

		case (state)
			ST_IDLE: begin
				if (frame_start) begin
					state           <= ST_READ0_ADDR;
					input_byte_addr <= baseImageI;
					pixel_count     <= 32'd0;
					total_pixels    <= frame_width * frame_height;
					frame_cycle_cur <= 32'd0;
					drain_count     <= 5'd20;
				end
			end

			ST_READ0_ADDR: state <= ST_READ0_WAIT;
			ST_READ0_WAIT: state <= ST_CAP0;

			ST_CAP0: state <= ST_READ1_ADDR;

			ST_READ1_ADDR: state <= ST_READ1_WAIT;
			ST_READ1_WAIT: state <= ST_CAP1;

			ST_CAP1: state <= ST_UNPACK;

			ST_UNPACK: begin
				pixel_count     <= pixel_count + 32'd1;
				input_byte_addr <= input_byte_addr + bytes_per_pixel;

				if (pixel_count + 32'd1 >= total_pixels)
					state <= ST_DRAIN;
				else if (write_pending)
					state <= ST_WRITE;
				else
					state <= ST_READ0_ADDR;
			end

			ST_WRITE: begin
				if (write_cross_word)
					state <= ST_WRITE2;
				else if (pixel_count >= total_pixels)
					state <= ST_DRAIN;
				else
					state <= ST_READ0_ADDR;
			end

			ST_WRITE2: begin
				if (pixel_count >= total_pixels)
					state <= ST_DRAIN;
				else
					state <= ST_READ0_ADDR;
			end

			ST_DRAIN: begin
				if (write_pending) begin
					state <= ST_WRITE;
				end else if (drain_count != 5'd0) begin
					drain_count <= drain_count - 5'd1;
				end else begin
					frame_done      <= 1'b1;
					frame_number    <= frame_number + 32'd1;
					frame_cycle_sum <= frame_cycle_sum + frame_cycle_cur;
					state           <= ST_IDLE;
				end
			end

			default: state <= ST_IDLE;
		endcase
	end
end

endmodule
