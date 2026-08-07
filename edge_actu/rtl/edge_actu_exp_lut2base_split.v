`timescale 1ns/1ps

module edge_actu_exp_lut2base_split (
  input  wire [31:0] value_bits,
  output wire [31:0] exp_bits
);

wire              underflow;
wire signed [9:0] exp2_k;
wire [11:0]       frac_code;
wire [31:0]       exp2_bits;

edge_actu_exp_range_q16 x_range (
  .value_bits(value_bits),
  .underflow(underflow),
  .exp2_k(exp2_k),
  .frac_code(frac_code)
);

edge_actu_exp2_split_core x_exp2 (
  .exp2_k(exp2_k),
  .frac_code(frac_code),
  .value_bits(exp2_bits)
);

assign exp_bits = underflow ? 32'b0 : exp2_bits;

endmodule
