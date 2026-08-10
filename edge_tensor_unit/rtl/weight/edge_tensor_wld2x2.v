// Candidate WLD path: packed-format conversion followed by dual-mode 2x2 WLD.
module edge_tensor_wld2x2(
  clk, rst_b,
  start, start_ready, start_bf16_mode, start_transpose,
  busy, done,
  load_valid, load_ready, load_idx, load_data,
  drain_valid, drain_ready, drain_data, drain_lane_valid,
  drain_transpose, drain_target_dot, drain_quarter
);

input          clk;
input          rst_b;
input          start;
output         start_ready;
input          start_bf16_mode;
input          start_transpose;
output         busy;
output         done;
input          load_valid;
output         load_ready;
input  [2:0]   load_idx;
input  [127:0] load_data;
output         drain_valid;
input          drain_ready;
output [127:0] drain_data;
output [3:0]   drain_lane_valid;
output         drain_transpose;
output [11:0]  drain_target_dot;
output [1:0]   drain_quarter;

reg            bf16_mode_q;
wire           unpack_in_ready;
wire           unpack_out_valid;
wire           unpack_out_ready;
wire [2:0]     unpack_out_idx;
wire [127:0]   unpack_out_data;
wire           circular_start_ready;
wire           circular_load_ready;

assign start_ready = circular_start_ready;
assign load_ready = busy && unpack_in_ready;
assign unpack_out_ready = circular_load_ready;

edge_weight_unpack_bf16 x_unpack (
  .clk(clk), .rst_b(rst_b),
  .in_valid(load_valid && busy), .in_ready(unpack_in_ready),
  .in_bf16_mode(bf16_mode_q), .in_idx(load_idx), .in_data(load_data),
  .out_valid(unpack_out_valid), .out_ready(unpack_out_ready),
  .out_idx(unpack_out_idx), .out_data(unpack_out_data)
);

edge_tensor_wld2x2_sidecar x_circular (
  .clk(clk), .rst_b(rst_b), .start(start),
  .start_transpose(start_transpose), .start_ready(circular_start_ready),
  .busy(busy), .done(done),
  .load_valid(unpack_out_valid), .load_ready(circular_load_ready),
  .load_data(unpack_out_data),
  .drain_valid(drain_valid), .drain_ready(drain_ready),
  .drain_data(drain_data), .drain_lane_valid(drain_lane_valid),
  .drain_transpose(drain_transpose),
  .drain_target_dot(drain_target_dot), .drain_quarter(drain_quarter)
);

always @(posedge clk or negedge rst_b) begin
  if (!rst_b)
    bf16_mode_q <= 1'b1;
  else if (start && start_ready)
    bf16_mode_q <= start_bf16_mode;
end

wire unused_unpack_idx = |unpack_out_idx;

endmodule
