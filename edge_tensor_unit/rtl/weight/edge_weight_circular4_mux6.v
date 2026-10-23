// E3 pin-compatible boundary for the shared packed WLD router.
module edge_weight_circular4_mux6(
  clk, rst_b, start_i, start_ready_o, mode_i, busy_o, done_o,
  load_valid_i, load_ready_o, load_data_i,
  drain_valid_o, drain_ready_i, drain_data_o,
  drain_target_dot_o, drain_fill_slot_o
);
input clk, rst_b, start_i;
output start_ready_o, busy_o, done_o;
input [2:0] mode_i;
input load_valid_i;
output load_ready_o;
input [127:0] load_data_i;
output [3:0] drain_valid_o;
input [3:0] drain_ready_i;
output [127:0] drain_data_o;
output [11:0] drain_target_dot_o;
output [7:0] drain_fill_slot_o;

edge_wld_packed_router #(.DOTS(8)) router (
  .clk(clk),
  .rst_b(rst_b),
  .start_i(start_i),
  .start_ready_o(start_ready_o),
  .mode_i(mode_i),
  .busy_o(busy_o),
  .done_o(done_o),
  .load_valid_i(load_valid_i),
  .load_ready_o(load_ready_o),
  .load_data_i(load_data_i),
  .drain_valid_o(drain_valid_o),
  .drain_ready_i(drain_ready_i),
  .drain_data_o(drain_data_o),
  .drain_target_dot_o(drain_target_dot_o),
  .drain_fill_slot_o(drain_fill_slot_o)
);
endmodule
