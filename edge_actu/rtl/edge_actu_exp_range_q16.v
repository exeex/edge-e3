`timescale 1ns/1ps

module edge_actu_exp_range_q16 (
  input  wire [31:0]       value_bits,
  output wire              underflow,
  output wire signed [9:0] exp2_k,
  output wire [11:0]       frac_code
);

localparam [31:0] EXP_UNDERFLOW_NEG_BITS = 32'hc2ae_0000; // -87.0
localparam [30:0] EXP_CLAMP_POS_MAG_BITS = 31'h42b0_0000; // +88.0
localparam signed [31:0] LOG2E_CODE_Q16 = 32'sd387270501;

wire        sign;
wire [7:0]  exponent;
wire [22:0] fraction;
wire [23:0] mantissa;
wire [30:0] magnitude_bits;
wire        is_zero;
wire        is_special;
wire        clamp_high;
wire signed [8:0] unbiased_exp;
wire signed [9:0] xq_shift;
wire [55:0] shifted_left;
wire [55:0] shifted_right;
wire [31:0] x_mag_q16;
wire signed [31:0] x_q16_pre;
wire signed [31:0] x_q16;
wire signed [63:0] z_product_q48;
wire signed [63:0] z_shifted;
wire signed [31:0] z_code;
wire signed [31:0] exp2_k_full;

assign sign = value_bits[31];
assign exponent = value_bits[30:23];
assign fraction = value_bits[22:0];
assign magnitude_bits = value_bits[30:0];
assign is_zero = (magnitude_bits == 31'b0);
assign is_special = (exponent == 8'hff);
assign underflow = sign && (value_bits >= EXP_UNDERFLOW_NEG_BITS);
assign clamp_high = (!sign) && (magnitude_bits >= EXP_CLAMP_POS_MAG_BITS);

assign mantissa = (exponent == 8'b0) ? {1'b0, fraction} : {1'b1, fraction};
assign unbiased_exp = (exponent == 8'b0) ? -9'sd126 :
                      ({1'b0, exponent} - 9'sd127);
assign xq_shift = unbiased_exp - 10'sd7;
assign shifted_left = {32'b0, mantissa} << xq_shift[5:0];
assign shifted_right = {32'b0, mantissa} >> ((-xq_shift) & 10'h03f);
assign x_mag_q16 = is_zero ? 32'b0 :
                   (xq_shift >= 0 ? shifted_left[31:0] :
                    shifted_right[31:0]);
assign x_q16_pre = sign ? -$signed(x_mag_q16) : $signed(x_mag_q16);
assign x_q16 = (underflow || is_special) ? 32'sd0 :
               (clamp_high ? 32'sd5767168 : x_q16_pre);

assign z_product_q48 = x_q16 * LOG2E_CODE_Q16;
assign z_shifted = z_product_q48 >>> 32;
assign z_code = z_shifted[31:0];
assign exp2_k_full = z_code >>> 12;
assign exp2_k = exp2_k_full[9:0];
assign frac_code = z_code[11:0];

endmodule
