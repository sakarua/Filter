// SRAM reader: sequential read and pixel unpacking.
module sram_reader (
	input             clk,
	input             rstn,
	input             pixel_size, // 0 = RGB888, 1 = RAW16
	input      [31:0] baseImageI,
	input             frame_start,
	input      [15:0] frame_width,
	input      [15:0] frame_height,
	input      [63:0] mem_di,
	input             write_pending,
	input             write_active,

	output            read_req,
	output     [20:0] read_addr,
	output            read_active,
	output            read_valid,
	output     [31:0] read_pixel_index,
	output     [ 7:0] red,
	output     [ 7:0] green,
	output     [ 7:0] blue,
	output     [15:0] raw_gray,

	output reg        frame_done,
	output reg [31:0] frame_number,
	output reg [31:0] frame_cycle_cur,
	output reg [31:0] frame_cycle_sum
);

localparam FORMAT_RGB888_BYTES = 2'd3;
localparam FORMAT_RAW16_BYTES  = 2'd2;

localparam RD_IDLE       = 3'd0;
localparam RD_READ       = 3'd1;
localparam RD_WAIT       = 3'd2;
localparam RD_DONE       = 3'd3;
localparam RD_HOLD       = 3'd4;
localparam RD_DRAIN      = 3'd5;
localparam RD_PAD_RIGHT  = 3'd6;
localparam RD_PAD_BOTTOM = 3'd7;

reg [23:0] rgb_buf;
reg [15:0] raw_buf;
reg [63:0] read_word_cache;
reg [20:0] read_word_cache_addr;
reg        read_word_cache_valid;

reg  [2:0]  read_state;
reg         read_pending;
reg  [31:0] total_pixels;
reg  [31:0] input_byte_addr;
reg  [31:0] pixel_count;
reg  [ 4:0] drain_count;
reg  [15:0] cur_row;
reg  [15:0] cur_col;
reg         pad_bottom_active;
reg  [15:0] pad_bottom_col;
reg  [2:0]  hold_state;

