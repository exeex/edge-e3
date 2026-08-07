`timescale 1ns/1ps

module edge_actu_rcp_lut_nr_fp32 (
  input  wire [31:0] value_bits,
  output wire [31:0] rcp_bits
);

wire        sign;
wire [7:0]  exponent;
wire [22:0] fraction;
wire [30:0] magnitude_bits;
wire        is_zero;
wire        is_special;
wire signed [9:0] unbiased_exp;
wire [16:0] den_q16;
wire [16:0] rcp_mant_q16;
wire        mant_is_one;
wire [17:0] norm_sig_q16;
wire signed [10:0] out_exp_unbiased;
wire signed [10:0] out_biased_exp;
wire        underflow;
wire        overflow;
wire [22:0] frac_bits;
wire [15:0] fraction_round_base;
wire        fraction_round_up;
wire [16:0] fraction_rounded;

assign sign = value_bits[31];
assign exponent = value_bits[30:23];
assign fraction = value_bits[22:0];
assign magnitude_bits = value_bits[30:0];
assign is_zero = (magnitude_bits == 31'b0);
assign is_special = (exponent == 8'hff);
assign unbiased_exp = {2'b0, exponent} - 10'sd127;

assign fraction_round_base = fraction[22:7];
assign fraction_round_up = fraction[6] && (|fraction[5:0] || fraction[7]);
assign fraction_rounded = {1'b0, fraction_round_base} + {16'b0, fraction_round_up};
assign den_q16 = 17'h1_0000 + fraction_rounded;

edge_actu_rcp_one_to_two_q16 x_rcp (
  .den_q16(den_q16),
  .rcp_q16(rcp_mant_q16)
);

assign mant_is_one = (rcp_mant_q16 == 17'h1_0000);
assign norm_sig_q16 = mant_is_one ? 18'h1_0000 : {rcp_mant_q16, 1'b0};
assign out_exp_unbiased = mant_is_one ?
                          -$signed({unbiased_exp[9], unbiased_exp}) :
                          (-$signed({unbiased_exp[9], unbiased_exp}) - 11'sd1);
assign out_biased_exp = out_exp_unbiased + 11'sd127;
assign underflow = is_zero || is_special || (out_biased_exp <= 11'sd0);
assign overflow = (out_biased_exp >= 11'sd255);
assign frac_bits = norm_sig_q16[15:0] << 7;

assign rcp_bits = underflow ? 32'h0000_0000 :
                  (overflow ? {sign, 8'hfe, 23'h7fffff} :
                   {sign, out_biased_exp[7:0], frac_bits});

endmodule
