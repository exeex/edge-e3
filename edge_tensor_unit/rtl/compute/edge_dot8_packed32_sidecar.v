// Experimental dot8 wrapper that converts packed weights only at local fill.
module edge_dot8_packed32_sidecar(
  clk, rst_b,
  weight_fill_valid_i, weight_fill_format_i, weight_fill_slot_i,
  weight_fill_data_i, weight_fill_bank_i,
  weight_activate_i, weight_activate_bank_i,
  in_valid, input_bf16_i, rsum_enable_i, rsum_first_i, rsum_last_i,
  out_valid, result_bf16_o
);

input          clk;
input          rst_b;
input          weight_fill_valid_i;
input  [1:0]   weight_fill_format_i;
input  [1:0]   weight_fill_slot_i;
input  [31:0]  weight_fill_data_i;
input          weight_fill_bank_i;
input          weight_activate_i;
input          weight_activate_bank_i;
input          in_valid;
input  [127:0] input_bf16_i;
input          rsum_enable_i, rsum_first_i, rsum_last_i;
output         out_valid;
output [15:0]  result_bf16_o;

wire [127:0] active_weight;
wire [31:0] unused_bf22;

edge_dot8_weight_bank_packed32 x_weight_bank (
  .clk(clk), .rst_b(rst_b),
  .fill_valid_i(weight_fill_valid_i),
  .fill_format_i(weight_fill_format_i), .fill_slot_i(weight_fill_slot_i),
  .fill_data_i(weight_fill_data_i), .fill_bank_i(weight_fill_bank_i),
  .activate_i(weight_activate_i), .activate_bank_i(weight_activate_bank_i),
  .active_weight_o(active_weight)
);

edge_dot8_kernel x_kernel (
  .clk(clk), .rst_b(rst_b), .in_valid(in_valid),
  .bf16_vec_i(input_bf16_i), .int8_vec_i(64'b0),
  .weight_bf16_mode_i(1'b1), .bf16_weight_vec_i(active_weight),
  .rsum_enable_i(rsum_enable_i), .rsum_first_i(rsum_first_i),
  .rsum_last_i(rsum_last_i),
  .out_valid(out_valid), .bf22_o(unused_bf22), .bf16_o(result_bf16_o)
);

endmodule
