module edge_dtcm_other_bank16_adapter(
  clk,
  cpurst_b,
  phase,
  bank_rdata,
  dma_addr,
  dma_rdata,
  dma_ready,
  dma_req,
  dma_rvalid,
  dma_we,
  dma_wdata,
  dma_wstrb,
  lsu_addr,
  lsu_rdata,
  lsu_ready,
  lsu_req,
  lsu_rvalid,
  lsu_we,
  lsu_wdata,
  lsu_wstrb,
  sld_addr,
  sld_rdata,
  sld_ready,
  sld_req,
  sld_rvalid,
  wld_addr,
  wld_rdata,
  wld_ready,
  wld_req,
  wld_rvalid,
  upper_bank_req,
  upper_bank_we,
  upper_bank_addr,
  upper_bank_wdata,
  upper_bank_wstrb
);

parameter READ_LATENCY = 1;
parameter LOWER_SIX = 0;
parameter ADDR_WIDTH       = 14;
parameter DATA_WIDTH       = 64;
parameter BYTE_WIDTH       = DATA_WIDTH / 8;
parameter DMA_DATA_WIDTH   = 128;
parameter DMA_BYTE_WIDTH   = DMA_DATA_WIDTH / 8;
parameter BANK_NUM         = 16;
parameter BANK_INDEX_WIDTH = 4;
parameter SRAM_ADDR_WIDTH  = 10;

localparam PAIR_NUM = 8;
localparam PAIR_REQ_WIDTH = 2;
localparam PAIR_WE_WIDTH = 2;
localparam PAIR_DATA_WIDTH = 2 * DATA_WIDTH;
localparam PAIR_BYTE_WIDTH = 2 * BYTE_WIDTH;
localparam REQUEST_REQ_LSB = 0;
localparam REQUEST_WE_LSB = REQUEST_REQ_LSB + PAIR_REQ_WIDTH;
localparam REQUEST_ADDR_LSB = REQUEST_WE_LSB + PAIR_WE_WIDTH;
localparam REQUEST_WDATA_LSB = REQUEST_ADDR_LSB + SRAM_ADDR_WIDTH;
localparam REQUEST_WSTRB_LSB = REQUEST_WDATA_LSB + PAIR_DATA_WIDTH;
localparam REQUEST_PAYLOAD_WIDTH = REQUEST_WSTRB_LSB + PAIR_BYTE_WIDTH;

input                         clk;
input                         cpurst_b;
input  [BANK_INDEX_WIDTH-1:0] phase;
input  [BANK_NUM*DATA_WIDTH-1:0] bank_rdata;
input  [ADDR_WIDTH-1:0]       dma_addr;
input                         dma_req;
input                         dma_we;
input  [DMA_DATA_WIDTH-1:0]   dma_wdata;
input  [DMA_BYTE_WIDTH-1:0]   dma_wstrb;
input  [ADDR_WIDTH-1:0]       lsu_addr;
input                         lsu_req;
input                         lsu_we;
input  [DATA_WIDTH-1:0]       lsu_wdata;
input  [BYTE_WIDTH-1:0]       lsu_wstrb;
input  [ADDR_WIDTH-1:0]       sld_addr;
input                         sld_req;
input  [ADDR_WIDTH-1:0]       wld_addr;
input                         wld_req;
output [DMA_DATA_WIDTH-1:0]   dma_rdata;
output                        dma_ready;
output                        dma_rvalid;
output [DATA_WIDTH-1:0]       lsu_rdata;
output                        lsu_ready;
output                        lsu_rvalid;
output [DMA_DATA_WIDTH-1:0]   sld_rdata;
output                        sld_ready;
output                        sld_rvalid;
output [DMA_DATA_WIDTH-1:0]   wld_rdata;
output                        wld_ready;
output                        wld_rvalid;
output [BANK_NUM-1:0]         upper_bank_req;
output [BANK_NUM-1:0]         upper_bank_we;
output [BANK_NUM*SRAM_ADDR_WIDTH-1:0] upper_bank_addr;
output [BANK_NUM*DATA_WIDTH-1:0] upper_bank_wdata;
output [BANK_NUM*BYTE_WIDTH-1:0] upper_bank_wstrb;

