`timescale 1ns/1ps

module edge_actu_exp2_pack_q28_fp32 (
  input  wire signed [9:0] exp2_k,
  input  wire [28:0]       mant_product_q28,
  output wire [31:0]       value_bits
);

wire signed [10:0] biased_exp;
wire               underflow;
wire               overflow;
wire [23:0]        sig_trunc;
wire [4:0]         sig_rem;
wire               sig_round_up;
wire [24:0]        sig_rounded_ext;
wire               sig_carry;
wire signed [10:0] packed_exp;
wire [23:0]        packed_sig;

assign underflow = (exp2_k < -10'sd126);
assign overflow = (exp2_k > 10'sd127);
assign biased_exp = exp2_k + 11'sd127;

assign sig_trunc = mant_product_q28[28:5];
assign sig_rem = mant_product_q28[4:0];
assign sig_round_up = (sig_rem > 5'd16) ||
                      ((sig_rem == 5'd16) && sig_trunc[0]);
assign sig_rounded_ext = {1'b0, sig_trunc} + {24'b0, sig_round_up};
assign sig_carry = sig_rounded_ext[24];
assign packed_exp = biased_exp + {10'b0, sig_carry};
assign packed_sig = sig_carry ? sig_rounded_ext[24:1] :
                    sig_rounded_ext[23:0];

assign value_bits = underflow ? 32'h0000_0000 :
                    ((overflow || (packed_exp >= 11'd255)) ? 32'h7f7f_ffff :
                     {1'b0, packed_exp[7:0], packed_sig[22:0]});

endmodule
