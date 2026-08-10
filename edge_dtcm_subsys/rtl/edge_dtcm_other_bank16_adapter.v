module edge_dtcm_other_bank16_adapter(
  clk,
  cpurst_b,
  external_busy_mask,
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
  lsu_bank_req,
  lsu_bank_we,
  lsu_bank,
  lsu_bank_addr,
  lsu_bank_wdata,
  lsu_bank_wstrb,
  dma_pair_req,
  dma_pair_we,
  dma_pair_bank0,
  dma_pair_bank1,
  dma_pair_addr,
  dma_pair_wdata,
  dma_pair_wstrb,
  dma_pair_rdata,
  sld_addr,
  sld_rdata,
  sld_ready,
  sld_req,
  sld_rvalid,
  sld_pair_req,
  sld_pair_bank0,
  sld_pair_bank1,
  sld_pair_addr,
  sld_pair_rdata,
  wld_addr,
  wld_rdata,
  wld_ready,
  wld_req,
  wld_rvalid,
  wld_pair_req,
  wld_pair_bank0,
  wld_pair_bank1,
  wld_pair_addr,
  wld_pair_rdata,
  active_mask,
  bank16_conflict
);

parameter ADDR_WIDTH       = 14;
parameter DATA_WIDTH       = 64;
parameter BYTE_WIDTH       = DATA_WIDTH / 8;
parameter DMA_DATA_WIDTH   = 128;
parameter DMA_BYTE_WIDTH   = DMA_DATA_WIDTH / 8;
parameter BANK_NUM         = 16;
parameter BANK_INDEX_WIDTH = 4;
parameter SRAM_ADDR_WIDTH  = 10;
parameter [3:0] LSU_PHASE_LATENCY_CYCLES = 4'd0;
parameter [3:0] DMA_PHASE_LATENCY_CYCLES = 4'd0;
parameter [2:0] FIXED_CH_LSU = 3'd1;
parameter [2:0] FIXED_CH_DMA = 3'd3;
parameter [2:0] FIXED_CH_WLD = 3'd5;
parameter [2:0] FIXED_CH_SLD = 3'd7;

input                         clk;
input                         cpurst_b;
input  [BANK_NUM-1:0]         external_busy_mask;
input  [BANK_INDEX_WIDTH-1:0] phase;
input  [BANK_NUM*DATA_WIDTH-1:0] bank_rdata;
input  [ADDR_WIDTH-1:0]       dma_addr;
input                         dma_req;
input                         dma_we;
input  [DMA_DATA_WIDTH-1:0]   dma_wdata;
input  [DMA_BYTE_WIDTH-1:0]   dma_wstrb;
input  [ADDR_WIDTH-1:0]       lsu_addr;
input  [ADDR_WIDTH-1:0]       sld_addr;
input                         sld_req;
input  [ADDR_WIDTH-1:0]       wld_addr;
input                         wld_req;
input                         lsu_req;
input                         lsu_we;
input  [DATA_WIDTH-1:0]       lsu_wdata;
input  [BYTE_WIDTH-1:0]       lsu_wstrb;
output [DMA_DATA_WIDTH-1:0]   dma_rdata;
output                        dma_ready;
output                        dma_rvalid;
output [DATA_WIDTH-1:0]       lsu_rdata;
output                        lsu_ready;
output                        lsu_rvalid;
output                        lsu_bank_req;
output                        lsu_bank_we;
output [BANK_INDEX_WIDTH-1:0] lsu_bank;
output [SRAM_ADDR_WIDTH-1:0]  lsu_bank_addr;
output [DATA_WIDTH-1:0]       lsu_bank_wdata;
output [BYTE_WIDTH-1:0]       lsu_bank_wstrb;
output                        dma_pair_req;
output                        dma_pair_we;
output [BANK_INDEX_WIDTH-1:0] dma_pair_bank0;
output [BANK_INDEX_WIDTH-1:0] dma_pair_bank1;
output [SRAM_ADDR_WIDTH-1:0]  dma_pair_addr;
output [DMA_DATA_WIDTH-1:0]   dma_pair_wdata;
output [DMA_BYTE_WIDTH-1:0]   dma_pair_wstrb;
input  [DMA_DATA_WIDTH-1:0]   dma_pair_rdata;
output [DMA_DATA_WIDTH-1:0]   sld_rdata;
output                        sld_ready;
output                        sld_rvalid;
output                        sld_pair_req;
output [BANK_INDEX_WIDTH-1:0] sld_pair_bank0;
output [BANK_INDEX_WIDTH-1:0] sld_pair_bank1;
output [SRAM_ADDR_WIDTH-1:0]  sld_pair_addr;
input  [DMA_DATA_WIDTH-1:0]   sld_pair_rdata;
output [DMA_DATA_WIDTH-1:0]   wld_rdata;
output                        wld_ready;
output                        wld_rvalid;
output                        wld_pair_req;
output [BANK_INDEX_WIDTH-1:0] wld_pair_bank0;
output [BANK_INDEX_WIDTH-1:0] wld_pair_bank1;
output [SRAM_ADDR_WIDTH-1:0]  wld_pair_addr;
input  [DMA_DATA_WIDTH-1:0]   wld_pair_rdata;
output [BANK_NUM-1:0]         active_mask;
output                        bank16_conflict;

