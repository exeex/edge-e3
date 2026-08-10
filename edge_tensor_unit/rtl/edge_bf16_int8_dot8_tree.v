// Pairwise BF16 x INT8 dot8 row for the Edge tensor prototype.
//
// This variant keeps a signed two's-complement internal mantissa and reduces
// lanes through a pipelined exponent-aligned adder tree. It is intended for
// resource/timing comparison against edge_dot8_unit.

module edge_bf16_int8_dot8_tree(
  clk,
  rst_b,
  in_valid,
  bf16_vec_i,
  int8_vec_i,
  out_valid,
  bf16_o
);

parameter MANT_WIDTH = 20;
parameter GUARD_BITS = 1;

input          clk;
input          rst_b;
input          in_valid;
input  [127:0] bf16_vec_i;
input  [63:0]  int8_vec_i;
output         out_valid;
output [15:0]  bf16_o;

reg                     s0_valid;
reg                     s1_valid;
reg                     s2_valid;
reg                     s3_valid;
reg                     s4_valid;
reg [7:0]               s0_exp [0:7];
reg signed [MANT_WIDTH-1:0] s0_mant [0:7];
reg [7:0]               s1_exp [0:3];
reg signed [MANT_WIDTH-1:0] s1_mant [0:3];
reg [7:0]               s2_exp [0:1];
reg signed [MANT_WIDTH-1:0] s2_mant [0:1];
reg [7:0]               s3_exp;
reg signed [MANT_WIDTH-1:0] s3_mant;
reg [15:0]              s4_bf16;

integer i;
reg [15:0] lane;
reg [7:0]  sig_comb;
reg [7:0]  wmag_comb;
reg [15:0] prod_comb;
reg signed [MANT_WIDTH-1:0] mant_comb;

assign out_valid = s4_valid;
assign bf16_o = s4_bf16;

