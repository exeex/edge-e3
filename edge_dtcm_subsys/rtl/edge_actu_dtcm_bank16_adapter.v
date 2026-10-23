module edge_actu_dtcm_bank16_adapter(
  clk, cpurst_b, phase,
  rd_req, rd_ready, rd_addr, rd_rvalid, rd_rdata,
  wr_req, wr_ready, wr_addr, wr_wdata, wr_wstrb,
  bank_req, bank_we, bank_addr, bank_wdata, bank_wstrb,
  bank_rdata
);

parameter READ_LATENCY = 1;
parameter UPPER_SHARED = 0;
parameter WIDE_H4 = 0;
parameter ADDR_WIDTH       = 14;
parameter DATA_WIDTH       = 64;
parameter BYTE_WIDTH       = DATA_WIDTH / 8;
parameter BEAT_WIDTH       = 128;
parameter BEAT_BYTE_WIDTH  = BEAT_WIDTH / 8;
parameter BANK_NUM         = 16;
parameter BANK_INDEX_WIDTH = 4;
parameter SRAM_ADDR_WIDTH  = 10;

localparam PAIR_NUM = 8;
localparam PAIR_DATA_WIDTH = 2 * DATA_WIDTH;
localparam PAIR_BYTE_WIDTH = 2 * BYTE_WIDTH;
localparam REQUEST_REQ_LSB = 0;
localparam REQUEST_WE_LSB = 2;
localparam REQUEST_ADDR_LSB = 4;
localparam REQUEST_WDATA_LSB = 4 + SRAM_ADDR_WIDTH;
localparam REQUEST_WSTRB_LSB = 4 + SRAM_ADDR_WIDTH + PAIR_DATA_WIDTH;
localparam REQUEST_PAYLOAD_WIDTH =
    4 + SRAM_ADDR_WIDTH + PAIR_DATA_WIDTH + PAIR_BYTE_WIDTH;

input                         clk;
input                         cpurst_b;
input  [BANK_INDEX_WIDTH-1:0] phase;
input                         rd_req;
input  [ADDR_WIDTH-1:0]       rd_addr;
input                         wr_req;
input  [ADDR_WIDTH-1:0]       wr_addr;
input  [BEAT_WIDTH-1:0]       wr_wdata;
input  [BEAT_BYTE_WIDTH-1:0]  wr_wstrb;
input  [BANK_NUM*DATA_WIDTH-1:0] bank_rdata;
output                        rd_ready;
output                        rd_rvalid;
output [BEAT_WIDTH-1:0]       rd_rdata;
output                        wr_ready;
output [BANK_NUM-1:0]         bank_req;
output [BANK_NUM-1:0]         bank_we;
output [BANK_NUM*SRAM_ADDR_WIDTH-1:0] bank_addr;
output [BANK_NUM*DATA_WIDTH-1:0] bank_wdata;
output [BANK_NUM*BYTE_WIDTH-1:0] bank_wstrb;

wire [ADDR_WIDTH-1:0]         req_addr;
wire                          req_valid;
wire                          req_we;
wire [2:0]                    rd_target_pair;
wire [2:0]                    wr_target_pair;
wire                          rd_phase_match;
wire                          wr_phase_match;
wire                          select_read;
wire                          select_write;
wire [2:0]                    pair_phase;
wire [2:0]                    target_pair;
wire [2:0]                    pair_delta;
wire [1:0]                    logical_group;
wire                          channel_match;
wire                          fire;
wire [SRAM_ADDR_WIDTH-1:0]    sram_addr;
wire [REQUEST_PAYLOAD_WIDTH-1:0] request_payload;
wire [4*REQUEST_PAYLOAD_WIDTH-1:0] logical_request_payload;
wire [PAIR_NUM*REQUEST_PAYLOAD_WIDTH-1:0] physical_request_payload;
wire [4*PAIR_DATA_WIDTH-1:0] logical_response_payload;
wire rd_rvalid_q;
reg [READ_LATENCY-1:0] valid_pipe;
integer stage;

genvar group_i;
genvar pair_i;

