// Circular distribution ends at each dot's local ingress; relay stays inside it.
module edge_tensor_dot_relay_weights(
 input wire clk,input wire rst_b,input wire weight_start_i,
 output wire weight_start_ready_o,input wire [1:0] weight_format_i,input wire weight_transpose_i,
 input wire weight_load_valid_i,output wire weight_load_ready_o,input wire [127:0] weight_load_data_i,
 input wire weight_drain_ready_i,output wire weight_done_o,output wire busy_o,
 input wire weight_fill_bank_i,input wire weight_activate_i,input wire weight_activate_bank_i,
 output wire [1023:0] active_weights_o
);
wire [3:0] drain_valid,drain_ready;
wire [127:0] drain_data;
wire [11:0] drain_target;
wire [7:0] drain_slot;
wire circular_ready,circular_done,circular_busy;
reg circular_complete_q,load_busy_q,done_q;
reg [7:0] dot_complete_q;
wire [7:0] dot_done,dot_ready;
wire [1:0] load_width_code=weight_format_i==0 ? 2'd0 : 2'd1;
wire start_fire=weight_start_i&&weight_start_ready_o;
assign weight_start_ready_o=!load_busy_q&&circular_ready;
assign weight_done_o=done_q;
assign busy_o=load_busy_q;
edge_wld_packed_router circular(
 .clk(clk),.rst_b(rst_b),.start_i(start_fire),.start_ready_o(circular_ready),
 .mode_i({load_width_code,weight_transpose_i}),.busy_o(circular_busy),.done_o(circular_done),
 .load_valid_i(weight_load_valid_i),.load_ready_o(weight_load_ready_o),.load_data_i(weight_load_data_i),
 .drain_valid_o(drain_valid),.drain_ready_i(drain_ready),.drain_data_o(drain_data),
 .drain_target_dot_o(drain_target),.drain_fill_slot_o(drain_slot));
genvar source_lane,dot;
for(source_lane=0;source_lane<4;source_lane=source_lane+1)begin : GEN_SOURCE_READY
 assign drain_ready[source_lane]=weight_drain_ready_i&&dot_ready[drain_target[source_lane*3+:3]];
end
always @(posedge clk or negedge rst_b)begin
 if(!rst_b)begin circular_complete_q<=0;dot_complete_q<=0;load_busy_q<=0;done_q<=0;end
 else begin
  done_q<=0;
  if(start_fire)begin
   circular_complete_q<=0;dot_complete_q<=0;load_busy_q<=1;
  end else if(load_busy_q)begin
   if(circular_done)circular_complete_q<=1;
   dot_complete_q<=dot_complete_q|dot_done;
   if((circular_complete_q||circular_done)&&(&(dot_complete_q|dot_done)))begin load_busy_q<=0;done_q<=1;end
  end
 end
end
for(dot=0;dot<8;dot=dot+1)begin : GEN_DOT
 reg local_valid;
 reg [31:0] local_data;
 reg [1:0] local_slot;
 integer lane;
 wire element_valid;
 wire [1:0] ingress_wtype;
 wire [15:0] element;
 wire [127:0] active_weight;
 // Distribution ends here at the dot entrance; downstream links stay inside
 // this dot. No dot-to-dot weight relay or array-wide second direction exists.
 always @*begin
  local_valid=0;local_data=0;local_slot=0;
  for(lane=0;lane<4;lane=lane+1)
   if(drain_valid[lane]&&drain_target[lane*3+:3]==3'(dot))begin
    local_valid=1;local_data=local_data|drain_data[lane*32+:32];local_slot=local_slot|drain_slot[lane*2+:2];
   end
 end
 edge_wld_dot_ingress ingress(
  .clk(clk),.rst_b(rst_b),.start_i(start_fire),.width_code_i(load_width_code),.wtype_i(weight_format_i),
  .advance_i(weight_drain_ready_i),.valid_i(local_valid),.ready_o(dot_ready[dot]),.data_i(local_data),
  .element_valid_o(element_valid),.element_o(element),.done_o(dot_done[dot]),.busy_o(),
  .wtype_o(ingress_wtype));
 edge_dot8_weight_bank_relay x_weight_bank(
  .clk(clk),.rst_b(rst_b),.shift_valid_i(element_valid),.weight_i(element),.format_i(ingress_wtype),
  .fill_bank_i(weight_fill_bank_i),.activate_i(weight_activate_i),.activate_bank_i(weight_activate_bank_i),
  .active_weight_o(active_weight));
 assign active_weights_o[dot*128+:128]=active_weight;
`ifndef SYNTHESIS
 reg [1:0] expected_slot_q;
 always @(posedge clk or negedge rst_b)
  if(!rst_b)expected_slot_q<=0;
  else if(start_fire)expected_slot_q<=0;
  else if(local_valid&&dot_ready[dot])begin
   if(local_slot!=expected_slot_q)$fatal(1,"dot ingress received out-of-order chunk dot=%0d",dot);
   expected_slot_q<=expected_slot_q+1'b1;
  end
`endif
end
`ifndef SYNTHESIS
always @(posedge clk)if(rst_b&&start_fire&&weight_format_i>1)$fatal(1,"E3 dot relay supports BF16/I8 only");
`endif
endmodule
