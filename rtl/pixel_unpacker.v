// 解包64-bit的SRAM输出数据
// The module captures two consecutive SRAM words through the same mem_di port
// so pixels crossing an 8-byte boundary can still be unpacked.
// format_raw16 = 0: RGB888格式
// format_raw16 = 1: RAW16格式
module pixel_unpacker (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        capture_word0,
    input  wire        capture_word1,
    input  wire        format_raw16,
    input  wire [63:0] mem_di,
    input  wire [ 2:0] byte_offset,
    output wire [ 7:0] red,
    output wire [ 7:0] green,
    output wire [ 7:0] blue,
    output wire [15:0] raw_gray
);

localparam ST_IDLE   = 2'd0;
localparam ST_WAIT   = 2'd1;
localparam ST_UNPACK = 2'd2;

reg [1:0]  state;
reg [63:0] word0;
reg [63:0] word1;  //一个像素数据可能跨越两个连续的64-bit word，因此需要两个寄存器暂存数据
reg        need_word1_lat;
reg [ 7:0] red_r;
reg [ 7:0] green_r;
reg [ 7:0] blue_r;
reg [15:0] raw_gray_r;

wire need_word1 = format_raw16 ? (byte_offset > 3'd6) : (byte_offset > 3'd5);
wire [127:0] byte_window = need_word1_lat ? {word1, word0} : {64'd0, word0}; //拼成一个完整的窗口
wire [6:0]   bit_offset  = {byte_offset, 3'b000}; //转换成位偏移

wire [23:0] rgb888 = byte_window >> bit_offset; //移动到该像素的起始位置
wire [15:0] raw16  = byte_window >> bit_offset;

assign red      = red_r;
assign green    = green_r;
assign blue     = blue_r;
assign raw_gray = raw_gray_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= ST_IDLE;
        word0          <= 64'd0;
        word1          <= 64'd0;
        need_word1_lat <= 1'b0;
        red_r          <= 8'd0;
        green_r        <= 8'd0;
        blue_r         <= 8'd0;
        raw_gray_r     <= 16'd0;
    end else begin
        case (state)
            ST_IDLE: begin
                if (capture_word0) begin
                    word0          <= mem_di;
                    need_word1_lat <= need_word1;
                    if (need_word1)
                        state <= ST_WAIT;
                    else
                        state <= ST_UNPACK;
                end
            end

            ST_WAIT: begin
                if (capture_word1) begin
                    word1 <= mem_di;
                    state <= ST_UNPACK;
                end
            end

            ST_UNPACK: begin
                if (format_raw16) begin
                    red_r      <= 8'd0;
                    green_r    <= 8'd0;
                    blue_r     <= 8'd0;
                    raw_gray_r <= raw16;
                end else begin
                    red_r      <= rgb888[7:0];
                    green_r    <= rgb888[15:8];
                    blue_r     <= rgb888[23:16];
                    raw_gray_r <= 16'd0;
                end
                state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
