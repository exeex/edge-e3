module edge_bf16_add_comb(
  a_raw,
  b_raw,
  y
);

input  [15:0] a_raw;
input  [15:0] b_raw;
output [15:0] y;

assign y[15:0] = bf16_add(a_raw[15:0], b_raw[15:0]);

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

function [15:0] rshift_rne16;
  input [15:0] value;
  input [7:0]  amount;
  reg [15:0] quotient;
  reg [15:0] remainder;
  reg [15:0] half;
  reg [15:0] mask;
  begin
    if (amount == 8'b0) begin
      rshift_rne16 = value;
    end else if (amount >= 8'd15) begin
      rshift_rne16 = 16'b0;
    end else begin
      quotient = value >> amount;
      mask = (16'h1 << amount) - 16'h1;
      remainder = value & mask;
      half = 16'h1 << (amount - 1'b1);
      rshift_rne16 = quotient
                   + ((remainder > half)
                      || ((remainder == half) && quotient[0]));
    end
  end
endfunction

function [3:0] msb_index11;
  input [10:0] value;
  integer idx;
  begin
    msb_index11 = 4'b0;
    for (idx = 0; idx < 11; idx = idx + 1) begin
      if (value[idx])
        msb_index11 = idx[3:0];
    end
  end
endfunction

function [15:0] normalize_add_sum_to_bf16;
  input signed [10:0] sum;
  input [7:0] exp_base;
  reg sign;
  reg [10:0] mag;
  reg [3:0]  msb;
  reg [15:0] rounded;
  reg [8:0]  sig;
  reg [8:0]  sub_sig;
  integer exp_field;
  integer shift;
  begin
    if (sum == 11'sd0) begin
      normalize_add_sum_to_bf16 = 16'h0000;
    end else begin
      sign = sum[10];
      mag = sign ? -sum : sum;
      msb = msb_index11(mag);
      exp_field = {24'b0, exp_base} + msb - 7;

      if (exp_field >= 255) begin
        normalize_add_sum_to_bf16 = sign ? 16'hff7f : 16'h7f7f;
      end else if (exp_field <= 0) begin
        shift = {24'b0, exp_base} - 1;
        if (shift >= 0)
          rounded = {5'b0, mag} << shift;
        else
          rounded = rshift_rne16({5'b0, mag}, -shift);
        sub_sig = rounded[8:0];
        if (sub_sig >= 9'd128)
          normalize_add_sum_to_bf16 = {sign, 8'h01, 7'h00};
        else
          normalize_add_sum_to_bf16 = {sign, 8'h00, sub_sig[6:0]};
      end else begin
        shift = msb - 7;
        if (shift >= 0)
          rounded = rshift_rne16({5'b0, mag}, shift);
        else
          rounded = {5'b0, mag} << (-shift);

        sig = rounded[8:0];
        if (sig >= 9'd256) begin
          sig = {1'b0, sig[8:1]};
          exp_field = exp_field + 1;
        end

        if (exp_field >= 255)
          normalize_add_sum_to_bf16 = sign ? 16'hff7f : 16'h7f7f;
        else
          normalize_add_sum_to_bf16 = {sign, exp_field[7:0], sig[6:0]};
      end
    end
  end
endfunction

function [15:0] bf16_add;
  input [15:0] a_raw_in;
  input [15:0] b_raw_in;
  reg [15:0] a;
  reg [15:0] b;
  reg [7:0]  exp_a;
  reg [7:0]  exp_b;
  reg [7:0]  exp_o;
  reg [7:0]  sig_a;
  reg [7:0]  sig_b;
  reg [15:0] aligned_a;
  reg [15:0] aligned_b;
  reg signed [10:0] signed_a;
  reg signed [10:0] signed_b;
  reg signed [10:0] signed_sum;
  begin
    a = sanitize_bf16(a_raw_in);
    b = sanitize_bf16(b_raw_in);
    exp_a = a[14:7];
    exp_b = b[14:7];
    exp_o = (exp_a >= exp_b) ? exp_a : exp_b;
    sig_a = (exp_a == 8'b0) ? {1'b0, a[6:0]} : {1'b1, a[6:0]};
    sig_b = (exp_b == 8'b0) ? {1'b0, b[6:0]} : {1'b1, b[6:0]};
    aligned_a = rshift_rne16({8'b0, sig_a}, exp_o - exp_a);
    aligned_b = rshift_rne16({8'b0, sig_b}, exp_o - exp_b);
    signed_a = {3'b0, aligned_a[7:0]};
    signed_b = {3'b0, aligned_b[7:0]};
    if (a[15])
      signed_a = -signed_a;
    if (b[15])
      signed_b = -signed_b;
    signed_sum = signed_a + signed_b;
    bf16_add = normalize_add_sum_to_bf16(signed_sum, exp_o);
  end
endfunction

endmodule