wire                          lsu_bank_req;
wire                          lsu_bank_we;
wire [BANK_INDEX_WIDTH-1:0]   lsu_bank;
wire [BANK_INDEX_WIDTH-1:0]   lsu_unused_bank1;
wire                          lsu_unused_bank1_valid;
wire [SRAM_ADDR_WIDTH-1:0]    lsu_bank_addr;
wire [DATA_WIDTH-1:0]         lsu_bank_wdata;
wire [BYTE_WIDTH-1:0]         lsu_bank_wstrb;
wire [BANK_INDEX_WIDTH-1:0]   lsu_rsp_bank0;
wire [BANK_INDEX_WIDTH-1:0]   lsu_rsp_bank1;
wire                          dma_pair_req;
wire                          dma_pair_we;
wire [BANK_INDEX_WIDTH-1:0]   dma_pair_bank0;
wire [BANK_INDEX_WIDTH-1:0]   dma_pair_bank1;
wire                          dma_unused_bank1_valid;
wire [SRAM_ADDR_WIDTH-1:0]    dma_pair_addr;
wire [DMA_DATA_WIDTH-1:0]     dma_pair_wdata;
wire [DMA_BYTE_WIDTH-1:0]     dma_pair_wstrb;
wire [BANK_INDEX_WIDTH-1:0]   dma_rsp_bank0_unused;
wire [BANK_INDEX_WIDTH-1:0]   dma_rsp_bank1_unused;
wire                          shared_ld_pair_req;
wire                          shared_ld_unused_bank_we;
wire [BANK_INDEX_WIDTH-1:0]   shared_ld_pair_bank0;
wire [BANK_INDEX_WIDTH-1:0]   shared_ld_pair_bank1;
wire                          shared_ld_unused_bank1_valid;
wire [SRAM_ADDR_WIDTH-1:0]    shared_ld_pair_addr;
wire [DMA_DATA_WIDTH-1:0]     shared_ld_unused_bank_wdata;
wire [DMA_BYTE_WIDTH-1:0]     shared_ld_unused_bank_wstrb;
wire [BANK_INDEX_WIDTH-1:0]   shared_ld_rsp_bank0_unused;
wire [BANK_INDEX_WIDTH-1:0]   shared_ld_rsp_bank1_unused;
wire                          shared_ld_select_wld;
wire                          shared_ld_req;
wire [ADDR_WIDTH-1:0]         shared_ld_addr;
wire                          shared_ld_ready;
wire                          shared_ld_rvalid;
wire [DMA_DATA_WIDTH-1:0]     shared_ld_rdata;
wire shared_ld_rsp_owner_wld_q;
reg [READ_LATENCY-1:0] owner_pipe;
integer stage;

wire [1:0]                    lsu_lane_req;
wire [1:0]                    lsu_lane_we;
wire [PAIR_DATA_WIDTH-1:0]    lsu_lane_wdata;
wire [PAIR_BYTE_WIDTH-1:0]    lsu_lane_wstrb;
wire [REQUEST_PAYLOAD_WIDTH-1:0] lsu_request_payload;
wire [REQUEST_PAYLOAD_WIDTH-1:0] dma_request_payload;
wire [REQUEST_PAYLOAD_WIDTH-1:0] shared_ld_request_payload;
wire [REQUEST_PAYLOAD_WIDTH-1:0] unused_channel_request_payload;
wire [4*REQUEST_PAYLOAD_WIDTH-1:0] logical_request_payload;
wire [PAIR_NUM*REQUEST_PAYLOAD_WIDTH-1:0] physical_request_payload;
wire [2:0]                    pair_phase;
wire [4*PAIR_DATA_WIDTH-1:0]  logical_response_payload;

genvar pair_i;

assign pair_phase[2:0] = phase[BANK_INDEX_WIDTH-1:1];

assign lsu_lane_req[1:0] =
    lsu_bank[0] ? {lsu_bank_req, 1'b0} : {1'b0, lsu_bank_req};
