// Compatibility boundary for bank-addressed tensor requests. It maps the
// physical bank bundle to the wide backend's client lanes and uses captured
// issue phase to restore responses. This is not a wire-area optimization.
module edge_dtcm_h4_wide_bank_bridge (
  input wire clk, rst_b,
  output wire ready_o,
  output wire [3:0] phase_o,
  input wire [15:0] req_i, write_i,
  input wire [159:0] addr_i,
  input wire [1023:0] data_i,
  input wire [127:0] strb_i,
  output wire [15:0] valid_o,
  output wire [1023:0] data_o
);
  wire [2:0] phase;
  assign phase_o={phase,1'b0};
  reg [7:0] req, wr;
  reg [103:0] addr;
  reg [1023:0] data;
  reg [127:0] strb;
  wire [7:0] grant, rsp_valid;
  wire [1023:0] rsp_data;
  reg [2:0] phase_q [0:3];
  reg [15:0] reads_q [0:3];
  integer pair_idx, bank_idx;
  always @* begin
    req=0;wr=0;addr=0;data=0;strb=0;
    for(integer lane=0;lane<8;lane=lane+1) begin
      pair_idx=2*((lane/2+int'(phase[1:0]))%4)
          +((lane%2)^((lane>=4)?int'(phase[2]):0));
      bank_idx=2*pair_idx;
      req[lane]=req_i[bank_idx] || req_i[bank_idx+1];
      wr[lane]=(req_i[bank_idx] && write_i[bank_idx]) || (req_i[bank_idx+1] && write_i[bank_idx+1]);
      addr[lane*13+:13]={req_i[bank_idx] ? addr_i[bank_idx*10+:10] : addr_i[(bank_idx+1)*10+:10],3'(pair_idx)};
      data[lane*128+:128]=data_i[bank_idx*64+:128];
      strb[lane*16+:16]={req_i[bank_idx+1] && write_i[bank_idx+1] ? strb_i[(bank_idx+1)*8+:8] : 8'b0,
          req_i[bank_idx] && write_i[bank_idx] ? strb_i[bank_idx*8+:8] : 8'b0};
    end
    // A BF16/host access may use only part of a wide port. Reserve both
    // halves; the other half is a dummy read or a zero-strobe write.
    for(integer p=0;p<2;p=p+1) begin
      if(req[2*p] && !req[2*p+1]) wr[2*p+1]=wr[2*p];
      if(req[2*p+1] && !req[2*p]) wr[2*p]=wr[2*p+1];
      req[2*p]=req[2*p] || req[2*p+1];
      req[2*p+1]=req[2*p];
    end
  end
  always @(posedge clk or negedge rst_b)
    if(!rst_b) begin
      for(integer k=0;k<4;k=k+1) reads_q[k]<=0;
    end else begin
      reads_q[0]<=ready_o ? req_i & ~write_i : 16'b0;
      for(integer k=1;k<4;k=k+1) reads_q[k]<=reads_q[k-1];
    end
  always @(posedge clk) begin
    phase_q[0]<=phase;
    for(integer k=1;k<4;k=k+1) phase_q[k]<=phase_q[k-1];
  end
  generate for(genvar bank=0;bank<16;bank=bank+1) begin: RESPONSE
    wire [1:0] port_idx=2'(bank/4)-phase_q[3][1:0];
    wire half_idx=1'((bank/2)%2) ^ (port_idx[1] && phase_q[3][2]);
    wire [2:0] lane={port_idx,half_idx};
    assign valid_o[bank]=reads_q[3][bank] && rsp_valid[lane];
    assign data_o[bank*64+:64]=rsp_data[lane*128+(bank%2)*64+:64];
  end endgenerate
  edge_dtcm_h4_wide x_backend(.clk(clk),.rst_b(rst_b),.ready_o(ready_o),.phase_o(phase),
    .req_i(req),.write_i(wr),.addr_i(addr),.data_i(data),.strb_i(strb),
    .grant_o(grant),.valid_o(rsp_valid),.data_o(rsp_data));
`ifndef SYNTHESIS
  always @(posedge clk) if(rst_b && ready_o) begin
    if(grant!=req) $fatal(1,"wide bank bridge dropped request");
    for(integer b=0;b<16;b=b+2)
      if(req_i[b] && req_i[b+1] &&
          (addr_i[b*10+:10]!=addr_i[(b+1)*10+:10] || write_i[b]!=write_i[b+1]))
        $fatal(1,"wide bank bridge incompatible 64-bit halves");
  end
`endif
endmodule
