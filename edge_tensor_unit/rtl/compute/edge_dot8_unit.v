// Compatibility wrapper around the reusable BF22 dot8 kernel.
module edge_dot8_unit(
  clk,
  rst_b,
  in_valid,
  bf16_vec_i,
  int8_vec_i,
  weight_bf16_mode_i,
  bf16_weight_vec_i,
  rsum_enable_i,
  rsum_first_i,
  rsum_last_i,
  out_valid,
  bf16_o
);

input          clk;
input          rst_b;
input          in_valid;
input  [127:0] bf16_vec_i;
input  [63:0]  int8_vec_i;
input          weight_bf16_mode_i;
input  [127:0] bf16_weight_vec_i;
input          rsum_enable_i;
input          rsum_first_i;
input          rsum_last_i;
output         out_valid;
output [15:0]  bf16_o;

wire [31:0] unused_bf22;

edge_dot8_kernel x_kernel (
  .clk                 (clk),
  .rst_b               (rst_b),
  .in_valid            (in_valid),
  .bf16_vec_i          (bf16_vec_i),
  .int8_vec_i          (int8_vec_i),
  .weight_bf16_mode_i  (weight_bf16_mode_i),
  .bf16_weight_vec_i   (bf16_weight_vec_i),
  .rsum_enable_i       (rsum_enable_i),
  .rsum_first_i        (rsum_first_i),
  .rsum_last_i         (rsum_last_i),
  .out_valid           (out_valid),
  .bf22_o              (unused_bf22),
  .bf16_o              (bf16_o)
);

endmodule
