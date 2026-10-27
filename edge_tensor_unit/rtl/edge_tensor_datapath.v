// E3 packed WLD relay ingress through final local banks and scale * dot + psum.
module edge_tensor_datapath #(parameter SCALE_BF20=0)(
  clk, rst_b,
  weight_start_i, weight_start_ready_o,
  weight_format_i, weight_transpose_i,
  weight_load_valid_i, weight_load_ready_o, weight_load_data_i,
  weight_drain_ready_i, weight_done_o,
  weight_fill_bank_i, weight_activate_i, weight_activate_bank_i,
  compute_valid_i, input_bf16_i, psum_bf16_i,
  late_psum_mode_i, late_psum_valid_i,
  scale_enable_i, scale_bf16_i, scale_extra_i,
  rsum_enable_i, rsum_first_i, rsum_last_i,
  dot_ready_o, output_valid_o, output_bf16_o,
  wide_enable_i, psum_fp32_i, output_fp32_o
);

input wide_enable_i;
input [255:0] psum_fp32_i;
output [255:0] output_fp32_o;
input clk, rst_b;
input weight_start_i;
output weight_start_ready_o;
input [2:0] weight_format_i;
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
input [31:0] scale_extra_i;
input rsum_enable_i, rsum_first_i, rsum_last_i;
output dot_ready_o;
output output_valid_o;
output [127:0] output_bf16_o;

generate begin : GEN_DOT_RELAY
wire [1023:0] active_weights;
wire [7:0] dot_valid;
wire [127:0] dot_bf16;
wire [255:0] dot_fp32;
edge_tensor_weights x_weights(
 .clk(clk),.rst_b(rst_b),.weight_start_i(weight_start_i),.weight_start_ready_o(weight_start_ready_o),
 .weight_format_i(weight_format_i),.weight_transpose_i(weight_transpose_i),
 .weight_load_valid_i(weight_load_valid_i),.weight_load_ready_o(weight_load_ready_o),
 .weight_load_data_i(weight_load_data_i),.weight_drain_ready_i(weight_drain_ready_i),
 .weight_done_o(weight_done_o),.busy_o(),.weight_fill_bank_i(weight_fill_bank_i),
 .weight_activate_i(weight_activate_i),.weight_activate_bank_i(weight_activate_bank_i),
 .active_weights_o(active_weights));
genvar dot;
for(dot=0;dot<8;dot=dot+1)begin : GEN_DOT
 edge_dot_kernel x_kernel(
  .clk(clk),.rst_b(rst_b),.in_valid(compute_valid_i),.bf16_vec_i(input_bf16_i),.int8_vec_i(64'b0),
  .weight_bf16_mode_i(1'b1),.bf16_weight_vec_i(active_weights[dot*128+:128]),.weight_exp_vec_i(64'b0),
  .external_product_vec_i(128'b0),.external_product_sign_i(8'b0),
  .rsum_enable_i(rsum_enable_i),.rsum_first_i(rsum_first_i),.rsum_last_i(rsum_last_i),
  .out_valid(dot_valid[dot]),.bf22_o(dot_fp32[dot*32+:32]),.bf16_o(dot_bf16[dot*16+:16]));
end
edge_tensor_scale_psum8 #(.SCALE_BF20(SCALE_BF20)) x_post(
 .clk(clk),.rst_b(rst_b),.dot_valid(dot_valid[0]),.dot_bf16(dot_bf16), .dot_fp32_i(dot_fp32),
 .late_psum_mode_i(late_psum_mode_i),.late_psum_valid_i(late_psum_valid_i),
 .wide_enable_i(wide_enable_i), .psum_fp32_i(psum_fp32_i), .output_fp32_o(output_fp32_o),
      .psum_bf16_i(psum_bf16_i),.scale_enable_i(scale_enable_i),.scale_bf16_i(scale_bf16_i),
  .scale_extra_i(SCALE_BF20 ? scale_extra_i : 32'b0),
 .rsum_enable_i(rsum_enable_i),.dot_ready_o(dot_ready_o),.out_valid(output_valid_o),.output_bf16_o(output_bf16_o));
end endgenerate
endmodule
