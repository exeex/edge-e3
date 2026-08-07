module edge_fpu_fmac_align_add(
  cpurst_b,
  forever_cpuclk,
  align_cancel,
  op0_sign,
  op0_exp,
  op0_sig,
  op1_sign,
  op1_exp,
  op1_sig,
  add_zero,
  add_sign,
  add_exp,
  add_sig_grs
);

input           cpurst_b;
input           forever_cpuclk;
input           align_cancel;
input           op0_sign;
input   signed [12:0] op0_exp;
input   [52:0] op0_sig;
input           op1_sign;
input   signed [12:0] op1_exp;
input   [52:0] op1_sig;
output          add_zero;
output          add_sign;
output  signed [12:0] add_exp;
output  [55:0] add_sig_grs;

wire            exp0_bigger;
wire            exp_equal;
wire            mag0_ge_mag1;
wire            same_sign;
wire            sum_carry;
wire    [12:0]  exp_diff;
wire    [63:0]  op0_ext;
wire    [63:0]  op1_ext;
wire    [63:0]  big_ext;
wire    [63:0]  small_ext;
wire    [63:0]  small_coarse;
wire    [63:0]  small_aligned;
wire    [64:0]  raw_add;
wire    [63:0]  raw_sub;
wire    [63:0]  sum_norm;
wire    [63:0]  diff_norm;
wire    [63:0]  result_norm;
wire    [6 :0]  lshift_amt;
wire    signed [12:0] exp_big;
wire    signed [12:0] exp_norm_sub;
wire    signed [12:0] sum_exp;
reg             same_sign_q;
reg             mag0_ge_mag1_q;
reg             big_sign_q;
reg     [1 :0]  fine_q;
reg     [63:0]  big_q;
reg     [63:0]  small_coarse_q;
reg     signed [12:0] exp_big_q;
reg             add_zero;
reg             add_sign;
reg     signed [12:0] add_exp;
reg     [55:0]  add_sig_grs;

