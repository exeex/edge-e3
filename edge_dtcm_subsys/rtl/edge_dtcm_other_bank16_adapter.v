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
  sld_addr,
  sld_rdata,
  sld_ready,
  sld_req,
  sld_rvalid,
  sld_pair_req,
  sld_pair_bank0,
  sld_pair_bank1,
  sld_pair_addr,
  wld_addr,
  wld_rdata,
  wld_ready,
  wld_req,
  wld_rvalid,
  wld_pair_req,
  wld_pair_bank0,
  wld_pair_bank1,
  wld_pair_addr,
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
output [DMA_DATA_WIDTH-1:0]   sld_rdata;
output                        sld_ready;
output                        sld_rvalid;
output                        sld_pair_req;
output [BANK_INDEX_WIDTH-1:0] sld_pair_bank0;
output [BANK_INDEX_WIDTH-1:0] sld_pair_bank1;
output [SRAM_ADDR_WIDTH-1:0]  sld_pair_addr;
output [DMA_DATA_WIDTH-1:0]   wld_rdata;
output                        wld_ready;
output                        wld_rvalid;
output                        wld_pair_req;
output [BANK_INDEX_WIDTH-1:0] wld_pair_bank0;
output [BANK_INDEX_WIDTH-1:0] wld_pair_bank1;
output [SRAM_ADDR_WIDTH-1:0]  wld_pair_addr;
output [BANK_NUM-1:0]         active_mask;
output                        bank16_conflict;

wire [BANK_INDEX_WIDTH-1:0]   lsu_bank;
wire [BANK_NUM-1:0]           lsu_active_mask;
wire [BANK_INDEX_WIDTH-1:0]   lsu_unused_bank1;
wire                          lsu_unused_bank1_valid;
wire [BANK_INDEX_WIDTH-1:0]   lsu_rsp_bank0;
wire [BANK_INDEX_WIDTH-1:0]   lsu_rsp_bank1;
wire [BANK_NUM-1:0]           dma_active_mask;
wire                          dma_unused_bank1_valid;
wire [BANK_INDEX_WIDTH-1:0]   dma_rsp_bank0;
wire [BANK_INDEX_WIDTH-1:0]   dma_rsp_bank1;
wire [BANK_NUM-1:0]           sld_active_mask;
wire                          sld_unused_bank_we;
wire                          sld_unused_bank1_valid;
wire [DMA_DATA_WIDTH-1:0]     sld_unused_bank_wdata;
wire [DMA_BYTE_WIDTH-1:0]     sld_unused_bank_wstrb;
wire [BANK_INDEX_WIDTH-1:0]   sld_rsp_bank0;
wire [BANK_INDEX_WIDTH-1:0]   sld_rsp_bank1;
wire [BANK_NUM-1:0]           wld_active_mask;
wire                          wld_unused_bank_we;
wire                          wld_unused_bank1_valid;
wire [DMA_DATA_WIDTH-1:0]     wld_unused_bank_wdata;
wire [DMA_BYTE_WIDTH-1:0]     wld_unused_bank_wstrb;
wire [BANK_INDEX_WIDTH-1:0]   wld_rsp_bank0;
wire [BANK_INDEX_WIDTH-1:0]   wld_rsp_bank1;

function [DATA_WIDTH-1:0] select_bank_data;
  input [BANK_NUM*DATA_WIDTH-1:0] data;
  input [BANK_INDEX_WIDTH-1:0] bank;
begin
  select_bank_data[DATA_WIDTH-1:0] =
      data[bank*DATA_WIDTH +: DATA_WIDTH];
end
endfunction


assign active_mask[BANK_NUM-1:0] =
    lsu_active_mask[BANK_NUM-1:0]
  | dma_active_mask[BANK_NUM-1:0]
  | sld_active_mask[BANK_NUM-1:0]
  | wld_active_mask[BANK_NUM-1:0];
