// Final dot-local A/B weight cells with independent element write enables.
module edge_dot8_weight_bank_elements(
  input wire clk, input wire rst_b,
  input wire [7:0] fill_valid_i, input wire [127:0] fill_data_i,
  input wire [1:0] fill_format_i, input wire fill_bank_i,
  input wire activate_i, input wire activate_bank_i,
  output wire [127:0] active_weight_o
);
reg active_bank_q;
always @(posedge clk or negedge rst_b) begin
  if (!rst_b) active_bank_q<=0;
  else if (activate_i) active_bank_q<=activate_bank_i;
end
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

genvar element;
generate for (element=0;element<8;element=element+1) begin : GEN_ELEMENT
  reg [15:0] bank0_q, bank1_q;
  wire [15:0] value=fill_format_i==0 ? fill_data_i[element*16 +: 16]
                                      : int8_to_bf16(fill_data_i[element*16 +: 8]);
  assign active_weight_o[element*16 +: 16]=active_bank_q ? bank1_q : bank0_q;
  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin bank0_q<=0;bank1_q<=0;end
    else if (fill_valid_i[element]) begin
      if (fill_bank_i) bank1_q<=value;else bank0_q<=value;
    end
  end
end endgenerate
endmodule
