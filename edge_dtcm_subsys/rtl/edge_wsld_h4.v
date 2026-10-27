// Scale-first WSLD slot bound to a wide-schedule narrow lane. The existing
// byte aligner is unchanged; ordered transport beats are delivered with a
// one-cycle acknowledged response after the slot reader requests them.
module edge_wsld_h4 #(
  parameter PORT = 2,
  parameter HALF = 1,
  parameter READ_LATENCY = 4
)(
  input wire clk, rst_b,
  input wire fabric_ready_i,
  input wire [2:0] phase_i,
  input wire start_i,
  output wire start_ready_o,
  input wire [15:0] base_i,
  input wire [31:0] config_i,
  input wire [15:0] global_bf16_i,
  output wire [31:0] sld_extra,
  output reg busy_o,
  output reg done_o,
  output wire req_o,
  output wire [12:0] addr_o,
  input wire grant_i,
  input wire rsp_valid_i,
  input wire [127:0] rsp_data_i,
  input wire sld_req, wld_req,
  output wire sld_ready, wld_ready,
  output wire sld_rvalid, wld_rvalid,
  output wire [127:0] sld_rdata, wld_rdata
);
  wire [15:0] weight_bytes = config_i[19:16]==1 ? {1'b0,config_i[7:0],7'b0}
      : config_i[19:16]==4 ? {3'b0,config_i[7:0],5'b0}
      : {2'b0,config_i[7:0],6'b0};
  wire [15:0] group_payload_bytes = weight_bytes + (config_i[15:12]==0 ?
      {11'b0,config_i[11:8],1'b0} : {12'b0,config_i[11:8]});
  wire [15:0] payload_bytes = config_i[20] ? group_payload_bytes << 1 : group_payload_bytes;
  wire [13:0] beats = 14'((payload_bytes+16'd15)>>4);
  wire descriptor_valid = config_i[7:0]!=0 && config_i[15:12]<=2 && config_i[31:21]==0
      && (!config_i[20] || (config_i[11:8]==8 && config_i[15:12]!=0))
      && (config_i[11:8]==1 || config_i[11:8]==8)
      && config_i[19:16]>=1 && config_i[19:16]<=5
      && base_i[0]==0 && base_i[15:14]==0
      && ({1'b0,base_i[13:1]}+beats<=14'd8192);
  wire transport_start_ready, transport_valid, transport_busy;
  wire [127:0] transport_data;
  wire slot_req;
  wire [15:0] slot_addr;
  wire slot_ready = transport_valid;
  wire transfer = slot_req && slot_ready;
  wire fire = start_i && start_ready_o;
  reg response_q;
  reg [127:0] response_data_q;
  reg [31:0] config_q;
  reg [15:0] global_q;
  reg [11:0] weights_left_q;
  reg [READ_LATENCY-1:0] last_q;
  assign start_ready_o = !busy_o && transport_start_ready && !response_q && descriptor_valid;
  always @(posedge clk or negedge rst_b)
    if(!rst_b) begin
      response_q<=0; busy_o<=0; done_o<=0; config_q<=0;global_q<=16'h3f80;
      weights_left_q<=0; last_q<=0;
    end else begin
      response_q<=transfer;
      done_o<=0;
      last_q[0]<=wld_req && wld_ready && weights_left_q==1;
      for(integer k=1;k<READ_LATENCY;k=k+1) last_q[k]<=last_q[k-1];
      if(fire) begin
        config_q<=config_i;global_q<=global_bf16_i; busy_o<=1;
        weights_left_q<=config_i[20] ? weight_bytes[15:4] << 1 : weight_bytes[15:4];
      end else if(wld_req && wld_ready) weights_left_q<=weights_left_q-1'b1;
      if(last_q[READ_LATENCY-1]) begin busy_o<=0; done_o<=1; end
    end
  always @(posedge clk) if(transfer) response_data_q<=transport_data;
  edge_dtcm_h4_narrow_reader #(.PORT(PORT),.HALF(HALF)) x_transport (
    .clk(clk),.rst_b(rst_b),.fabric_ready_i(fabric_ready_i),.phase_i(phase_i),
    .start_i(fire),.start_ready_o(transport_start_ready),
    .base_i(base_i[13:1]),.count_i(beats),.busy_o(transport_busy),.done_o(),
    .req_o(req_o),.addr_o(addr_o),.grant_i(grant_i),
    .rsp_valid_i(rsp_valid_i),.rsp_data_i(rsp_data_i),
    .valid_o(transport_valid),.data_o(transport_data),.ready_i(slot_req));
  edge_wsld_slot_reader #(.READ_LATENCY(READ_LATENCY)) x_slot (
    .clk(clk),.cpurst_b(rst_b),.start(fire),.active(busy_o),
    .base_addr(base_i),.config_i(fire ? config_i : config_q),
    .global_bf16_i(fire?global_bf16_i:global_q),.sld_extra(sld_extra),
    .rd_req(slot_req),.rd_addr(slot_addr),.rd_ready(slot_ready),
    .rd_rvalid(response_q),.rd_rdata(response_data_q),
    .sld_req(sld_req),.wld_req(wld_req),.sld_ready(sld_ready),.wld_ready(wld_ready),
    .sld_rvalid(sld_rvalid),.wld_rvalid(wld_rvalid),
    .sld_rdata(sld_rdata),.wld_rdata(wld_rdata));
`ifndef SYNTHESIS
  always @(posedge clk) if(rst_b && done_o && (transport_busy || response_q))
    $fatal(1,"WSLD completed before transport drain");
`endif
endmodule
