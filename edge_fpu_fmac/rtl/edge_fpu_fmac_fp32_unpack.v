module edge_fpu_fmac_fp32_unpack(
  input  [31:0] src,
  output        sign,
  output signed [12:0] exp,
  output [23:0] sig,
  output        zero,
  output        subnormal,
  output        normal,
  output        inf,
  output        qnan,
  output        snan
);

wire exp_zero = !(|src[30:23]);
wire exp_ones = &src[30:23];
wire frac_nonzero = |src[22:0];
reg [4:0] lzc;
integer i;
reg found;

always @* begin
  lzc = 5'd23;
  found = 1'b0;
  for (i = 22; i >= 0; i = i - 1) begin
    if (!found && src[i]) begin
      lzc = 22 - i;
      found = 1'b1;
    end
  end
end

assign sign = src[31];
assign zero = exp_zero && !frac_nonzero;
assign subnormal = exp_zero && frac_nonzero;
assign inf = exp_ones && !frac_nonzero;
assign qnan = exp_ones && frac_nonzero && src[22];
assign snan = exp_ones && frac_nonzero && !src[22];
assign normal = !exp_zero && !exp_ones;
assign exp = exp_zero
             ? (-13'sd127 - {8'b0, lzc})
             : ({5'b0, src[30:23]} - 13'sd127);
assign sig = exp_zero
             ? ({1'b0, src[22:0]} << (lzc + 5'd1))
             : {1'b1, src[22:0]};

endmodule
