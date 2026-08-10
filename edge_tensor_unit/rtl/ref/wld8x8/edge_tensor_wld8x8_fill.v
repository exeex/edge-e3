// Reference wrapper for the original full 8x8 WLD staging array.
module edge_tensor_wld8x8_fill(
  clk,
  rst_b,
  start,
  start_ready,
  start_bf16_mode,
  start_transpose,
  busy,
  done,
  load_valid,
  load_idx,
  load_data,
  load_done,
  weight_fill_start,
  weight_fill_start_ready,
  weight_fill_valid,
  weight_fill_ready,
  weight_fill_pair_idx,
  weight_fill_data,
  weight_fill_last,
  weight_fill_bf16_mode
);

parameter DATA_WIDTH = 64;
parameter PAIR_WIDTH = DATA_WIDTH * 2;

input                  clk;
input                  rst_b;
input                  start;
input                  start_bf16_mode;
input                  start_transpose;
input                  load_valid;
input  [2:0]           load_idx;
input  [PAIR_WIDTH-1:0] load_data;
input                  weight_fill_start_ready;
input                  weight_fill_ready;
output                 start_ready;
output                 busy;
output                 done;
output                 load_done;
output                 weight_fill_start;
output                 weight_fill_valid;
output [1:0]           weight_fill_pair_idx;
output [PAIR_WIDTH-1:0] weight_fill_data;
output                 weight_fill_last;
output                 weight_fill_bf16_mode;

reg                    busy_q;
reg                    drain_pending_q;
reg                    drain_bf16_mode_q;
reg                    drain_transpose_q;

wire                   start_accept;
wire                   drain_busy;
wire [1:0]             drain_col_pair;
wire [PAIR_WIDTH-1:0]  drain_data;
wire                   drain_done;
wire                   drain_start;
wire                   drain_valid;

assign start_ready = (!busy_q || drain_done)
                   && !drain_pending_q
                   && weight_fill_start_ready;
assign start_accept = start && start_ready;
assign busy = busy_q;
assign done = drain_done;
assign drain_start = drain_pending_q;

assign weight_fill_start = start_accept;
assign weight_fill_bf16_mode = start_accept ? start_bf16_mode
                                            : drain_bf16_mode_q;
assign weight_fill_valid = drain_valid;
assign weight_fill_pair_idx[1:0] = drain_col_pair[1:0];
assign weight_fill_data[PAIR_WIDTH-1:0] = drain_data[PAIR_WIDTH-1:0];
assign weight_fill_last = drain_done;

edge_tensor_wld_reg x_edge_tensor_wld_reg (
  .clk(clk),
  .clear(start_accept),
  .drain_busy(drain_busy),
  .drain_col_pair(drain_col_pair[1:0]),
  .drain_data(drain_data[PAIR_WIDTH-1:0]),
  .drain_done(drain_done),
  .drain_start(drain_start),
  .drain_bf16_mode(drain_bf16_mode_q),
  .drain_transpose(drain_transpose_q),
  .drain_valid(drain_valid),
  .load_data(load_data[PAIR_WIDTH-1:0]),
  .load_done(load_done),
  .load_idx(load_idx[2:0]),
  .load_bf16_mode(drain_bf16_mode_q),
  .load_valid(load_valid),
  .rst_b(rst_b)
);

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    busy_q <= 1'b0;
    drain_pending_q <= 1'b0;
    drain_bf16_mode_q <= 1'b0;
    drain_transpose_q <= 1'b0;
  end else begin
    if (start_accept) begin
      busy_q <= 1'b1;
      drain_pending_q <= 1'b1;
      drain_bf16_mode_q <= start_bf16_mode;
      drain_transpose_q <= start_transpose;
    end else begin
      if (drain_start)
        drain_pending_q <= 1'b0;
      if (drain_done)
        busy_q <= 1'b0;
    end
  end
end

endmodule
