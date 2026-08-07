module edge_fpu_fmac_narrow_fmadd(
  cpurst_b,
  forever_cpuclk,
  fmadd_cancel,
  fmadd_mul_only,
  fmadd_neg_product,
  fmadd_neg_addend,
  fmadd_rm,
  fmadd_src0,
  fmadd_src1,
  fmadd_src2,
  fmadd_result,
  fmadd_fflags
);

input           cpurst_b;
input           forever_cpuclk;
input           fmadd_cancel;
input           fmadd_mul_only;
input           fmadd_neg_product;
input           fmadd_neg_addend;
input   [2 :0]  fmadd_rm;
input   [31:0]  fmadd_src0;
input   [31:0]  fmadd_src1;
input   [31:0]  fmadd_src2;
output  [31:0]  fmadd_result;
output  [4 :0]  fmadd_fflags;

wire            add_sign;
wire            add_zero;
wire            addend_sign;
wire            any_nan;
wire            any_snan;
wire            exp_product_bigger;
wire            exp_equal;
wire            finite_carry;
wire            inf_cancel;
wire            inf_zero;
wire            mag_product_ge_addend;
wire            product_inf;
wire            product_lost_low_bits;
wire            product_sign;
wire            product_zero;
wire            same_sign;
wire            special_vld;
wire            sum_carry;
wire            wide_add_sign;
wire            wide_round_sign;
wire            wide_add_zero;
wire            wide_single_candidate;
wire            wide_single_use;
reg             special_vld_d0;
reg             special_vld_d1;
reg             wide_single_candidate_d0;
reg             wide_single_candidate_d1;
reg             mul_only_d0;
reg             mul_only_d1;
reg             product_zero_d0;
reg             product_zero_d1;
reg             product_sign_d0;
reg             product_sign_d1;
reg     [2 :0]  rm_d0;
reg     [2 :0]  rm_d1;
reg     [31:0]  special_result_d0;
reg     [31:0]  special_result_d1;
reg     [4 :0]  special_fflags_d0;
reg     [4 :0]  special_fflags_d1;
reg     [31:0]  narrow_finite_result_d0;
reg     [31:0]  narrow_finite_result_d1;
reg     [4 :0]  narrow_finite_fflags_d0;
reg     [4 :0]  narrow_finite_fflags_d1;
wire    [4 :0]  finite_fflags;
wire    [4 :0]  narrow_finite_fflags;
wire    [4 :0]  special_fflags;
wire    [4 :0]  wide_single_fflags;
wire    [4 :0]  lshift_amt;
wire    [12:0]  exp_diff;
wire    [23:0]  src0_sig;
wire    [23:0]  src1_sig;
wire    [23:0]  src2_sig;
wire    [26:0]  add_sig_grs;
wire    [26:0]  addend_sig_grs;
wire    [26:0]  diff_norm;
wire    [26:0]  mag_big;
wire    [26:0]  mag_small;
wire    [26:0]  product_aligned;
wire    [26:0]  product_shifted;
wire    [26:0]  product_sig_grs;
wire    [26:0]  result_norm;
wire    [26:0]  result_norm_sticky;
wire    [26:0]  src2_aligned;
wire    [26:0]  src2_shifted;
wire    [26:0]  sum_norm;
wire    [26:0]  raw_sub;
wire    [27:0]  raw_add;
wire    [47:0]  product;
wire    [31:0]  canonical_inf;
wire    [31:0]  canonical_qnan;
wire    [31:0]  finite_result;
wire    [31:0]  narrow_finite_result;
wire    [31:0]  special_result;
wire    [31:0]  wide_single_result;
wire    [52:0]  wide_addend_sig;
wire    [52:0]  wide_product_sig;
wire    [55:0]  wide_add_sig_grs;
wire            src0_inf;
wire            src0_qnan;
wire            src0_sign;
wire            src0_snan;
wire            src0_subnormal;
wire            src0_normal;
wire            src0_zero;
wire            src1_inf;
wire            src1_qnan;
wire            src1_sign;
wire            src1_snan;
wire            src1_subnormal;
wire            src1_normal;
wire            src1_zero;
wire            src2_inf;
wire            src2_qnan;
wire            src2_sign;
wire            src2_snan;
wire            src2_subnormal;
wire            src2_normal;
wire            src2_zero;
wire    signed [12:0] add_exp;
wire    signed [12:0] exp_big;
wire    signed [12:0] exp_norm_sub;
wire    signed [12:0] product_exp;
wire    signed [12:0] product_exp_norm;
wire    signed [12:0] src0_exp;
wire    signed [12:0] src1_exp;
wire    signed [12:0] src2_exp;
wire    signed [12:0] sum_exp;
wire    signed [12:0] wide_add_exp;
wire    signed [12:0] wide_addend_exp;
wire    signed [12:0] wide_product_exp;

