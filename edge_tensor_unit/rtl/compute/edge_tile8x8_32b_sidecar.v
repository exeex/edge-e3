// Experimental 8-row router for four 32-bit WLD channels.
module edge_tile8x8_32b_sidecar(
  clk, rst_b,
  weight_fill_valid_i, weight_fill_data_i, weight_fill_target_dot_i,
  weight_fill_quarter_i, weight_fill_bank_i,
  weight_activate_i, weight_activate_bank_i,
  in_valid, input_bf16_i,
  out_valid, output_bf16_o
);

input          clk;
input          rst_b;
input          weight_fill_valid_i;
input  [127:0] weight_fill_data_i;
input  [11:0]  weight_fill_target_dot_i;
input  [1:0]   weight_fill_quarter_i;
input          weight_fill_bank_i;
input          weight_activate_i;
input          weight_activate_bank_i;
input          in_valid;
input  [127:0] input_bf16_i;
output         out_valid;
output [127:0] output_bf16_o;

wire [7:0] dot_valid;
reg  [7:0] dot_fill_valid;
reg  [31:0] dot_fill_data [0:7];
integer route_i;

assign out_valid = dot_valid[0];

always @(*) begin
  dot_fill_valid = 8'b0;
  for (route_i = 0; route_i < 8; route_i = route_i + 1)
    dot_fill_data[route_i] = 32'b0;
  if (weight_fill_valid_i) begin
    for (route_i = 0; route_i < 4; route_i = route_i + 1) begin
      // A circular 2x2 channel only selects one of its fixed dot pair.
      // The upper target bits are descriptive metadata, not a crossbar address.
      if (weight_fill_target_dot_i[route_i*3]) begin
        dot_fill_valid[route_i*2+1] = 1'b1;
        dot_fill_data[route_i*2+1] = weight_fill_data_i[route_i*32 +: 32];
      end else begin
        dot_fill_valid[route_i*2] = 1'b1;
        dot_fill_data[route_i*2] = weight_fill_data_i[route_i*32 +: 32];
      end
    end
  end
end

generate
  genvar row;
  for (row = 0; row < 8; row = row + 1) begin : GEN_ROWS
    edge_dot8_32b_sidecar x_dot (
      .clk(clk), .rst_b(rst_b),
      .weight_fill_valid_i(dot_fill_valid[row]),
      .weight_fill_quarter_i(weight_fill_quarter_i),
      .weight_fill_data_i(dot_fill_data[row]),
      .weight_fill_bank_i(weight_fill_bank_i),
      .weight_activate_i(weight_activate_i),
      .weight_activate_bank_i(weight_activate_bank_i),
      .in_valid(in_valid), .input_bf16_i(input_bf16_i),
      .out_valid(dot_valid[row]),
      .result_bf16_o(output_bf16_o[row*16 +: 16])
    );
  end
endgenerate

endmodule
