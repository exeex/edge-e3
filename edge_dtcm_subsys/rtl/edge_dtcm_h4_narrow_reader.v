// Experimental contiguous 128-bit read stream over a wide-schedule narrow
// lane. The eight-beat issue window follows local H4 ownership, while the
// reserved reorder buffer restores contiguous order. No raw-route stalls.
module edge_dtcm_h4_narrow_reader #(
  parameter PORT = 2,
  parameter HALF = 0
)(
  input wire clk, rst_b,
  input wire fabric_ready_i,
  input wire [2:0] phase_i,
  input wire start_i,
  output wire start_ready_o,
  input wire [12:0] base_i,
  input wire [13:0] count_i,
  output reg busy_o,
  output reg done_o,
  output wire req_o,
  output wire [12:0] addr_o,
  input wire grant_i,
  input wire rsp_valid_i,
  input wire [127:0] rsp_data_i,
  output wire valid_o,
  output wire [127:0] data_o,
  input wire ready_i
);
  reg [12:0] base_q;
  reg [13:0] count_q, window_q, consumed_q, received_q;
  reg [7:0] issued_q;
  reg output_started_q;
  wire [1:0] group_idx = phase_i[1:0] + 2'(PORT);
  wire half_idx = 1'(HALF) ^ phase_i[2];
  wire [2:0] offset = {group_idx, half_idx} - base_q[2:0];
  wire [13:0] index = window_q + {11'b0, offset};
  wire credit, take_valid;
  wire accepted = req_o && grant_i;
  reg [3:0] tag_q [0:3];
  wire [7:0] issued_next = issued_q | (accepted ? (8'b1 << offset) : 8'b0);
  reg window_complete;
  always @* begin
    window_complete = 1;
    for (integer k=0; k<8; k=k+1)
      if (window_q + 14'(k) < count_q && !issued_next[k]) window_complete=0;
  end
  assign start_ready_o = !busy_o && fabric_ready_i;
  assign addr_o = base_q + index[12:0];
  assign req_o = busy_o && fabric_ready_i && index < count_q
      && !issued_q[offset] && credit;
  assign valid_o = busy_o && output_started_q && take_valid;
  always @(posedge clk) begin
    tag_q[0] <= index[3:0];
    for (integer k=1; k<4; k=k+1) tag_q[k] <= tag_q[k-1];
  end
  always @(posedge clk or negedge rst_b)
    if (!rst_b) begin
      busy_o<=0; done_o<=0; base_q<=0; count_q<=0;
      window_q<=0; issued_q<=0; consumed_q<=0; received_q<=0;
      output_started_q<=0;
    end else begin
      done_o<=0;
      if (start_i && start_ready_o) begin
        base_q<=base_i; count_q<=count_i; window_q<=0; issued_q<=0;
        consumed_q<=0; received_q<=0; output_started_q<=0;
        busy_o<=count_i!=0; done_o<=count_i==0;
      end else if (busy_o) begin
        if (window_q < count_q && window_complete) begin
          window_q<=window_q+14'd8; issued_q<=0;
        end else issued_q<=issued_next;
        if (rsp_valid_i) begin
          received_q<=received_q+14'd1;
          if (received_q==14'd7 || received_q+14'd1==count_q) output_started_q<=1;
        end
        if (valid_o && ready_i) begin
          consumed_q<=consumed_q+14'd1;
          if (consumed_q+14'd1==count_q) begin busy_o<=0; done_o<=1; end
        end
      end
    end
  edge_dtcm_beat_reorder x_reorder (
    .clk(clk), .rst_b(rst_b), .alloc_i(accepted),
    .alloc_index_i(index[3:0]), .alloc_ready_o(credit),
    .fill_i(rsp_valid_i), .fill_index_i(tag_q[3]), .fill_data_i(rsp_data_i),
    .take_index_i(consumed_q[3:0]), .take_ready_i(valid_o && ready_i),
    .take_valid_o(take_valid), .take_data_o(data_o));
`ifndef SYNTHESIS
  always @(posedge clk) if (rst_b) begin
    if (start_i && start_ready_o && ({1'b0,base_i}+count_i > 14'd8192))
      $fatal(1, "narrow reader range exceeds DTCM");
    if (rsp_valid_i && !busy_o) $fatal(1, "narrow reader unexpected response");
  end
`endif
endmodule
