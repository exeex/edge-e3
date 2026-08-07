module edge_fpu_fmac_fp32_round_pack(
  input                    sign,
  input signed [12:0]      exp,
  input        [26:0]      sig_grs,
  input        [2:0]       rm,
  output       [31:0]      result,
  output       [4:0]       fflags
);

function [26:0] rshift_sticky;
  input [26:0] value;
  input [12:0] shift;
  reg [26:0] coarse;
  begin
    if (shift >= 13'd27) begin
      rshift_sticky = {26'b0, |value};
    end else begin
      case (shift[4:3])
        2'd0: coarse = value;
        2'd1: coarse = {8'b0, value[26:9], value[8] || (|value[7:0])};
        2'd2: coarse = {16'b0, value[26:17], value[16] || (|value[15:0])};
        default: coarse = {24'b0, value[26:25], value[24] || (|value[23:0])};
      endcase
      case (shift[2:0])
        3'd0: rshift_sticky = coarse;
        3'd1: rshift_sticky = {1'b0, coarse[26:2], coarse[1] || coarse[0]};
        3'd2: rshift_sticky = {2'b0, coarse[26:3], coarse[2] || (|coarse[1:0])};
        3'd3: rshift_sticky = {3'b0, coarse[26:4], coarse[3] || (|coarse[2:0])};
        3'd4: rshift_sticky = {4'b0, coarse[26:5], coarse[4] || (|coarse[3:0])};
        3'd5: rshift_sticky = {5'b0, coarse[26:6], coarse[5] || (|coarse[4:0])};
        3'd6: rshift_sticky = {6'b0, coarse[26:7], coarse[6] || (|coarse[5:0])};
        default: rshift_sticky = {7'b0, coarse[26:8], coarse[7] || (|coarse[6:0])};
      endcase
    end
  end
endfunction

wire exact_zero = !(|sig_grs);
wire subnormal = !exact_zero && (exp < -13'sd126);
wire [12:0] sub_shift = -13'sd126 - exp;
wire [26:0] rounded_sig = subnormal
                        ? rshift_sticky(sig_grs, sub_shift) : sig_grs;
wire [23:0] main = rounded_sig[26:3];
wire guard_bit = rounded_sig[2];
wire round_bit = rounded_sig[1];
wire sticky_bit = rounded_sig[0];
wire inexact = guard_bit || round_bit || sticky_bit;
wire rne = rm == 3'b000;
wire rmm = rm == 3'b100;
wire rdn = rm == 3'b010;
wire rup = rm == 3'b011;
wire increment = (rne && guard_bit && (round_bit || sticky_bit || main[0]))
               || (rmm && guard_bit)
               || (rup && !sign && inexact)
               || (rdn && sign && inexact);
wire [24:0] rounded = {1'b0, main} + {{24{1'b0}}, increment};
wire carry = rounded[24];
wire normal_from_sub = subnormal && rounded[23];
wire signed [12:0] out_exp_full = exp + 13'sd127 + {{12{1'b0}}, carry};
wire [7:0] out_exp = out_exp_full[7:0];
wire overflow = (exp > 13'sd127) || ((exp == 13'sd127) && carry);
wire round_to_inf = rne || rmm || (rup && !sign) || (rdn && sign);
wire tiny = subnormal && !normal_from_sub;
wire underflow = tiny && inexact;
wire [31:0] normal_result = {sign, out_exp,
                             carry ? rounded[23:1] : rounded[22:0]};
wire [31:0] subnormal_result = normal_from_sub
                              ? {sign, 8'h01, 23'b0}
                              : {sign, 8'h00, rounded[22:0]};
wire [31:0] overflow_result = round_to_inf
                             ? {sign, 8'hff, 23'b0}
                             : {sign, 8'hfe, 23'h7f_ffff};

assign result = overflow ? overflow_result
              : exact_zero ? {sign, 31'b0}
              : subnormal ? subnormal_result
              : normal_result;
assign fflags = {1'b0, 1'b0, overflow, underflow, overflow || inexact};

endmodule
