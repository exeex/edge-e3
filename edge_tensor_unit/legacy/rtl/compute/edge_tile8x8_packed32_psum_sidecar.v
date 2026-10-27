// Packed-weight tile sidecar with the maintained six-stage psum alignment.
module edge_tile8x8_packed32_psum_sidecar(
  clk, rst_b,
  weight_fill_valid_i, weight_fill_lane_valid_i,
  weight_fill_format_i, weight_fill_data_i,
  weight_fill_target_dot_i, weight_fill_slot_i, weight_fill_bank_i,
  weight_activate_i, weight_activate_bank_i,
  in_valid, input_bf16_i, psum_bf16_i,
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
input [127:0] input_bf16_i;
input [127:0] psum_bf16_i;
output out_valid;
output [127:0] output_bf16_o;

wire dot_valid;
wire [127:0] dot_bf16;
wire [15:0] sum_lane [0:7];
reg [127:0] psum_d0, psum_d1, psum_d2, psum_d3, psum_d4, psum_d5;
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
  .weight_fill_slot_i({4{weight_fill_slot_i}}),
  .weight_fill_bank_i(weight_fill_bank_i),
  .weight_activate_i(weight_activate_i),
  .weight_activate_bank_i(weight_activate_bank_i),
  .in_valid(in_valid), .input_bf16_i(input_bf16_i),
  .rsum_enable_i(1'b0), .rsum_first_i(1'b0), .rsum_last_i(1'b0),
  .out_valid(dot_valid), .output_bf16_o(dot_bf16)
);

generate
  genvar lane_g;
  for (lane_g=0; lane_g<8; lane_g=lane_g+1) begin : GEN_PSUM
    edge_psum x_add (
      .a_raw(dot_bf16[lane_g*16 +: 16]),
      .b_raw(psum_d5[lane_g*16 +: 16]),
      .y(sum_lane[lane_g])
    );
  end
endgenerate

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    psum_d0 <= 0; psum_d1 <= 0; psum_d2 <= 0;
    psum_d3 <= 0; psum_d4 <= 0; psum_d5 <= 0;
    output_q <= 0; output_valid_q <= 0;
  end else begin
    psum_d0 <= psum_bf16_i;
    psum_d1 <= psum_d0;
    psum_d2 <= psum_d1;
    psum_d3 <= psum_d2;
    psum_d4 <= psum_d3;
    psum_d5 <= psum_d4;
    output_valid_q <= dot_valid;
    if (dot_valid)
      output_q <= {sum_lane[7], sum_lane[6], sum_lane[5], sum_lane[4],
                   sum_lane[3], sum_lane[2], sum_lane[1], sum_lane[0]};
  end
end
endmodule
