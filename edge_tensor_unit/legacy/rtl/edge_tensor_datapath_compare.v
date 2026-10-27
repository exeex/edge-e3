// E3 packed WLD relay ingress through final local banks and scale * dot + psum.
module edge_tensor_datapath_compare #(parameter RELAY_WEIGHT=2)(
  clk, rst_b,
  weight_start_i, weight_start_ready_o,
  weight_format_i, weight_transpose_i,
  weight_load_valid_i, weight_load_ready_o, weight_load_data_i,
  weight_drain_ready_i, weight_done_o,
  weight_fill_bank_i, weight_activate_i, weight_activate_bank_i,
  compute_valid_i, input_bf16_i, psum_bf16_i,
  late_psum_mode_i, late_psum_valid_i,
  scale_enable_i, scale_bf16_i,
  rsum_enable_i, rsum_first_i, rsum_last_i,
  dot_ready_o, output_valid_o, output_bf16_o,
  wide_enable_i, psum_fp32_i, output_fp32_o
);

input wide_enable_i;
input [255:0] psum_fp32_i;
output [255:0] output_fp32_o;
input clk, rst_b;
input weight_start_i;
output weight_start_ready_o;
input [2:0] weight_format_i;
input weight_transpose_i;
input weight_load_valid_i;
output weight_load_ready_o;
input [127:0] weight_load_data_i;
input weight_drain_ready_i;
output weight_done_o;
input weight_fill_bank_i, weight_activate_i, weight_activate_bank_i;
input compute_valid_i;
input [127:0] input_bf16_i, psum_bf16_i;
input late_psum_mode_i, late_psum_valid_i;
input scale_enable_i;
input [127:0] scale_bf16_i;
input rsum_enable_i, rsum_first_i, rsum_last_i;
output dot_ready_o;
output output_valid_o;
output [127:0] output_bf16_o;

generate if (RELAY_WEIGHT==1) begin : GEN_RELAY
wire [63:0] take_valid;
wire [1023:0] take_data;
wire [1:0] width_code;
wire [2:0] relay_mode={weight_format_i,weight_transpose_i};
wire [7:0] dot_valid;
wire [127:0] dot_bf16;
wire [255:0] dot_fp32;

edge_wld_relay_router #(.DOTS(8)) x_weight_ingress (
  .clk(clk), .rst_b(rst_b), .start_i(weight_start_i),
  .start_ready_o(weight_start_ready_o), .mode_i(relay_mode),
  .load_valid_i(weight_load_valid_i), .load_ready_o(weight_load_ready_o),
  .load_data_i(weight_load_data_i), .advance_i(weight_drain_ready_i),
  .busy_o(), .done_o(weight_done_o),
  .take_valid_o(take_valid), .take_data_o(take_data), .width_code_o(width_code)
);

