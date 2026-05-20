// SRAM reader: sequential read and pixel unpacking
module sram_reader (
	input             clk,
	input             rstn,
	input             pixel_size,//输入信号格式选择：0=RGB888, 1=RAW16
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
	//图像数据
	output            read_valid,
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

localparam RD_IDLE  = 3'd0;
localparam RD_READ  = 3'd1;
localparam RD_WAIT  = 3'd2;
localparam RD_DONE  = 3'd3;
localparam RD_HOLD  = 3'd4;
localparam RD_DRAIN = 3'd5;

reg [23:0] rgb_buf;
reg [15:0] raw_buf;

reg  [2:0]  read_state;
reg         read_pending;
reg  [31:0] total_pixels;
reg  [31:0] input_byte_addr;
reg  [31:0] pixel_count;
reg  [ 4:0] drain_count;

wire [1:0]  bytes_per_pixel = pixel_size ? FORMAT_RAW16_BYTES : FORMAT_RGB888_BYTES;
wire [23:0] read_byte_addr  = input_byte_addr[23:0];
wire [20:0] read_word_addr  = read_byte_addr[23:3];

wire [2:0]  unpk_byte_offset = read_byte_addr[2:0];//像素起始地址在字内的偏移
wire [63:0] mem_di_shift = mem_di >> {unpk_byte_offset, 3'b000};//根据像素起始地址调整数据对齐

wire        crossword  = pixel_size ? (unpk_byte_offset > 3'd6) : (unpk_byte_offset > 3'd5);//像素数据是否跨字

wire        pixel_complete   = (read_state == RD_DONE) && (read_pending ? 1'b1 : ~crossword);

assign read_req = (read_state == RD_WAIT);
assign read_active = (read_state == RD_READ) || (read_state == RD_WAIT) || (read_state == RD_DONE);
assign read_addr = read_word_addr + (read_pending ? 21'd1 : 21'd0);

//图像数据
assign read_valid      = pixel_complete;
assign red      = pixel_size ? 8'd0 : rgb_buf[7:0];
assign green    = pixel_size ? 8'd0 : rgb_buf[15:8];
assign blue     = pixel_size ? 8'd0 : rgb_buf[23:16];
assign raw_gray = pixel_size ? raw_buf : 16'd0;



//SRAM读取状态机
always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		read_state      <= RD_IDLE;
		input_byte_addr <= 32'd0;
		pixel_count     <= 32'd0;
		total_pixels    <= 32'd0;
		drain_count     <= 5'd0;
		read_pending <= 1'b0;
		rgb_buf       <= 24'd0;
		raw_buf       <= 16'd0;
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
					read_state      <= RD_WAIT;
				end
			end

			RD_WAIT: begin
				if (!write_active)
					read_state <= RD_READ;
			end

			RD_READ: begin
				if (!read_pending) begin//第一个字
					if (pixel_size) begin// RAW16
						if (crossword)
							raw_buf[7:0] <= mem_di_shift[7:0];
						else
							raw_buf <= mem_di_shift[15:0];
					end 
                    else begin// RGB888
						if (crossword) begin
							if (unpk_byte_offset == 3'd6)
								rgb_buf[15:0] <= mem_di_shift[15:0];
							else
								rgb_buf[7:0] <= mem_di_shift[7:0];
						end 
                        else begin
							rgb_buf <= mem_di_shift[23:0];
						end
					end
				end 
                else begin//第二个字
					if (pixel_size) begin// RAW16
						raw_buf[15:8] <= mem_di_shift[7:0];
					end 
                    else begin// RGB888
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
					read_state <= RD_READ;
				end 
				else begin
					read_pending <= 1'b0;
					pixel_count     <= pixel_count + 32'd1;
					input_byte_addr <= input_byte_addr + bytes_per_pixel;

					if (pixel_count + 32'd1 >= total_pixels)
						read_state <= RD_DRAIN;
					else if (write_pending)
						read_state <= RD_HOLD;
					else
						read_state <= RD_READ;
				end
			end

			RD_HOLD: begin
				if (!write_pending && !write_active)
					read_state <= RD_READ;
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
