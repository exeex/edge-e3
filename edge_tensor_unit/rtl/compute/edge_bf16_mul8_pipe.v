// Eight reusable synthesis-friendly BF16 multipliers for the Q8 scale stage.
//
// This follows the vec8dot product representation: sanitize both BF16 inputs,
// multiply two fixed 8-bit significands, and carry a signed 10-bit synthetic
// exponent into a separate normalization stage.  Keeping the product and
// exponent fixed-width avoids the generic 32-bit variable-shift arithmetic
// that previously dominated the scale path after synthesis.
module edge_bf16_mul8_pipe(
  clk,
  rst_b,
  in_valid,
  a_vec_i,
  b_vec_i,
  out_valid,
  y_vec_o
);

input          clk;
input          rst_b;
input          in_valid;
input  [127:0] a_vec_i;
input  [127:0] b_vec_i;
output         out_valid;
output [127:0] y_vec_o;

reg         s0_valid;
reg         s1_valid;
reg [15:0]  s0_a [0:7];
reg [15:0]  s0_b [0:7];
reg [15:0]  s1_product [0:7];
reg         s1_sign [0:7];
reg         s1_zero [0:7];
reg signed [9:0] s1_exp [0:7];

integer lane;
reg [7:0] a_sig_comb;
reg [7:0] b_sig_comb;

assign out_valid = s1_valid;

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

function [3:0] msb_index16;
  input [15:0] value;
  integer idx;
  begin
    msb_index16 = 4'b0;
    for (idx = 0; idx < 16; idx = idx + 1)
      if (value[idx])
        msb_index16 = idx[3:0];
  end
endfunction

// Fixed cases are intentional.  They infer the same bounded mux structure as
// vec8dot's coarse/fine alignment rather than a 32-bit barrel shifter.
function [15:0] rshift_rne16_fixed;
  input [15:0] value;
  input [4:0] amount;
  reg [15:0] quotient;
  reg guard_bit;
  reg sticky_bit;
  begin
    quotient = 16'b0;
    guard_bit = 1'b0;
    sticky_bit = 1'b0;
    case (amount)
      5'd0: quotient = value;
      5'd1: begin quotient = value >> 1; guard_bit = value[0]; end
      5'd2: begin quotient = value >> 2; guard_bit = value[1]; sticky_bit = |value[0:0]; end
      5'd3: begin quotient = value >> 3; guard_bit = value[2]; sticky_bit = |value[1:0]; end
      5'd4: begin quotient = value >> 4; guard_bit = value[3]; sticky_bit = |value[2:0]; end
      5'd5: begin quotient = value >> 5; guard_bit = value[4]; sticky_bit = |value[3:0]; end
      5'd6: begin quotient = value >> 6; guard_bit = value[5]; sticky_bit = |value[4:0]; end
      5'd7: begin quotient = value >> 7; guard_bit = value[6]; sticky_bit = |value[5:0]; end
      5'd8: begin quotient = value >> 8; guard_bit = value[7]; sticky_bit = |value[6:0]; end
      5'd9: begin quotient = value >> 9; guard_bit = value[8]; sticky_bit = |value[7:0]; end
      5'd10: begin quotient = value >> 10; guard_bit = value[9]; sticky_bit = |value[8:0]; end
      5'd11: begin quotient = value >> 11; guard_bit = value[10]; sticky_bit = |value[9:0]; end
      5'd12: begin quotient = value >> 12; guard_bit = value[11]; sticky_bit = |value[10:0]; end
      5'd13: begin quotient = value >> 13; guard_bit = value[12]; sticky_bit = |value[11:0]; end
      5'd14: begin quotient = value >> 14; guard_bit = value[13]; sticky_bit = |value[12:0]; end
      5'd15: begin quotient = value >> 15; guard_bit = value[14]; sticky_bit = |value[13:0]; end
      5'd16: begin quotient = 16'b0; guard_bit = value[15]; sticky_bit = |value[14:0]; end
      default: begin quotient = 16'b0; guard_bit = 1'b0; sticky_bit = |value; end
    endcase
    rshift_rne16_fixed = quotient
                       + {15'b0,
                          (guard_bit && (sticky_bit || quotient[0]))};
  end
endfunction

function [15:0] lshift_product_fixed;
  input [15:0] value;
  input [3:0] amount;
  begin
    case (amount)
      4'd0: lshift_product_fixed = value;
      4'd1: lshift_product_fixed = value << 1;
      4'd2: lshift_product_fixed = value << 2;
      4'd3: lshift_product_fixed = value << 3;
      4'd4: lshift_product_fixed = value << 4;
      4'd5: lshift_product_fixed = value << 5;
      4'd6: lshift_product_fixed = value << 6;
      4'd7: lshift_product_fixed = value << 7;
      4'd8: lshift_product_fixed = value << 8;
      4'd9: lshift_product_fixed = value << 9;
      4'd10: lshift_product_fixed = value << 10;
      4'd11: lshift_product_fixed = value << 11;
      4'd12: lshift_product_fixed = value << 12;
      4'd13: lshift_product_fixed = value << 13;
      4'd14: lshift_product_fixed = value << 14;
      default: lshift_product_fixed = value << 15;
    endcase
  end
endfunction

