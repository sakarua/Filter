// SRAM writer: queues border pass-through pixels and filtered inner pixels,
// then writes them back to the single-port SRAM when the reader is idle.
module sram_writer (
	input             clk,
	input             rstn,
	input             pixel_size,
	input      [31:0] baseImageO,
	input      [15:0] frame_width,
	input      [15:0] frame_height,
	input             gray_valid,
	input      [31:0] gray_index,
	input      [15:0] gray_data,
	input             window_valid,
	input      [31:0] window_center_index,
	input      [15:0] filter_data,
	input             read_active,
	output            write_pending,
	output            write_active,
	output     [20:0] write_addr,
	output     [ 7:0] write_mask,
	output     [63:0] write_word
);

localparam WR_IDLE   = 2'd0;
localparam WR_WRITE  = 2'd1;
localparam WR_WRITE2 = 2'd2;

localparam FIFO_AW    = 5;
localparam FIFO_DEPTH = 1 << FIFO_AW;

reg  [1:0]  write_state;
reg  [2:0]  filter_valid_pipe;
reg  [31:0] center_index_d0;
reg  [31:0] center_index_d1;
reg  [31:0] center_index_d2;
reg  [31:0] write_byte_addr;
reg  [15:0] write_data;

reg  [31:0] fifo_index [0:FIFO_DEPTH-1];
reg  [15:0] fifo_data  [0:FIFO_DEPTH-1];
reg  [FIFO_AW-1:0] wr_ptr;
reg  [FIFO_AW-1:0] rd_ptr;
reg  [FIFO_AW:0]   fifo_count;
reg  [FIFO_AW-1:0] wr_ptr_next;
reg  [FIFO_AW:0]   fifo_count_next;

wire        filter_valid = filter_valid_pipe[2];
wire        fifo_full    = (fifo_count > (FIFO_DEPTH - 2));
wire        start_write  = (write_state == WR_IDLE) && (fifo_count != 0) && !read_active;

assign write_pending = (fifo_count != 0);

always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		filter_valid_pipe <= 3'b0;
		center_index_d0   <= 32'd0;
		center_index_d1   <= 32'd0;
		center_index_d2   <= 32'd0;
	end else begin
		filter_valid_pipe <= {filter_valid_pipe[1:0], window_valid};
		center_index_d0   <= window_center_index;
		center_index_d1   <= center_index_d0;
		center_index_d2   <= center_index_d1;
	end
end

always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		wr_ptr          <= {FIFO_AW{1'b0}};
		rd_ptr          <= {FIFO_AW{1'b0}};
		fifo_count      <= {(FIFO_AW+1){1'b0}};
		write_byte_addr <= 32'd0;
		write_data      <= 16'd0;
	end else begin
		wr_ptr_next     = wr_ptr;
		fifo_count_next = fifo_count;

		if (filter_valid && !fifo_full) begin
			fifo_index[wr_ptr_next] <= center_index_d2;
			fifo_data [wr_ptr_next] <= filter_data;
			wr_ptr_next             = wr_ptr_next + {{(FIFO_AW-1){1'b0}}, 1'b1};
			fifo_count_next         = fifo_count_next + {{FIFO_AW{1'b0}}, 1'b1};
		end

		if (start_write) begin
			write_byte_addr <= baseImageO + (pixel_size ? {fifo_index[rd_ptr][30:0], 1'b0} : fifo_index[rd_ptr]);
			write_data      <= fifo_data[rd_ptr];
			rd_ptr          <= rd_ptr + {{(FIFO_AW-1){1'b0}}, 1'b1};
			fifo_count_next = fifo_count_next - {{FIFO_AW{1'b0}}, 1'b1};
		end

		wr_ptr     <= wr_ptr_next;
		fifo_count <= fifo_count_next;
	end
end

wire [2:0] write_lane = write_byte_addr[2:0];
wire       write_cross_word = pixel_size & (write_lane == 3'd7);
wire [20:0] write_word_addr = write_byte_addr[23:3];

assign write_mask = (write_state == WR_WRITE2) ? 8'hfe :
						write_cross_word ? ~(8'b0000_0001 << write_lane) :
						pixel_size ? ~((8'b0000_0001 << write_lane) | (8'b0000_0010 << write_lane)) :
						~(8'b0000_0001 << write_lane);

assign write_word = (write_state == WR_WRITE2) ? {56'd0, write_data[15:8]} :
						 write_cross_word ? ({56'd0, write_data[7:0]} << {write_lane, 3'b000}) :
						 pixel_size ? ({48'd0, write_data} << {write_lane, 3'b000}) :
						 ({56'd0, write_data[7:0]} << {write_lane, 3'b000});

assign write_addr = (write_state == WR_WRITE2) ? (write_word_addr + 21'd1) : write_word_addr;
assign write_active = (write_state != WR_IDLE);

always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		write_state <= WR_IDLE;
	end else begin
		case (write_state)
			WR_IDLE: begin
				if (start_write)
					write_state <= WR_WRITE;
			end

			WR_WRITE: begin
				if (write_cross_word)
					write_state <= WR_WRITE2;
				else
					write_state <= WR_IDLE;
			end

			WR_WRITE2: write_state <= WR_IDLE;
			default: write_state <= WR_IDLE;
		endcase
	end
end

endmodule