genvar dot;
for (dot=0;dot<8;dot=dot+1) begin : GEN_DOT
  wire [127:0] active_weight;
  edge_dot8_weight_bank_elements x_weight_bank (
    .clk(clk), .rst_b(rst_b), .fill_valid_i(take_valid[dot*8 +: 8]),
    .fill_data_i(take_data[dot*128 +: 128]), .fill_format_i(width_code),
    .fill_bank_i(weight_fill_bank_i), .activate_i(weight_activate_i),
    .activate_bank_i(weight_activate_bank_i), .active_weight_o(active_weight)
  );
  edge_dot_kernel x_kernel (
    .clk(clk), .rst_b(rst_b), .in_valid(compute_valid_i),
    .bf16_vec_i(input_bf16_i), .int8_vec_i(64'b0),
    .weight_bf16_mode_i(1'b1), .bf16_weight_vec_i(active_weight),
    .weight_exp_vec_i(64'b0), .external_product_vec_i(128'b0),
    .external_product_sign_i(8'b0), .rsum_enable_i(rsum_enable_i),
    .rsum_first_i(rsum_first_i), .rsum_last_i(rsum_last_i),
    .out_valid(dot_valid[dot]), .bf22_o(dot_fp32[dot*32+:32]), .bf16_o(dot_bf16[dot*16 +: 16])
  );
end
edge_tensor_scale_psum8 x_post (
  .clk(clk), .rst_b(rst_b), .dot_valid(dot_valid[0]), .dot_bf16(dot_bf16), .dot_fp32_i(dot_fp32),
  .late_psum_mode_i(late_psum_mode_i), .late_psum_valid_i(late_psum_valid_i),
  .wide_enable_i(wide_enable_i), .psum_fp32_i(psum_fp32_i), .output_fp32_o(output_fp32_o),
      .psum_bf16_i(psum_bf16_i), .scale_enable_i(scale_enable_i),
  .scale_bf16_i(scale_bf16_i), .rsum_enable_i(rsum_enable_i),
  .dot_ready_o(dot_ready_o), .out_valid(output_valid_o), .output_bf16_o(output_bf16_o)
);
`ifndef SYNTHESIS
always @(posedge clk)
  if (rst_b && weight_start_i && weight_start_ready_o && weight_format_i>1)
    $fatal(1,"E3 relay product supports BF16 and signed I8 only");
`endif
end else if (RELAY_WEIGHT==2) begin : GEN_DOT_RELAY
wire [1023:0] active_weights;
wire [7:0] dot_valid;
wire [127:0] dot_bf16;
wire [255:0] dot_fp32;
edge_tensor_weights x_weights(
 .clk(clk),.rst_b(rst_b),.weight_start_i(weight_start_i),.weight_start_ready_o(weight_start_ready_o),
 .weight_format_i(weight_format_i),.weight_transpose_i(weight_transpose_i),
 .weight_load_valid_i(weight_load_valid_i),.weight_load_ready_o(weight_load_ready_o),
 .weight_load_data_i(weight_load_data_i),.weight_drain_ready_i(weight_drain_ready_i),
 .weight_done_o(weight_done_o),.busy_o(),.weight_fill_bank_i(weight_fill_bank_i),
 .weight_activate_i(weight_activate_i),.weight_activate_bank_i(weight_activate_bank_i),
 .active_weights_o(active_weights));
genvar dot;
for(dot=0;dot<8;dot=dot+1)begin : GEN_DOT
 edge_dot_kernel x_kernel(
  .clk(clk),.rst_b(rst_b),.in_valid(compute_valid_i),.bf16_vec_i(input_bf16_i),.int8_vec_i(64'b0),
  .weight_bf16_mode_i(1'b1),.bf16_weight_vec_i(active_weights[dot*128+:128]),.weight_exp_vec_i(64'b0),
  .external_product_vec_i(128'b0),.external_product_sign_i(8'b0),
  .rsum_enable_i(rsum_enable_i),.rsum_first_i(rsum_first_i),.rsum_last_i(rsum_last_i),
  .out_valid(dot_valid[dot]),.bf22_o(dot_fp32[dot*32+:32]),.bf16_o(dot_bf16[dot*16+:16]));
end
edge_tensor_scale_psum8 x_post(
 .clk(clk),.rst_b(rst_b),.dot_valid(dot_valid[0]),.dot_bf16(dot_bf16), .dot_fp32_i(dot_fp32),
 .late_psum_mode_i(late_psum_mode_i),.late_psum_valid_i(late_psum_valid_i),
 .wide_enable_i(wide_enable_i), .psum_fp32_i(psum_fp32_i), .output_fp32_o(output_fp32_o),
      .psum_bf16_i(psum_bf16_i),.scale_enable_i(scale_enable_i),.scale_bf16_i(scale_bf16_i),
 .rsum_enable_i(rsum_enable_i),.dot_ready_o(dot_ready_o),.out_valid(output_valid_o),.output_bf16_o(output_bf16_o));
end else begin : GEN_CIRCULAR
wire [127:0] drain_data;
wire [3:0] drain_lane_valid;
wire [7:0] drain_slot;
wire [11:0] drain_target_dot;
wire circular_busy;
reg [1:0] drain_format_q;
wire [2:0] circular_mode = weight_format_i == 2'd0
                             ? (weight_transpose_i ? 3'd1 : 3'd0)
                             : (weight_transpose_i ? 3'd3 : 3'd2);

edge_weight_circular4_mux6 x_weight_circular (
  .clk(clk), .rst_b(rst_b),
  .start_i(weight_start_i), .start_ready_o(weight_start_ready_o),
  .mode_i(circular_mode), .busy_o(circular_busy), .done_o(weight_done_o),
  .load_valid_i(weight_load_valid_i), .load_ready_o(weight_load_ready_o),
  .load_data_i(weight_load_data_i),
  .drain_valid_o(drain_lane_valid),
  .drain_ready_i({4{weight_drain_ready_i}}),
  .drain_data_o(drain_data), .drain_target_dot_o(drain_target_dot),
  .drain_fill_slot_o(drain_slot)
);

edge_tile8x8_packed32_scale_psum_sidecar x_tile (
  .clk(clk), .rst_b(rst_b),
  .weight_fill_valid_i(|drain_lane_valid && weight_drain_ready_i),
  .weight_fill_lane_valid_i(drain_lane_valid & {4{weight_drain_ready_i}}),
  .weight_fill_format_i(drain_format_q), .weight_fill_data_i(drain_data),
  .weight_fill_target_dot_i(drain_target_dot),
  .weight_fill_slot_i(drain_slot), .weight_fill_bank_i(weight_fill_bank_i),
  .weight_activate_i(weight_activate_i),
  .weight_activate_bank_i(weight_activate_bank_i),
  .in_valid(compute_valid_i), .input_bf16_i(input_bf16_i),
  .late_psum_mode_i(late_psum_mode_i),
  .late_psum_valid_i(late_psum_valid_i),
  .wide_enable_i(wide_enable_i), .psum_fp32_i(psum_fp32_i), .output_fp32_o(output_fp32_o),
      .psum_bf16_i(psum_bf16_i),
  .scale_enable_i(scale_enable_i), .scale_bf16_i(scale_bf16_i),
  .rsum_enable_i(rsum_enable_i), .rsum_first_i(rsum_first_i),
  .rsum_last_i(rsum_last_i), .dot_ready_o(dot_ready_o),
  .out_valid(output_valid_o), .output_bf16_o(output_bf16_o)
);

always @(posedge clk or negedge rst_b) begin
  if (!rst_b)
    drain_format_q <= 2'd0;
  else if (weight_start_i && weight_start_ready_o)
    drain_format_q <= weight_format_i;
end

wire unused_circular_busy = circular_busy;
end endgenerate
endmodule
