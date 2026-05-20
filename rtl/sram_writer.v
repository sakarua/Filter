// SRAM writer: captures filtered pixels and writes back to SRAM
module sram_writer (
	input             clk,
	input             rstn,
	input             pixel_size,
	input      [31:0] baseImageO,
	input             window_valid,
	input      [31:0] window_center_index,
	input      [15:0] filter_data,
	input             read_active,
	output reg        write_pending,
	output            write_active,
	output     [20:0] write_addr,
	output     [ 7:0] write_mask,
	output     [63:0] write_word
);

localparam WR_IDLE  = 2'd0;
localparam WR_WRITE = 2'd1;
localparam WR_WRITE2 = 2'd2;

reg  [1:0]  write_state;
reg  [2:0]  filter_valid_pipe;
reg  [31:0] center_index_d0;
reg  [31:0] center_index_d1;
reg  [31:0] center_index_d2;
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
		end else if (write_state == WR_WRITE) begin
			write_pending <= 1'b0;
		end
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
				if (write_pending && !read_active)
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
