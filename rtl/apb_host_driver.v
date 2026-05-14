`define PROBE_APB 1

// APB 主机驱动模型：用于仿真中发起 APB 读写访问
module apb_host_driver (
	input  pclk,
	input  presetn,
	//////
	output reg        psel,
	output reg        penable,
	output reg        pwrite,
	output reg [31:0] paddr,
	output reg [31:0] pwdata,
	//////
	input             pready,
	input      [31:0] prdata
);

	parameter dealy = 2;

	reg        state_wr, state_rd;
	reg        wr_cmd, wr_sta, wr_ena, wr_end;
	reg        rd_cmd, rd_sta, rd_ena, rd_end;
	reg [31:0] addr_w, addr_r;
	reg [31:0] data_w, rd_dat;

	initial begin
		wr_cmd   = 0;
		rd_cmd   = 0;
		state_wr = 0;
		state_rd = 0;
		addr_w   = 0;
		addr_r   = 0;
		data_w   = 0;
	end

	// APB 时序驱动
	always @(posedge pclk or negedge presetn) begin
		if (~presetn) begin
			psel    <= 0;
			penable <= 0;
			pwrite  <= 0;
			paddr   <= 0;
			pwdata  <= 0;
		end else begin
			if (state_wr) begin
				if (wr_sta) begin
					psel    <= 1'd1;
					penable <= 1'd0;
					pwrite  <= 1'd1;
					paddr   <= addr_w;
					pwdata  <= data_w;
				end

				if (wr_ena) begin
					penable <= 1'd1;
				end

				if (pready) begin
					psel    <= 1'd0;
					penable <= 1'd0;
					pwrite  <= 1'd0;
				end
			end else if (state_rd) begin
				if (rd_sta) begin
					psel    <= 1'd1;
					penable <= 1'd0;
					pwrite  <= 1'd0;
					paddr   <= addr_r;
					pwdata  <= 32'd0;
				end

				if (rd_ena) begin
					penable <= 1'd1;
				end

				if (pready) begin
					psel    <= 1'd0;
					penable <= 1'd0;
				end
			end
		end
	end

	// 状态推进与数据采样
	always @(posedge pclk or negedge presetn) begin
		if (~presetn) begin
			wr_sta <= 0;
			wr_ena <= 0;
			wr_end <= 0;
			rd_sta <= 0;
			rd_ena <= 0;
			rd_end <= 0;
			rd_dat <= 0;
		end else begin
			wr_sta <= wr_cmd;
			wr_ena <= wr_sta;
			wr_end <= state_wr & !wr_cmd & !wr_sta & !wr_ena & pready;
			rd_sta <= rd_cmd;
			rd_ena <= rd_sta;
			rd_end <= state_rd & !rd_cmd & !rd_sta & !rd_ena & pready;
			rd_dat <= state_rd & pready ? prdata : rd_dat;
		end
	end

	task waiting;
		begin
			#1;
		end
	endtask

	// APB 读任务
	task read_apb;
		input  [31:0] addr;
		output [31:0] data;
		begin
			addr_r   = addr;
			state_rd = 1;
			rd_cmd   = 1;
			while (!rd_sta) waiting;
			rd_cmd = 0;
			while (!rd_ena) waiting;
			while (!rd_end) waiting;
			data = rd_dat;
			state_rd = 0;
			while (!rd_end) waiting;
			if (`PROBE_APB) $display("READ_APB: addr[%h], data[%h]", addr, data);
		end
	endtask

	// APB 写任务
	task write_apb;
		input [31:0] addr;
		input [31:0] data;
		begin
			if (`PROBE_APB) $display("WRITE_APB: addr[%h], data[%h]", addr, data);
			addr_w   = addr;
			data_w   = data;
			state_wr = 1;
			wr_cmd   = 1;
			while (!wr_sta) waiting;
			wr_cmd = 0;
			while (!wr_ena) waiting;
			while (!wr_end) waiting;
			state_wr = 0;
			while (!wr_end) waiting;
		end
	endtask

endmodule
