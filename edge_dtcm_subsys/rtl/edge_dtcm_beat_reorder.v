// Indexed 128-bit beat storage with issue-time reservation. A client may
// select sequential output indices (read deskew) or permuted ones (writes).
// Reservations include all responses in flight; backpressure ends here.
module edge_dtcm_beat_reorder #(
  parameter DATA_WIDTH = 128,
  parameter INDEX_WIDTH = 4
)(
  input wire clk, rst_b,
  input wire alloc_i,
  input wire [INDEX_WIDTH-1:0] alloc_index_i,
  output wire alloc_ready_o,
  input wire fill_i,
  input wire [INDEX_WIDTH-1:0] fill_index_i,
  input wire [DATA_WIDTH-1:0] fill_data_i,
  input wire [INDEX_WIDTH-1:0] take_index_i,
  input wire take_ready_i,
  output wire take_valid_o,
  output wire [DATA_WIDTH-1:0] take_data_o
);
  localparam DEPTH = 1 << INDEX_WIDTH;
  reg [DEPTH-1:0] reserved_q, valid_q;
  reg [DATA_WIDTH-1:0] data_q [0:DEPTH-1];
  assign alloc_ready_o = !reserved_q[alloc_index_i];
  assign take_valid_o = valid_q[take_index_i];
  assign take_data_o = data_q[take_index_i];
  always @(posedge clk or negedge rst_b)
    if (!rst_b) begin reserved_q <= 0; valid_q <= 0; end
    else begin
      if (alloc_i && alloc_ready_o) reserved_q[alloc_index_i] <= 1;
      if (fill_i) valid_q[fill_index_i] <= 1;
      if (take_valid_o && take_ready_i) begin
        reserved_q[take_index_i] <= 0;
        valid_q[take_index_i] <= 0;
      end
    end
  always @(posedge clk) if (fill_i) data_q[fill_index_i] <= fill_data_i;
`ifndef SYNTHESIS
  always @(posedge clk) if (rst_b) begin
    if (alloc_i && !alloc_ready_o) $fatal(1, "reorder allocation without credit");
    if (fill_i && ((!reserved_q[fill_index_i] &&
        !(alloc_i && alloc_ready_o && alloc_index_i == fill_index_i)) ||
        valid_q[fill_index_i])) $fatal(1, "unreserved/duplicate reorder response");
  end
`endif
endmodule
