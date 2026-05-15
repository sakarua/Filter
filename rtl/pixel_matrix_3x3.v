//
// Streaming 3x3 window generator.
// A valid window is generated after the third row and third column arrive.
//
module pixel_matrix_3x3 #(
    parameter DATA_WIDTH = 8,
    parameter MAX_FRAME_WIDTH = 2048
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    frame_start,
    input  wire                    pixel_valid,
    input  wire [DATA_WIDTH-1:0]   pixel_data,
    input  wire [15:0]             frame_width,

    output reg                     window_valid,
    output reg  [31:0]             center_index,
    output reg  [DATA_WIDTH-1:0]   data11,
    output reg  [DATA_WIDTH-1:0]   data12,
    output reg  [DATA_WIDTH-1:0]   data13,
    output reg  [DATA_WIDTH-1:0]   data21,
    output reg  [DATA_WIDTH-1:0]   data22,
    output reg  [DATA_WIDTH-1:0]   data23,
    output reg  [DATA_WIDTH-1:0]   data31,
    output reg  [DATA_WIDTH-1:0]   data32,
    output reg  [DATA_WIDTH-1:0]   data33
);

reg [DATA_WIDTH-1:0] line0 [0:MAX_FRAME_WIDTH-1];
reg [DATA_WIDTH-1:0] line1 [0:MAX_FRAME_WIDTH-1];

reg [15:0] col;
reg [15:0] row;

reg [DATA_WIDTH-1:0] line0_d1;
reg [DATA_WIDTH-1:0] line0_d2;
reg [DATA_WIDTH-1:0] line1_d1;
reg [DATA_WIDTH-1:0] line1_d2;
reg [DATA_WIDTH-1:0] curr_d1;
reg [DATA_WIDTH-1:0] curr_d2;

wire width_last = (col == frame_width - 16'd1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        col          <= 16'd0;
        row          <= 16'd0;
        line0_d1     <= {DATA_WIDTH{1'b0}};
        line0_d2     <= {DATA_WIDTH{1'b0}};
        line1_d1     <= {DATA_WIDTH{1'b0}};
        line1_d2     <= {DATA_WIDTH{1'b0}};
        curr_d1      <= {DATA_WIDTH{1'b0}};
        curr_d2      <= {DATA_WIDTH{1'b0}};
        window_valid <= 1'b0;
        center_index <= 32'd0;
        data11       <= {DATA_WIDTH{1'b0}};
        data12       <= {DATA_WIDTH{1'b0}};
        data13       <= {DATA_WIDTH{1'b0}};
        data21       <= {DATA_WIDTH{1'b0}};
        data22       <= {DATA_WIDTH{1'b0}};
        data23       <= {DATA_WIDTH{1'b0}};
        data31       <= {DATA_WIDTH{1'b0}};
        data32       <= {DATA_WIDTH{1'b0}};
        data33       <= {DATA_WIDTH{1'b0}};
    end else if (frame_start) begin
        col          <= 16'd0;
        row          <= 16'd0;
        line0_d1     <= {DATA_WIDTH{1'b0}};
        line0_d2     <= {DATA_WIDTH{1'b0}};
        line1_d1     <= {DATA_WIDTH{1'b0}};
        line1_d2     <= {DATA_WIDTH{1'b0}};
        curr_d1      <= {DATA_WIDTH{1'b0}};
        curr_d2      <= {DATA_WIDTH{1'b0}};
        window_valid <= 1'b0;
        center_index <= 32'd0;
    end else begin
        window_valid <= 1'b0;

        if (pixel_valid) begin
            if ((row >= 16'd2) && (col >= 16'd2)) begin
                window_valid <= 1'b1;
                center_index <= ((row - 16'd1) * frame_width) + (col - 16'd1);
                data11       <= line0_d2;
                data12       <= line0_d1;
                data13       <= line0[col];
                data21       <= line1_d2;
                data22       <= line1_d1;
                data23       <= line1[col];
                data31       <= curr_d2;
                data32       <= curr_d1;
                data33       <= pixel_data;
            end

            line0[col] <= line1[col];
            line1[col] <= pixel_data;

            if (width_last) begin
                col      <= 16'd0;
                row      <= row + 16'd1;
                line0_d1 <= {DATA_WIDTH{1'b0}};
                line0_d2 <= {DATA_WIDTH{1'b0}};
                line1_d1 <= {DATA_WIDTH{1'b0}};
                line1_d2 <= {DATA_WIDTH{1'b0}};
                curr_d1  <= {DATA_WIDTH{1'b0}};
                curr_d2  <= {DATA_WIDTH{1'b0}};
            end else begin
                col      <= col + 16'd1;
                line0_d2 <= line0_d1;
                line0_d1 <= line0[col];
                line1_d2 <= line1_d1;
                line1_d1 <= line1[col];
                curr_d2  <= curr_d1;
                curr_d1  <= pixel_data;
            end
        end
    end
end

endmodule
