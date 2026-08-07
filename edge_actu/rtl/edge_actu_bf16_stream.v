`timescale 1ns/1ps

module edge_actu_bf16_stream #(
  parameter PIPE_STAGES = 9
) (
  input wire clk,
  input wire cpurst_b,
  input wire in_valid,
  output wire in_ready,
  input wire [2:0] in_mode,
  input wire [15:0] in_bf16,
  input wire [31:0] in_scalar_bits,
  input wire softmax_sum_clear,
  output wire out_valid,
  output wire [2:0] out_mode,
  output wire [15:0] out_bf16,
  output wire softmax_sum_valid,
  output wire [31:0] softmax_sum_bits
);

wire [31:0] internal_out_bits;

edge_actu #(.PIPE_STAGES(PIPE_STAGES)) core (
  .forever_cpuclk(clk),
  .cpurst_b(cpurst_b),
  .in_valid(in_valid),
  .in_ready(in_ready),
  .in_mode(in_mode),
  .in_value({in_bf16, 16'b0}),
  .in_softmax_max(in_scalar_bits),
  .softmax_sum_clear(softmax_sum_clear),
  .out_valid(out_valid),
  .out_mode(out_mode),
  .out_value(internal_out_bits),
  .softmax_sum_valid(softmax_sum_valid),
  .softmax_sum_value(softmax_sum_bits)
);

assign out_bf16 = internal_out_bits[31:16];

endmodule
