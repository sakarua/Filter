// Median filter with variable window mask and exact median behavior.
// Pipeline latency is 3 clocks from input window to target_data.
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
reg [DATA_WIDTH-1:0] pack_s0 [0:8];
reg [DATA_WIDTH-1:0] s1_c [0:8];
reg [DATA_WIDTH-1:0] s2_c [0:8];
reg [DATA_WIDTH-1:0] s3_c [0:8];
reg [DATA_WIDTH-1:0] s1_r [0:8];
reg [DATA_WIDTH-1:0] s2_r [0:8];
reg [3:0]            cnt_s0;
reg [3:0]            cnt_s1;
reg [3:0]            cnt_s2;
reg [DATA_WIDTH:0]   sum_mid;
reg [DATA_WIDTH-1:0] median_comb;
reg [DATA_WIDTH-1:0] median_d;
reg [DATA_WIDTH-1:0] tmp_s1;
reg [DATA_WIDTH-1:0] tmp_s2;
reg [DATA_WIDTH-1:0] tmp_s3;
integer i;
integer j;
integer count;

always @* begin
    val[0] = data11; val[1] = data12; val[2] = data13;
    val[3] = data21; val[4] = data22; val[5] = data23;
    val[6] = data31; val[7] = data32; val[8] = data33;

    count = 0;
    for (i = 0; i < 9; i = i + 1)
        pack_s0[i] = {DATA_WIDTH{1'b1}};

    for (i = 0; i < 9; i = i + 1) begin
        if (mask[i]) begin
            pack_s0[count] = val[i];
            count = count + 1;
        end
    end
    cnt_s0 = count[3:0];

    for (i = 0; i < 9; i = i + 1)
        s1_c[i] = pack_s0[i];

    // Stage-1: phases 0(even), 1(odd), 2(even)
    for (j = 0; j < 8; j = j + 2) begin
        if (s1_c[j] > s1_c[j + 1]) begin
            tmp_s1 = s1_c[j];
            s1_c[j] = s1_c[j + 1];
            s1_c[j + 1] = tmp_s1;
        end
    end
    for (j = 1; j < 8; j = j + 2) begin
        if (s1_c[j] > s1_c[j + 1]) begin
            tmp_s1 = s1_c[j];
            s1_c[j] = s1_c[j + 1];
            s1_c[j + 1] = tmp_s1;
        end
    end
    for (j = 0; j < 8; j = j + 2) begin
        if (s1_c[j] > s1_c[j + 1]) begin
            tmp_s1 = s1_c[j];
            s1_c[j] = s1_c[j + 1];
            s1_c[j + 1] = tmp_s1;
        end
    end
end

always @* begin
    for (i = 0; i < 9; i = i + 1)
        s2_c[i] = s1_r[i];

    // Stage-2: phases 3(odd), 4(even), 5(odd)
    for (j = 1; j < 8; j = j + 2) begin
        if (s2_c[j] > s2_c[j + 1]) begin
            tmp_s2 = s2_c[j];
            s2_c[j] = s2_c[j + 1];
            s2_c[j + 1] = tmp_s2;
        end
    end
    for (j = 0; j < 8; j = j + 2) begin
        if (s2_c[j] > s2_c[j + 1]) begin
            tmp_s2 = s2_c[j];
            s2_c[j] = s2_c[j + 1];
            s2_c[j + 1] = tmp_s2;
        end
    end
    for (j = 1; j < 8; j = j + 2) begin
        if (s2_c[j] > s2_c[j + 1]) begin
            tmp_s2 = s2_c[j];
            s2_c[j] = s2_c[j + 1];
            s2_c[j + 1] = tmp_s2;
        end
    end
end

always @* begin
    for (i = 0; i < 9; i = i + 1)
        s3_c[i] = s2_r[i];

    // Stage-3: phases 6(even), 7(odd), 8(even)
    for (j = 0; j < 8; j = j + 2) begin
        if (s3_c[j] > s3_c[j + 1]) begin
            tmp_s3 = s3_c[j];
            s3_c[j] = s3_c[j + 1];
            s3_c[j + 1] = tmp_s3;
        end
    end
    for (j = 1; j < 8; j = j + 2) begin
        if (s3_c[j] > s3_c[j + 1]) begin
            tmp_s3 = s3_c[j];
            s3_c[j] = s3_c[j + 1];
            s3_c[j + 1] = tmp_s3;
        end
    end
    for (j = 0; j < 8; j = j + 2) begin
        if (s3_c[j] > s3_c[j + 1]) begin
            tmp_s3 = s3_c[j];
            s3_c[j] = s3_c[j + 1];
            s3_c[j + 1] = tmp_s3;
        end
    end

    sum_mid = {(DATA_WIDTH+1){1'b0}};
    if (cnt_s2 == 4'd0) begin
        median_comb = {DATA_WIDTH{1'b0}};
    end else if (cnt_s2[0]) begin
        median_comb = s3_c[cnt_s2 >> 1];
    end else begin
        sum_mid = s3_c[(cnt_s2 >> 1) - 1] + s3_c[cnt_s2 >> 1];
        median_comb = (sum_mid + 1'b1) >> 1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_s1 <= 4'd0;
        cnt_s2 <= 4'd0;
        for (i = 0; i < 9; i = i + 1) begin
            s1_r[i] <= {DATA_WIDTH{1'b0}};
            s2_r[i] <= {DATA_WIDTH{1'b0}};
        end
        median_d <= {DATA_WIDTH{1'b0}};
    end else begin
        cnt_s1 <= cnt_s0;
        cnt_s2 <= cnt_s1;
        for (i = 0; i < 9; i = i + 1) begin
            s1_r[i] <= s1_c[i];
            s2_r[i] <= s2_c[i];
        end
        median_d <= median_comb;
    end
end

assign target_data = median_d;

endmodule
