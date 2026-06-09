// Median filter (3x3) with mask support and exact median behavior.
// Keeps 3-cycle output latency.
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

reg [DATA_WIDTH-1:0] val [0:8];
reg [DATA_WIDTH-1:0] pack [0:8];
reg [DATA_WIDTH-1:0] sort_s1 [0:8];
reg [DATA_WIDTH-1:0] sort_s1_r [0:8];
reg [DATA_WIDTH-1:0] sort_s2 [0:8];
reg [DATA_WIDTH-1:0] swap_tmp_s1;
reg [DATA_WIDTH-1:0] swap_tmp_s2;
reg [DATA_WIDTH-1:0] median_comb_s2;
reg [3:0]            count_s1_r;
reg [DATA_WIDTH-1:0] median_d0;
reg [DATA_WIDTH-1:0] median_d1;
reg [DATA_WIDTH-1:0] median_d2;
reg [DATA_WIDTH:0]   sum_mid_s2;
integer i;
integer j;
integer count;

always @* begin
    val[0] = data11; val[1] = data12; val[2] = data13;
    val[3] = data21; val[4] = data22; val[5] = data23;
    val[6] = data31; val[7] = data32; val[8] = data33;

    count = 0;
    for (i = 0; i < 9; i = i + 1) begin
        if (mask[i]) begin
            pack[count] = val[i];
            count = count + 1;
        end
    end

    for (i = 0; i < 9; i = i + 1) begin
        if (i >= count)
            pack[i] = {DATA_WIDTH{1'b1}};
    end

    for (i = 0; i < 9; i = i + 1)
        sort_s1[i] = pack[i];

    // First half sort passes.
    for (i = 0; i < 4; i = i + 1) begin
        for (j = 0; j < 8; j = j + 1) begin
            if (sort_s1[j] > sort_s1[j + 1]) begin
                swap_tmp_s1 = sort_s1[j];
                sort_s1[j] = sort_s1[j + 1];
                sort_s1[j + 1] = swap_tmp_s1;
            end
        end
    end
end

always @* begin
    sum_mid_s2 = {(DATA_WIDTH+1){1'b0}};
    for (i = 0; i < 9; i = i + 1)
        sort_s2[i] = sort_s1_r[i];

    // Second half sort passes.
    for (i = 0; i < 5; i = i + 1) begin
        for (j = 0; j < 8; j = j + 1) begin
            if (sort_s2[j] > sort_s2[j + 1]) begin
                swap_tmp_s2 = sort_s2[j];
                sort_s2[j] = sort_s2[j + 1];
                sort_s2[j + 1] = swap_tmp_s2;
            end
        end
    end

    if (count_s1_r <= 0) begin
        median_comb_s2 = {DATA_WIDTH{1'b0}};
    end else if (count_s1_r[0]) begin
        median_comb_s2 = sort_s2[count_s1_r >> 1];
    end else begin
        // For even valid count on borders, use average of two middle values.
        sum_mid_s2 = sort_s2[(count_s1_r >> 1) - 1] + sort_s2[count_s1_r >> 1];
        median_comb_s2 = (sum_mid_s2 + 1'b1) >> 1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        count_s1_r <= 4'd0;
        for (i = 0; i < 9; i = i + 1)
            sort_s1_r[i] <= {DATA_WIDTH{1'b0}};
        median_d0 <= {DATA_WIDTH{1'b0}};
        median_d1 <= {DATA_WIDTH{1'b0}};
        median_d2 <= {DATA_WIDTH{1'b0}};
    end else begin
        count_s1_r <= count[3:0];
        for (i = 0; i < 9; i = i + 1)
            sort_s1_r[i] <= sort_s1[i];
        median_d0 <= median_comb_s2;
        median_d1 <= median_d0;
        median_d2 <= median_d1;
    end
end

assign target_data = median_d2;

endmodule
