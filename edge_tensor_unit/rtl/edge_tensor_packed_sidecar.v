// Complete packed-weight tensor sidecar through scale * dot + psum.
module edge_tensor_packed_sidecar(
  clk, rst_b,
  weight_start_i, weight_start_ready_o,
  weight_format_i, weight_transpose_i,
  weight_load_valid_i, weight_load_ready_o, weight_load_data_i,
  weight_drain_ready_i, weight_done_o,
  weight_fill_bank_i, weight_activate_i, weight_activate_bank_i,
  compute_valid_i, input_bf16_i, psum_bf16_i,
  late_psum_mode_i, late_psum_valid_i,
  scale_enable_i, scale_bf16_i,
  rsum_enable_i, rsum_first_i, rsum_last_i,
  dot_ready_o, output_valid_o, output_bf16_o
);

input clk, rst_b;
input weight_start_i;
output weight_start_ready_o;
input [1:0] weight_format_i;
input weight_transpose_i;
input weight_load_valid_i;
output weight_load_ready_o;
input [127:0] weight_load_data_i;
input weight_drain_ready_i;
output weight_done_o;
input weight_fill_bank_i, weight_activate_i, weight_activate_bank_i;
input compute_valid_i;
input [127:0] input_bf16_i, psum_bf16_i;
input late_psum_mode_i, late_psum_valid_i;
input scale_enable_i;
input [127:0] scale_bf16_i;
input rsum_enable_i, rsum_first_i, rsum_last_i;
output dot_ready_o;
output output_valid_o;
output [127:0] output_bf16_o;

wire drain_valid;
wire [127:0] drain_data;
wire [3:0] drain_lane_valid;
wire [1:0] drain_format, drain_slot;
wire [11:0] drain_target_dot;

edge_weight_circular4 x_weight_circular (
  .clk(clk), .rst_b(rst_b),
  .start(weight_start_i), .start_ready(weight_start_ready_o),
  .start_weight_format(weight_format_i),
  .start_transpose(weight_transpose_i), .busy(), .done(weight_done_o),
  .load_valid(weight_load_valid_i), .load_ready(weight_load_ready_o),
  .load_data(weight_load_data_i),
  .drain_valid(drain_valid), .drain_ready(weight_drain_ready_i),
  .drain_data(drain_data), .drain_lane_valid(drain_lane_valid),
  .drain_weight_format(drain_format),
  .drain_target_dot(drain_target_dot), .drain_fill_slot(drain_slot)
);

edge_tile8x8_packed32_scale_psum_sidecar x_tile (
  .clk(clk), .rst_b(rst_b),
  .weight_fill_valid_i(drain_valid && weight_drain_ready_i),
  .weight_fill_lane_valid_i(drain_lane_valid),
  .weight_fill_format_i(drain_format), .weight_fill_data_i(drain_data),
  .weight_fill_target_dot_i(drain_target_dot),
  .weight_fill_slot_i(drain_slot), .weight_fill_bank_i(weight_fill_bank_i),
  .weight_activate_i(weight_activate_i),
  .weight_activate_bank_i(weight_activate_bank_i),
  .in_valid(compute_valid_i), .input_bf16_i(input_bf16_i),
  .late_psum_mode_i(late_psum_mode_i),
  .late_psum_valid_i(late_psum_valid_i),
  .psum_bf16_i(psum_bf16_i),
  .scale_enable_i(scale_enable_i), .scale_bf16_i(scale_bf16_i),
  .rsum_enable_i(rsum_enable_i), .rsum_first_i(rsum_first_i),
  .rsum_last_i(rsum_last_i), .dot_ready_o(dot_ready_o),
  .out_valid(output_valid_o), .output_bf16_o(output_bf16_o)
);
endmodule
