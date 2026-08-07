`timescale 1ns/1ps

module edge_actu_exp2_split_core (
  input  wire signed [9:0] exp2_k,
  input  wire [11:0]       frac_code,
  output wire [31:0]       value_bits
);

wire [14:0] mant_q14;
wire [28:0] mant_product_q28;

edge_actu_exp2_split_mant_q14 x_mant (
  .frac_code(frac_code),
  .mant_product_q28(mant_product_q28),
  .mant_q14(mant_q14)
);

edge_actu_exp2_pack_q28_fp32 x_pack (
  .exp2_k(exp2_k),
  .mant_product_q28(mant_product_q28),
  .value_bits(value_bits)
);

endmodule
