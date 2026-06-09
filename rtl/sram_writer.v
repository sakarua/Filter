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
(* shreg_extract = "no" *)
reg  [3:0]  filter_valid_pipe;
(* shreg_extract = "no" *)
reg  [31:0] center_index_d0;
(* shreg_extract = "no" *)
reg  [31:0] center_index_d1;
(* shreg_extract = "no" *)
reg  [31:0] center_index_d2;
(* shreg_extract = "no" *)
reg  [31:0] center_index_d3;
reg  [2:0]  raw_latency_count;
reg  [31:0] raw_out_index;
reg         raw_frame_done;
reg  [31:0] write_byte_addr;
reg  [15:0] write_data;

reg  [31:0] fifo_index [0:FIFO_DEPTH-1];
reg  [15:0] fifo_data  [0:FIFO_DEPTH-1];
reg  [20:0] pack_fifo_addr [0:FIFO_DEPTH-1];
reg  [ 7:0] pack_fifo_mask [0:FIFO_DEPTH-1];
reg  [63:0] pack_fifo_word [0:FIFO_DEPTH-1];
reg  [FIFO_AW-1:0] wr_ptr;
reg  [FIFO_AW-1:0] rd_ptr;
reg  [FIFO_AW:0]   fifo_count;
reg  [FIFO_AW-1:0] wr_ptr_next;
reg  [FIFO_AW:0]   fifo_count_next;
reg  [FIFO_AW-1:0] pack_wr_ptr;
reg  [FIFO_AW-1:0] pack_rd_ptr;
reg  [FIFO_AW:0]   pack_fifo_count;
reg  [FIFO_AW-1:0] pack_wr_ptr_next;
reg  [FIFO_AW:0]   pack_fifo_count_next;
reg                 pack_valid;
reg  [20:0]         pack_addr;
reg  [ 7:0]         pack_mask;
reg  [63:0]         pack_word;
reg  [20:0]         pack_addr_next;
reg  [ 7:0]         pack_mask_next;
reg  [63:0]         pack_word_next;
reg                 pack_valid_next;
reg                 pack_enqueue;
reg  [20:0]         pack_enqueue_addr;
reg  [ 7:0]         pack_enqueue_mask;
reg  [63:0]         pack_enqueue_word;
reg  [20:0]         rgb_word_addr;
reg  [ 2:0]         rgb_lane;
reg  [ 7:0]         rgb_lane_mask;
reg  [63:0]         rgb_lane_word;
reg  [20:0]         write_word_addr_reg;
reg  [ 7:0]         write_mask_reg;
reg  [63:0]         write_word_reg;

