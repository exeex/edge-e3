// Formal-WLD-compatible boundary backed by packed circular weight routing.
module edge_tensor_packed_wld_tile(
  clk, rst_b,
  start, start_ready, start_bf16_mode, start_transpose,
  busy, done,
  load_valid, load_ready, load_idx, load_data,
  weight_activate, weight_activate_ready,
  weight_active_valid, weight_pending_valid,
  compute_valid, late_psum_mode_i, late_psum_valid_i,
  input_bf16_i, psum_bf16_i,
  scale_enable_i, scale_bf16_i, rsum_enable_i, rsum_first_i, rsum_last_i,
  dot_ready_o, output_valid, output_bf16_o
);

input clk, rst_b;
input start, start_bf16_mode, start_transpose;
output start_ready, busy, done;
input load_valid;
output load_ready;
input [2:0] load_idx;
input [127:0] load_data;
input weight_activate;
output weight_activate_ready;
output weight_active_valid, weight_pending_valid;
input compute_valid;
input late_psum_mode_i, late_psum_valid_i;
input [127:0] input_bf16_i, psum_bf16_i;
input scale_enable_i;
input [127:0] scale_bf16_i;
input rsum_enable_i, rsum_first_i, rsum_last_i;
output dot_ready_o;
output output_valid;
output [127:0] output_bf16_o;

localparam WEIGHT_BF16 = 2'd0;
localparam WEIGHT_I8   = 2'd1;

wire [1:0] weight_format = start_bf16_mode ? WEIGHT_BF16 : WEIGHT_I8;

// load_idx remains at this compatibility boundary for protocol parity.  The
// circular consumes accepted beats in order, as guaranteed by the WLD client.
wire unused_load_idx = &{1'b0, load_idx};

assign busy = !start_ready;

edge_tensor_packed_bank_sidecar x_packed_bank (
  .clk(clk), .rst_b(rst_b),
  .weight_start_i(start), .weight_start_ready_o(start_ready),
  .weight_format_i(weight_format), .weight_transpose_i(start_transpose),
  .weight_load_valid_i(load_valid), .weight_load_ready_o(load_ready),
  .weight_load_data_i(load_data), .weight_drain_ready_i(1'b1),
  .weight_done_o(done),
  .weight_activate_i(weight_activate),
  .weight_activate_ready_o(weight_activate_ready),
  .weight_active_valid_o(weight_active_valid),
  .weight_pending_valid_o(weight_pending_valid),
  .compute_valid_i(compute_valid), .input_bf16_i(input_bf16_i),
  .psum_bf16_i(psum_bf16_i), .late_psum_mode_i(late_psum_mode_i),
  .late_psum_valid_i(late_psum_valid_i), .scale_enable_i(scale_enable_i),
  .scale_bf16_i(scale_bf16_i),
  .rsum_enable_i(rsum_enable_i), .rsum_first_i(rsum_first_i),
  .rsum_last_i(rsum_last_i), .dot_ready_o(dot_ready_o),
  .output_valid_o(output_valid), .output_bf16_o(output_bf16_o)
);

endmodule
