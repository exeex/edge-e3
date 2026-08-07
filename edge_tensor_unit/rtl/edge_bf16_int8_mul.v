// Deterministic BF16 x INT8 multiplier for the Edge tensor prototype.
//
// This is a combinational, synthesizable reference datapath. It matches
// bf16_int8_mul_ref.c for round-to-nearest-even and the prototype special
// value policy: NaN -> 0, +/-Inf -> +/-BF16 max finite for non-zero INT8.

module edge_bf16_int8_mul(
  bf16_i,
  int8_i,
  bf16_o
);

input  [15:0] bf16_i;
input  [7:0]  int8_i;
output [15:0] bf16_o;

wire        a_sign;
wire [7:0]  a_exp;
wire [6:0]  a_frac;
wire        a_nan;
wire        a_inf;
wire        a_zero;
wire        w_sign;
wire [7:0]  w_mag;
wire        w_zero;
wire        prod_sign;

reg  [15:0] result;
reg  [7:0]  sig;
reg  [15:0] prod_mag;
reg  [31:0] rounded;
reg  [31:0] sub_rounded;
reg  [8:0]  sig_rounded;
reg  [8:0]  sub_sig;
reg  [4:0]  msb;
integer     scale_exp;
integer     unbiased_exp;
integer     exp_field;
integer     shift;

assign a_sign   = bf16_i[15];
assign a_exp    = bf16_i[14:7];
assign a_frac   = bf16_i[6:0];
assign a_nan    = (a_exp == 8'hff) && (a_frac != 7'b0);
assign a_inf    = (a_exp == 8'hff) && (a_frac == 7'b0);
assign a_zero   = (a_exp == 8'b0) && (a_frac == 7'b0);
assign w_sign   = int8_i[7];
assign w_mag    = w_sign ? (~int8_i + 8'b1) : int8_i;
assign w_zero   = (int8_i == 8'b0);
assign prod_sign = a_sign ^ w_sign;
assign bf16_o   = result;

function [4:0] msb_index16;
  input [15:0] value;
  integer idx;
  begin
    msb_index16 = 5'b0;
    for (idx = 0; idx < 16; idx = idx + 1) begin
      if (value[idx])
        msb_index16 = idx[4:0];
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

always @* begin
  result = 16'h0000;
  sig = 8'b0;
  prod_mag = 16'b0;
  rounded = 32'b0;
  sub_rounded = 32'b0;
  sig_rounded = 9'b0;
  sub_sig = 9'b0;
  msb = 5'b0;
  scale_exp = 0;
  unbiased_exp = 0;
  exp_field = 0;
  shift = 0;

  if (w_zero || a_nan) begin
    result = 16'h0000;
  end else if (a_zero) begin
    result = {prod_sign, 15'b0};
  end else if (a_inf) begin
    result = prod_sign ? 16'hff7f : 16'h7f7f;
  end else begin
    sig = (a_exp == 8'b0) ? {1'b0, a_frac} : {1'b1, a_frac};
    prod_mag = sig * w_mag;

    if (prod_mag == 16'b0) begin
      result = 16'h0000;
    end else begin
      msb = msb_index16(prod_mag);
      scale_exp = (a_exp == 8'b0) ? -133 : ({24'b0, a_exp} - 134);
      unbiased_exp = scale_exp + msb;

      if (unbiased_exp >= -126) begin
        exp_field = unbiased_exp + 127;
        shift = msb - 7;

        if (shift >= 0)
          rounded = rshift_rne({16'b0, prod_mag}, shift);
        else
          rounded = {16'b0, prod_mag} << (-shift);

        sig_rounded = rounded[8:0];
        if (sig_rounded[8]) begin
          sig_rounded = {1'b0, sig_rounded[8:1]};
          exp_field = exp_field + 1;
        end

        if (exp_field >= 255)
          result = prod_sign ? 16'hff7f : 16'h7f7f;
        else
          result = {prod_sign, exp_field[7:0], sig_rounded[6:0]};
      end else begin
        shift = scale_exp + 133;
        if (shift >= 0)
          sub_rounded = {16'b0, prod_mag} << shift;
        else
          sub_rounded = rshift_rne({16'b0, prod_mag}, -shift);

        sub_sig = sub_rounded[8:0];
        if (sub_sig >= 9'd128)
          result = {prod_sign, 8'h01, 7'h00};
        else
          result = {prod_sign, 8'h00, sub_sig[6:0]};
      end
    end
  end
end

endmodule
