// Packed staging terminates at dot-local ingress; final banks shift in-dot.
module edge_tensor_dot_relay_weights(
 input wire clk,input wire rst_b,input wire weight_start_i,
 output wire weight_start_ready_o,input wire [1:0] weight_format_i,input wire weight_transpose_i,
 input wire weight_load_valid_i,output wire weight_load_ready_o,input wire [127:0] weight_load_data_i,
 input wire weight_drain_ready_i,output wire weight_done_o,output wire busy_o,
 input wire weight_fill_bank_i,input wire weight_activate_i,input wire weight_activate_bank_i,
 output wire [1023:0] active_weights_o
);
wire [3:0] group_valid;
wire [7:0] group_lane;
wire [127:0] raw_weights;
wire [1:0] ingress_wtype;
edge_wld_fixed_group_buffer #(.DOTS(8),.LANES(2)) buffer(
 .clk(clk),.rst_b(rst_b),.start_i(weight_start_i),.start_ready_o(weight_start_ready_o),
 // Transport type stays intact until dot-local promotion to BF16.
 .wtype_i(weight_format_i),.transpose_i(weight_transpose_i),
 .load_valid_i(weight_load_valid_i),.load_ready_o(weight_load_ready_o),.load_data_i(weight_load_data_i),
 .drain_valid_o(group_valid),.drain_ready_i(weight_drain_ready_i),.drain_data_o(raw_weights),
 .wtype_o(ingress_wtype),.drain_lane_o(group_lane),.busy_o(busy_o),.done_o(weight_done_o));
genvar dot;
for(dot=0;dot<8;dot=dot+1)begin : GEN_DOT
 edge_dot8_weight_bank_relay #(.STEP(2)) x_weight_bank(
  .clk(clk),.rst_b(rst_b),.shift_valid_i(group_valid[dot/2]&&weight_drain_ready_i&&group_lane[(dot/2)*2+:2]==2'(dot%2)),
  .weight_i(raw_weights[(dot/2)*32+:32]),.format_i(ingress_wtype),
  .fill_bank_i(weight_fill_bank_i),.activate_i(weight_activate_i),.activate_bank_i(weight_activate_bank_i),
  .active_weight_o(active_weights_o[dot*128+:128]));
end
`ifndef SYNTHESIS
always @(posedge clk)
 if(rst_b&&weight_start_i&&weight_start_ready_o&&weight_format_i==2)
  $fatal(1,"E3 dot relay supports BF16/I8/FP4; FP8 encoding is not defined");
`endif
endmodule