// Fixed channels 1, 3, 5, and 7 rotate onto distinct bank pairs each cycle.
assign bank16_conflict = (lsu_req && !lsu_ready)
                      || (dma_req && !dma_ready)
                      || (sld_req && !sld_ready)
                      || (wld_req && !wld_ready);
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
  .rsp_bank0(lsu_rsp_bank0[BANK_INDEX_WIDTH-1:0]),
  .rsp_bank1(lsu_rsp_bank1[BANK_INDEX_WIDTH-1:0]),
  .rsp_bank0_rdata(select_bank_data(bank_rdata, lsu_rsp_bank0)),
  .rsp_bank1_rdata({DATA_WIDTH{1'b0}}),
  .active_mask(lsu_active_mask[BANK_NUM-1:0])
);

edge_dtcm_upper_io #(
  .ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .LANES(2),
  .BANK_NUM(BANK_NUM),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
  .FIXED_CHANNEL(FIXED_CH_DMA),
  .ALLOW_WRITE(1)
) x_dma_io (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .phase(phase[BANK_INDEX_WIDTH-1:0]),
  .blocked_bank_mask(external_busy_mask[BANK_NUM-1:0]),
  .req(dma_req),
  .req_we(dma_we),
  .req_addr(dma_addr[ADDR_WIDTH-1:0]),
  .req_wdata(dma_wdata[DMA_DATA_WIDTH-1:0]),
  .req_wstrb(dma_wstrb[DMA_BYTE_WIDTH-1:0]),
  .ready(dma_ready),
  .rvalid(dma_rvalid),
  .rdata(dma_rdata[DMA_DATA_WIDTH-1:0]),
  .bank_req(dma_pair_req),
  .bank_we(dma_pair_we),
  .bank0(dma_pair_bank0[BANK_INDEX_WIDTH-1:0]),
  .bank1(dma_pair_bank1[BANK_INDEX_WIDTH-1:0]),
  .bank1_valid(dma_unused_bank1_valid),
  .bank_addr(dma_pair_addr[SRAM_ADDR_WIDTH-1:0]),
  .bank_wdata(dma_pair_wdata[DMA_DATA_WIDTH-1:0]),
  .bank_wstrb(dma_pair_wstrb[DMA_BYTE_WIDTH-1:0]),
  .rsp_bank0(dma_rsp_bank0[BANK_INDEX_WIDTH-1:0]),
  .rsp_bank1(dma_rsp_bank1[BANK_INDEX_WIDTH-1:0]),
  .rsp_bank0_rdata(select_bank_data(bank_rdata, dma_rsp_bank0)),
  .rsp_bank1_rdata(select_bank_data(bank_rdata, dma_rsp_bank1)),
  .active_mask(dma_active_mask[BANK_NUM-1:0])
);
edge_dtcm_upper_io #(
  .ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .LANES(2),
  .BANK_NUM(BANK_NUM),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
  .FIXED_CHANNEL(FIXED_CH_SLD),
  .ALLOW_WRITE(0)
) x_sld_io (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .phase(phase[BANK_INDEX_WIDTH-1:0]),
  .blocked_bank_mask(external_busy_mask[BANK_NUM-1:0]),
  .req(sld_req),
  .req_we(1'b0),
  .req_addr(sld_addr[ADDR_WIDTH-1:0]),
  .req_wdata({DMA_DATA_WIDTH{1'b0}}),
  .req_wstrb({DMA_BYTE_WIDTH{1'b0}}),
  .ready(sld_ready),
  .rvalid(sld_rvalid),
  .rdata(sld_rdata[DMA_DATA_WIDTH-1:0]),
  .bank_req(sld_pair_req),
  .bank_we(sld_unused_bank_we),
  .bank0(sld_pair_bank0[BANK_INDEX_WIDTH-1:0]),
  .bank1(sld_pair_bank1[BANK_INDEX_WIDTH-1:0]),
  .bank1_valid(sld_unused_bank1_valid),
  .bank_addr(sld_pair_addr[SRAM_ADDR_WIDTH-1:0]),
  .bank_wdata(sld_unused_bank_wdata[DMA_DATA_WIDTH-1:0]),
  .bank_wstrb(sld_unused_bank_wstrb[DMA_BYTE_WIDTH-1:0]),
  .rsp_bank0(sld_rsp_bank0[BANK_INDEX_WIDTH-1:0]),
  .rsp_bank1(sld_rsp_bank1[BANK_INDEX_WIDTH-1:0]),
  .rsp_bank0_rdata(select_bank_data(bank_rdata, sld_rsp_bank0)),
  .rsp_bank1_rdata(select_bank_data(bank_rdata, sld_rsp_bank1)),
  .active_mask(sld_active_mask[BANK_NUM-1:0])
);
edge_dtcm_upper_io #(
  .ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .LANES(2),
  .BANK_NUM(BANK_NUM),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
  .FIXED_CHANNEL(FIXED_CH_WLD),
  .ALLOW_WRITE(0)
) x_wld_io (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .phase(phase[BANK_INDEX_WIDTH-1:0]),
  .blocked_bank_mask(external_busy_mask[BANK_NUM-1:0]),
  .req(wld_req),
  .req_we(1'b0),
  .req_addr(wld_addr[ADDR_WIDTH-1:0]),
  .req_wdata({DMA_DATA_WIDTH{1'b0}}),
  .req_wstrb({DMA_BYTE_WIDTH{1'b0}}),
  .ready(wld_ready),
  .rvalid(wld_rvalid),
  .rdata(wld_rdata[DMA_DATA_WIDTH-1:0]),
  .bank_req(wld_pair_req),
  .bank_we(wld_unused_bank_we),
  .bank0(wld_pair_bank0[BANK_INDEX_WIDTH-1:0]),
  .bank1(wld_pair_bank1[BANK_INDEX_WIDTH-1:0]),
  .bank1_valid(wld_unused_bank1_valid),
  .bank_addr(wld_pair_addr[SRAM_ADDR_WIDTH-1:0]),
  .bank_wdata(wld_unused_bank_wdata[DMA_DATA_WIDTH-1:0]),
  .bank_wstrb(wld_unused_bank_wstrb[DMA_BYTE_WIDTH-1:0]),
  .rsp_bank0(wld_rsp_bank0[BANK_INDEX_WIDTH-1:0]),
  .rsp_bank1(wld_rsp_bank1[BANK_INDEX_WIDTH-1:0]),
  .rsp_bank0_rdata(select_bank_data(bank_rdata, wld_rsp_bank0)),
  .rsp_bank1_rdata(select_bank_data(bank_rdata, wld_rsp_bank1)),
  .active_mask(wld_active_mask[BANK_NUM-1:0])
);

endmodule