function [15:0] sanitize_bf16;
  input [15:0] value;
  begin
    if ((value[14:7] == 8'hff) && (value[6:0] != 7'b0))
      sanitize_bf16 = 16'h0000;
    else if ((value[14:0] == 15'h7f80))
      sanitize_bf16 = value[15] ? 16'hff7f : 16'h7f7f;
    else
      sanitize_bf16 = value;
  end
endfunction

function signed [MANT_WIDTH-1:0] align_mant;
  input signed [MANT_WIDTH-1:0] mant;
  input [7:0] diff;
  begin
    if (diff >= MANT_WIDTH[7:0])
      align_mant = {MANT_WIDTH{1'b0}};
    else
      align_mant = mant >>> diff;
  end
endfunction

function [MANT_WIDTH+7:0] merge_pair;
  input [7:0] exp_a;
  input signed [MANT_WIDTH-1:0] mant_a;
  input [7:0] exp_b;
  input signed [MANT_WIDTH-1:0] mant_b;
  reg [7:0] exp_o;
  reg signed [MANT_WIDTH-1:0] mant_o;
  begin
    exp_o = (exp_a >= exp_b) ? exp_a : exp_b;
    mant_o = align_mant(mant_a, exp_o - exp_a)
           + align_mant(mant_b, exp_o - exp_b);
    merge_pair = {exp_o, mant_o[MANT_WIDTH-1:0]};
  end
endfunction

function [4:0] msb_index24;
  input [MANT_WIDTH-1:0] value;
  integer idx;
  begin
    msb_index24 = 5'b0;
    for (idx = 0; idx < MANT_WIDTH; idx = idx + 1) begin
      if (value[idx])
        msb_index24 = idx[4:0];
    end
  end
endfunction

function [31:0] rshift_rne;
  input [31:0] value;
  input integer amount;
  reg [31:0] quotient;
  reg [31:0] remainder;
  reg [31:0] half;
  reg [31:0] mask;
  begin
    if (amount <= 0) begin
      rshift_rne = value;
    end else if (amount >= 31) begin
      rshift_rne = 32'b0;
    end else begin
      quotient = value >> amount;
      mask = (32'h1 << amount) - 32'h1;
      remainder = value & mask;
      half = 32'h1 << (amount - 1);
      rshift_rne = quotient
                 + ((remainder > half)
                    || ((remainder == half) && quotient[0]));
    end
  end
endfunction

function [15:0] normalize_tree_to_bf16;
  input signed [MANT_WIDTH-1:0] sum;
  input [7:0] exp_base;
  reg sign;
  reg [MANT_WIDTH-1:0] mag;
  reg [4:0] msb;
  reg [31:0] rounded;
  reg [8:0] sig;
  reg [8:0] sub_sig;
  integer exp_field;
  integer shift;
  begin
    if (sum == {MANT_WIDTH{1'b0}}) begin
      normalize_tree_to_bf16 = 16'h0000;
    end else begin
      sign = sum[MANT_WIDTH-1];
      mag = sign ? -sum : sum;
      msb = msb_index24(mag);
      exp_field = {24'b0, exp_base} + msb - GUARD_BITS - 7;

      if (exp_field >= 255) begin
        normalize_tree_to_bf16 = sign ? 16'hff7f : 16'h7f7f;
      end else if (exp_field <= 0) begin
        shift = {24'b0, exp_base} - GUARD_BITS - 1;
        if (shift >= 0)
          rounded = {8'b0, mag} << shift;
        else
          rounded = rshift_rne({8'b0, mag}, -shift);
        sub_sig = rounded[8:0];
        if (sub_sig >= 9'd128)
          normalize_tree_to_bf16 = {sign, 8'h01, 7'h00};
        else
          normalize_tree_to_bf16 = {sign, 8'h00, sub_sig[6:0]};
      end else begin
        shift = msb - GUARD_BITS - 14;
        if (shift >= 0)
          rounded = rshift_rne({8'b0, mag}, shift);
        else
          rounded = {8'b0, mag} << (-shift);

        sig = rounded[8:0];
        if (sig >= 9'd256) begin
          sig = {1'b0, sig[8:1]};
          exp_field = exp_field + 1;
        end

        if (exp_field >= 255)
          normalize_tree_to_bf16 = sign ? 16'hff7f : 16'h7f7f;
        else
          normalize_tree_to_bf16 = {sign, exp_field[7:0], sig[6:0]};
      end
    end
  end
endfunction

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    s0_valid <= 1'b0;
    s1_valid <= 1'b0;
    s2_valid <= 1'b0;
    s3_valid <= 1'b0;
    s4_valid <= 1'b0;
    s3_exp <= 8'b0;
    s3_mant <= {MANT_WIDTH{1'b0}};
    s4_bf16 <= 16'b0;
  end else begin
    s0_valid <= in_valid;
    s1_valid <= s0_valid;
    s2_valid <= s1_valid;
    s3_valid <= s2_valid;
    s4_valid <= s3_valid;

    for (i = 0; i < 8; i = i + 1) begin
      lane = sanitize_bf16(bf16_vec_i[i*16 +: 16]);
      sig_comb = (lane[14:7] == 8'b0) ? {1'b0, lane[6:0]}
                                      : {1'b1, lane[6:0]};
      wmag_comb = int8_vec_i[i*8 + 7] ? (~int8_vec_i[i*8 +: 8] + 8'b1)
                                      : int8_vec_i[i*8 +: 8];
      prod_comb = sig_comb * wmag_comb;
      mant_comb = {{(MANT_WIDTH-16-GUARD_BITS){1'b0}},
                   prod_comb[15:0],
                   {GUARD_BITS{1'b0}}};
      if (lane[15] ^ int8_vec_i[i*8 + 7])
        mant_comb = -mant_comb;
      if ((lane[14:0] == 15'b0) || (int8_vec_i[i*8 +: 8] == 8'b0))
        mant_comb = {MANT_WIDTH{1'b0}};
      s0_exp[i] <= lane[14:7];
      s0_mant[i] <= mant_comb;
    end

    for (i = 0; i < 4; i = i + 1) begin
      {s1_exp[i], s1_mant[i]} <= merge_pair(s0_exp[i*2],
                                             s0_mant[i*2],
                                             s0_exp[i*2+1],
                                             s0_mant[i*2+1]);
    end

    for (i = 0; i < 2; i = i + 1) begin
      {s2_exp[i], s2_mant[i]} <= merge_pair(s1_exp[i*2],
                                             s1_mant[i*2],
                                             s1_exp[i*2+1],
                                             s1_mant[i*2+1]);
    end

    {s3_exp, s3_mant} <= merge_pair(s2_exp[0], s2_mant[0],
                                    s2_exp[1], s2_mant[1]);
    s4_bf16 <= normalize_tree_to_bf16(s3_mant, s3_exp);
  end
end

endmodule
