// Final A/B cells are themselves the single-direction intra-dot relay.
// Source order is element 0..7; STEP=2 injects low/high into cells 6/7.
// Two interleaved 16-bit rails move toward cell 0 within the same dot.
module edge_dot8_weight_bank_relay #(parameter STEP=1)(
 input wire clk,input wire rst_b,input wire shift_valid_i,input wire [STEP*16-1:0] weight_i,
 input wire [1:0] format_i,input wire fill_bank_i,
 input wire activate_i,input wire activate_bank_i,
 output wire [127:0] active_weight_o
);
reg active_bank_q;
wire [15:0] relay[0:7];
wire [15:0] decoded[0:STEP-1];
genvar pair;
for(pair=0;pair<STEP;pair=pair+1)begin : DECODE
 assign decoded[pair]=format_i==0?weight_i[pair*16+:16]:format_i==3?fp4_to_bf16(weight_i[pair*16+:4]):int8_to_bf16(weight_i[pair*16+:8]);
end
always @(posedge clk or negedge rst_b)
 if(!rst_b)active_bank_q<=0;else if(activate_i)active_bank_q<=activate_bank_i;
// E2M1: +/-{0, .5, 1, 1.5, 2, 3, 4, 6}; exact BF16 promotion.
function [15:0] fp4_to_bf16;
 input [3:0] value;
 reg [14:0] magnitude;
 begin
  case(value[2:0])
   0:magnitude=15'h0000; 1:magnitude=15'h3f00;
   2:magnitude=15'h3f80; 3:magnitude=15'h3fc0;
   4:magnitude=15'h4000; 5:magnitude=15'h4040;
   6:magnitude=15'h4080; 7:magnitude=15'h40c0;
  endcase
  fp4_to_bf16={value[3],magnitude};
 end
endfunction
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

genvar lane;
generate for(lane=0;lane<8;lane=lane+1)begin : GEN_LANE
 reg [15:0] bank0_q,bank1_q;
 wire [15:0] incoming;
 if(lane>=8-STEP)begin : GEN_INGRESS
  assign incoming=decoded[lane-(8-STEP)];
 end else begin : GEN_NEIGHBOR
  assign incoming=relay[lane+STEP];
 end
 assign relay[lane]=fill_bank_i?bank1_q:bank0_q;
 assign active_weight_o[lane*16+:16]=active_bank_q?bank1_q:bank0_q;
 always @(posedge clk or negedge rst_b)begin
  if(!rst_b)begin bank0_q<=0;bank1_q<=0;end
  else if(shift_valid_i)begin
   if(fill_bank_i)bank1_q<=incoming;else bank0_q<=incoming;
  end
 end
end endgenerate
`ifndef SYNTHESIS
initial if(STEP!=1&&STEP!=2)$fatal(1,"unsupported weight relay step");
`endif
endmodule