function [15:0] normalize_product_to_bf16;
  input [15:0] product;
  input signed [9:0] product_exp;
  input sign;
  input force_zero;
  reg [3:0] msb;
  reg signed [9:0] exp_field;
  reg signed [9:0] sub_shift;
  reg [15:0] rounded_right;
  reg [15:0] rounded_left;
  reg [8:0] sig_rounded;
  reg [4:0] right_amount;
  begin
    msb = msb_index16(product);
    // Match vec8dot's synthetic exponent convention exactly.  product_exp
    // already contains both biased BF16 exponents minus 134.
    exp_field = product_exp + $signed({6'b0, msb}) - 10'sd7;
    // A subnormal BF16 fraction unit is 2^-133.  Since product_exp uses
    // vec8dot's biased convention, the integer product shifts by exp-1.
    sub_shift = product_exp - 10'sd1;
    rounded_right = 16'b0;
    rounded_left = 16'b0;
    sig_rounded = 9'b0;
    right_amount = 5'b0;

    if (force_zero || product == 16'b0) begin
      normalize_product_to_bf16 = 16'h0000;
    end else if (exp_field >= 10'sd255) begin
      normalize_product_to_bf16 = sign ? 16'hff7f : 16'h7f7f;
    end else if (exp_field > 10'sd0) begin
      if (msb >= 4'd7) begin
        right_amount = {1'b0, msb} - 5'd7;
        rounded_right = rshift_rne16_fixed(product, right_amount);
        sig_rounded = rounded_right[8:0];
      end else begin
        rounded_left = lshift_product_fixed(product,
                                             {1'b0, (3'd7 - msb[2:0])});
        sig_rounded = rounded_left[8:0];
      end

      if (sig_rounded[8]) begin
        sig_rounded = {1'b0, sig_rounded[8:1]};
        exp_field = exp_field + 10'sd1;
      end

      if (exp_field >= 10'sd255)
        normalize_product_to_bf16 = sign ? 16'hff7f : 16'h7f7f;
      else
        normalize_product_to_bf16 = {sign, exp_field[7:0],
                                     sig_rounded[6:0]};
    end else begin
      if (sub_shift >= 10'sd0) begin
        rounded_left = lshift_product_fixed(product, sub_shift[3:0]);
        sig_rounded = rounded_left[8:0];
      end else if (sub_shift <= -10'sd17) begin
        sig_rounded = 9'b0;
      end else begin
        right_amount = (~sub_shift[4:0]) + 5'd1;
        rounded_right = rshift_rne16_fixed(product, right_amount);
        sig_rounded = rounded_right[8:0];
      end

      if (sig_rounded >= 9'd128)
        normalize_product_to_bf16 = {sign, 8'h01, 7'h00};
      else
        normalize_product_to_bf16 = {sign, 8'h00,
                                     sig_rounded[6:0]};
    end
  end
endfunction

genvar output_lane;
generate
  for (output_lane = 0; output_lane < 8; output_lane = output_lane + 1) begin : gen_output
    assign y_vec_o[output_lane*16 +: 16] = normalize_product_to_bf16(
        s1_product[output_lane], s1_exp[output_lane],
        s1_sign[output_lane], s1_zero[output_lane]);
  end
endgenerate

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    s0_valid <= 1'b0;
    s1_valid <= 1'b0;
    for (lane = 0; lane < 8; lane = lane + 1) begin
      s0_a[lane] <= 16'b0;
      s0_b[lane] <= 16'b0;
      s1_product[lane] <= 16'b0;
      s1_sign[lane] <= 1'b0;
      s1_zero[lane] <= 1'b1;
      s1_exp[lane] <= 10'sd0;
    end
  end else begin
    s0_valid <= in_valid;
    s1_valid <= s0_valid;
    if (in_valid) begin
      for (lane = 0; lane < 8; lane = lane + 1) begin
        s0_a[lane] <= sanitize_bf16(a_vec_i[lane*16 +: 16]);
        s0_b[lane] <= sanitize_bf16(b_vec_i[lane*16 +: 16]);
      end
    end
    if (s0_valid) begin
      for (lane = 0; lane < 8; lane = lane + 1) begin
      a_sig_comb = (s0_a[lane][14:7] == 8'b0)
                 ? {1'b0, s0_a[lane][6:0]}
                 : {1'b1, s0_a[lane][6:0]};
      b_sig_comb = (s0_b[lane][14:7] == 8'b0)
                 ? {1'b0, s0_b[lane][6:0]}
                 : {1'b1, s0_b[lane][6:0]};
      s1_product[lane] <= a_sig_comb * b_sig_comb;
      s1_sign[lane] <= s0_a[lane][15] ^ s0_b[lane][15];
      s1_zero[lane] <= (s0_a[lane][14:0] == 15'b0)
                    || (s0_b[lane][14:0] == 15'b0);
      s1_exp[lane] <= $signed({2'b0, (s0_a[lane][14:7] == 0)
                                      ? 8'd1 : s0_a[lane][14:7]})
                    + $signed({2'b0, (s0_b[lane][14:7] == 0)
                                      ? 8'd1 : s0_b[lane][14:7]})
                    - 10'sd134;
      end
    end
  end
end

endmodule
