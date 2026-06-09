// Median filter (3x3) with mask support and 3-cycle pipeline latency.
// Timing-friendly implementation: row sort + median-of-three composition.
module median_filter_3x3 #(
    parameter DATA_WIDTH = 16
) (
    input wire                      clk,
    input wire                      rst_n,
    input wire [DATA_WIDTH-1:0]     data11,
    input wire [DATA_WIDTH-1:0]     data12,
    input wire [DATA_WIDTH-1:0]     data13,
    input wire [DATA_WIDTH-1:0]     data21,
    input wire [DATA_WIDTH-1:0]     data22,
    input wire [DATA_WIDTH-1:0]     data23,
    input wire [DATA_WIDTH-1:0]     data31,
    input wire [DATA_WIDTH-1:0]     data32,
    input wire [DATA_WIDTH-1:0]     data33,
    input wire [8:0]                mask,
    output wire [DATA_WIDTH-1:0]    target_data
);

function [DATA_WIDTH-1:0] min2;
    input [DATA_WIDTH-1:0] a;
    input [DATA_WIDTH-1:0] b;
    begin
        min2 = (a < b) ? a : b;
    end
endfunction

function [DATA_WIDTH-1:0] max2;
    input [DATA_WIDTH-1:0] a;
    input [DATA_WIDTH-1:0] b;
    begin
        max2 = (a > b) ? a : b;
    end
endfunction

function [DATA_WIDTH-1:0] med3;
    input [DATA_WIDTH-1:0] a;
    input [DATA_WIDTH-1:0] b;
    input [DATA_WIDTH-1:0] c;
    begin
        med3 = max2(min2(a, b), min2(max2(a, b), c));
    end
endfunction

reg [DATA_WIDTH-1:0] s0_d0;
reg [DATA_WIDTH-1:0] s1_d0;
reg [DATA_WIDTH-1:0] s2_d0;
reg [DATA_WIDTH-1:0] s3_d0;
reg [DATA_WIDTH-1:0] s4_d0;
reg [DATA_WIDTH-1:0] s5_d0;
reg [DATA_WIDTH-1:0] s6_d0;
reg [DATA_WIDTH-1:0] s7_d0;
reg [DATA_WIDTH-1:0] s8_d0;

reg [DATA_WIDTH-1:0] row0_min_d1;
reg [DATA_WIDTH-1:0] row0_mid_d1;
reg [DATA_WIDTH-1:0] row0_max_d1;
reg [DATA_WIDTH-1:0] row1_min_d1;
reg [DATA_WIDTH-1:0] row1_mid_d1;
reg [DATA_WIDTH-1:0] row1_max_d1;
reg [DATA_WIDTH-1:0] row2_min_d1;
reg [DATA_WIDTH-1:0] row2_mid_d1;
reg [DATA_WIDTH-1:0] row2_max_d1;

reg [DATA_WIDTH-1:0] max_of_mins_d2;
reg [DATA_WIDTH-1:0] mid_of_mids_d2;
reg [DATA_WIDTH-1:0] min_of_maxs_d2;
reg [DATA_WIDTH-1:0] median_d3;

wire [DATA_WIDTH-1:0] m0 = mask[0] ? data11 : data22;
wire [DATA_WIDTH-1:0] m1 = mask[1] ? data12 : data22;
wire [DATA_WIDTH-1:0] m2 = mask[2] ? data13 : data22;
wire [DATA_WIDTH-1:0] m3 = mask[3] ? data21 : data22;
wire [DATA_WIDTH-1:0] m4 = mask[4] ? data22 : data22;
wire [DATA_WIDTH-1:0] m5 = mask[5] ? data23 : data22;
wire [DATA_WIDTH-1:0] m6 = mask[6] ? data31 : data22;
wire [DATA_WIDTH-1:0] m7 = mask[7] ? data32 : data22;
wire [DATA_WIDTH-1:0] m8 = mask[8] ? data33 : data22;

