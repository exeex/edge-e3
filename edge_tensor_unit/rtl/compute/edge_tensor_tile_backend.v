// Selectable legacy-fill or packed-raw-WLD tensor tile backend.
module edge_tensor_tile_backend #(
  parameter PACKED_WEIGHT = 0,
  parameter RELAY_WEIGHT = 2
)(
  clk, rst_b,
  compute_valid, late_psum_mode_i, late_psum_valid_i,
  input_bf16_i, psum_bf16_i, scale_enable_i, scale_bf16_i,
  rsum_enable_i, rsum_first_i, rsum_last_i,
  legacy_fill_bf16_mode_i, legacy_fill_start_i,
  legacy_fill_start_ready_o, legacy_fill_valid_i, legacy_fill_ready_o,
  legacy_fill_pair_idx_i, legacy_fill_data_i, legacy_fill_last_i,
  packed_start_i, packed_start_ready_o, packed_wtype_i,
  packed_transpose_i, packed_busy_o, packed_done_o,
  packed_load_valid_i, packed_load_ready_o, packed_load_idx_i,
  packed_load_data_i,
  weight_activate_i, weight_activate_ready_o,
  weight_fill_busy_o, weight_active_valid_o, weight_pending_valid_o,
  dot_ready_o, output_valid_o, output_bf16_o
);

input clk, rst_b;
input compute_valid, late_psum_mode_i, late_psum_valid_i;
input [127:0] input_bf16_i, psum_bf16_i;
input scale_enable_i;
input [127:0] scale_bf16_i;
input rsum_enable_i, rsum_first_i, rsum_last_i;
input legacy_fill_bf16_mode_i, legacy_fill_start_i, legacy_fill_valid_i;
output legacy_fill_start_ready_o, legacy_fill_ready_o;
input [1:0] legacy_fill_pair_idx_i;
input [127:0] legacy_fill_data_i;
input legacy_fill_last_i;
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

generate
  if (PACKED_WEIGHT) begin : GEN_PACKED
    wire packed_active_valid, packed_pending_valid;
    edge_tensor_packed_wld_tile #(.RELAY_WEIGHT(RELAY_WEIGHT)) x_tile (
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
      .psum_bf16_i(psum_bf16_i), .scale_enable_i(scale_enable_i),
      .scale_bf16_i(scale_bf16_i), .rsum_enable_i(rsum_enable_i),
      .rsum_first_i(rsum_first_i), .rsum_last_i(rsum_last_i),
      .dot_ready_o(dot_ready_o), .output_valid(output_valid_o),
      .output_bf16_o(output_bf16_o)
    );
    assign legacy_fill_start_ready_o = 1'b0;
    assign legacy_fill_ready_o = 1'b0;
    assign weight_fill_busy_o = packed_busy_o;
    assign weight_active_valid_o = packed_active_valid;
    assign weight_pending_valid_o = packed_pending_valid;
  end else begin : GEN_LEGACY
    edge_tile8x8_unit x_tile (
      .clk(clk), .rst_b(rst_b), .compute_valid(compute_valid),
      .late_psum_mode_i(late_psum_mode_i),
      .late_psum_valid_i(late_psum_valid_i),
      .input_bf16_i(input_bf16_i), .psum_bf16_i(psum_bf16_i),
      .scale_enable_i(scale_enable_i), .scale_bf16_i(scale_bf16_i),
      .rsum_enable_i(rsum_enable_i), .rsum_first_i(rsum_first_i),
      .rsum_last_i(rsum_last_i),
      .weight_fill_bf16_mode_i(legacy_fill_bf16_mode_i),
      .weight_fill_start(legacy_fill_start_i),
      .weight_fill_start_ready(legacy_fill_start_ready_o),
      .weight_fill_valid(legacy_fill_valid_i),
      .weight_fill_ready(legacy_fill_ready_o),
      .weight_fill_pair_idx(legacy_fill_pair_idx_i),
      .weight_fill_data(legacy_fill_data_i),
      .weight_fill_last(legacy_fill_last_i),
      .weight_activate(weight_activate_i),
      .weight_activate_ready(weight_activate_ready_o),
      .weight_fill_busy(weight_fill_busy_o),
      .weight_active_valid(weight_active_valid_o),
      .weight_pending_valid(weight_pending_valid_o),
      .dot_ready_o(dot_ready_o), .output_valid(output_valid_o),
      .output_bf16_o(output_bf16_o)
    );
    assign packed_start_ready_o = 1'b0;
    assign packed_busy_o = 1'b0;
    assign packed_done_o = 1'b0;
    assign packed_load_ready_o = 1'b0;
  end
endgenerate

endmodule
