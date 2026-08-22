// Smallest arithmetic leaf used by the BF16 dot lane: an 8x8 significand
// multiply between explicit input and output pipeline registers.
module edge_bf16_sig_mul_probe (
  input         clk,
  input         rst_b,
  input         in_valid,
  input  [7:0]  lhs_sig_i,
  input  [7:0]  rhs_sig_i,
  output reg    out_valid,
  output reg [15:0] product_o
);

reg       valid_q;
reg [7:0] lhs_sig_q;
reg [7:0] rhs_sig_q;

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    valid_q   <= 1'b0;
    lhs_sig_q <= 8'b0;
    rhs_sig_q <= 8'b0;
    out_valid <= 1'b0;
    product_o <= 16'b0;
  end else begin
    valid_q   <= in_valid;
    lhs_sig_q <= lhs_sig_i;
    rhs_sig_q <= rhs_sig_i;
    out_valid <= valid_q;
    product_o <= lhs_sig_q * rhs_sig_q;
  end
end

endmodule