wire [1:0]  bytes_per_pixel = pixel_size ? FORMAT_RAW16_BYTES : FORMAT_RGB888_BYTES;
wire [23:0] read_byte_addr  = input_byte_addr[23:0];
wire [20:0] read_word_addr  = read_byte_addr[23:3];
wire [20:0] read_target_addr = read_word_addr + (read_pending ? 21'd1 : 21'd0);
wire [2:0]  unpk_byte_offset = read_byte_addr[2:0];
wire        read_word_cache_hit = read_word_cache_valid && (read_word_cache_addr == read_target_addr);
wire [63:0] read_word_data = read_word_cache_hit ? read_word_cache : mem_di;
wire [63:0] mem_di_shift = read_pending ? read_word_data : (read_word_data >> {unpk_byte_offset, 3'b000});

wire crossword = pixel_size ? (unpk_byte_offset > 3'd6) : (unpk_byte_offset > 3'd5);
wire pixel_complete = (read_state == RD_DONE) && (read_pending ? 1'b1 : ~crossword);
wire pad_valid = (read_state == RD_PAD_RIGHT) || (read_state == RD_PAD_BOTTOM);
wire last_col = (frame_width != 16'd0) && (cur_col == (frame_width - 16'd1));
wire last_row = (frame_height != 16'd0) && (cur_row == (frame_height - 16'd1));

assign read_req = (read_state == RD_WAIT) && !read_word_cache_hit;
assign read_active = (read_state == RD_READ) || (read_state == RD_WAIT) || (read_state == RD_DONE);
assign read_addr = read_target_addr;

assign read_valid = pixel_complete || pad_valid;
assign read_pixel_index = pixel_count;
assign red      = pixel_size ? 8'd0 : rgb_buf[7:0];
assign green    = pixel_size ? 8'd0 : rgb_buf[15:8];
assign blue     = pixel_size ? 8'd0 : rgb_buf[23:16];
assign raw_gray = pixel_size ? raw_buf : 16'd0;

always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		read_state      <= RD_IDLE;
		input_byte_addr <= 32'd0;
		pixel_count     <= 32'd0;
		total_pixels    <= 32'd0;
		drain_count     <= 5'd0;
		read_pending    <= 1'b0;
		rgb_buf         <= 24'd0;
		raw_buf         <= 16'd0;
		read_word_cache <= 64'd0;
		read_word_cache_addr <= 21'd0;
		read_word_cache_valid <= 1'b0;
		cur_row         <= 16'd0;
		cur_col         <= 16'd0;
		pad_bottom_active <= 1'b0;
		pad_bottom_col  <= 16'd0;
		hold_state     <= RD_WAIT;
		frame_done      <= 1'b0;
		frame_number    <= 32'd0;
		frame_cycle_cur <= 32'd0;
		frame_cycle_sum <= 32'd0;
	end else begin
		frame_done <= 1'b0;

		if ((read_state != RD_IDLE) || write_active)
			frame_cycle_cur <= frame_cycle_cur + 32'd1;

		case (read_state)
			RD_IDLE: begin
				if (frame_start) begin
					total_pixels    <= frame_width * frame_height;
					input_byte_addr <= baseImageI;
					pixel_count     <= 32'd0;
					drain_count     <= 5'd20;
					frame_cycle_cur <= 32'd0;
					read_pending    <= 1'b0;
					read_word_cache_valid <= 1'b0;
					cur_row         <= 16'd0;
					cur_col         <= 16'd0;
					pad_bottom_active <= 1'b0;
					pad_bottom_col  <= 16'd0;
					hold_state     <= RD_WAIT;
					read_state      <= RD_WAIT;
				end
			end

			RD_WAIT: begin
				if (!write_active) begin
					if (read_word_cache_hit) begin
						if (!read_pending) begin
							if (pixel_size) begin
								if (crossword)
									raw_buf[7:0] <= mem_di_shift[7:0];
								else
									raw_buf <= mem_di_shift[15:0];
							end else begin
								if (crossword) begin
									if (unpk_byte_offset == 3'd6)
										rgb_buf[15:0] <= mem_di_shift[15:0];
									else
										rgb_buf[7:0] <= mem_di_shift[7:0];
								end else begin
									rgb_buf <= mem_di_shift[23:0];
								end
							end
						end else begin
							if (pixel_size) begin
								raw_buf[15:8] <= mem_di_shift[7:0];
							end else begin
								if (unpk_byte_offset == 3'd6)
									rgb_buf[23:16] <= mem_di_shift[7:0];
								else
									rgb_buf[23:8] <= mem_di_shift[15:0];
							end
						end
						read_state <= RD_DONE;
					end else begin
						read_state <= RD_READ;
					end
				end
			end

			RD_READ: begin
				if (!read_word_cache_hit) begin
					read_word_cache       <= mem_di;
					read_word_cache_addr  <= read_target_addr;
					read_word_cache_valid <= 1'b1;
				end

				if (!read_pending) begin
					if (pixel_size) begin
						if (crossword)
							raw_buf[7:0] <= mem_di_shift[7:0];
						else
							raw_buf <= mem_di_shift[15:0];
					end else begin
						if (crossword) begin
							if (unpk_byte_offset == 3'd6)
								rgb_buf[15:0] <= mem_di_shift[15:0];
							else
								rgb_buf[7:0] <= mem_di_shift[7:0];
						end else begin
							rgb_buf <= mem_di_shift[23:0];
						end
					end
				end else begin
					if (pixel_size) begin
						raw_buf[15:8] <= mem_di_shift[7:0];
					end else begin
						if (unpk_byte_offset == 3'd6)
							rgb_buf[23:16] <= mem_di_shift[7:0];
						else
							rgb_buf[23:8] <= mem_di_shift[15:0];
					end
				end
				read_state <= RD_DONE;
			end

			RD_DONE: begin
				if (!read_pending && crossword) begin
					read_pending <= 1'b1;
					read_state   <= RD_WAIT;
				end else begin
					read_pending    <= 1'b0;
					pixel_count     <= pixel_count + 32'd1;
					input_byte_addr <= input_byte_addr + bytes_per_pixel;
					if (!last_col) begin
						cur_col <= cur_col + 16'd1;
					end else if (!last_row) begin
						cur_col <= 16'd0;
						cur_row <= cur_row + 16'd1;
					end

					if (last_col) begin
						read_state <= RD_PAD_RIGHT;
						if (pixel_count + 32'd1 >= total_pixels)
							pad_bottom_active <= 1'b1;
					end else if (pixel_count + 32'd1 >= total_pixels) begin
						read_state <= RD_DRAIN;
					end else if (write_pending) begin
						hold_state <= RD_WAIT;
						read_state <= RD_HOLD;
					end else begin
						read_state <= RD_WAIT;
					end
				end
			end

			RD_HOLD: begin
				if (!write_pending && !write_active)
					read_state <= hold_state;
			end

			RD_PAD_RIGHT: begin
				rgb_buf <= 24'd0;
				raw_buf <= 16'd0;
				if (pad_bottom_active) begin
					pad_bottom_col <= 16'd0;
					read_state <= RD_PAD_BOTTOM;
					pad_bottom_active <= 1'b0;
				end else if (write_pending) begin
					hold_state <= RD_PAD_RIGHT;
					read_state <= RD_HOLD;
				end else begin
					read_state <= RD_WAIT;
				end
			end

			RD_PAD_BOTTOM: begin
				rgb_buf <= 24'd0;
				raw_buf <= 16'd0;
				if (write_pending) begin
					hold_state <= RD_PAD_BOTTOM;
					read_state <= RD_HOLD;
				end else if (pad_bottom_col > frame_width) begin
					read_state <= RD_DRAIN;
					pad_bottom_col <= 16'd0;
				end else begin
					pad_bottom_col <= pad_bottom_col + 16'd1;
					read_state <= RD_PAD_BOTTOM;
				end
			end

			RD_DRAIN: begin
				if (write_pending || write_active) begin
					read_state <= RD_DRAIN;
				end else if (drain_count != 5'd0) begin
					drain_count <= drain_count - 5'd1;
				end else begin
					frame_done      <= 1'b1;
					frame_number    <= frame_number + 32'd1;
					frame_cycle_sum <= frame_cycle_sum + frame_cycle_cur;
					read_state      <= RD_IDLE;
				end
			end

			default: read_state <= RD_IDLE;
		endcase
	end
end

endmodule
