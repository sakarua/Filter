`timescale 1ns/10ps

module algorithm_cycle_tb;
	localparam CLK_HALF_PERIOD = 2;
	localparam int IMG_WIDTH   = 480;
	localparam int IMG_HEIGHT  = 640;
	localparam int IMG_PIXELS  = IMG_WIDTH * IMG_HEIGHT;
	localparam int FILTER_LATENCY = 3; // median_filter_3x3 流水深度：median_d0/d1/d2 共 3 级

	reg clk;
	reg rst_n;
	reg frame_start_r;

	reg        rgb_valid;
	reg [7:0]  red;
	reg [7:0]  green;
	reg [7:0]  blue;
	reg [15:0] feed_row;
	reg [15:0] feed_col;
	reg        feed_bottom;
	reg        feed_done;

	wire [7:0] y;
	wire [7:0] cb;
	wire [7:0] cr;

	RGB2YCbCr u_rgb2ycbcr (
		.clk   (clk),
		.rst_n (rst_n),
		.red   (red),
		.green (green),
		.blue  (blue),
		.y     (y),
		.cb    (cb),
		.cr    (cr)
	);

	reg [2:0] rgb_valid_pipe;
	wire      gray_valid = rgb_valid_pipe[2];
	wire [15:0] gray_data = {8'd0, y};

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n)
			rgb_valid_pipe <= 3'b0;
		else
			rgb_valid_pipe <= {rgb_valid_pipe[1:0], rgb_valid};
	end

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
	wire [15:0] frame_width = IMG_WIDTH[15:0];
	wire [15:0] frame_height = IMG_HEIGHT[15:0];
	wire [15:0] stream_width = frame_width + 16'd1;

	pixel_matrix_3x3 #(
		.DATA_WIDTH(16)
	) u_pixel_matrix_3x3 (
		.clk          (clk),
		.rst_n        (rst_n),
		.frame_start  (frame_start_r),
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

	wire [8:0] window_mask = {
		~(center_bottom | center_right),
		~center_bottom,
		~(center_bottom | center_left),
		~center_right,
		1'b1,
		~center_left,
		~(center_top | center_right),
		~center_top,
		~(center_top | center_left)
	};

	median_filter_3x3 #(
		.DATA_WIDTH(16)
	) u_median_filter_3x3 (
		.clk         (clk),
		.rst_n       (rst_n),
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

	reg [FILTER_LATENCY-1:0] filter_valid_pipe;
	reg [31:0] center_index_pipe [0:FILTER_LATENCY-1];
	wire       filter_valid = filter_valid_pipe[FILTER_LATENCY-1];
	wire [31:0] center_index_aligned = center_index_pipe[FILTER_LATENCY-1];
	wire       filter_in_frame = filter_valid && (center_index_aligned < IMG_PIXELS);
	wire       last_filter_pixel = filter_in_frame && ((center_index_aligned + 32'd1) == IMG_PIXELS);
	integer   pipe_idx;

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			filter_valid_pipe <= {FILTER_LATENCY{1'b0}};
			for (pipe_idx = 0; pipe_idx < FILTER_LATENCY; pipe_idx = pipe_idx + 1)
				center_index_pipe[pipe_idx] <= 32'd0;
		end else begin
			filter_valid_pipe <= {filter_valid_pipe[FILTER_LATENCY-2:0], window_valid};
			center_index_pipe[0] <= window_center_index;
			for (pipe_idx = 1; pipe_idx < FILTER_LATENCY; pipe_idx = pipe_idx + 1)
				center_index_pipe[pipe_idx] <= center_index_pipe[pipe_idx - 1];
		end
	end

	integer input_valid_cycles;
	integer gray_valid_cycles;
	integer window_valid_cycles;
	integer filter_valid_cycles;
	integer ideal_wall_cycles;
	reg     ideal_counting;

	initial begin
		clk = 1'b0;
		forever #(CLK_HALF_PERIOD) clk = ~clk;
	end

	initial begin
		rst_n       = 1'b0;
		frame_start_r = 1'b0;
		#1us;
		rst_n       = 1'b1;
		@(posedge clk); // 等一拍后拉起 frame_start，在首个 gray_valid 到来前到达 pixel_matrix
		frame_start_r = 1'b1;
		@(posedge clk);
		frame_start_r = 1'b0;
	end

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			rgb_valid <= 1'b0;
			red <= 8'd0;
			green <= 8'd0;
			blue <= 8'd0;
			feed_row <= 16'd0;
			feed_col <= 16'd0;
			feed_bottom <= 1'b0;
			feed_done <= 1'b0;
		end else if (!feed_done) begin
			rgb_valid <= 1'b1;
			if (feed_bottom || (feed_col == frame_width)) begin
				red <= 8'd0;
				green <= 8'd0;
				blue <= 8'd0;
			end else begin
				red <= feed_col[7:0];
				green <= feed_row[7:0];
				blue <= feed_col[7:0] ^ feed_row[7:0];
			end

			if (feed_col == frame_width) begin
				feed_col <= 16'd0;
				if (feed_bottom) begin
					feed_done <= 1'b1;
				end else if (feed_row == (frame_height - 16'd1)) begin
					feed_bottom <= 1'b1;
				end else begin
					feed_row <= feed_row + 16'd1;
				end
			end else begin
				feed_col <= feed_col + 16'd1;
			end
		end else begin
			rgb_valid <= 1'b0;
			red <= 8'd0;
			green <= 8'd0;
			blue <= 8'd0;
		end
	end

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			input_valid_cycles  <= 0;
			gray_valid_cycles   <= 0;
			window_valid_cycles <= 0;
			filter_valid_cycles <= 0;
			ideal_wall_cycles   <= 0;
			ideal_counting      <= 1'b0;
		end else begin
			if (rgb_valid)
				input_valid_cycles <= input_valid_cycles + 1;
			if (gray_valid)
				gray_valid_cycles <= gray_valid_cycles + 1;
			if (window_valid)
				window_valid_cycles <= window_valid_cycles + 1;
			if (filter_in_frame)
				filter_valid_cycles <= filter_valid_cycles + 1;

			if (!ideal_counting && gray_valid)
				ideal_counting <= 1'b1;
			if (ideal_counting)
				ideal_wall_cycles <= ideal_wall_cycles + 1;

			if (last_filter_pixel) begin
				$display("Ideal algorithm cycles: wall=%0d, input_valid=%0d, gray_valid=%0d, window_valid=%0d, filter_valid=%0d",
						 ideal_wall_cycles + 1,
						 input_valid_cycles,
						 gray_valid_cycles + (gray_valid ? 1 : 0),
						 window_valid_cycles + (window_valid ? 1 : 0),
						 filter_valid_cycles + 1);
				$stop;
			end
		end
	end

	initial begin
		#5ms;
		$display("ERROR: algorithm_cycle_tb timeout");
		$stop;
	end

endmodule
