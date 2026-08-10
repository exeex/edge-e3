// Experimental dot8 wrapper with 32-bit weight fill and local double buffers.
module edge_dot8_32b_sidecar(
  clk, rst_b,
  weight_fill_valid_i, weight_fill_quarter_i, weight_fill_data_i,
  weight_fill_bank_i, weight_activate_i, weight_activate_bank_i,
  in_valid, input_bf16_i,
  out_valid, result_bf16_o
);

input          clk;
input          rst_b;
input          weight_fill_valid_i;
input  [1:0]   weight_fill_quarter_i;
input  [31:0]  weight_fill_data_i;
input          weight_fill_bank_i;
input          weight_activate_i;
input          weight_activate_bank_i;
input          in_valid;
input  [127:0] input_bf16_i;
output         out_valid;
output [15:0]  result_bf16_o;

reg [127:0] weight_bank0_q;
reg [127:0] weight_bank1_q;
reg         active_bank_q;
wire [127:0] active_weight;
wire [31:0] unused_bf22;

assign active_weight = active_bank_q ? weight_bank1_q : weight_bank0_q;

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    weight_bank0_q <= 128'b0;
    weight_bank1_q <= 128'b0;
    active_bank_q <= 1'b0;
  end else begin
    if (weight_fill_valid_i) begin
      if (weight_fill_bank_i)
        weight_bank1_q[{weight_fill_quarter_i, 5'b0} +: 32]
            <= weight_fill_data_i;
      else
        weight_bank0_q[{weight_fill_quarter_i, 5'b0} +: 32]
            <= weight_fill_data_i;
    end
    if (weight_activate_i)
      active_bank_q <= weight_activate_bank_i;
  end
end

edge_dot8_kernel x_kernel (
  .clk(clk), .rst_b(rst_b), .in_valid(in_valid),
  .bf16_vec_i(input_bf16_i), .int8_vec_i(64'b0),
  .weight_bf16_mode_i(1'b1), .bf16_weight_vec_i(active_weight),
  .rsum_enable_i(1'b0), .rsum_first_i(1'b0), .rsum_last_i(1'b0),
  .out_valid(out_valid), .bf22_o(unused_bf22),
  .bf16_o(result_bf16_o)
);

endmodule