wire        filter_valid = filter_valid_pipe[3];
wire        fifo_full    = (fifo_count > (FIFO_DEPTH - 2));
wire        pack_fifo_full = (pack_fifo_count > (FIFO_DEPTH - 2));
wire        raw_start_write = pixel_size && (write_state == WR_IDLE) && (fifo_count != 0) && !read_active;
wire        pack_start_write = !pixel_size && (write_state == WR_IDLE) && (pack_fifo_count != 0) && !read_active;
wire        start_write  = raw_start_write || pack_start_write;
wire [31:0] total_pixels = frame_width * frame_height;
wire        filter_in_frame = filter_valid && (center_index_d3 < total_pixels);
wire        raw_filter_ready = (raw_latency_count == 3'd4);
wire        raw_enqueue = pixel_size && filter_valid && raw_filter_ready && !raw_frame_done &&
						  (raw_out_index < total_pixels) && !fifo_full;
wire        last_filter_pixel = (center_index_d3 + 32'd1) == total_pixels;
wire [31:0] rgb_byte_addr = baseImageO + center_index_d3;
assign write_pending = pixel_size ? (fifo_count != 0) : (pack_fifo_count != 0);

always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		filter_valid_pipe <= 4'b0;
		center_index_d0   <= 32'd0;
		center_index_d1   <= 32'd0;
		center_index_d2   <= 32'd0;
		center_index_d3   <= 32'd0;
		raw_latency_count <= 3'd0;
		raw_out_index     <= 32'd0;
		raw_frame_done    <= 1'b0;
	end else begin
		filter_valid_pipe <= {filter_valid_pipe[2:0], window_valid};
		center_index_d0   <= window_center_index;
		center_index_d1   <= center_index_d0;
		center_index_d2   <= center_index_d1;
		center_index_d3   <= center_index_d2;

		if (!pixel_size) begin
			raw_latency_count <= 3'd0;
			raw_out_index     <= 32'd0;
			raw_frame_done    <= 1'b0;
		end else if (raw_frame_done && gray_valid && (gray_index == 32'd0)) begin
			raw_latency_count <= 3'd0;
			raw_out_index     <= 32'd0;
			raw_frame_done    <= 1'b0;
		end else if (filter_valid && !raw_frame_done) begin
			if (!raw_filter_ready) begin
				raw_latency_count <= raw_latency_count + 3'd1;
			end else if (raw_enqueue) begin
				if ((raw_out_index + 32'd1) >= total_pixels) begin
					raw_frame_done <= 1'b1;
				end else begin
					raw_out_index <= raw_out_index + 32'd1;
				end
			end
		end
	end
end

always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
		wr_ptr          <= {FIFO_AW{1'b0}};
		rd_ptr          <= {FIFO_AW{1'b0}};
		fifo_count      <= {(FIFO_AW+1){1'b0}};
		pack_wr_ptr     <= {FIFO_AW{1'b0}};
		pack_rd_ptr     <= {FIFO_AW{1'b0}};
		pack_fifo_count <= {(FIFO_AW+1){1'b0}};
		pack_valid      <= 1'b0;
		pack_addr       <= 21'd0;
		pack_mask       <= 8'hff;
		pack_word       <= 64'd0;
		write_byte_addr <= 32'd0;
		write_data      <= 16'd0;
		write_word_addr_reg <= 21'd0;
		write_mask_reg      <= 8'hff;
		write_word_reg      <= 64'd0;
	end else begin
		wr_ptr_next     = wr_ptr;
		fifo_count_next = fifo_count;
		pack_wr_ptr_next     = pack_wr_ptr;
		pack_fifo_count_next = pack_fifo_count;
		pack_valid_next      = pack_valid;
		pack_addr_next       = pack_addr;
		pack_mask_next       = pack_mask;
		pack_word_next       = pack_word;
		pack_enqueue         = 1'b0;
		pack_enqueue_addr    = 21'd0;
		pack_enqueue_mask    = 8'hff;
		pack_enqueue_word    = 64'd0;
		rgb_word_addr        = rgb_byte_addr[23:3];
		rgb_lane             = rgb_byte_addr[2:0];
		rgb_lane_mask        = ~(8'b0000_0001 << rgb_lane);
		rgb_lane_word        = ({56'd0, filter_data[7:0]} << {rgb_lane, 3'b000});

		if (raw_enqueue) begin
			fifo_index[wr_ptr_next] <= raw_out_index;
			fifo_data [wr_ptr_next] <= filter_data;
			wr_ptr_next             = wr_ptr_next + {{(FIFO_AW-1){1'b0}}, 1'b1};
			fifo_count_next         = fifo_count_next + {{FIFO_AW{1'b0}}, 1'b1};
		end

		if (filter_in_frame && !pixel_size) begin
			if (!pack_valid_next) begin
				pack_valid_next = 1'b1;
				pack_addr_next  = rgb_word_addr;
				pack_mask_next  = rgb_lane_mask;
				pack_word_next  = rgb_lane_word;
			end else if (pack_addr_next == rgb_word_addr) begin
				pack_mask_next = pack_mask_next & rgb_lane_mask;
				pack_word_next = pack_word_next | rgb_lane_word;
			end else begin
				pack_enqueue      = 1'b1;
				pack_enqueue_addr = pack_addr_next;
				pack_enqueue_mask = pack_mask_next;
				pack_enqueue_word = pack_word_next;
				pack_valid_next   = 1'b1;
				pack_addr_next    = rgb_word_addr;
				pack_mask_next    = rgb_lane_mask;
				pack_word_next    = rgb_lane_word;
			end

			if (last_filter_pixel) begin
				pack_enqueue      = 1'b1;
				pack_enqueue_addr = pack_addr_next;
				pack_enqueue_mask = pack_mask_next;
				pack_enqueue_word = pack_word_next;
				pack_valid_next   = 1'b0;
				pack_mask_next    = 8'hff;
				pack_word_next    = 64'd0;
			end
		end

		if (pack_enqueue && !pack_fifo_full) begin
			pack_fifo_addr[pack_wr_ptr_next] <= pack_enqueue_addr;
			pack_fifo_mask[pack_wr_ptr_next] <= pack_enqueue_mask;
			pack_fifo_word[pack_wr_ptr_next] <= pack_enqueue_word;
			pack_wr_ptr_next                 = pack_wr_ptr_next + {{(FIFO_AW-1){1'b0}}, 1'b1};
			pack_fifo_count_next             = pack_fifo_count_next + {{FIFO_AW{1'b0}}, 1'b1};
		end

		if (raw_start_write) begin
			write_byte_addr <= baseImageO + (pixel_size ? {fifo_index[rd_ptr][30:0], 1'b0} : fifo_index[rd_ptr]);
			write_data      <= fifo_data[rd_ptr];
			rd_ptr          <= rd_ptr + {{(FIFO_AW-1){1'b0}}, 1'b1};
			fifo_count_next = fifo_count_next - {{FIFO_AW{1'b0}}, 1'b1};
		end else if (pack_start_write) begin
			write_word_addr_reg <= pack_fifo_addr[pack_rd_ptr];
			write_mask_reg      <= pack_fifo_mask[pack_rd_ptr];
			write_word_reg      <= pack_fifo_word[pack_rd_ptr];
			pack_rd_ptr         <= pack_rd_ptr + {{(FIFO_AW-1){1'b0}}, 1'b1};
			pack_fifo_count_next = pack_fifo_count_next - {{FIFO_AW{1'b0}}, 1'b1};
		end

		wr_ptr     <= wr_ptr_next;
		fifo_count <= fifo_count_next;
		pack_wr_ptr     <= pack_wr_ptr_next;
		pack_fifo_count <= pack_fifo_count_next;
		pack_valid      <= pack_valid_next;
		pack_addr       <= pack_addr_next;
		pack_mask       <= pack_mask_next;
		pack_word       <= pack_word_next;
	end
end

wire [2:0] write_lane = write_byte_addr[2:0];
wire       write_cross_word = pixel_size & (write_lane == 3'd7);
wire [20:0] write_word_addr = write_byte_addr[23:3];

assign write_mask = !pixel_size ? write_mask_reg :
					(write_state == WR_WRITE2) ? 8'hfe :
						write_cross_word ? ~(8'b0000_0001 << write_lane) :
						pixel_size ? ~((8'b0000_0001 << write_lane) | (8'b0000_0010 << write_lane)) :
						~(8'b0000_0001 << write_lane);

assign write_word = !pixel_size ? write_word_reg :
					 (write_state == WR_WRITE2) ? {56'd0, write_data[15:8]} :
						 write_cross_word ? ({56'd0, write_data[7:0]} << {write_lane, 3'b000}) :
						 pixel_size ? ({48'd0, write_data} << {write_lane, 3'b000}) :
						 ({56'd0, write_data[7:0]} << {write_lane, 3'b000});

assign write_addr = !pixel_size ? write_word_addr_reg :
					(write_state == WR_WRITE2) ? (write_word_addr + 21'd1) : write_word_addr;
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
