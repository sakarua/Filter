// Median filter with variable window mask, 3 clock latency.
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
reg [DATA_WIDTH-1:0] sort [0:8];
reg [DATA_WIDTH-1:0] median_comb;
reg [DATA_WIDTH-1:0] median_d0;
reg [DATA_WIDTH-1:0] median_d1;
reg [DATA_WIDTH-1:0] median_d2;
reg [DATA_WIDTH:0]   sum_mid;
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
    for (i = count; i < 9; i = i + 1) begin
        pack[i] = {DATA_WIDTH{1'b1}};
    end

    for (i = 0; i < 9; i = i + 1)
        sort[i] = pack[i];

    for (i = 0; i < 9; i = i + 1) begin
        for (j = 0; j < 8; j = j + 1) begin
            if (sort[j] > sort[j + 1]) begin
                median_comb = sort[j];
                sort[j] = sort[j + 1];
                sort[j + 1] = median_comb;
            end
        end
    end

    if (count <= 0) begin
        median_comb = {DATA_WIDTH{1'b0}};
    end else if (count[0]) begin
        median_comb = sort[count >> 1];
    end else begin
        sum_mid = sort[(count >> 1) - 1] + sort[count >> 1];
        median_comb = (sum_mid + 1'b1) >> 1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        median_d0 <= {DATA_WIDTH{1'b0}};
        median_d1 <= {DATA_WIDTH{1'b0}};
        median_d2 <= {DATA_WIDTH{1'b0}};
    end else begin
        median_d0 <= median_comb;
        median_d1 <= median_d0;
        median_d2 <= median_d1;
    end
end

assign target_data = median_d2;

endmodule
