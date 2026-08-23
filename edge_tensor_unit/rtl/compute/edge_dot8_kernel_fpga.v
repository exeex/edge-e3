// Xilinx-oriented dot8 wrapper. Arithmetic and latency match edge_dot_kernel;
// the significand multipliers and signed aligned-product adder tree request
// DSP mapping while retaining the generic kernel hierarchy and arithmetic.
module edge_dot8_kernel_fpga #(
  parameter PARTIAL_ONLY = 0
)(
  input wire clk,input wire rst_b,input wire in_valid,
  input wire [127:0]bf16_vec_i,input wire [63:0]int8_vec_i,
  input wire weight_bf16_mode_i,input wire [127:0]bf16_weight_vec_i,
  input wire rsum_enable_i,input wire rsum_first_i,input wire rsum_last_i,
  output wire out_valid,output wire [31:0]bf22_o,output wire [15:0]bf16_o,
  output wire partial_valid_o,output wire signed [23:0]partial_sum_o,
  output wire signed [9:0]partial_exp_o
);
edge_dot_kernel #(
  .PARTIAL_ONLY(PARTIAL_ONLY), .FPGA_DSP_ADD(1), .FPGA_DSP_MUL(1)
) kernel(
  .clk(clk),.rst_b(rst_b),.in_valid(in_valid),
  .bf16_vec_i(bf16_vec_i),.int8_vec_i(int8_vec_i),
  .weight_bf16_mode_i(weight_bf16_mode_i),
  .bf16_weight_vec_i(bf16_weight_vec_i),
  .weight_exp_vec_i(64'b0),
  .external_product_vec_i(128'b0),.external_product_sign_i(8'b0),
  .rsum_enable_i(rsum_enable_i),.rsum_first_i(rsum_first_i),
  .rsum_last_i(rsum_last_i),.out_valid(out_valid),.bf22_o(bf22_o),
  .bf16_o(bf16_o),.partial_valid_o(partial_valid_o),
  .partial_sum_o(partial_sum_o),.partial_exp_o(partial_exp_o));
endmodule

module edge_dot8_kernel_fpga_partial(
  input wire clk,input wire rst_b,input wire in_valid,
  input wire [127:0]bf16_vec_i,input wire [63:0]int8_vec_i,
  input wire weight_bf16_mode_i,input wire [127:0]bf16_weight_vec_i,
  output wire partial_valid_o,output wire signed [23:0]partial_sum_o,
  output wire signed [9:0]partial_exp_o
);
wire unused_valid;wire[31:0]unused_bf22;wire[15:0]unused_bf16;
edge_dot8_kernel_fpga #(.PARTIAL_ONLY(1)) kernel(
  .clk(clk),.rst_b(rst_b),.in_valid(in_valid),
  .bf16_vec_i(bf16_vec_i),.int8_vec_i(int8_vec_i),
  .weight_bf16_mode_i(weight_bf16_mode_i),
  .bf16_weight_vec_i(bf16_weight_vec_i),
  .rsum_enable_i(1'b0),.rsum_first_i(1'b0),.rsum_last_i(1'b0),
  .out_valid(unused_valid),.bf22_o(unused_bf22),.bf16_o(unused_bf16),
  .partial_valid_o(partial_valid_o),.partial_sum_o(partial_sum_o),
  .partial_exp_o(partial_exp_o));
endmodule

module edge_dot_kernel_logic_partial(
  input wire clk,input wire rst_b,input wire in_valid,
  input wire [127:0]bf16_vec_i,input wire [63:0]int8_vec_i,
  input wire weight_bf16_mode_i,input wire [127:0]bf16_weight_vec_i,
  output wire partial_valid_o,output wire signed [23:0]partial_sum_o,
  output wire signed [9:0]partial_exp_o
);
wire unused_valid;wire[31:0]unused_bf22;wire[15:0]unused_bf16;
edge_dot_kernel #(
  .PARTIAL_ONLY(1), .FPGA_DSP_ADD(0), .FPGA_DSP_MUL(0)
) kernel(
  .clk(clk),.rst_b(rst_b),.in_valid(in_valid),
  .bf16_vec_i(bf16_vec_i),.int8_vec_i(int8_vec_i),
  .weight_bf16_mode_i(weight_bf16_mode_i),
  .bf16_weight_vec_i(bf16_weight_vec_i),
  .rsum_enable_i(1'b0),.rsum_first_i(1'b0),.rsum_last_i(1'b0),
  .out_valid(unused_valid),.bf22_o(unused_bf22),.bf16_o(unused_bf16),
  .partial_valid_o(partial_valid_o),.partial_sum_o(partial_sum_o),
  .partial_exp_o(partial_exp_o));
endmodule
