// Experimental 8-row router for four packed 32-bit weight channels.
module edge_tile8x8_packed32_sidecar(
  clk, rst_b,
  weight_fill_valid_i, weight_fill_lane_valid_i,
  weight_fill_format_i, weight_fill_data_i,
  weight_fill_target_dot_i, weight_fill_slot_i, weight_fill_bank_i,
  weight_activate_i, weight_activate_bank_i,
  in_valid, input_bf16_i,
  out_valid, output_bf16_o
);

input          clk;
input          rst_b;
input          weight_fill_valid_i;
input  [3:0]   weight_fill_lane_valid_i;
input  [1:0]   weight_fill_format_i;
input  [127:0] weight_fill_data_i;
input  [11:0]  weight_fill_target_dot_i;
input  [1:0]   weight_fill_slot_i;
input          weight_fill_bank_i;
input          weight_activate_i;
input          weight_activate_bank_i;
input          in_valid;
input  [127:0] input_bf16_i;
output         out_valid;
output [127:0] output_bf16_o;

wire [7:0] dot_valid;
reg [7:0] dot_fill_valid;
reg [31:0] dot_fill_data [0:7];
integer lane_i;
integer dot_i;

assign out_valid = dot_valid[0];

always @(*) begin
  dot_fill_valid = 8'b0;
  for (dot_i = 0; dot_i < 8; dot_i = dot_i + 1)
    dot_fill_data[dot_i] = 32'b0;
  if (weight_fill_valid_i) begin
    for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
      for (dot_i = 0; dot_i < 8; dot_i = dot_i + 1) begin
        if (weight_fill_lane_valid_i[lane_i]
            && weight_fill_target_dot_i[lane_i*3 +: 3] == dot_i[2:0]) begin
          dot_fill_valid[dot_i] = 1'b1;
          dot_fill_data[dot_i] = weight_fill_data_i[lane_i*32 +: 32];
        end
      end
    end
  end
end

generate
  genvar row_g;
  for (row_g = 0; row_g < 8; row_g = row_g + 1) begin : GEN_ROWS
    edge_dot8_packed32_sidecar x_dot (
      .clk(clk), .rst_b(rst_b),
      .weight_fill_valid_i(dot_fill_valid[row_g]),
      .weight_fill_format_i(weight_fill_format_i),
      .weight_fill_slot_i(weight_fill_slot_i),
      .weight_fill_data_i(dot_fill_data[row_g]),
      .weight_fill_bank_i(weight_fill_bank_i),
      .weight_activate_i(weight_activate_i),
      .weight_activate_bank_i(weight_activate_bank_i),
      .in_valid(in_valid), .input_bf16_i(input_bf16_i),
      .out_valid(dot_valid[row_g]),
      .result_bf16_o(output_bf16_o[row_g*16 +: 16])
    );
  end
endgenerate

endmodule
