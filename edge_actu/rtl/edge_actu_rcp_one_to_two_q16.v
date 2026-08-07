`timescale 1ns/1ps

module edge_actu_rcp_one_to_two_q16 (
  input  wire [16:0] den_q16,
  output wire [16:0] rcp_q16
);

wire [8:0]  seed_q8;
wire [16:0] y0_q16;
wire [33:0] xy_product_q32;
wire [33:0] xy_rounded_q32;
wire [17:0] xy_q16;
wire [17:0] corr_q16;
wire [34:0] y1_product_q32;
wire [34:0] y1_rounded_q32;

edge_actu_rcp_radix16_seed x_seed (
  .den_q16(den_q16),
  .seed_q8(seed_q8)
);

assign y0_q16 = {seed_q8, 8'b0};
assign xy_product_q32 = den_q16 * y0_q16;
assign xy_rounded_q32 = xy_product_q32 + 34'h0000_8000;
assign xy_q16 = xy_rounded_q32[33:16];
assign corr_q16 = 18'h2_0000 - xy_q16;
assign y1_product_q32 = y0_q16 * corr_q16;
assign y1_rounded_q32 = y1_product_q32 + 35'h0000_8000;
assign rcp_q16 = y1_rounded_q32[32:16];

endmodule
