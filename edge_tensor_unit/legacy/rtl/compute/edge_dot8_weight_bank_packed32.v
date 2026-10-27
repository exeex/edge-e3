// Dot-local canonical BF16 double bank with a packed 32-bit fill port.
module edge_dot8_weight_bank_packed32(
  clk, rst_b,
  fill_valid_i, fill_format_i, fill_slot_i, fill_data_i, fill_bank_i,
  activate_i, activate_bank_i, active_weight_o
);
input clk, rst_b, fill_valid_i;
input [1:0] fill_format_i;
input [1:0] fill_slot_i;
input [31:0] fill_data_i;
input fill_bank_i, activate_i, activate_bank_i;
output [127:0] active_weight_o;

localparam WEIGHT_BF16 = 2'd0;
localparam WEIGHT_I8 = 2'd1;
reg [127:0] weight_bank0_q;
reg [127:0] weight_bank1_q;
reg active_bank_q;
reg [63:0] converted_i8;
integer element_i;

assign active_weight_o = active_bank_q ? weight_bank1_q : weight_bank0_q;

function [15:0] int8_to_bf16;
  input [7:0] value;
  reg sign;
  reg [7:0] mag;
  begin
    sign = value[7];
    mag = sign ? (~value + 8'b1) : value;
    casez (mag)
      8'b1???????: int8_to_bf16 = {sign, 8'd134, mag[6:0]};
      8'b01??????: int8_to_bf16 = {sign, 8'd133, mag[5:0], 1'b0};
      8'b001?????: int8_to_bf16 = {sign, 8'd132, mag[4:0], 2'b0};
      8'b0001????: int8_to_bf16 = {sign, 8'd131, mag[3:0], 3'b0};
      8'b00001???: int8_to_bf16 = {sign, 8'd130, mag[2:0], 4'b0};
      8'b000001??: int8_to_bf16 = {sign, 8'd129, mag[1:0], 5'b0};
      8'b0000001?: int8_to_bf16 = {sign, 8'd128, mag[0], 6'b0};
      8'b00000001: int8_to_bf16 = {sign, 8'd127, 7'b0};
      default:     int8_to_bf16 = 16'b0;
    endcase
  end
endfunction

always @(*) begin
  converted_i8 = 64'b0;
  for (element_i=0; element_i<4; element_i=element_i+1)
    converted_i8[element_i*16 +: 16] =
        int8_to_bf16(fill_data_i[element_i*8 +: 8]);
end

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    weight_bank0_q <= 128'b0;
    weight_bank1_q <= 128'b0;
    active_bank_q <= 1'b0;
  end else begin
    if (fill_valid_i && fill_bank_i) begin
      if (fill_format_i == WEIGHT_BF16) begin
        case (fill_slot_i)
          2'd0: weight_bank1_q[31:0] <= fill_data_i;
          2'd1: weight_bank1_q[63:32] <= fill_data_i;
          2'd2: weight_bank1_q[95:64] <= fill_data_i;
          2'd3: weight_bank1_q[127:96] <= fill_data_i;
        endcase
      end else if (fill_format_i == WEIGHT_I8) begin
        if (fill_slot_i[0]) weight_bank1_q[127:64] <= converted_i8;
        else weight_bank1_q[63:0] <= converted_i8;
      end
    end else if (fill_valid_i) begin
      if (fill_format_i == WEIGHT_BF16) begin
        case (fill_slot_i)
          2'd0: weight_bank0_q[31:0] <= fill_data_i;
          2'd1: weight_bank0_q[63:32] <= fill_data_i;
          2'd2: weight_bank0_q[95:64] <= fill_data_i;
          2'd3: weight_bank0_q[127:96] <= fill_data_i;
        endcase
      end else if (fill_format_i == WEIGHT_I8) begin
        if (fill_slot_i[0]) weight_bank0_q[127:64] <= converted_i8;
        else weight_bank0_q[63:0] <= converted_i8;
      end
    end
    if (activate_i) active_bank_q <= activate_bank_i;
  end
end
endmodule
