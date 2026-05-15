// Median filter, 3 clock latency.
module median_filter_3x3 #(
    parameter DATA_WIDTH = 8
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
    output wire [DATA_WIDTH-1:0]    target_data
);

wire [DATA_WIDTH-1:0] max_data1;
wire [DATA_WIDTH-1:0] mid_data1;
wire [DATA_WIDTH-1:0] min_data1;
wire [DATA_WIDTH-1:0] max_data2;
wire [DATA_WIDTH-1:0] mid_data2;
wire [DATA_WIDTH-1:0] min_data2;
wire [DATA_WIDTH-1:0] max_data3;
wire [DATA_WIDTH-1:0] mid_data3;
wire [DATA_WIDTH-1:0] min_data3;
wire [DATA_WIDTH-1:0] max_min_data;
wire [DATA_WIDTH-1:0] mid_mid_data;
wire [DATA_WIDTH-1:0] min_max_data;

sort3 #(.DATA_WIDTH(DATA_WIDTH)) u_sort3_1 (
    .clk      (clk),
    .rst_n    (rst_n),
    .data1    (data11),
    .data2    (data12),
    .data3    (data13),
    .max_data (max_data1),
    .mid_data (mid_data1),
    .min_data (min_data1)
);

sort3 #(.DATA_WIDTH(DATA_WIDTH)) u_sort3_2 (
    .clk      (clk),
    .rst_n    (rst_n),
    .data1    (data21),
    .data2    (data22),
    .data3    (data23),
    .max_data (max_data2),
    .mid_data (mid_data2),
    .min_data (min_data2)
);

sort3 #(.DATA_WIDTH(DATA_WIDTH)) u_sort3_3 (
    .clk      (clk),
    .rst_n    (rst_n),
    .data1    (data31),
    .data2    (data32),
    .data3    (data33),
    .max_data (max_data3),
    .mid_data (mid_data3),
    .min_data (min_data3)
);

sort3 #(.DATA_WIDTH(DATA_WIDTH)) u_sort3_4 (
    .clk      (clk),
    .rst_n    (rst_n),
    .data1    (max_data1),
    .data2    (max_data2),
    .data3    (max_data3),
    .max_data (),
    .mid_data (),
    .min_data (max_min_data)
);

sort3 #(.DATA_WIDTH(DATA_WIDTH)) u_sort3_5 (
    .clk      (clk),
    .rst_n    (rst_n),
    .data1    (mid_data1),
    .data2    (mid_data2),
    .data3    (mid_data3),
    .max_data (),
    .mid_data (mid_mid_data),
    .min_data ()
);

sort3 #(.DATA_WIDTH(DATA_WIDTH)) u_sort3_6 (
    .clk      (clk),
    .rst_n    (rst_n),
    .data1    (min_data1),
    .data2    (min_data2),
    .data3    (min_data3),
    .max_data (min_max_data),
    .mid_data (),
    .min_data ()
);

sort3 #(.DATA_WIDTH(DATA_WIDTH)) u_sort3_7 (
    .clk      (clk),
    .rst_n    (rst_n),
    .data1    (max_min_data),
    .data2    (mid_mid_data),
    .data3    (min_max_data),
    .max_data (),
    .mid_data (target_data),
    .min_data ()
);

endmodule