function [63:0] rshift_sticky_coarse;
  input [63:0] value;
  input [10:0] coarse;
  begin
    case(coarse)
      11'd0:  rshift_sticky_coarse = value;
      11'd1:  rshift_sticky_coarse = {4'b0, value[63:5], value[4] | (|value[3:0])};
      11'd2:  rshift_sticky_coarse = {8'b0, value[63:9], value[8] | (|value[7:0])};
      11'd3:  rshift_sticky_coarse = {12'b0, value[63:13], value[12] | (|value[11:0])};
      11'd4:  rshift_sticky_coarse = {16'b0, value[63:17], value[16] | (|value[15:0])};
      11'd5:  rshift_sticky_coarse = {20'b0, value[63:21], value[20] | (|value[19:0])};
      11'd6:  rshift_sticky_coarse = {24'b0, value[63:25], value[24] | (|value[23:0])};
      11'd7:  rshift_sticky_coarse = {28'b0, value[63:29], value[28] | (|value[27:0])};
      11'd8:  rshift_sticky_coarse = {32'b0, value[63:33], value[32] | (|value[31:0])};
      11'd9:  rshift_sticky_coarse = {36'b0, value[63:37], value[36] | (|value[35:0])};
      11'd10: rshift_sticky_coarse = {40'b0, value[63:41], value[40] | (|value[39:0])};
      11'd11: rshift_sticky_coarse = {44'b0, value[63:45], value[44] | (|value[43:0])};
      11'd12: rshift_sticky_coarse = {48'b0, value[63:49], value[48] | (|value[47:0])};
      11'd13: rshift_sticky_coarse = {52'b0, value[63:53], value[52] | (|value[51:0])};
      11'd14: rshift_sticky_coarse = {56'b0, value[63:57], value[56] | (|value[55:0])};
      11'd15: rshift_sticky_coarse = {60'b0, value[63:61], value[60] | (|value[59:0])};
      default: rshift_sticky_coarse = {63'b0, |value};
    endcase
  end
endfunction

function [63:0] rshift_sticky_fine;
  input [63:0] value;
  input [1 :0] fine;
  begin
    case(fine[1:0])
      2'd0:    rshift_sticky_fine = value[63:0];
      2'd1:    rshift_sticky_fine = {1'b0, value[63:2],
                                     value[1] || value[0]};
      2'd2:    rshift_sticky_fine = {2'b0, value[63:3],
                                     value[2] || (|value[1:0])};
      2'd3:    rshift_sticky_fine = {3'b0, value[63:4],
                                     value[3] || (|value[2:0])};
      default: rshift_sticky_fine = {64{1'bx}};
    endcase
  end
endfunction

function [63:0] lshift_stage8;
  input [63:0] value;
  input [6 :0] shift;
  reg   [63:0] coarse;
  begin
    case(shift[5:3])
      3'd0:    coarse = value;
      3'd1:    coarse = {value[55:0], 8'b0};
      3'd2:    coarse = {value[47:0], 16'b0};
      3'd3:    coarse = {value[39:0], 24'b0};
      3'd4:    coarse = {value[31:0], 32'b0};
      3'd5:    coarse = {value[23:0], 40'b0};
      3'd6:    coarse = {value[15:0], 48'b0};
      default: coarse = {value[7:0], 56'b0};
    endcase

    case(shift[2:0])
      3'd0:    lshift_stage8 = coarse;
      3'd1:    lshift_stage8 = {coarse[62:0], 1'b0};
      3'd2:    lshift_stage8 = {coarse[61:0], 2'b0};
      3'd3:    lshift_stage8 = {coarse[60:0], 3'b0};
      3'd4:    lshift_stage8 = {coarse[59:0], 4'b0};
      3'd5:    lshift_stage8 = {coarse[58:0], 5'b0};
      3'd6:    lshift_stage8 = {coarse[57:0], 6'b0};
      default: lshift_stage8 = {coarse[56:0], 7'b0};
    endcase
  end
endfunction

function [6:0] leading_zero_count;
  input [63:0] value;
  integer i;
  reg found;
  begin
    leading_zero_count = 7'd63;
    found = 1'b0;
    for(i = 62; i >= 0; i = i - 1) begin
      if(!found && value[i]) begin
        leading_zero_count = 62 - i;
        found = 1'b1;
      end
    end
  end
endfunction

assign same_sign = op0_sign == op1_sign;
assign exp0_bigger = op0_exp > op1_exp;
assign exp_equal = op0_exp == op1_exp;
assign mag0_ge_mag1 = exp0_bigger
                   || (exp_equal && (op0_sig[52:0] >= op1_sig[52:0]));
assign exp_big = mag0_ge_mag1 ? op0_exp : op1_exp;
assign exp_diff[12:0] = mag0_ge_mag1 ? op0_exp - op1_exp
                                      : op1_exp - op0_exp;

assign op0_ext[63:0] = {1'b0, op0_sig[52:0], 10'b0};
assign op1_ext[63:0] = {1'b0, op1_sig[52:0], 10'b0};
assign big_ext = mag0_ge_mag1 ? op0_ext : op1_ext;
assign small_ext = mag0_ge_mag1 ? op1_ext : op0_ext;
assign small_coarse = rshift_sticky_coarse(small_ext, exp_diff[12:2]);

always @(posedge forever_cpuclk or negedge cpurst_b) begin
  if(!cpurst_b) begin
    same_sign_q <= 1'b0;
    mag0_ge_mag1_q <= 1'b0;
    big_sign_q <= 1'b0;
    fine_q <= 2'b0;
    big_q <= 64'b0;
    small_coarse_q <= 64'b0;
    exp_big_q <= 13'sd0;
  end else if(align_cancel) begin
    same_sign_q <= 1'b0;
    mag0_ge_mag1_q <= 1'b0;
    big_sign_q <= 1'b0;
    fine_q <= 2'b0;
    big_q <= 64'b0;
    small_coarse_q <= 64'b0;
    exp_big_q <= 13'sd0;
  end else begin
    same_sign_q <= same_sign;
    mag0_ge_mag1_q <= mag0_ge_mag1;
    big_sign_q <= mag0_ge_mag1 ? op0_sign : op1_sign;
    fine_q <= exp_diff[1:0];
    big_q <= big_ext;
    small_coarse_q <= small_coarse;
    exp_big_q <= exp_big;
  end
end

assign small_aligned = rshift_sticky_fine(small_coarse_q, fine_q);

assign raw_add = {1'b0, big_q} + {1'b0, small_aligned};
assign raw_sub = big_q - small_aligned;

assign sum_carry = raw_add[63];
assign sum_norm = sum_carry
                ? {1'b0, raw_add[63:2], |raw_add[1:0]}
                : raw_add[63:0];
assign sum_exp = exp_big_q + {12'b0, sum_carry};

wire add_zero_pre = !same_sign_q && (raw_sub == 64'b0);
assign lshift_amt = leading_zero_count(raw_sub);
assign diff_norm = add_zero_pre ? 64'b0
                 : lshift_stage8(raw_sub, lshift_amt);
assign exp_norm_sub = exp_big_q - {6'b0, lshift_amt};

assign result_norm = same_sign_q ? sum_norm : diff_norm;

always @(posedge forever_cpuclk or negedge cpurst_b) begin
  if(!cpurst_b) begin
    add_zero <= 1'b0;
    add_sign <= 1'b0;
    add_exp <= 13'sd0;
    add_sig_grs <= 56'b0;
  end else if(align_cancel) begin
    add_zero <= 1'b0;
    add_sign <= 1'b0;
    add_exp <= 13'sd0;
    add_sig_grs <= 56'b0;
  end else begin
    add_zero <= add_zero_pre;
    add_sign <= add_zero_pre ? 1'b0 : big_sign_q;
    add_exp <= add_zero_pre ? 13'sd0
             : same_sign_q ? sum_exp : exp_norm_sub;
    add_sig_grs <= {result_norm[62:8], |result_norm[7:0]};
  end
end

endmodule