wire [DATA_WIDTH-1:0] row0_min_w = min2(min2(s0_d0, s1_d0), s2_d0);
wire [DATA_WIDTH-1:0] row0_max_w = max2(max2(s0_d0, s1_d0), s2_d0);
wire [DATA_WIDTH-1:0] row0_mid_w = med3(s0_d0, s1_d0, s2_d0);
wire [DATA_WIDTH-1:0] row1_min_w = min2(min2(s3_d0, s4_d0), s5_d0);
wire [DATA_WIDTH-1:0] row1_max_w = max2(max2(s3_d0, s4_d0), s5_d0);
wire [DATA_WIDTH-1:0] row1_mid_w = med3(s3_d0, s4_d0, s5_d0);
wire [DATA_WIDTH-1:0] row2_min_w = min2(min2(s6_d0, s7_d0), s8_d0);
wire [DATA_WIDTH-1:0] row2_max_w = max2(max2(s6_d0, s7_d0), s8_d0);
wire [DATA_WIDTH-1:0] row2_mid_w = med3(s6_d0, s7_d0, s8_d0);

wire [DATA_WIDTH-1:0] max_of_mins_w = max2(max2(row0_min_d1, row1_min_d1), row2_min_d1);
wire [DATA_WIDTH-1:0] mid_of_mids_w = med3(row0_mid_d1, row1_mid_d1, row2_mid_d1);
wire [DATA_WIDTH-1:0] min_of_maxs_w = min2(min2(row0_max_d1, row1_max_d1), row2_max_d1);
wire [DATA_WIDTH-1:0] median_w = med3(max_of_mins_d2, mid_of_mids_d2, min_of_maxs_d2);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s0_d0 <= {DATA_WIDTH{1'b0}};
        s1_d0 <= {DATA_WIDTH{1'b0}};
        s2_d0 <= {DATA_WIDTH{1'b0}};
        s3_d0 <= {DATA_WIDTH{1'b0}};
        s4_d0 <= {DATA_WIDTH{1'b0}};
        s5_d0 <= {DATA_WIDTH{1'b0}};
        s6_d0 <= {DATA_WIDTH{1'b0}};
        s7_d0 <= {DATA_WIDTH{1'b0}};
        s8_d0 <= {DATA_WIDTH{1'b0}};

        row0_min_d1 <= {DATA_WIDTH{1'b0}};
        row0_mid_d1 <= {DATA_WIDTH{1'b0}};
        row0_max_d1 <= {DATA_WIDTH{1'b0}};
        row1_min_d1 <= {DATA_WIDTH{1'b0}};
        row1_mid_d1 <= {DATA_WIDTH{1'b0}};
        row1_max_d1 <= {DATA_WIDTH{1'b0}};
        row2_min_d1 <= {DATA_WIDTH{1'b0}};
        row2_mid_d1 <= {DATA_WIDTH{1'b0}};
        row2_max_d1 <= {DATA_WIDTH{1'b0}};

        max_of_mins_d2 <= {DATA_WIDTH{1'b0}};
        mid_of_mids_d2 <= {DATA_WIDTH{1'b0}};
        min_of_maxs_d2 <= {DATA_WIDTH{1'b0}};
        median_d3 <= {DATA_WIDTH{1'b0}};
    end else begin
        // stage-0: mask invalid border taps to center pixel
        s0_d0 <= m0;
        s1_d0 <= m1;
        s2_d0 <= m2;
        s3_d0 <= m3;
        s4_d0 <= m4;
        s5_d0 <= m5;
        s6_d0 <= m6;
        s7_d0 <= m7;
        s8_d0 <= m8;

        // stage-1: sort each row into min/mid/max
        row0_min_d1 <= row0_min_w;
        row0_mid_d1 <= row0_mid_w;
        row0_max_d1 <= row0_max_w;
        row1_min_d1 <= row1_min_w;
        row1_mid_d1 <= row1_mid_w;
        row1_max_d1 <= row1_max_w;
        row2_min_d1 <= row2_min_w;
        row2_mid_d1 <= row2_mid_w;
        row2_max_d1 <= row2_max_w;

        // stage-2: reduce three row results into three candidates
        max_of_mins_d2 <= max_of_mins_w;
        mid_of_mids_d2 <= mid_of_mids_w;
        min_of_maxs_d2 <= min_of_maxs_w;

        // stage-3: compose exact median of 9
        median_d3 <= median_w;
    end
end

    assign target_data = median_d3;

endmodule
