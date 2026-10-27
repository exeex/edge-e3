// Fixed packed-WLD product tile boundary.
module edge_tensor_tile_backend #(parameter SCALE_BF20=0)(
  clk, rst_b,
  compute_valid, late_psum_mode_i, late_psum_valid_i,
  input_bf16_i, psum_bf16_i, scale_enable_i, scale_bf16_i, scale_extra_i,
  rsum_enable_i, rsum_first_i, rsum_last_i,
  packed_start_i, packed_start_ready_o, packed_wtype_i,
  packed_transpose_i, packed_busy_o, packed_done_o,
  packed_load_valid_i, packed_load_ready_o, packed_load_idx_i,
  packed_load_data_i,
  weight_activate_i, weight_activate_ready_o,
  weight_fill_busy_o, weight_active_valid_o, weight_pending_valid_o,
  dot_ready_o, output_valid_o, output_bf16_o,
  wide_enable_i, psum_fp32_i, output_fp32_o
);

input wide_enable_i;
input [255:0] psum_fp32_i;
output [255:0] output_fp32_o;
input clk, rst_b;
input compute_valid, late_psum_mode_i, late_psum_valid_i;
input [127:0] input_bf16_i, psum_bf16_i;
input scale_enable_i;
input [127:0] scale_bf16_i;
input [31:0] scale_extra_i;
input rsum_enable_i, rsum_first_i, rsum_last_i;
input packed_start_i, packed_transpose_i;
input [3:0] packed_wtype_i;
output packed_start_ready_o, packed_busy_o, packed_done_o;
input packed_load_valid_i;
output packed_load_ready_o;
input [2:0] packed_load_idx_i;
input [127:0] packed_load_data_i;
input weight_activate_i;
output weight_activate_ready_o, weight_fill_busy_o;
output weight_active_valid_o, weight_pending_valid_o;
output dot_ready_o, output_valid_o;
output [127:0] output_bf16_o;

generate begin : GEN_PACKED
    wire packed_active_valid, packed_pending_valid;
    edge_tensor_wld_tile #(.SCALE_BF20(SCALE_BF20)) x_tile (
      .clk(clk), .rst_b(rst_b),
      .start(packed_start_i), .start_ready(packed_start_ready_o),
      .start_wtype(packed_wtype_i),
      .start_transpose(packed_transpose_i),
      .busy(packed_busy_o), .done(packed_done_o),
      .load_valid(packed_load_valid_i), .load_ready(packed_load_ready_o),
      .load_idx(packed_load_idx_i), .load_data(packed_load_data_i),
      .weight_activate(weight_activate_i),
      .weight_activate_ready(weight_activate_ready_o),
      .weight_active_valid(packed_active_valid),
      .weight_pending_valid(packed_pending_valid),
      .compute_valid(compute_valid), .late_psum_mode_i(late_psum_mode_i),
      .late_psum_valid_i(late_psum_valid_i), .input_bf16_i(input_bf16_i),
      .wide_enable_i(wide_enable_i), .psum_fp32_i(psum_fp32_i), .output_fp32_o(output_fp32_o),
      .psum_bf16_i(psum_bf16_i), .scale_enable_i(scale_enable_i),
      .scale_bf16_i(scale_bf16_i),
  .scale_extra_i(SCALE_BF20 ? scale_extra_i : 32'b0), .rsum_enable_i(rsum_enable_i),
      .rsum_first_i(rsum_first_i), .rsum_last_i(rsum_last_i),
      .dot_ready_o(dot_ready_o), .output_valid(output_valid_o),
      .output_bf16_o(output_bf16_o)
    );
    assign weight_fill_busy_o = packed_busy_o;
    assign weight_active_valid_o = packed_active_valid;
    assign weight_pending_valid_o = packed_pending_valid;
  end
endgenerate
endmodule
