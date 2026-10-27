// Compatibility wrapper around the reusable BF22 dot8 kernel.
module edge_dot8_unit #(
  parameter EXTERNAL_WEIGHT_EXP = 0
)(
  clk,
  rst_b,
  in_valid,
  bf16_vec_i,
  int8_vec_i,
  weight_bf16_mode_i,
  bf16_weight_vec_i,
  weight_exp_vec_i,
  rsum_enable_i,
  rsum_first_i,
  rsum_last_i,
  out_valid,
  bf16_o, bf22_o
);

input          clk;
input          rst_b;
input          in_valid;
input  [127:0] bf16_vec_i;
input  [63:0]  int8_vec_i;
input          weight_bf16_mode_i;
input  [127:0] bf16_weight_vec_i;
input  [63:0]  weight_exp_vec_i;
input          rsum_enable_i;
input          rsum_first_i;
input          rsum_last_i;
output         out_valid;
output [15:0]  bf16_o;

output [31:0] bf22_o;

edge_dot_kernel #(.EXTERNAL_WEIGHT_EXP(EXTERNAL_WEIGHT_EXP)) x_kernel (
  .clk                 (clk),
  .rst_b               (rst_b),
  .in_valid            (in_valid),
  .bf16_vec_i          (bf16_vec_i),
  .int8_vec_i          (int8_vec_i),
  .weight_bf16_mode_i  (weight_bf16_mode_i),
  .bf16_weight_vec_i   (bf16_weight_vec_i),
  .weight_exp_vec_i    (weight_exp_vec_i),
  .external_product_vec_i(128'b0),
  .external_product_sign_i(8'b0),
  .rsum_enable_i       (rsum_enable_i),
  .rsum_first_i        (rsum_first_i),
  .rsum_last_i         (rsum_last_i),
  .out_valid           (out_valid),
  .bf22_o              (bf22_o),
  .bf16_o              (bf16_o)
);

endmodule
