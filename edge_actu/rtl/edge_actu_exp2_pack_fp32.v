`timescale 1ns/1ps

module edge_actu_exp2_pack_fp32 (
  input  wire signed [9:0] exp2_k,
  input  wire [14:0]       mant_q14,
  output wire [31:0]       value_bits
);

wire signed [10:0] biased_exp;
wire [22:0]        frac_bits;
wire               underflow;
wire               overflow;

assign biased_exp = exp2_k + 11'sd127;
assign frac_bits = mant_q14[13:0] << 9;
assign underflow = (exp2_k < -10'sd126);
assign overflow = (exp2_k > 10'sd127);

assign value_bits = underflow ? 32'h0000_0000 :
                    (overflow ? 32'h7f7f_ffff :
                     {1'b0, biased_exp[7:0], frac_bits});

endmodule