assign pair_phase = phase[BANK_INDEX_WIDTH-1:1];
assign rd_target_pair = rd_addr[BANK_INDEX_WIDTH-1:1];
assign wr_target_pair = wr_addr[BANK_INDEX_WIDTH-1:1];
assign rd_phase_match = UPPER_SHARED ?
    (rd_target_pair == (WIDE_H4 ? {2'(pair_phase[1:0]+3),pair_phase[2]} : 3'(pair_phase + 3'd4))) :
    rd_target_pair[0] == pair_phase[0];
assign wr_phase_match = UPPER_SHARED ?
    (wr_target_pair == (WIDE_H4 ? {2'(pair_phase[1:0]+3),pair_phase[2]} : 3'(pair_phase + 3'd4))) :
    wr_target_pair[0] == pair_phase[0];
assign select_read = rd_req && rd_phase_match;
assign select_write = wr_req && wr_phase_match && !select_read;
assign req_valid = select_read || select_write;
assign req_we = select_write;
assign req_addr = select_write ? wr_addr : rd_addr;
assign target_pair = req_addr[BANK_INDEX_WIDTH-1:1];
assign pair_delta = target_pair - pair_phase;
assign logical_group = pair_delta[2:1];
assign channel_match = UPPER_SHARED ?
    (target_pair == (WIDE_H4 ? {2'(pair_phase[1:0]+3),pair_phase[2]} : 3'(pair_phase + 3'd4))) :
    target_pair[0] == pair_phase[0];
assign fire = req_valid && channel_match;
assign rd_ready = select_read;
assign wr_ready = select_write;
assign sram_addr =
    req_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];

assign request_payload =
    {wr_wstrb, wr_wdata, sram_addr,
     ({2{req_we}} & {2{fire}}), {2{fire}}};

generate
  for (group_i = 0; group_i < 4; group_i = group_i + 1) begin: LOGICAL_GROUP
    assign logical_request_payload[
        group_i*REQUEST_PAYLOAD_WIDTH +: REQUEST_PAYLOAD_WIDTH] =
        logical_group == group_i[1:0]
        ? request_payload : {REQUEST_PAYLOAD_WIDTH{1'b0}};
  end
endgenerate

generate if (UPPER_SHARED) begin: DIRECT_CHANNEL
  reg [2:0] response_pair_pipe [0:READ_LATENCY-1];
  integer st;
  always @(posedge clk or negedge cpurst_b)
    if (!cpurst_b) begin
      for (st=0; st<READ_LATENCY; st=st+1) response_pair_pipe[st] <= 0;
    end else begin
      response_pair_pipe[0] <= target_pair;
      for (st=1; st<READ_LATENCY; st=st+1)
        response_pair_pipe[st] <= response_pair_pipe[st-1];
    end
  for (genvar p=0; p<8; p=p+1) begin: PAIR
    assign physical_request_payload[p*REQUEST_PAYLOAD_WIDTH +: REQUEST_PAYLOAD_WIDTH] =
        target_pair == 3'(p) ? request_payload : {REQUEST_PAYLOAD_WIDTH{1'b0}};
  end
  assign rd_rdata = bank_rdata[
      response_pair_pipe[READ_LATENCY-1]*PAIR_DATA_WIDTH +: PAIR_DATA_WIDTH];
end else begin: LEGACY_CHANNELS
reg [1:0] group_pipe [0:READ_LATENCY-1];
integer group_stage;
always @(posedge clk or negedge cpurst_b)
  if (!cpurst_b) begin
    for (group_stage=0; group_stage<READ_LATENCY; group_stage=group_stage+1)
      group_pipe[group_stage] <= 0;
  end else begin
    group_pipe[0] <= logical_group;
    for (group_stage=1; group_stage<READ_LATENCY; group_stage=group_stage+1)
      group_pipe[group_stage] <= group_pipe[group_stage-1];
  end
edge_dtcm_upper_pair_router #(
  .READ_LATENCY(READ_LATENCY),
  .REQUEST_WIDTH(REQUEST_PAYLOAD_WIDTH),
  .RESPONSE_WIDTH(PAIR_DATA_WIDTH), .CHANNEL_PARITY(0)
) x_lower_pair_router (
  .clk(clk), .cpurst_b(cpurst_b), .pair_phase(pair_phase),
  .logical_request_payload(logical_request_payload),
  .physical_request_payload(physical_request_payload),
  .physical_response_payload(bank_rdata),
  .logical_response_payload(logical_response_payload)
);
assign rd_rdata = logical_response_payload[
    group_pipe[READ_LATENCY-1]*PAIR_DATA_WIDTH +: PAIR_DATA_WIDTH];
end endgenerate

generate
  for (pair_i = 0; pair_i < PAIR_NUM; pair_i = pair_i + 1) begin: PHYSICAL_PAIR
    wire [REQUEST_PAYLOAD_WIDTH-1:0] payload;
    assign payload = physical_request_payload[
        pair_i*REQUEST_PAYLOAD_WIDTH +: REQUEST_PAYLOAD_WIDTH];
    assign bank_req[pair_i*2 +: 2] = payload[REQUEST_REQ_LSB +: 2];
    assign bank_we[pair_i*2 +: 2] = payload[REQUEST_WE_LSB +: 2];
    assign bank_addr[(pair_i*2)*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] =
        payload[REQUEST_ADDR_LSB +: SRAM_ADDR_WIDTH];
    assign bank_addr[(pair_i*2+1)*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] =
        payload[REQUEST_ADDR_LSB +: SRAM_ADDR_WIDTH];
    assign bank_wdata[(pair_i*2)*DATA_WIDTH +: PAIR_DATA_WIDTH] =
        payload[REQUEST_WDATA_LSB +: PAIR_DATA_WIDTH];
    assign bank_wstrb[(pair_i*2)*BYTE_WIDTH +: PAIR_BYTE_WIDTH] =
        payload[REQUEST_WSTRB_LSB +: PAIR_BYTE_WIDTH];
  end
endgenerate

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    valid_pipe <= 0;
  end else begin
    valid_pipe[0] <= fire && !req_we;
    for (stage=1; stage<READ_LATENCY; stage=stage+1) begin
      valid_pipe[stage] <= valid_pipe[stage-1];
    end
  end
end
assign rd_rvalid_q = valid_pipe[READ_LATENCY-1];

assign rd_rvalid = rd_rvalid_q;

endmodule
