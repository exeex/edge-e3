// Packed-weight tile sidecar implementing scale * dot + psum.
module edge_tile8x8_packed32_scale_psum_sidecar(
  clk, rst_b,
  weight_fill_valid_i, weight_fill_lane_valid_i,
  weight_fill_format_i, weight_fill_data_i,
  weight_fill_target_dot_i, weight_fill_slot_i, weight_fill_bank_i,
  weight_activate_i, weight_activate_bank_i,
  in_valid, input_bf16_i, psum_bf16_i, scale_enable_i, scale_bf16_i,
  out_valid, output_bf16_o
);

input clk, rst_b, weight_fill_valid_i;
input [3:0] weight_fill_lane_valid_i;
input [1:0] weight_fill_format_i;
input [127:0] weight_fill_data_i;
input [11:0] weight_fill_target_dot_i;
input [1:0] weight_fill_slot_i;
input weight_fill_bank_i, weight_activate_i, weight_activate_bank_i;
input in_valid;
input [127:0] input_bf16_i, psum_bf16_i;
input scale_enable_i;
input [127:0] scale_bf16_i;
output out_valid;
output [127:0] output_bf16_o;

wire dot_valid;
wire [127:0] dot_bf16;
wire scaled_mul_valid;
wire [127:0] scaled_mul_bf16;
wire [15:0] bypass_sum_lane [0:7];
wire [15:0] scaled_sum_lane [0:7];
reg [127:0] psum_d0, psum_d1, psum_d2, psum_d3, psum_d4, psum_d5;
reg [127:0] scale_d0, scale_d1, scale_d2, scale_d3, scale_d4, scale_d5;
reg scale_enable_d0, scale_enable_d1, scale_enable_d2;
reg scale_enable_d3, scale_enable_d4, scale_enable_d5;
reg [127:0] scaled_psum_d0, scaled_psum_d1;
reg [127:0] output_q;
reg output_valid_q;

assign out_valid = output_valid_q;
assign output_bf16_o = output_q;

edge_tile8x8_packed32_sidecar x_dot_tile (
  .clk(clk), .rst_b(rst_b),
  .weight_fill_valid_i(weight_fill_valid_i),
  .weight_fill_lane_valid_i(weight_fill_lane_valid_i),
  .weight_fill_format_i(weight_fill_format_i),
  .weight_fill_data_i(weight_fill_data_i),
  .weight_fill_target_dot_i(weight_fill_target_dot_i),
  .weight_fill_slot_i(weight_fill_slot_i),
  .weight_fill_bank_i(weight_fill_bank_i),
  .weight_activate_i(weight_activate_i),
  .weight_activate_bank_i(weight_activate_bank_i),
  .in_valid(in_valid), .input_bf16_i(input_bf16_i),
  .out_valid(dot_valid), .output_bf16_o(dot_bf16)
);

edge_bf16_mul8_pipe x_scale_mul (
  .clk(clk), .rst_b(rst_b),
  .in_valid(dot_valid && scale_enable_d5),
  .a_vec_i(dot_bf16), .b_vec_i(scale_d5),
  .out_valid(scaled_mul_valid), .y_vec_o(scaled_mul_bf16)
);

generate
  genvar lane_g;
  for (lane_g=0; lane_g<8; lane_g=lane_g+1) begin : GEN_SUM
    edge_psum x_bypass_add (
      .a_raw(dot_bf16[lane_g*16 +: 16]),
      .b_raw(psum_d5[lane_g*16 +: 16]),
      .y(bypass_sum_lane[lane_g])
    );
    edge_psum x_scaled_add (
      .a_raw(scaled_mul_bf16[lane_g*16 +: 16]),
      .b_raw(scaled_psum_d1[lane_g*16 +: 16]),
      .y(scaled_sum_lane[lane_g])
    );
  end
endgenerate

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    psum_d0<=0; psum_d1<=0; psum_d2<=0; psum_d3<=0; psum_d4<=0; psum_d5<=0;
    scale_d0<=0; scale_d1<=0; scale_d2<=0; scale_d3<=0; scale_d4<=0; scale_d5<=0;
    scale_enable_d0<=0; scale_enable_d1<=0; scale_enable_d2<=0;
    scale_enable_d3<=0; scale_enable_d4<=0; scale_enable_d5<=0;
    scaled_psum_d0<=0; scaled_psum_d1<=0;
    output_q<=0; output_valid_q<=0;
  end else begin
    psum_d0<=psum_bf16_i; psum_d1<=psum_d0; psum_d2<=psum_d1;
    psum_d3<=psum_d2; psum_d4<=psum_d3; psum_d5<=psum_d4;
    scale_d0<=scale_bf16_i; scale_d1<=scale_d0; scale_d2<=scale_d1;
    scale_d3<=scale_d2; scale_d4<=scale_d3; scale_d5<=scale_d4;
    scale_enable_d0<=scale_enable_i; scale_enable_d1<=scale_enable_d0;
    scale_enable_d2<=scale_enable_d1; scale_enable_d3<=scale_enable_d2;
    scale_enable_d4<=scale_enable_d3; scale_enable_d5<=scale_enable_d4;
    scaled_psum_d0<=psum_d5;
    scaled_psum_d1<=scaled_psum_d0;

    output_valid_q <= (dot_valid && !scale_enable_d5) || scaled_mul_valid;
    if (scaled_mul_valid)
      output_q <= {scaled_sum_lane[7], scaled_sum_lane[6],
                   scaled_sum_lane[5], scaled_sum_lane[4],
                   scaled_sum_lane[3], scaled_sum_lane[2],
                   scaled_sum_lane[1], scaled_sum_lane[0]};
    else if (dot_valid && !scale_enable_d5)
      output_q <= {bypass_sum_lane[7], bypass_sum_lane[6],
                   bypass_sum_lane[5], bypass_sum_lane[4],
                   bypass_sum_lane[3], bypass_sum_lane[2],
                   bypass_sum_lane[1], bypass_sum_lane[0]};
  end
end
endmodule