wire [BANK_INDEX_WIDTH-1:0]   lsu_bank;
wire [BANK_INDEX_WIDTH-1:0]   dma_bank0;
wire [BANK_INDEX_WIDTH-1:0]   dma_bank1;
wire [BANK_INDEX_WIDTH-1:0]   sld_bank0;
wire [BANK_INDEX_WIDTH-1:0]   sld_bank1;
wire [BANK_INDEX_WIDTH-1:0]   wld_bank0;
wire [BANK_INDEX_WIDTH-1:0]   wld_bank1;
wire [BANK_NUM-1:0]           lsu_active_mask;
wire [BANK_INDEX_WIDTH-1:0]   lsu_unused_bank1;
wire                          lsu_unused_bank1_valid;
wire [BANK_NUM-1:0]           dma_mask;
wire [BANK_NUM-1:0]           sld_mask;
wire [BANK_NUM-1:0]           wld_mask;
wire                          dma_lower_conflict;
wire                          sld_lower_conflict;
wire                          wld_lower_conflict;
wire                          dma_channel_match;
wire                          sld_channel_match;
wire                          wld_channel_match;
wire                          dma_candidate;
wire                          sld_candidate;
wire                          wld_candidate;
wire                          dma_fire;
wire                          sld_fire;
wire                          wld_fire;
wire                          unused_phase_inputs;
wire [SRAM_ADDR_WIDTH-1:0]    dma_sram_addr;
wire [SRAM_ADDR_WIDTH-1:0]    sld_sram_addr;
wire [SRAM_ADDR_WIDTH-1:0]    wld_sram_addr;
reg                           dma_rvalid_q;
reg                           sld_rvalid_q;
reg                           wld_rvalid_q;

function [BANK_NUM-1:0] one_bank_mask;
  input [BANK_INDEX_WIDTH-1:0] bank;
  integer i;
