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
wire        frame_done;
wire        frame_done_pclk;
wire [31:0] frame_number;
wire [31:0] frame_cycle_cur;
wire [31:0] frame_cycle_sum;
reg         frame_done_toggle;
reg         frame_done_meta;
reg         frame_done_sync;
reg         frame_done_sync_d;

always @(posedge clk or negedge rstn) begin
	if (!rstn)
		frame_done_toggle <= 1'b0;
	else if (frame_done)
		frame_done_toggle <= ~frame_done_toggle;
end

always @(posedge pclk or negedge prstn) begin
	if (!prstn) begin
		frame_done_meta   <= 1'b0;
		frame_done_sync   <= 1'b0;
		frame_done_sync_d <= 1'b0;
	end else begin
		frame_done_meta   <= frame_done_toggle;
		frame_done_sync   <= frame_done_meta;
		frame_done_sync_d <= frame_done_sync;
	end
end

assign frame_done_pclk = frame_done_sync ^ frame_done_sync_d;

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
	.frame_done      (frame_done_pclk),
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

wire [7:0]  red;
wire [7:0]  green;
wire [7:0]  blue;
wire [15:0] raw_gray;
wire        read_valid;
wire [31:0] read_pixel_index;

wire        read_req;
wire [20:0] read_addr;
wire        read_active;
wire        write_pending;
wire        write_active;
wire [20:0] write_addr;
wire [7:0]  write_mask;
wire [63:0] write_word;

sram_reader u_sram_reader (
	.clk            (clk),
	.rstn           (rstn),
	.pixel_size     (pixel_size),
	.baseImageI     (baseImageI),
	.frame_start    (frame_start),
	.frame_width    (frame_width),
	.frame_height   (frame_height),
	.mem_di         (mem_di),
	.write_pending  (write_pending),
	.write_active   (write_active),
	.read_req       (read_req),
	.read_addr      (read_addr),
	.read_active    (read_active),
	.read_valid   	(read_valid),
	.read_pixel_index(read_pixel_index),
	.red     		(red),
	.green   		(green),
	.blue   		(blue),
	.raw_gray		(raw_gray),
	.frame_done     (frame_done),
	.frame_number   (frame_number),
	.frame_cycle_cur(frame_cycle_cur),
	.frame_cycle_sum(frame_cycle_sum)
);

wire [7:0] y;
wire [7:0] cb;
wire [7:0] cr;

RGB2YCbCr u_rgb2ycbcr (
	.clk   (clk),
	.rst_n (rstn),
	.red   (red),
	.green (green),
	.blue  (blue),
	.y     (y),
	.cb    (cb),
	.cr    (cr)
);

reg [2:0] rgb_valid_pipe;
reg [31:0] rgb_index_pipe0;
reg [31:0] rgb_index_pipe1;
reg [31:0] rgb_index_pipe2;

always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		rgb_valid_pipe <= 3'b0;
		rgb_index_pipe0 <= 32'd0;
		rgb_index_pipe1 <= 32'd0;
		rgb_index_pipe2 <= 32'd0;
	end else begin
		rgb_valid_pipe <= {rgb_valid_pipe[1:0], read_valid & ~pixel_size};
		rgb_index_pipe0 <= read_pixel_index;
		rgb_index_pipe1 <= rgb_index_pipe0;
		rgb_index_pipe2 <= rgb_index_pipe1;
	end
end

wire        gray_valid = pixel_size ? read_valid : rgb_valid_pipe[2];
wire [15:0] gray_data  = pixel_size ? raw_gray : {8'd0, y};
wire [31:0] gray_index = pixel_size ? read_pixel_index : rgb_index_pipe2;

wire        window_valid;
wire [31:0] window_center_index;
wire [15:0] window_center_row;
wire [15:0] window_center_col;
wire [15:0] data11;
wire [15:0] data12;
wire [15:0] data13;
wire [15:0] data21;
wire [15:0] data22;
wire [15:0] data23;
wire [15:0] data31;
wire [15:0] data32;
wire [15:0] data33;

wire [15:0] stream_width = frame_width + 16'd1;

pixel_matrix_3x3 #(
	.DATA_WIDTH(16)
) u_pixel_matrix_3x3 (
	.clk          (clk),
	.rst_n        (rstn),
	.frame_start  (frame_start),
	.pixel_valid  (gray_valid),
	.pixel_data   (gray_data),
	.frame_width  (frame_width),
	.stream_width (stream_width),
	.window_valid (window_valid),
	.center_index (window_center_index),
	.center_row   (window_center_row),
	.center_col   (window_center_col),
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
wire        center_top    = (window_center_row == 16'd0);
wire        center_bottom = (window_center_row == (frame_height - 16'd1));
wire        center_left   = (window_center_col == 16'd0);
wire        center_right  = (window_center_col == (frame_width - 16'd1));

wire mask_0 = ~(center_top | center_left);
wire mask_1 = ~(center_top);
wire mask_2 = ~(center_top | center_right);
wire mask_3 = ~(center_left);
wire mask_4 = 1'b1;
wire mask_5 = ~(center_right);
wire mask_6 = ~(center_bottom | center_left);
wire mask_7 = ~(center_bottom);
wire mask_8 = ~(center_bottom | center_right);

wire [8:0] window_mask = {
	mask_8, mask_7, mask_6, mask_5, mask_4, mask_3, mask_2, mask_1, mask_0
};

median_filter_3x3 #(
	.DATA_WIDTH(16)
) u_median_filter_3x3 (
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
	.mask        (window_mask),
	.target_data (filter_data)
);

sram_writer u_sram_writer (
	.clk               (clk),
	.rstn              (rstn),
	.pixel_size        (pixel_size),
	.baseImageO        (baseImageO),
	.frame_width       (frame_width),
	.frame_height      (frame_height),
	.gray_valid        (gray_valid),
	.gray_index        (gray_index),
	.gray_data         (gray_data),
	.window_valid      (window_valid),
	.window_center_index(window_center_index),
	.filter_data       (filter_data),
	.read_active       (read_active),
	.write_pending     (write_pending),
	.write_active      (write_active),
	.write_addr        (write_addr),
	.write_mask        (write_mask),
	.write_word        (write_word)
);

(* IOB = "TRUE" *) reg        mem_csn_r;
(* IOB = "TRUE" *) reg [ 7:0] mem_wen_r;
(* IOB = "TRUE" *) reg [20:0] mem_adr_r;
(* IOB = "TRUE" *) reg [63:0] mem_do_r;

always @(posedge clk) begin
	if (!rstn) begin
		mem_csn_r <= 1'b1;
		mem_wen_r <= 8'hff;
		mem_adr_r <= 21'd0;
		mem_do_r  <= 64'd0;
	end else if (write_active) begin
		mem_csn_r <= 1'b0;
		mem_wen_r <= write_mask;
		mem_adr_r <= write_addr;
		mem_do_r  <= write_word;
	end else if (read_req) begin
		mem_csn_r <= 1'b0;
		mem_wen_r <= 8'hff;
		mem_adr_r <= read_addr;
		mem_do_r  <= 64'd0;
	end else begin
		mem_csn_r <= 1'b1;
		mem_wen_r <= 8'hff;
		mem_do_r  <= 64'd0;
	end
end

assign mem_csn = mem_csn_r;
assign mem_wen = mem_wen_r;
assign mem_adr = mem_adr_r;
assign mem_do  = mem_do_r;

endmodule
