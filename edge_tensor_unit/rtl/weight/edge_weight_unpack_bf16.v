// Converts a packed WLD beat into the canonical 8-lane BF16 weight stream.
module edge_weight_unpack_bf16(
  clk, rst_b,
  in_valid, in_ready, in_bf16_mode, in_idx, in_data,
  out_valid, out_ready, out_idx, out_data
);

input          clk;
input          rst_b;
input          in_valid;
output         in_ready;
input          in_bf16_mode;
input  [2:0]   in_idx;
input  [127:0] in_data;
output         out_valid;
input          out_ready;
output [2:0]   out_idx;
output [127:0] out_data;

reg           valid_q;
reg           bf16_mode_q;
reg           i8_phase_q;
reg [2:0]     idx_q;
reg [127:0]   data_q;
reg [127:0]   converted_i8;
integer lane_i;

wire out_accept;
wire final_slice;

assign out_valid = valid_q;
assign out_idx = bf16_mode_q ? idx_q : {idx_q[1:0], i8_phase_q};
assign out_data = bf16_mode_q ? data_q : converted_i8;
assign final_slice = bf16_mode_q || i8_phase_q;
assign out_accept = out_valid && out_ready;
assign in_ready = !valid_q || (out_accept && final_slice);

function [15:0] int8_to_bf16;
  input [7:0] value;
  reg sign;
  reg [7:0] mag;
  reg [2:0] msb;
  reg [7:0] normalized;
  integer bit_i;
  begin
    if (value == 8'b0) begin
      int8_to_bf16 = 16'b0;
    end else begin
      sign = value[7];
      mag = sign ? (~value + 8'b1) : value;
      msb = 3'b0;
      for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1)
        if (mag[bit_i])
          msb = bit_i[2:0];
      normalized = mag << (3'd7 - msb);
      int8_to_bf16 = {sign, (8'd127 + {5'b0, msb}), normalized[6:0]};
    end
  end
endfunction

always @(*) begin
  converted_i8 = 128'b0;
  for (lane_i = 0; lane_i < 8; lane_i = lane_i + 1)
    converted_i8[lane_i*16 +: 16] =
        int8_to_bf16(data_q[(i8_phase_q*8+lane_i)*8 +: 8]);
end

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    valid_q <= 1'b0;
    bf16_mode_q <= 1'b0;
    i8_phase_q <= 1'b0;
    idx_q <= 3'b0;
    data_q <= 128'b0;
  end else begin
    if (out_accept && !final_slice)
      i8_phase_q <= 1'b1;

    if (in_valid && in_ready) begin
      valid_q <= 1'b1;
      bf16_mode_q <= in_bf16_mode;
      i8_phase_q <= 1'b0;
      idx_q <= in_idx;
      data_q <= in_data;
    end else if (out_accept && final_slice) begin
      valid_q <= 1'b0;
    end
  end
end

endmodule