function [4:0] leading_zero_count;
  input [26:0] value;
  integer i;
  reg found;
  begin
    leading_zero_count = 5'd27;
    found = 1'b0;
    for(i = 26; i >= 0; i = i - 1) begin
      if(!found && value[i]) begin
        leading_zero_count = 26 - i;
        found = 1'b1;
      end
    end
end
endfunction

function [26:0] lshift_stage8;
  input [26:0] value;
  input [4 :0] shift;
  reg   [26:0] coarse;
  begin
    case(shift[4:3])
      2'd0:    coarse = value[26:0];
      2'd1:    coarse = {value[18:0], 8'b0};
      2'd2:    coarse = {value[10:0], 16'b0};
      default: coarse = {value[2 :0], 24'b0};
    endcase

    case(shift[2:0])
      3'd0:    lshift_stage8 = coarse[26:0];
      3'd1:    lshift_stage8 = {coarse[25:0], 1'b0};
      3'd2:    lshift_stage8 = {coarse[24:0], 2'b0};
      3'd3:    lshift_stage8 = {coarse[23:0], 3'b0};
      3'd4:    lshift_stage8 = {coarse[22:0], 4'b0};
      3'd5:    lshift_stage8 = {coarse[21:0], 5'b0};
      3'd6:    lshift_stage8 = {coarse[20:0], 6'b0};
      default: lshift_stage8 = {coarse[19:0], 7'b0};
    endcase
  end
endfunction

edge_fpu_fmac_fp32_unpack x_src0_unpack (
  .src       (fmadd_src0), .sign(src0_sign), .exp(src0_exp),
  .sig       (src0_sig), .zero(src0_zero), .subnormal(src0_subnormal),
  .normal    (src0_normal), .inf(src0_inf), .qnan(src0_qnan), .snan(src0_snan)
);

edge_fpu_fmac_fp32_unpack x_src1_unpack (
  .src       (fmadd_src1), .sign(src1_sign), .exp(src1_exp),
  .sig       (src1_sig), .zero(src1_zero), .subnormal(src1_subnormal),
  .normal    (src1_normal), .inf(src1_inf), .qnan(src1_qnan), .snan(src1_snan)
);

edge_fpu_fmac_fp32_unpack x_src2_unpack (
  .src       (fmadd_src2), .sign(src2_sign), .exp(src2_exp),
  .sig       (src2_sig), .zero(src2_zero), .subnormal(src2_subnormal),
  .normal    (src2_normal), .inf(src2_inf), .qnan(src2_qnan), .snan(src2_snan)
);

assign product_sign = src0_sign ^ src1_sign ^ fmadd_neg_product;
assign addend_sign = src2_sign ^ fmadd_neg_addend;
assign any_snan = src0_snan || src1_snan || src2_snan;
assign any_nan = any_snan
              || src0_qnan
              || src1_qnan
              || src2_qnan;
assign inf_zero = (src0_inf && src1_zero)
               || (src1_inf && src0_zero);
assign product_inf = (src0_inf || src1_inf)
                  && !inf_zero
                  && !any_nan;
assign inf_cancel = product_inf
                 && src2_inf
                 && (product_sign ^ addend_sign);
assign product_zero = src0_zero || src1_zero;

assign canonical_qnan = 32'h7fc0_0000;
assign canonical_inf = {product_inf ? product_sign : addend_sign,
                        8'hff, 23'b0};

assign special_vld = any_nan
                  || inf_zero
                  || inf_cancel
                  || product_inf
                  || src2_inf;
assign special_result = (any_nan || inf_zero || inf_cancel)
                      ? canonical_qnan : canonical_inf;
assign special_fflags[4:0] = {any_snan || inf_zero || inf_cancel, 4'b0000};

assign product[47:0] = src0_sig[23:0] * src1_sig[23:0];
assign product_exp = src0_exp + src1_exp;
assign finite_carry = product[47];
assign product_exp_norm = product_exp + {12'b0, finite_carry};
assign product_lost_low_bits = !product_zero
                            && (finite_carry
                                ? |product[21:0]
                                : |product[20:0]);
assign product_sig_grs[26:0] = product_zero
                               ? 27'b0
                               : finite_carry
                                 ? {product[47:24],
                                    product[23],
                                    product[22],
                                    |product[21:0]}
                                 : {product[46:23],
                                    product[22],
                                    product[21],
                                    |product[20:0]};
assign addend_sig_grs[26:0] = src2_zero
                              ? 27'b0
                              : {src2_sig[23:0], 3'b0};

assign same_sign = product_sign == addend_sign;
assign exp_product_bigger = product_exp_norm > src2_exp;
assign exp_equal = product_exp_norm == src2_exp;
assign mag_product_ge_addend = !product_zero
                            && (src2_zero
                             || exp_product_bigger
                             || (exp_equal
                              && (product_sig_grs[26:0] >= addend_sig_grs[26:0])));
assign exp_big = mag_product_ge_addend ? product_exp_norm : src2_exp;
assign exp_diff[12:0] = mag_product_ge_addend
                        ? product_exp_norm - src2_exp
                        : src2_exp - product_exp_norm;

edge_fpu_fmac_narrow_shift_sticky_2stage  x_product_shift (
  .shift_in  (product_sig_grs[26:0]),
  .shift_amt (exp_diff[12:0]       ),
  .shift_out (product_shifted[26:0])
);

edge_fpu_fmac_narrow_shift_sticky_2stage  x_src2_shift (
  .shift_in  (addend_sig_grs[26:0] ),
  .shift_amt (exp_diff[12:0]       ),
  .shift_out (src2_shifted[26:0]   )
);

assign product_aligned[26:0] = mag_product_ge_addend
                               ? product_sig_grs[26:0]
                               : product_shifted[26:0];
assign src2_aligned[26:0] = mag_product_ge_addend
                            ? src2_shifted[26:0]
                            : addend_sig_grs[26:0];
assign mag_big[26:0] = mag_product_ge_addend
                       ? product_aligned[26:0]
                       : src2_aligned[26:0];
assign mag_small[26:0] = mag_product_ge_addend
                         ? src2_aligned[26:0]
                         : product_aligned[26:0];

assign raw_add[27:0] = {1'b0, mag_big[26:0]}
                     + {1'b0, mag_small[26:0]};
assign raw_sub[26:0] = mag_big[26:0] - mag_small[26:0];

assign sum_carry = raw_add[27];
assign sum_norm[26:0] = sum_carry
                        ? {raw_add[27:2], |raw_add[1:0]}
                        : raw_add[26:0];
assign sum_exp = exp_big + {12'b0, sum_carry};

assign add_zero = !same_sign && (raw_sub[26:0] == 27'b0);
assign lshift_amt[4:0] = leading_zero_count(raw_sub[26:0]);
assign diff_norm[26:0] = add_zero
                         ? 27'b0
                         : lshift_stage8(raw_sub[26:0], lshift_amt[4:0]);
assign exp_norm_sub = exp_big - {8'b0, lshift_amt[4:0]};

assign result_norm[26:0] = same_sign ? sum_norm[26:0] : diff_norm[26:0];
assign result_norm_sticky[26:0] = product_lost_low_bits && !add_zero
                                ? {result_norm[26:1], result_norm[0] | !add_zero}
                                : result_norm[26:0];
assign add_sign = add_zero ? (fmadd_rm == 3'b010)
                : mag_product_ge_addend ? product_sign
                : addend_sign;
assign add_exp = add_zero ? 13'sd0
               : same_sign ? sum_exp
               : exp_norm_sub;
assign add_sig_grs[26:0] = result_norm_sticky[26:0];

edge_fpu_fmac_fp32_round_pack x_round_pack (
  .sign     (add_sign), .exp(add_exp), .sig_grs(add_sig_grs),
  .rm       (fmadd_rm), .result(narrow_finite_result),
  .fflags   (narrow_finite_fflags)
);

// Single FMADD needs a fused-width align/add path; compressing the exact
// 24x24 product to 24+GRS before adding src2 loses tie/carry information.
assign wide_product_sig[52:0] = product_zero
                                ? 53'b0
                                : finite_carry
                                  ? {product[47:0], 5'b0}
                                  : {product[46:0], 6'b0};
assign wide_addend_sig[52:0] = {src2_sig[23:0], 29'b0};
assign wide_product_exp = product_exp_norm + 13'sd127;
assign wide_addend_exp = src2_exp + 13'sd127;

edge_fpu_fmac_align_add  x_wide_single_align_add (
  .cpurst_b     (cpurst_b                 ),
  .forever_cpuclk(forever_cpuclk          ),
  .align_cancel(fmadd_cancel              ),
  .op0_sign    (product_sign             ),
  .op0_exp     (wide_product_exp         ),
  .op0_sig     (wide_product_sig[52:0]   ),
  .op1_sign    (addend_sign              ),
  .op1_exp     (wide_addend_exp          ),
  .op1_sig     (wide_addend_sig[52:0]    ),
  .add_zero    (wide_add_zero            ),
  .add_sign    (wide_add_sign            ),
  .add_exp     (wide_add_exp             ),
  .add_sig_grs (wide_add_sig_grs[55:0]   )
);

edge_fpu_fmac_fp32_fused_round_pack x_wide_single_round_pack (
  .sign       (wide_round_sign), .biased_exp(wide_add_exp),
  .sig_grs    (wide_add_sig_grs), .rm(rm_d1),
  .result     (wide_single_result), .fflags(wide_single_fflags)
);

// IEEE-754 exact cancellation produces -0 only under round-down; all other
// supported static rounding modes produce +0.  Keep this decision beside the
// delayed rounding mode so the wide pipeline cannot use a younger instruction.
assign wide_round_sign = wide_add_zero ? (rm_d1 == 3'b010) : wide_add_sign;

assign wide_single_candidate = (src0_normal || src0_subnormal)
                            && (src1_normal || src1_subnormal)
                            && (src2_normal || src2_subnormal);
assign wide_single_use = wide_single_candidate_d1
                      && !wide_add_zero;
assign finite_result = wide_single_use
                     ? wide_single_result : narrow_finite_result_d1;
assign finite_fflags[4:0] = wide_single_use
                            ? wide_single_fflags[4:0]
                            : narrow_finite_fflags_d1[4:0];

always @(posedge forever_cpuclk or negedge cpurst_b) begin
  if(!cpurst_b) begin
    special_vld_d0 <= 1'b0;
    special_vld_d1 <= 1'b0;
    wide_single_candidate_d0 <= 1'b0;
    wide_single_candidate_d1 <= 1'b0;
    mul_only_d0 <= 1'b0;
    mul_only_d1 <= 1'b0;
    product_zero_d0 <= 1'b0;
    product_zero_d1 <= 1'b0;
    product_sign_d0 <= 1'b0;
    product_sign_d1 <= 1'b0;
    rm_d0 <= 3'b0;
    rm_d1 <= 3'b0;
    special_result_d0 <= 32'b0;
    special_result_d1 <= 32'b0;
    special_fflags_d0 <= 5'b0;
    special_fflags_d1 <= 5'b0;
    narrow_finite_result_d0 <= 32'b0;
    narrow_finite_result_d1 <= 32'b0;
    narrow_finite_fflags_d0 <= 5'b0;
    narrow_finite_fflags_d1 <= 5'b0;
  end else if(fmadd_cancel) begin
    special_vld_d0 <= 1'b0;
    special_vld_d1 <= 1'b0;
    wide_single_candidate_d0 <= 1'b0;
    wide_single_candidate_d1 <= 1'b0;
    mul_only_d0 <= 1'b0;
    mul_only_d1 <= 1'b0;
    product_zero_d0 <= 1'b0;
    product_zero_d1 <= 1'b0;
    product_sign_d0 <= 1'b0;
    product_sign_d1 <= 1'b0;
    rm_d0 <= 3'b0;
    rm_d1 <= 3'b0;
    special_result_d0 <= 32'b0;
    special_result_d1 <= 32'b0;
    special_fflags_d0 <= 5'b0;
    special_fflags_d1 <= 5'b0;
    narrow_finite_result_d0 <= 32'b0;
    narrow_finite_result_d1 <= 32'b0;
    narrow_finite_fflags_d0 <= 5'b0;
    narrow_finite_fflags_d1 <= 5'b0;
  end else begin
    special_vld_d0 <= special_vld;
    special_vld_d1 <= special_vld_d0;
    wide_single_candidate_d0 <= wide_single_candidate;
    wide_single_candidate_d1 <= wide_single_candidate_d0;
    mul_only_d0 <= fmadd_mul_only;
    mul_only_d1 <= mul_only_d0;
    product_zero_d0 <= product_zero;
    product_zero_d1 <= product_zero_d0;
    product_sign_d0 <= product_sign;
    product_sign_d1 <= product_sign_d0;
    rm_d0 <= fmadd_rm;
    rm_d1 <= rm_d0;
    special_result_d0 <= special_result;
    special_result_d1 <= special_result_d0;
    special_fflags_d0 <= special_fflags;
    special_fflags_d1 <= special_fflags_d0;
    narrow_finite_result_d0 <= narrow_finite_result;
    narrow_finite_result_d1 <= narrow_finite_result_d0;
    narrow_finite_fflags_d0 <= narrow_finite_fflags;
    narrow_finite_fflags_d1 <= narrow_finite_fflags_d0;
  end
end

// A multiply is represented internally as product + +0.  The generic adder
// cancellation rule chooses +0, but IEEE-754 multiplication requires the
// zero sign to remain the product sign.
assign fmadd_result = special_vld_d1 ? special_result_d1
                    : (mul_only_d1 && product_zero_d1)
                      ? {product_sign_d1, 31'b0}
                      : finite_result;
assign fmadd_fflags[4:0] = special_vld_d1
                           ? special_fflags_d1[4:0]
                           : finite_fflags[4:0];

endmodule
