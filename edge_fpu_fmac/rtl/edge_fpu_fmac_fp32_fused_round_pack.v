module edge_fpu_fmac_fp32_fused_round_pack(
  input                    sign,
  input signed [12:0]      biased_exp,
  input        [55:0]      sig_grs,
  input        [2:0]       rm,
  output       [31:0]      result,
  output       [4:0]       fflags
);

function [55:0] rshift_sticky;
  input [55:0] value;
  input [12:0] shift;
  reg [55:0] coarse;
  begin
    if(shift >= 13'd56)
      rshift_sticky = {55'b0, |value};
    else begin
      case(shift[5:3])
        3'd0: coarse = value;
        3'd1: coarse = {8'b0, value[55:9], value[8] | (|value[7:0])};
        3'd2: coarse = {16'b0, value[55:17], value[16] | (|value[15:0])};
        3'd3: coarse = {24'b0, value[55:25], value[24] | (|value[23:0])};
        3'd4: coarse = {32'b0, value[55:33], value[32] | (|value[31:0])};
        3'd5: coarse = {40'b0, value[55:41], value[40] | (|value[39:0])};
        default: coarse = {48'b0, value[55:49], value[48] | (|value[47:0])};
      endcase
      case(shift[2:0])
        3'd0: rshift_sticky = coarse;
        3'd1: rshift_sticky = {1'b0, coarse[55:2], coarse[1] | coarse[0]};
        3'd2: rshift_sticky = {2'b0, coarse[55:3], coarse[2] | (|coarse[1:0])};
        3'd3: rshift_sticky = {3'b0, coarse[55:4], coarse[3] | (|coarse[2:0])};
        3'd4: rshift_sticky = {4'b0, coarse[55:5], coarse[4] | (|coarse[3:0])};
        3'd5: rshift_sticky = {5'b0, coarse[55:6], coarse[5] | (|coarse[4:0])};
        3'd6: rshift_sticky = {6'b0, coarse[55:7], coarse[6] | (|coarse[5:0])};
        default: rshift_sticky = {7'b0, coarse[55:8], coarse[7] | (|coarse[6:0])};
      endcase
    end
  end
endfunction

wire [12:0] subnormal_shift = biased_exp <= 13'sd0
                            ? 13'd1 - biased_exp : 13'd0;
wire [55:0] rounded_sig = rshift_sticky(sig_grs, subnormal_shift);
wire [23:0] main = rounded_sig[55:32];
wire guard_bit = rounded_sig[31];
wire round_bit = rounded_sig[30];
wire sticky_bit = |rounded_sig[29:0];
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
wire [7:0] out_exp = biased_exp[7:0] + {{7{1'b0}}, carry};
wire exact_zero = !(|sig_grs);
wire overflow = (biased_exp >= 13'sd255)
             || ((biased_exp == 13'sd254) && carry);
wire subnormal_to_normal = (biased_exp <= 13'sd0) && rounded[23];
wire underflow = !overflow && !exact_zero && inexact
              && (biased_exp <= 13'sd0) && !subnormal_to_normal;
wire round_to_inf = rne || rmm || (rup && !sign) || (rdn && sign);
wire [31:0] finite_result = biased_exp > 13'sd0
                          ? {sign, out_exp,
                             carry ? rounded[23:1] : rounded[22:0]}
                          : {sign, subnormal_to_normal ? 8'd1 : 8'd0,
                             rounded[22:0]};

assign result = overflow
              ? (round_to_inf ? {sign, 8'hff, 23'b0}
                                : {sign, 8'hfe, 23'h7f_ffff})
              : finite_result;
assign fflags = {1'b0, 1'b0, overflow, underflow,
                 overflow || inexact};

endmodule
