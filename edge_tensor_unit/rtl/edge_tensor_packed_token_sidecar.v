// Packed tensor sidecar with explicit fresh-load/reuse weight tokens.
module edge_tensor_packed_token_sidecar(
  clk, rst_b,
  weight_start_i, weight_start_ready_o,
  weight_format_i, weight_transpose_i,
  weight_load_valid_i, weight_load_ready_o, weight_load_data_i,
  weight_drain_ready_i, weight_done_o,
  weight_reuse_i, weight_reuse_ready_o,
  weight_token_valid_o, weight_token_reuse_o, weight_token_consume_i,
  weight_active_valid_o,
  compute_valid_i, input_bf16_i, psum_bf16_i,
  scale_enable_i, scale_bf16_i,
  output_valid_o, output_bf16_o
);

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
input weight_reuse_i;
output weight_reuse_ready_o;
output weight_token_valid_o, weight_token_reuse_o;
input weight_token_consume_i;
output weight_active_valid_o;
input compute_valid_i;
input [127:0] input_bf16_i, psum_bf16_i;
input scale_enable_i;
input [127:0] scale_bf16_i;
output output_valid_o;
output [127:0] output_bf16_o;

reg reuse_token_q;
wire inner_start_ready;
wire activate_ready;
wire active_valid;
wire pending_valid;
wire reuse_accept = weight_reuse_i && weight_reuse_ready_o;
wire consume_accept = weight_token_consume_i && weight_token_valid_o;
wire consume_fresh = consume_accept && pending_valid;

assign weight_start_ready_o = inner_start_ready && !reuse_token_q;
assign weight_reuse_ready_o = active_valid && !pending_valid
                            && !reuse_token_q && inner_start_ready;
assign weight_token_valid_o = pending_valid || reuse_token_q;
assign weight_token_reuse_o = reuse_token_q;
assign weight_active_valid_o = active_valid;

edge_tensor_packed_bank_sidecar x_bank_owner (
  .clk(clk), .rst_b(rst_b),
  .weight_start_i(weight_start_i && weight_start_ready_o),
  .weight_start_ready_o(inner_start_ready),
  .weight_format_i(weight_format_i),
  .weight_transpose_i(weight_transpose_i),
  .weight_load_valid_i(weight_load_valid_i),
  .weight_load_ready_o(weight_load_ready_o),
  .weight_load_data_i(weight_load_data_i),
  .weight_drain_ready_i(weight_drain_ready_i), .weight_done_o(weight_done_o),
  .weight_activate_i(consume_fresh),
  .weight_activate_ready_o(activate_ready),
  .weight_active_valid_o(active_valid),
  .weight_pending_valid_o(pending_valid),
  .compute_valid_i(compute_valid_i), .input_bf16_i(input_bf16_i),
  .psum_bf16_i(psum_bf16_i),
  .late_psum_mode_i(1'b0), .late_psum_valid_i(1'b1),
  .scale_enable_i(scale_enable_i),
  .scale_bf16_i(scale_bf16_i),
  .rsum_enable_i(1'b0), .rsum_first_i(1'b0), .rsum_last_i(1'b0),
  .dot_ready_o(),
  .output_valid_o(output_valid_o), .output_bf16_o(output_bf16_o)
);

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    reuse_token_q <= 1'b0;
  end else begin
    if (reuse_accept)
      reuse_token_q <= 1'b1;
    if (consume_accept && reuse_token_q)
      reuse_token_q <= 1'b0;
  end
end

wire unused_activate_ready = activate_ready;
endmodule
