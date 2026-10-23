// Phase-selected writes with ordered retirement. beat_done is delayed until
// SRAM commit, so circular DMA cannot release a partially written slot.
module edge_dtcm_h4_stream_writer (
  input wire clk, rst_b,
  input wire [2:0] phase_i,
  input wire valid_i,
  output wire ready_o,
  input wire [13:0] addr_i,
  input wire [127:0] data_i,
  input wire [15:0] strb_i,
  output wire busy_o, done_o,
  output reg req_o,
  output wire [13:0] addr_o,
  output wire [127:0] data_o,
  output wire [15:0] strb_o,
  input wire grant_i
);
  reg [13:0] addresses [0:15];
  reg [127:0] data [0:15];
  reg [15:0] strobes [0:15];
  reg [15:0] occupied, issued, committed;
  reg [3:0] head, tail;
  reg [3:0] tag [0:2];
  reg [2:0] pending;
  reg [3:0] selected;
  integer index;
  wire [2:0] pair_idx={2'(phase_i[1:0]+3),~phase_i[2]};
  assign ready_o=!occupied[tail];
  assign busy_o=|occupied;
  assign done_o=occupied[head] && committed[head];
  assign addr_o=addresses[selected];
  assign data_o=data[selected];
  assign strb_o=strobes[selected];
  always @* begin
    req_o=0;selected=head;
    for(integer k=0;k<16;k=k+1) begin
      index=(int'(head)+k)%16;
      if(!req_o && occupied[index] && !issued[index] && addresses[index][3:1]==pair_idx) begin
        req_o=1;selected=4'(index);
      end
    end
  end
  always @(posedge clk or negedge rst_b) begin
    if(!rst_b) begin occupied<=0;issued<=0;committed<=0;head<=0;tail<=0;pending<=0;end
    else begin
      pending<={pending[1:0],req_o && grant_i};
      if(valid_i && ready_o) begin
        occupied[tail]<=1;issued[tail]<=0;committed[tail]<=0;
        addresses[tail]<=addr_i;data[tail]<=data_i;strobes[tail]<=strb_i;tail<=tail+1'b1;
      end
      if(req_o && grant_i) issued[selected]<=1;
      if(pending[2]) committed[tag[2]]<=1;
      if(done_o) begin occupied[head]<=0;head<=head+1'b1;end
    end
  end
  always @(posedge clk) begin
    tag[0]<=selected;tag[1]<=tag[0];tag[2]<=tag[1];
  end
endmodule
