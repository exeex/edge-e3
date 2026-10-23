// Packed tensor sidecar with automatic double-bank ownership.
module edge_tensor_packed_bank_sidecar #(parameter RELAY_WEIGHT=2)(
  clk, rst_b,
  weight_start_i, weight_start_ready_o,
  weight_format_i, weight_transpose_i,
  weight_load_valid_i, weight_load_ready_o, weight_load_data_i,
  weight_drain_ready_i, weight_done_o,
  weight_activate_i, weight_activate_ready_o,
  weight_active_valid_o, weight_pending_valid_o,
  compute_valid_i, input_bf16_i, psum_bf16_i,
  late_psum_mode_i, late_psum_valid_i,
  scale_enable_i, scale_bf16_i,
  rsum_enable_i, rsum_first_i, rsum_last_i,
  dot_ready_o, output_valid_o, output_bf16_o
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
input weight_activate_i;
output weight_activate_ready_o;
output weight_active_valid_o, weight_pending_valid_o;
input compute_valid_i;
input [127:0] input_bf16_i, psum_bf16_i;
input late_psum_mode_i, late_psum_valid_i;
input scale_enable_i;
input [127:0] scale_bf16_i;
input rsum_enable_i, rsum_first_i, rsum_last_i;
output dot_ready_o;
output output_valid_o;
output [127:0] output_bf16_o;

reg active_bank_q;
reg active_valid_q;
reg fill_bank_q;
reg pending_bank_q;
reg pending_valid_q;
wire inner_start_ready;
wire inner_done;
wire start_accept = weight_start_i && weight_start_ready_o;
wire activate_accept = weight_activate_i && weight_activate_ready_o;

// Completion must first be claimed by this owner. During inner_done the
// pending bit has not clocked yet; accepting a new load could overwrite the
// just-completed bank, or choose the wrong bank on simultaneous activation.
assign weight_start_ready_o = inner_start_ready && !pending_valid_q && !inner_done;
assign weight_activate_ready_o = pending_valid_q || inner_done;
assign weight_active_valid_o = active_valid_q;
assign weight_pending_valid_o = pending_valid_q;
assign weight_done_o = inner_done;

edge_tensor_packed_sidecar #(.RELAY_WEIGHT(RELAY_WEIGHT)) x_packed (
  .clk(clk), .rst_b(rst_b),
  .weight_start_i(weight_start_i && weight_start_ready_o),
  .weight_start_ready_o(inner_start_ready),
  .weight_format_i(weight_format_i),
  .weight_transpose_i(weight_transpose_i),
  .weight_load_valid_i(weight_load_valid_i),
  .weight_load_ready_o(weight_load_ready_o),
  .weight_load_data_i(weight_load_data_i),
  .weight_drain_ready_i(weight_drain_ready_i), .weight_done_o(inner_done),
  .weight_fill_bank_i(fill_bank_q),
  .weight_activate_i(activate_accept),
  .weight_activate_bank_i(inner_done ? fill_bank_q : pending_bank_q),
  .compute_valid_i(compute_valid_i), .input_bf16_i(input_bf16_i),
  .psum_bf16_i(psum_bf16_i), .late_psum_mode_i(late_psum_mode_i),
  .late_psum_valid_i(late_psum_valid_i), .scale_enable_i(scale_enable_i),
  .scale_bf16_i(scale_bf16_i),
  .rsum_enable_i(rsum_enable_i), .rsum_first_i(rsum_first_i),
  .rsum_last_i(rsum_last_i), .dot_ready_o(dot_ready_o),
  .output_valid_o(output_valid_o), .output_bf16_o(output_bf16_o)
);

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    active_bank_q <= 1'b0;
    active_valid_q <= 1'b0;
    fill_bank_q <= 1'b1;
    pending_bank_q <= 1'b0;
    pending_valid_q <= 1'b0;
  end else begin
    if (start_accept)
      fill_bank_q <= !active_bank_q;

    if (inner_done) begin
      pending_bank_q <= fill_bank_q;
      pending_valid_q <= 1'b1;
    end

    if (activate_accept) begin
      active_bank_q <= inner_done ? fill_bank_q : pending_bank_q;
      active_valid_q <= 1'b1;
      pending_valid_q <= 1'b0;
    end
  end
end
endmodule
