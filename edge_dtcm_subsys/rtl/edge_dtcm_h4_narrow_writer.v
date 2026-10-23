// Contiguous narrow writes -> local H4 commutator order. Byte masks travel
// with data. Completion includes the fixed SRAM write pipeline tail.
module edge_dtcm_h4_narrow_writer #(
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
  input wire valid_i,
  output wire ready_o,
  input wire [127:0] data_i,
  input wire [15:0] strb_i,
  output wire req_o,
  output wire [12:0] addr_o,
  output wire [127:0] data_o,
  output wire [15:0] strb_o,
  input wire grant_i
);
  reg [12:0] base_q;
  reg [13:0] count_q, window_q, loaded_q, sent_q;
  reg [7:0] issued_q;
  reg [1:0] drain_q;
  wire [1:0] group_idx = phase_i[1:0] + 2'(PORT);
  wire half_idx = 1'(HALF) ^ phase_i[2];
  wire [2:0] offset = {group_idx, half_idx} - base_q[2:0];
  wire [13:0] index = window_q + {11'b0,offset};
  wire credit, take_valid;
  wire enqueue = valid_i && ready_o;
  wire accepted = req_o && grant_i;
  wire [143:0] payload;
  wire [7:0] issued_next = issued_q | (accepted ? (8'b1 << offset) : 8'b0);
  reg window_complete;
  always @* begin
    window_complete=1;
    for(integer k=0;k<8;k=k+1)
      if(window_q+14'(k)<count_q && !issued_next[k]) window_complete=0;
  end
  assign start_ready_o = !busy_o && fabric_ready_i;
  assign ready_o = busy_o && loaded_q<count_q && credit;
  assign req_o = busy_o && fabric_ready_i && index<count_q
      && !issued_q[offset] && take_valid;
  assign addr_o = base_q + index[12:0];
  assign data_o = payload[127:0];
  assign strb_o = payload[143:128];
  always @(posedge clk or negedge rst_b)
    if(!rst_b) begin
      busy_o<=0; done_o<=0; base_q<=0; count_q<=0; window_q<=0;
      loaded_q<=0; sent_q<=0; issued_q<=0; drain_q<=0;
    end else begin
      done_o<=0;
      if(start_i && start_ready_o) begin
        base_q<=base_i; count_q<=count_i; window_q<=0;
        loaded_q<=0; sent_q<=0; issued_q<=0; drain_q<=0;
        busy_o<=count_i!=0; done_o<=count_i==0;
      end else if(busy_o) begin
        if(enqueue) loaded_q<=loaded_q+14'd1;
        if(window_q<count_q && window_complete) begin
          window_q<=window_q+14'd8; issued_q<=0;
        end else issued_q<=issued_next;
        if(accepted) begin
          sent_q<=sent_q+14'd1;
          if(sent_q+14'd1==count_q) drain_q<=3;
        end
        if(drain_q!=0) begin
          drain_q<=drain_q-2'd1;
          if(drain_q==1) begin busy_o<=0; done_o<=1; end
        end
      end
    end
  edge_dtcm_beat_reorder #(.DATA_WIDTH(144)) x_reorder (
    .clk(clk), .rst_b(rst_b), .alloc_i(enqueue),
    .alloc_index_i(loaded_q[3:0]), .alloc_ready_o(credit),
    .fill_i(enqueue), .fill_index_i(loaded_q[3:0]), .fill_data_i({strb_i,data_i}),
    .take_index_i(index[3:0]), .take_ready_i(accepted),
    .take_valid_o(take_valid), .take_data_o(payload));
`ifndef SYNTHESIS
  always @(posedge clk) if(rst_b && start_i && start_ready_o &&
      ({1'b0,base_i}+count_i>14'd8192)) $fatal(1,"narrow writer range exceeds DTCM");
`endif
endmodule
