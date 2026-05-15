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

reg [63:0] word0;
reg [63:0] word1;  //一个像素数据可能跨越两个连续的64-bit word，因此需要两个寄存器暂存数据

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        word0 <= 64'd0;
        word1 <= 64'd0;
    end else begin
        if (capture_word0)
            word0 <= mem_di;
        if (capture_word1)
            word1 <= mem_di;
    end
end

wire [127:0] byte_window = {word1, word0}; //拼成一个完整的窗口
wire [6:0]   bit_offset  = {byte_offset, 3'b000}; //转换成位偏移

wire [23:0] rgb888 = byte_window >> bit_offset;
wire [15:0] raw16  = byte_window >> bit_offset;

assign red      = rgb888[ 7: 0];
assign green    = rgb888[15: 8];
assign blue     = rgb888[23:16];
assign raw_gray = format_raw16 ? raw16 : 16'd0;

endmodule
