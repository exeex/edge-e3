// Existing AXI DMA engine bound to one wide-schedule narrow lane.
// Completion waits for both AXI retirement and physical SRAM transport drain.
module edge_dma_h4_wide #(
  parameter AXI_ADDR_WIDTH=40,
  parameter PORT=3,
  parameter HALF=1
)(
  input wire clk, rst_b,
  input wire fabric_ready_i,
  input wire [2:0] phase_i,
  input wire start_i,
  output wire start_ready_o,
  input wire dir_i,
  input wire [AXI_ADDR_WIDTH-1:0] axi_addr_i,
  input wire [15:0] dtcm_addr_i,
  input wire [31:0] length_i,
  output reg busy_o, done_o,
  output wire req_o, write_o,
  output wire [12:0] addr_o,
  output wire [127:0] data_o,
  output wire [15:0] strb_o,
  input wire grant_i, rsp_valid_i,
  input wire [127:0] rsp_data_i,
  output wire [AXI_ADDR_WIDTH-1:0] axi_araddr, axi_awaddr,
  output wire [7:0] axi_arlen, axi_awlen,
  output wire axi_arvalid, axi_awvalid,
  input wire axi_arready, axi_awready,
  input wire [127:0] axi_rdata,
  input wire axi_rvalid, axi_rlast,
  output wire axi_rready,
  output wire [127:0] axi_wdata,
  output wire [15:0] axi_wstrb,
  output wire axi_wvalid, axi_wlast,
  input wire axi_wready, axi_bvalid,
  output wire axi_bready
);
  wire [31:0] beat_count= (length_i>>4) + {31'b0,|length_i[3:0]};
  wire range_ok=dtcm_addr_i[0]==0 && dtcm_addr_i[15:14]==0
      && beat_count<=8192 && ({19'b0,dtcm_addr_i[13:1]}+beat_count<=8192);
  wire read_start_ready,write_start_ready,read_busy,write_busy;
  wire engine_busy,engine_done;
  reg dir_q,engine_done_q;
  wire fire=start_i && start_ready_o;
  wire launch=fire && length_i!=0;
  wire read_req,write_req,read_valid,write_ready;
  wire [12:0] read_addr,write_addr;
  wire [127:0] read_data,write_data;
  wire [15:0] write_mask;
  wire dma_req,dma_we,dma_ready;
  wire [13:0] dma_addr;
  wire [127:0] dma_data;
  wire [15:0] dma_mask;
  wire transfer=dir_q && dma_req && dma_ready;
  reg response_q;
  reg [127:0] response_data_q;
  assign start_ready_o=!busy_o && !engine_busy && !response_q
      && read_start_ready && write_start_ready && range_ok;
  // The legacy engine treats ready as acceptance, including its A2D FIFO
  // pop path. Never advertise it outside an actual DTCM request.
  assign dma_ready=dma_req && (dir_q ? read_valid : write_ready);
  assign req_o=dir_q ? read_req : write_req;
  assign write_o=!dir_q;
  assign addr_o=dir_q ? read_addr : write_addr;
  assign data_o=write_data;
  assign strb_o=dir_q ? 16'b0 : write_mask;
  always @(posedge clk or negedge rst_b)
    if(!rst_b)begin busy_o<=0;done_o<=0;dir_q<=0;engine_done_q<=0;response_q<=0;end
    else begin
      done_o<=0;response_q<=transfer;
      if(fire)begin
        busy_o<=length_i!=0;done_o<=length_i==0;dir_q<=dir_i;engine_done_q<=0;
      end else if(busy_o)begin
        if(engine_done)engine_done_q<=1;
        if((engine_done_q || engine_done) && !read_busy && !write_busy && !response_q)begin
          busy_o<=0;done_o<=1;
        end
      end
    end
  always @(posedge clk) if(transfer)response_data_q<=read_data;
  edge_dtcm_h4_narrow_reader #(.PORT(PORT),.HALF(HALF)) x_reader(
    .clk(clk),.rst_b(rst_b),.fabric_ready_i(fabric_ready_i),.phase_i(phase_i),
    .start_i(launch && dir_i),.start_ready_o(read_start_ready),
    .base_i(dtcm_addr_i[13:1]),.count_i(beat_count[13:0]),.busy_o(read_busy),.done_o(),
    .req_o(read_req),.addr_o(read_addr),.grant_i(grant_i && dir_q),
    .rsp_valid_i(rsp_valid_i && dir_q),.rsp_data_i(rsp_data_i),
    .valid_o(read_valid),.data_o(read_data),.ready_i(dir_q && dma_req));
  edge_dtcm_h4_narrow_writer #(.PORT(PORT),.HALF(HALF)) x_writer(
    .clk(clk),.rst_b(rst_b),.fabric_ready_i(fabric_ready_i),.phase_i(phase_i),
    .start_i(launch && !dir_i),.start_ready_o(write_start_ready),
    .base_i(dtcm_addr_i[13:1]),.count_i(beat_count[13:0]),.busy_o(write_busy),.done_o(),
    .valid_i(!dir_q && dma_req && dma_we),.ready_o(write_ready),.data_i(dma_data),.strb_i(dma_mask),
    .req_o(write_req),.addr_o(write_addr),.data_o(write_data),.strb_o(write_mask),
    .grant_i(grant_i && !dir_q));
  edge_dtcm_dma #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),.DTCM_ADDR_WIDTH(14)) x_dma(
    .clk(clk),.cpurst_b(rst_b),.start(launch),.start_dir(dir_i),
    .start_axi_addr(axi_addr_i),.start_dtcm_addr(dtcm_addr_i[13:0]),.start_len(length_i),
    .dma_busy(engine_busy),.dma_done(engine_done),.dma_dtcm_req(dma_req),.dma_dtcm_we(dma_we),
    .dma_dtcm_addr(dma_addr),.dma_dtcm_wdata(dma_data),.dma_dtcm_wstrb(dma_mask),
    .dma_dtcm_ready(dma_ready),.dma_dtcm_rvalid(response_q),.dma_dtcm_rdata(response_data_q),
    .dma_lease_channel(),.dma_lease_cycles(),.dma_lease_delay(),.dma_lease_valid(),
    .axi_araddr(axi_araddr),
    .axi_arlen(axi_arlen),
    .axi_arvalid(axi_arvalid),
    .axi_arready(axi_arready),
    .axi_awaddr(axi_awaddr),
    .axi_awlen(axi_awlen),
    .axi_awvalid(axi_awvalid),
    .axi_awready(axi_awready),
    .axi_rdata(axi_rdata),
    .axi_rvalid(axi_rvalid),
    .axi_rlast(axi_rlast),
    .axi_rready(axi_rready),
    .axi_wdata(axi_wdata),
    .axi_wstrb(axi_wstrb),
    .axi_wvalid(axi_wvalid),
    .axi_wlast(axi_wlast),
    .axi_wready(axi_wready),
    .axi_bvalid(axi_bvalid),
    .axi_bready(axi_bready));
`ifndef SYNTHESIS
  reg [13:0] next_address_q;
  always @(posedge clk or negedge rst_b)
    if(!rst_b) next_address_q<=0;
    else if(fire) next_address_q<=dtcm_addr_i[13:0];
    else if(dma_req && dma_ready) begin
      if(dma_addr!=next_address_q || dma_we==dir_q)
        $fatal(1,"DMA narrow transport address/direction mismatch");
      next_address_q<=next_address_q+14'd2;
    end
`endif
endmodule
