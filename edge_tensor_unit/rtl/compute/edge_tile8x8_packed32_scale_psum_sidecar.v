// Packed-weight tile sidecar implementing scale * dot + psum.
module edge_tile8x8_packed32_scale_psum_sidecar(
  clk, rst_b,
  weight_fill_valid_i, weight_fill_lane_valid_i,
  weight_fill_format_i, weight_fill_data_i,
  weight_fill_target_dot_i, weight_fill_slot_i, weight_fill_bank_i,
  weight_activate_i, weight_activate_bank_i,
  in_valid, late_psum_mode_i, late_psum_valid_i,
  input_bf16_i, psum_bf16_i, scale_enable_i, scale_bf16_i,
  rsum_enable_i, rsum_first_i, rsum_last_i,
  dot_ready_o, out_valid, output_bf16_o
);

input clk, rst_b, weight_fill_valid_i;
input [3:0] weight_fill_lane_valid_i;
input [1:0] weight_fill_format_i;
input [127:0] weight_fill_data_i;
input [11:0] weight_fill_target_dot_i;
input [7:0] weight_fill_slot_i;
input weight_fill_bank_i, weight_activate_i, weight_activate_bank_i;
input in_valid;
input late_psum_mode_i, late_psum_valid_i;
input [127:0] input_bf16_i, psum_bf16_i;
input scale_enable_i;
input [127:0] scale_bf16_i;
input rsum_enable_i, rsum_first_i, rsum_last_i;
output out_valid;
output dot_ready_o;
output [127:0] output_bf16_o;

wire dot_valid;
wire [127:0] dot_bf16;
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
  .rsum_enable_i(rsum_enable_i), .rsum_first_i(rsum_first_i),
  .rsum_last_i(rsum_last_i),
  .out_valid(dot_valid), .output_bf16_o(dot_bf16)
);

edge_tensor_scale_psum8 x_post (
  .clk(clk), .rst_b(rst_b), .dot_valid(dot_valid), .dot_bf16(dot_bf16),
  .late_psum_mode_i(late_psum_mode_i), .late_psum_valid_i(late_psum_valid_i),
  .psum_bf16_i(psum_bf16_i), .scale_enable_i(scale_enable_i),
  .scale_bf16_i(scale_bf16_i), .rsum_enable_i(rsum_enable_i),
  .dot_ready_o(dot_ready_o), .out_valid(out_valid), .output_bf16_o(output_bf16_o)
);
endmodule