begin
  one_bank_mask[BANK_NUM-1:0] = {BANK_NUM{1'b0}};
  for (i = 0; i < BANK_NUM; i = i + 1) begin
    if (bank == i[BANK_INDEX_WIDTH-1:0])
      one_bank_mask[i] = 1'b1;
  end
end
endfunction

function [BANK_NUM-1:0] pair_mask;
  input [BANK_INDEX_WIDTH-1:0] bank;
begin
  pair_mask[BANK_NUM-1:0] =
      one_bank_mask({bank[BANK_INDEX_WIDTH-1:1], 1'b0})
    | one_bank_mask({bank[BANK_INDEX_WIDTH-1:1], 1'b1});
end
endfunction

function channel_matches_pair;
  input [2:0] channel;
  input [BANK_INDEX_WIDTH-1:0] phase_i;
  input [BANK_INDEX_WIDTH-1:0] bank;
  reg [2:0] phase_pair;
  reg [2:0] target_pair;
begin
  phase_pair[2:0] = phase_i[BANK_INDEX_WIDTH-1:1];
  target_pair[2:0] = bank[BANK_INDEX_WIDTH-1:1];
  channel_matches_pair = ((channel[2:0] + phase_pair[2:0]) == target_pair[2:0]);
end
endfunction

assign dma_bank0[BANK_INDEX_WIDTH-1:0] =
    dma_addr[BANK_INDEX_WIDTH-1:0];
assign dma_bank1[BANK_INDEX_WIDTH-1:0] =
    dma_addr[BANK_INDEX_WIDTH-1:0] + {{BANK_INDEX_WIDTH-1{1'b0}}, 1'b1};
assign sld_bank0[BANK_INDEX_WIDTH-1:0] = sld_addr[BANK_INDEX_WIDTH-1:0];
assign sld_bank1[BANK_INDEX_WIDTH-1:0] =
    sld_addr[BANK_INDEX_WIDTH-1:0] + {{BANK_INDEX_WIDTH-1{1'b0}}, 1'b1};
assign wld_bank0[BANK_INDEX_WIDTH-1:0] = wld_addr[BANK_INDEX_WIDTH-1:0];
assign wld_bank1[BANK_INDEX_WIDTH-1:0] =
    wld_addr[BANK_INDEX_WIDTH-1:0] + {{BANK_INDEX_WIDTH-1{1'b0}}, 1'b1};
assign dma_mask[BANK_NUM-1:0] = one_bank_mask(dma_bank0[BANK_INDEX_WIDTH-1:0])
                              | one_bank_mask(dma_bank1[BANK_INDEX_WIDTH-1:0]);
assign sld_mask[BANK_NUM-1:0] = one_bank_mask(sld_bank0[BANK_INDEX_WIDTH-1:0])
                              | one_bank_mask(sld_bank1[BANK_INDEX_WIDTH-1:0]);
assign wld_mask[BANK_NUM-1:0] = one_bank_mask(wld_bank0[BANK_INDEX_WIDTH-1:0])
                              | one_bank_mask(wld_bank1[BANK_INDEX_WIDTH-1:0]);
assign dma_lower_conflict =
    (dma_mask[BANK_NUM-1:0] & external_busy_mask[BANK_NUM-1:0])
    != {BANK_NUM{1'b0}};
assign sld_lower_conflict =
    (sld_mask[BANK_NUM-1:0] & external_busy_mask[BANK_NUM-1:0])
    != {BANK_NUM{1'b0}};
assign wld_lower_conflict =
    (wld_mask[BANK_NUM-1:0] & external_busy_mask[BANK_NUM-1:0])
    != {BANK_NUM{1'b0}};
assign dma_channel_match =
    channel_matches_pair(FIXED_CH_DMA[2:0],
                         phase[BANK_INDEX_WIDTH-1:0],
                         dma_bank0[BANK_INDEX_WIDTH-1:0]);
assign sld_channel_match =
    channel_matches_pair(FIXED_CH_SLD[2:0], phase[BANK_INDEX_WIDTH-1:0],
                         sld_bank0[BANK_INDEX_WIDTH-1:0]);
assign wld_channel_match =
    channel_matches_pair(FIXED_CH_WLD[2:0], phase[BANK_INDEX_WIDTH-1:0],
                         wld_bank0[BANK_INDEX_WIDTH-1:0]);

assign dma_candidate = dma_req
                    && dma_channel_match
                    && !dma_lower_conflict;
assign sld_candidate = sld_req && sld_channel_match && !sld_lower_conflict;
assign wld_candidate = wld_req && wld_channel_match && !wld_lower_conflict;
assign dma_fire = dma_candidate;
assign sld_fire = sld_candidate;
assign wld_fire = wld_candidate;
assign dma_ready = dma_fire;
assign sld_ready = sld_fire;
assign wld_ready = wld_fire;
assign active_mask[BANK_NUM-1:0] =
    lsu_active_mask[BANK_NUM-1:0]
  | (dma_req ? dma_mask[BANK_NUM-1:0] : {BANK_NUM{1'b0}})
  | (sld_req ? sld_mask[BANK_NUM-1:0] : {BANK_NUM{1'b0}})
  | (wld_req ? wld_mask[BANK_NUM-1:0] : {BANK_NUM{1'b0}});
// Fixed channels 1, 3, 5, and 7 rotate onto distinct bank pairs each cycle.
assign bank16_conflict = (lsu_req && !lsu_ready)
                      || (dma_req && !dma_ready)
                      || (sld_req && !sld_ready)
                      || (wld_req && !wld_ready);
assign unused_phase_inputs = (|LSU_PHASE_LATENCY_CYCLES[3:0])
                          || (|DMA_PHASE_LATENCY_CYCLES[3:0]);
assign dma_sram_addr[SRAM_ADDR_WIDTH-1:0] =
    dma_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign sld_sram_addr[SRAM_ADDR_WIDTH-1:0] =
    sld_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign wld_sram_addr[SRAM_ADDR_WIDTH-1:0] =
    wld_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
edge_dtcm_upper_io #(
  .ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .LANES(1),
  .BANK_NUM(BANK_NUM),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
  .FIXED_CHANNEL(FIXED_CH_LSU),
  .ALLOW_WRITE(1)
) x_lsu_io (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .phase(phase[BANK_INDEX_WIDTH-1:0]),
  .blocked_bank_mask(external_busy_mask[BANK_NUM-1:0]),
  .req(lsu_req),
  .req_we(lsu_we),
  .req_addr(lsu_addr[ADDR_WIDTH-1:0]),
  .req_wdata(lsu_wdata[DATA_WIDTH-1:0]),
  .req_wstrb(lsu_wstrb[BYTE_WIDTH-1:0]),
  .ready(lsu_ready),
  .rvalid(lsu_rvalid),
  .rdata(lsu_rdata[DATA_WIDTH-1:0]),
  .bank_req(lsu_bank_req),
  .bank_we(lsu_bank_we),
  .bank0(lsu_bank[BANK_INDEX_WIDTH-1:0]),
  .bank1(lsu_unused_bank1[BANK_INDEX_WIDTH-1:0]),
  .bank1_valid(lsu_unused_bank1_valid),
  .bank_addr(lsu_bank_addr[SRAM_ADDR_WIDTH-1:0]),
  .bank_wdata(lsu_bank_wdata[DATA_WIDTH-1:0]),
  .bank_wstrb(lsu_bank_wstrb[BYTE_WIDTH-1:0]),
  .bank_rdata(bank_rdata[BANK_NUM*DATA_WIDTH-1:0]),
  .active_mask(lsu_active_mask[BANK_NUM-1:0])
);

assign dma_pair_req = dma_fire;
assign dma_pair_we = dma_we;
assign dma_pair_bank0[BANK_INDEX_WIDTH-1:0] = dma_bank0[BANK_INDEX_WIDTH-1:0];
assign dma_pair_bank1[BANK_INDEX_WIDTH-1:0] = dma_bank1[BANK_INDEX_WIDTH-1:0];
assign dma_pair_addr[SRAM_ADDR_WIDTH-1:0] = dma_sram_addr[SRAM_ADDR_WIDTH-1:0];
assign dma_pair_wdata[DMA_DATA_WIDTH-1:0] = dma_wdata[DMA_DATA_WIDTH-1:0];
assign dma_pair_wstrb[DMA_BYTE_WIDTH-1:0] = dma_wstrb[DMA_BYTE_WIDTH-1:0];
assign sld_pair_req = sld_fire;
assign sld_pair_bank0[BANK_INDEX_WIDTH-1:0] = sld_bank0[BANK_INDEX_WIDTH-1:0];
assign sld_pair_bank1[BANK_INDEX_WIDTH-1:0] = sld_bank1[BANK_INDEX_WIDTH-1:0];
assign sld_pair_addr[SRAM_ADDR_WIDTH-1:0] = sld_sram_addr[SRAM_ADDR_WIDTH-1:0];
assign wld_pair_req = wld_fire;
assign wld_pair_bank0[BANK_INDEX_WIDTH-1:0] = wld_bank0[BANK_INDEX_WIDTH-1:0];
assign wld_pair_bank1[BANK_INDEX_WIDTH-1:0] = wld_bank1[BANK_INDEX_WIDTH-1:0];
assign wld_pair_addr[SRAM_ADDR_WIDTH-1:0] = wld_sram_addr[SRAM_ADDR_WIDTH-1:0];

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    dma_rvalid_q <= 1'b0;
    sld_rvalid_q <= 1'b0;
    wld_rvalid_q <= 1'b0;
  end else begin
    dma_rvalid_q <= dma_fire && !dma_we;
    sld_rvalid_q <= sld_fire;
    wld_rvalid_q <= wld_fire;
  end
end

assign dma_rvalid = dma_rvalid_q;
assign dma_rdata[DMA_DATA_WIDTH-1:0] = dma_pair_rdata[DMA_DATA_WIDTH-1:0];
assign sld_rvalid = sld_rvalid_q;
assign sld_rdata[DMA_DATA_WIDTH-1:0] = sld_pair_rdata[DMA_DATA_WIDTH-1:0];
assign wld_rvalid = wld_rvalid_q;
assign wld_rdata[DMA_DATA_WIDTH-1:0] = wld_pair_rdata[DMA_DATA_WIDTH-1:0];

endmodule