assign lsu_lane_we[1:0] = {2{lsu_bank_we}} & lsu_lane_req[1:0];
assign lsu_lane_wdata[PAIR_DATA_WIDTH-1:0] =
    lsu_bank[0]
    ? {lsu_bank_wdata[DATA_WIDTH-1:0], {DATA_WIDTH{1'b0}}}
    : {{DATA_WIDTH{1'b0}}, lsu_bank_wdata[DATA_WIDTH-1:0]};
assign lsu_lane_wstrb[PAIR_BYTE_WIDTH-1:0] =
    lsu_bank[0]
    ? {lsu_bank_wstrb[BYTE_WIDTH-1:0], {BYTE_WIDTH{1'b0}}}
    : {{BYTE_WIDTH{1'b0}}, lsu_bank_wstrb[BYTE_WIDTH-1:0]};

assign lsu_request_payload[REQUEST_PAYLOAD_WIDTH-1:0] =
    {lsu_lane_wstrb[PAIR_BYTE_WIDTH-1:0],
     lsu_lane_wdata[PAIR_DATA_WIDTH-1:0],
     lsu_bank_addr[SRAM_ADDR_WIDTH-1:0],
     lsu_lane_we[1:0], lsu_lane_req[1:0]};
assign dma_request_payload[REQUEST_PAYLOAD_WIDTH-1:0] =
    {dma_pair_wstrb[PAIR_BYTE_WIDTH-1:0],
     dma_pair_wdata[PAIR_DATA_WIDTH-1:0],
     dma_pair_addr[SRAM_ADDR_WIDTH-1:0],
     ({2{dma_pair_we}} & {2{dma_pair_req}}), {2{dma_pair_req}}};
assign shared_ld_request_payload[REQUEST_PAYLOAD_WIDTH-1:0] =
    {{PAIR_BYTE_WIDTH{1'b0}}, {PAIR_DATA_WIDTH{1'b0}},
     shared_ld_pair_addr[SRAM_ADDR_WIDTH-1:0], 2'b00,
     {2{shared_ld_pair_req}}};
assign unused_channel_request_payload[REQUEST_PAYLOAD_WIDTH-1:0] =
    {REQUEST_PAYLOAD_WIDTH{1'b0}};

// Compressed logical groups 0, 1, 2, and 3 represent fixed channels
// 1, 3, 5, and 7 in legacy mode. H4 maps LSU/DMA to 6/7 and
// keeps SLD/WLD together on lower channel 5.
assign logical_request_payload[4*REQUEST_PAYLOAD_WIDTH-1:0] =
    {unused_channel_request_payload, shared_ld_request_payload,
     dma_request_payload, lsu_request_payload};

generate if (LOWER_SIX) begin: SIX_CHANNELS
  // The shared SLD/WLD route belongs to lower channel 5. LSU/DMA own
  // upper 6/7. Decode each physical pair once; no upper/lower borrowing.
  reg [2:0] phase_pipe [0:READ_LATENCY-1];
  integer st;
  always @(posedge clk or negedge cpurst_b)
    if (!cpurst_b) begin
      for (st=0; st<READ_LATENCY; st=st+1) phase_pipe[st] <= 0;
    end else begin
      phase_pipe[0] <= pair_phase;
      for (st=1; st<READ_LATENCY; st=st+1) phase_pipe[st] <= phase_pipe[st-1];
    end
  for (genvar p=0; p<8; p=p+1) begin: PAIR
    wire [2:0] channel = 3'(p) - pair_phase;
    // Two binary payload choices. Unowned slots suppress request only;
    // there is no reason to zero their wide address/data/strobe buses.
    wire [REQUEST_PAYLOAD_WIDTH-1:0] upper_payload =
        channel[0] ? dma_request_payload : lsu_request_payload;
    wire [REQUEST_PAYLOAD_WIDTH-1:0] payload =
        channel[1] ? upper_payload : shared_ld_request_payload;
    assign physical_request_payload[p*REQUEST_PAYLOAD_WIDTH +: REQUEST_PAYLOAD_WIDTH] =
        {payload[REQUEST_PAYLOAD_WIDTH-1:PAIR_REQ_WIDTH],
         payload[PAIR_REQ_WIDTH-1:0] & {PAIR_REQ_WIDTH{channel >= 3'd5}}};
  end
  for (genvar c=0; c<3; c=c+1) begin: RESPONSE
    localparam [2:0] CHANNEL = c == 0 ? 3'd6 : c == 1 ? 3'd7 : 3'd5;
    wire [2:0] response_pair = phase_pipe[READ_LATENCY-1] + CHANNEL;
    assign logical_response_payload[c*PAIR_DATA_WIDTH +: PAIR_DATA_WIDTH] =
        bank_rdata[response_pair*PAIR_DATA_WIDTH +: PAIR_DATA_WIDTH];
  end
  assign logical_response_payload[3*PAIR_DATA_WIDTH +: PAIR_DATA_WIDTH] = 0;
end else begin: LEGACY_CHANNELS
edge_dtcm_upper_pair_router #(
  .REQUEST_WIDTH(REQUEST_PAYLOAD_WIDTH),
  .READ_LATENCY(READ_LATENCY),
  .RESPONSE_WIDTH(PAIR_DATA_WIDTH)
) x_upper_pair_router (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .pair_phase(pair_phase[2:0]),
  .logical_request_payload(
      logical_request_payload[4*REQUEST_PAYLOAD_WIDTH-1:0]),
  .physical_request_payload(
      physical_request_payload[PAIR_NUM*REQUEST_PAYLOAD_WIDTH-1:0]),
  .physical_response_payload(bank_rdata[BANK_NUM*DATA_WIDTH-1:0]),
  .logical_response_payload(
      logical_response_payload[4*PAIR_DATA_WIDTH-1:0])
);
end endgenerate

generate
  for (pair_i = 0; pair_i < PAIR_NUM; pair_i = pair_i + 1) begin: PHYSICAL_PAIR
    wire [REQUEST_PAYLOAD_WIDTH-1:0] pair_payload;

    assign pair_payload[REQUEST_PAYLOAD_WIDTH-1:0] =
        physical_request_payload[pair_i*REQUEST_PAYLOAD_WIDTH
                                 +: REQUEST_PAYLOAD_WIDTH];
    assign upper_bank_req[pair_i*2 +: 2] =
        pair_payload[REQUEST_REQ_LSB +: PAIR_REQ_WIDTH];
    assign upper_bank_we[pair_i*2 +: 2] =
        pair_payload[REQUEST_WE_LSB +: PAIR_WE_WIDTH];
    assign upper_bank_addr[(pair_i*2)*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] =
        pair_payload[REQUEST_ADDR_LSB +: SRAM_ADDR_WIDTH];
    assign upper_bank_addr[(pair_i*2+1)*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] =
        pair_payload[REQUEST_ADDR_LSB +: SRAM_ADDR_WIDTH];
    assign upper_bank_wdata[(pair_i*2)*DATA_WIDTH +: PAIR_DATA_WIDTH] =
        pair_payload[REQUEST_WDATA_LSB +: PAIR_DATA_WIDTH];
    assign upper_bank_wstrb[(pair_i*2)*BYTE_WIDTH +: PAIR_BYTE_WIDTH] =
        pair_payload[REQUEST_WSTRB_LSB +: PAIR_BYTE_WIDTH];
  end
endgenerate

edge_dtcm_upper_io #(
  .READ_LATENCY(READ_LATENCY),
  .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .LANES(1),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH), .FIXED_CHANNEL(LOWER_SIX ? 3'd6 : 3'd1), .ALLOW_WRITE(1)
) x_lsu_io (
  .clk(clk), .cpurst_b(cpurst_b), .phase(phase),
  .req(lsu_req), .req_we(lsu_we), .req_addr(lsu_addr),
  .req_wdata(lsu_wdata), .req_wstrb(lsu_wstrb),
  .ready(lsu_ready), .rvalid(lsu_rvalid), .rdata(lsu_rdata),
  .bank_req(lsu_bank_req), .bank_we(lsu_bank_we), .bank0(lsu_bank),
  .bank1(lsu_unused_bank1), .bank1_valid(lsu_unused_bank1_valid),
  .bank_addr(lsu_bank_addr), .bank_wdata(lsu_bank_wdata),
  .bank_wstrb(lsu_bank_wstrb), .rsp_bank0(lsu_rsp_bank0),
  .rsp_bank1(lsu_rsp_bank1),
  .rsp_bank0_rdata(lsu_rsp_bank0[0]
                   ? logical_response_payload[0*PAIR_DATA_WIDTH+DATA_WIDTH
                                              +: DATA_WIDTH]
                   : logical_response_payload[0*PAIR_DATA_WIDTH
                                              +: DATA_WIDTH]),
  .rsp_bank1_rdata({DATA_WIDTH{1'b0}})
);

edge_dtcm_upper_io #(
  .READ_LATENCY(READ_LATENCY),
  .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .LANES(2),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH), .FIXED_CHANNEL(LOWER_SIX ? 3'd7 : 3'd3), .ALLOW_WRITE(1)
) x_dma_io (
  .clk(clk), .cpurst_b(cpurst_b), .phase(phase),
  .req(dma_req), .req_we(dma_we), .req_addr(dma_addr),
  .req_wdata(dma_wdata), .req_wstrb(dma_wstrb),
  .ready(dma_ready), .rvalid(dma_rvalid), .rdata(dma_rdata),
  .bank_req(dma_pair_req), .bank_we(dma_pair_we), .bank0(dma_pair_bank0),
  .bank1(dma_pair_bank1), .bank1_valid(dma_unused_bank1_valid),
  .bank_addr(dma_pair_addr), .bank_wdata(dma_pair_wdata),
  .bank_wstrb(dma_pair_wstrb), .rsp_bank0(dma_rsp_bank0_unused),
  .rsp_bank1(dma_rsp_bank1_unused),
  .rsp_bank0_rdata(logical_response_payload[1*PAIR_DATA_WIDTH
                                            +: DATA_WIDTH]),
  .rsp_bank1_rdata(logical_response_payload[1*PAIR_DATA_WIDTH+DATA_WIDTH
                                            +: DATA_WIDTH])
);

// WLD wins a simultaneous request and SLD keeps its request asserted until
// WLD releases the shared port. Only the selected requester observes ready.
// Capture the accepted owner so the SRAM response cannot be routed
// to a requester that arrived later.
assign shared_ld_select_wld = wld_req;
assign shared_ld_req = wld_req || sld_req;
assign shared_ld_addr[ADDR_WIDTH-1:0] =
    shared_ld_select_wld ? wld_addr[ADDR_WIDTH-1:0]
                         : sld_addr[ADDR_WIDTH-1:0];
assign wld_ready = shared_ld_ready && shared_ld_select_wld;
assign sld_ready = shared_ld_ready && !shared_ld_select_wld && sld_req;
assign wld_rvalid = shared_ld_rvalid && shared_ld_rsp_owner_wld_q;
assign sld_rvalid = shared_ld_rvalid && !shared_ld_rsp_owner_wld_q;
assign wld_rdata[DMA_DATA_WIDTH-1:0] = shared_ld_rdata[DMA_DATA_WIDTH-1:0];
assign sld_rdata[DMA_DATA_WIDTH-1:0] = shared_ld_rdata[DMA_DATA_WIDTH-1:0];

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) owner_pipe <= 0;
  else begin
    owner_pipe[0] <= shared_ld_select_wld;
    for (stage=1; stage<READ_LATENCY; stage=stage+1)
      owner_pipe[stage] <= owner_pipe[stage-1];
  end
end
assign shared_ld_rsp_owner_wld_q = owner_pipe[READ_LATENCY-1];

edge_dtcm_upper_io #(
  .READ_LATENCY(READ_LATENCY),
  .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .LANES(2),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH), .FIXED_CHANNEL(3'd5), .ALLOW_WRITE(0)
) x_shared_ld_io (
  .clk(clk), .cpurst_b(cpurst_b), .phase(phase),
  .req(shared_ld_req), .req_we(1'b0), .req_addr(shared_ld_addr),
  .req_wdata({DMA_DATA_WIDTH{1'b0}}),
  .req_wstrb({DMA_BYTE_WIDTH{1'b0}}),
  .ready(shared_ld_ready), .rvalid(shared_ld_rvalid),
  .rdata(shared_ld_rdata),
  .bank_req(shared_ld_pair_req), .bank_we(shared_ld_unused_bank_we),
  .bank0(shared_ld_pair_bank0), .bank1(shared_ld_pair_bank1),
  .bank1_valid(shared_ld_unused_bank1_valid),
  .bank_addr(shared_ld_pair_addr),
  .bank_wdata(shared_ld_unused_bank_wdata),
  .bank_wstrb(shared_ld_unused_bank_wstrb),
  .rsp_bank0(shared_ld_rsp_bank0_unused),
  .rsp_bank1(shared_ld_rsp_bank1_unused),
  .rsp_bank0_rdata(logical_response_payload[2*PAIR_DATA_WIDTH
                                            +: DATA_WIDTH]),
  .rsp_bank1_rdata(logical_response_payload[2*PAIR_DATA_WIDTH+DATA_WIDTH
                                            +: DATA_WIDTH])
);

endmodule
