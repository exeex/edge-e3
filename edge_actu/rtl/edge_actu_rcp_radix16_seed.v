`timescale 1ns/1ps

module edge_actu_rcp_radix16_seed (
  input  wire [16:0] den_q16,
  output wire [8:0]  seed_q8
);

function [3:0] select_digit;
  input [21:0] rem_shifted;
  input [16:0] den;
  integer digit;
  reg found;
  reg [31:0] product;
  reg [31:0] rem_ext;
  begin
    select_digit = 4'h0;
    found = 1'b0;
    rem_ext = {10'b0, rem_shifted};
    for (digit = 15; digit >= 0; digit = digit - 1) begin
      product = {15'b0, den} * digit;
      if (!found && (rem_ext >= product)) begin
        select_digit = digit[3:0];
        found = 1'b1;
      end
    end
  end
endfunction

wire [16:0] safe_den;
wire [21:0] rem0_shift;
wire [3:0]  digit0;
wire [21:0] rem1;
wire [21:0] rem1_shift;
wire [3:0]  digit1;
wire [21:0] rem2;
wire [8:0]  q_unrounded;
wire        round_up;
wire [21:0] safe_den_ext;

assign safe_den = (den_q16 == 17'b0) ? 17'd1 : den_q16;
assign safe_den_ext = {5'b0, safe_den};

assign rem0_shift = {1'b0, 1'b1, 16'b0, 4'b0};
assign digit0 = select_digit(rem0_shift, safe_den);
assign rem1 = rem0_shift - (safe_den * digit0);

assign rem1_shift = rem1 << 4;
assign digit1 = select_digit(rem1_shift, safe_den);
assign rem2 = rem1_shift - (safe_den * digit1);

assign q_unrounded = {1'b0, digit0, digit1};
assign round_up = ((rem2 << 1) >= safe_den_ext);
assign seed_q8 = q_unrounded + {8'b0, round_up};

endmodule
