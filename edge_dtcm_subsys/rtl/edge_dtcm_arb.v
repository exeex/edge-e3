module edge_dtcm_arb(
  clk,
  cpurst_b,
  dma_addr,
  dma_rdata,
  dma_ready,
  dma_req,
  dma_rvalid,
  dma_lease_channel,
  dma_lease_cycles,
  dma_lease_delay,
  dma_lease_valid,
  dma_we,
  dma_wdata,
  dma_wstrb,
  lsu_addr,
  lsu_rdata,
  lsu_ready,
  lsu_req,
  lsu_store_block,
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
  tensor_native_active_mask,
  tensor_native_bank_addr,
  tensor_native_bank_req,
  tensor_native_bank_rdata,
  tensor_native_bank_wdata,
  tensor_native_bank_we,
  tensor_native_bank_wstrb,
  tensor_native_phase,
  actu_active_mask,
  actu_bank_addr,
  actu_bank_req,
  actu_bank_rdata,
  actu_bank_wdata,
  actu_bank_we,
  actu_bank_wstrb,
  tensor_io_lease_channel_mask,
  tensor_io_lease_cycles,
  tensor_io_lease_delay,
  tensor_io_lease1_channel_mask,
  tensor_io_lease1_cycles,
  tensor_io_lease1_delay,
  tensor_io_lease1_valid,
  tensor_io_lease2_channel_mask,
  tensor_io_lease2_cycles,
  tensor_io_lease2_delay,
  tensor_io_lease2_valid,
  tensor_io_lease_valid,
  tensor_wld_lease_channel_mask,
  tensor_wld_lease_cycles,
  tensor_wld_lease_delay,
  tensor_wld_lease_valid
);

parameter ADDR_WIDTH          = 14;
parameter DATA_WIDTH          = 64;
parameter BYTE_WIDTH          = DATA_WIDTH / 8;
parameter DMA_DATA_WIDTH      = 128;
parameter DMA_BYTE_WIDTH      = DMA_DATA_WIDTH / 8;
parameter BANK_NUM            = 16;
parameter BANK_INDEX_WIDTH    = 4;
parameter SEGMENT_NUM         = 1;
parameter SEGMENT_INDEX_WIDTH = 1;
parameter SRAM_ADDR_WIDTH     = 10;
parameter [3:0] LSU_LOOKAHEAD       = 4'd1;
parameter [3:0] TENSOR_IO_LOOKAHEAD = 4'd2;
parameter [3:0] TENSOR_WLD_LOOKAHEAD = 4'd2;
parameter [3:0] DMA_LOOKAHEAD       = 4'd3;

input                    clk;
input                    cpurst_b;
input  [ADDR_WIDTH-1:0]  dma_addr;
input                    dma_req;
input  [2:0]             dma_lease_channel;
input  [8:0]             dma_lease_cycles;
input  [3:0]             dma_lease_delay;
input                    dma_lease_valid;
input                    dma_we;
input  [DMA_DATA_WIDTH-1:0] dma_wdata;
input  [DMA_BYTE_WIDTH-1:0] dma_wstrb;
output [DMA_DATA_WIDTH-1:0] dma_rdata;
output                   dma_ready;
output                   dma_rvalid;
input  [ADDR_WIDTH-1:0]  lsu_addr;
input                    lsu_req;
input                    lsu_store_block;
input                    lsu_we;
input  [DATA_WIDTH-1:0]  lsu_wdata;
input  [BYTE_WIDTH-1:0]  lsu_wstrb;
output [DATA_WIDTH-1:0]  lsu_rdata;
output                   lsu_ready;
output                   lsu_rvalid;
input  [ADDR_WIDTH-1:0]  sld_addr;
input                    sld_req;
output [DMA_DATA_WIDTH-1:0] sld_rdata;
output                   sld_ready;
output                   sld_rvalid;
input  [ADDR_WIDTH-1:0]  wld_addr;
input                    wld_req;
output [DMA_DATA_WIDTH-1:0] wld_rdata;
output                   wld_ready;
output                   wld_rvalid;
input  [BANK_NUM-1:0]    tensor_native_active_mask;
input  [BANK_NUM*SRAM_ADDR_WIDTH-1:0] tensor_native_bank_addr;
input  [BANK_NUM-1:0]    tensor_native_bank_req;
output [BANK_NUM*DATA_WIDTH-1:0] tensor_native_bank_rdata;
input  [BANK_NUM*DATA_WIDTH-1:0] tensor_native_bank_wdata;
input  [BANK_NUM-1:0]    tensor_native_bank_we;
input  [BANK_NUM*BYTE_WIDTH-1:0] tensor_native_bank_wstrb;
output [BANK_INDEX_WIDTH-1:0] tensor_native_phase;
input  [BANK_NUM-1:0]    actu_active_mask;
input  [BANK_NUM*SRAM_ADDR_WIDTH-1:0] actu_bank_addr;
input  [BANK_NUM-1:0]    actu_bank_req;
output [BANK_NUM*DATA_WIDTH-1:0] actu_bank_rdata;
input  [BANK_NUM*DATA_WIDTH-1:0] actu_bank_wdata;
input  [BANK_NUM-1:0]    actu_bank_we;
input  [BANK_NUM*BYTE_WIDTH-1:0] actu_bank_wstrb;
input  [7:0]             tensor_io_lease_channel_mask;
input  [8:0]             tensor_io_lease_cycles;
input  [3:0]             tensor_io_lease_delay;
input  [7:0]             tensor_io_lease1_channel_mask;
input  [8:0]             tensor_io_lease1_cycles;
input  [3:0]             tensor_io_lease1_delay;
input                    tensor_io_lease1_valid;
input  [7:0]             tensor_io_lease2_channel_mask;
input  [8:0]             tensor_io_lease2_cycles;
input  [3:0]             tensor_io_lease2_delay;
input                    tensor_io_lease2_valid;
input                    tensor_io_lease_valid;
input  [7:0]             tensor_wld_lease_channel_mask;
input  [8:0]             tensor_wld_lease_cycles;
input  [3:0]             tensor_wld_lease_delay;
input                    tensor_wld_lease_valid;

wire [BANK_NUM-1:0]      tensor_lower_owned_mask;
wire [BANK_NUM-1:0]      lower_bank_req;
wire [BANK_NUM-1:0]      lower_bank_we;
wire [BANK_NUM*SRAM_ADDR_WIDTH-1:0] lower_bank_addr;
wire [BANK_NUM*DATA_WIDTH-1:0] lower_bank_wdata;
wire [BANK_NUM*BYTE_WIDTH-1:0] lower_bank_wstrb;
wire [BANK_NUM-1:0]      other_bank_req;
wire [BANK_NUM-1:0]      other_bank_we;
wire [BANK_NUM*SRAM_ADDR_WIDTH-1:0] other_bank_addr;
wire [BANK_NUM*DATA_WIDTH-1:0] other_bank_wdata;
wire [BANK_NUM*BYTE_WIDTH-1:0] other_bank_wstrb;
wire [BANK_NUM*DATA_WIDTH-1:0] bank_rdata;
wire [BANK_NUM-1:0]      bank_rvalid_unused;
wire [BANK_INDEX_WIDTH-1:0] bank16_phase_unused;
wire                     unused_lease_inputs;

assign unused_lease_inputs = dma_lease_valid || (|dma_lease_channel[2:0])
                          || (|dma_lease_cycles[8:0])
                          || (|dma_lease_delay[3:0])
                          || tensor_io_lease_valid
                          || tensor_io_lease1_valid
                          || tensor_io_lease2_valid
                          || tensor_wld_lease_valid
                          || (|tensor_io_lease_channel_mask[7:0])
                          || (|tensor_io_lease_cycles[8:0])
                          || (|tensor_io_lease_delay[3:0])
                          || (|tensor_io_lease1_channel_mask[7:0])
                          || (|tensor_io_lease1_cycles[8:0])
                          || (|tensor_io_lease1_delay[3:0])
                          || (|tensor_io_lease2_channel_mask[7:0])
                          || (|tensor_io_lease2_cycles[8:0])
                          || (|tensor_io_lease2_delay[3:0])
                          || (|tensor_wld_lease_channel_mask[7:0])
                          || (|tensor_wld_lease_cycles[8:0])
                          || (|tensor_wld_lease_delay[3:0])
                          || (SEGMENT_NUM[0])
                          || (SEGMENT_INDEX_WIDTH[0])
                          || (LSU_LOOKAHEAD[0])
                          || (TENSOR_IO_LOOKAHEAD[0])
                          || (TENSOR_WLD_LOOKAHEAD[0])
                          || (DMA_LOOKAHEAD[0])
                          || (|tensor_native_active_mask[BANK_NUM-1:0])
                          || (|actu_active_mask[BANK_NUM-1:0]);

assign tensor_lower_owned_mask[BANK_NUM-1:0] =
    bank16_phase_unused[1] ? 16'hcccc : 16'h3333;
assign tensor_native_bank_rdata[BANK_NUM*DATA_WIDTH-1:0] =
    bank_rdata[BANK_NUM*DATA_WIDTH-1:0];
assign actu_bank_rdata[BANK_NUM*DATA_WIDTH-1:0] =
    bank_rdata[BANK_NUM*DATA_WIDTH-1:0];
assign tensor_native_phase[BANK_INDEX_WIDTH-1:0] =
    bank16_phase_unused[BANK_INDEX_WIDTH-1:0];
assign lower_bank_req[BANK_NUM-1:0] =
    (tensor_native_bank_req[BANK_NUM-1:0] | actu_bank_req[BANK_NUM-1:0]) &
    {BANK_NUM{!lsu_store_block}};
assign lower_bank_we[BANK_NUM-1:0] =
    tensor_native_bank_we[BANK_NUM-1:0] | actu_bank_we[BANK_NUM-1:0];
assign lower_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0] =
    (|actu_bank_req[BANK_NUM-1:0])
    ? actu_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0]
    : tensor_native_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0];
assign lower_bank_wdata[BANK_NUM*DATA_WIDTH-1:0] =
    (|actu_bank_req[BANK_NUM-1:0])
    ? actu_bank_wdata[BANK_NUM*DATA_WIDTH-1:0]
    : tensor_native_bank_wdata[BANK_NUM*DATA_WIDTH-1:0];
assign lower_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0] =
    (|actu_bank_req[BANK_NUM-1:0])
    ? actu_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0]
    : tensor_native_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0];

edge_dtcm_other_bank16_adapter #(
  .ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .DMA_DATA_WIDTH(DMA_DATA_WIDTH),
  .BANK_NUM(BANK_NUM),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH)
) x_other_adapter (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .phase(bank16_phase_unused[BANK_INDEX_WIDTH-1:0]),
  .bank_rdata(bank_rdata[BANK_NUM*DATA_WIDTH-1:0]),
  .dma_addr(dma_addr[ADDR_WIDTH-1:0]),
  .dma_rdata(dma_rdata[DMA_DATA_WIDTH-1:0]),
  .dma_ready(dma_ready),
  .dma_req(dma_req && !lsu_store_block),
  .dma_rvalid(dma_rvalid),
  .dma_we(dma_we),
  .dma_wdata(dma_wdata[DMA_DATA_WIDTH-1:0]),
  .dma_wstrb(dma_wstrb[DMA_BYTE_WIDTH-1:0]),
  .lsu_addr(lsu_addr[ADDR_WIDTH-1:0]),
  .lsu_rdata(lsu_rdata[DATA_WIDTH-1:0]),
  .lsu_ready(lsu_ready),
  .lsu_req(lsu_req),
  .lsu_rvalid(lsu_rvalid),
  .lsu_we(lsu_we),
  .lsu_wdata(lsu_wdata[DATA_WIDTH-1:0]),
  .lsu_wstrb(lsu_wstrb[BYTE_WIDTH-1:0]),
  .sld_addr(sld_addr[ADDR_WIDTH-1:0]),
  .sld_rdata(sld_rdata[DMA_DATA_WIDTH-1:0]),
  .sld_ready(sld_ready),
  .sld_req(sld_req && !lsu_store_block),
  .sld_rvalid(sld_rvalid),
  .wld_addr(wld_addr[ADDR_WIDTH-1:0]),
  .wld_rdata(wld_rdata[DMA_DATA_WIDTH-1:0]),
  .wld_ready(wld_ready),
  .wld_req(wld_req && !lsu_store_block),
  .wld_rvalid(wld_rvalid),
  .upper_bank_req(other_bank_req[BANK_NUM-1:0]),
  .upper_bank_we(other_bank_we[BANK_NUM-1:0]),
  .upper_bank_addr(other_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0]),
  .upper_bank_wdata(other_bank_wdata[BANK_NUM*DATA_WIDTH-1:0]),
  .upper_bank_wstrb(other_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0])
);

edge_dtcm_bank16_raw_fabric #(
  .BANK_NUM(BANK_NUM),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .ADDR_WIDTH(SRAM_ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .SPLIT_MODE(1)
) x_raw_fabric (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .phase(bank16_phase_unused[BANK_INDEX_WIDTH-1:0]),
  .bank_req({BANK_NUM{1'b0}}),
  .bank_we({BANK_NUM{1'b0}}),
  .bank_addr({BANK_NUM*SRAM_ADDR_WIDTH{1'b0}}),
  .bank_wdata({BANK_NUM*DATA_WIDTH{1'b0}}),
  .bank_wstrb({BANK_NUM*BYTE_WIDTH{1'b0}}),
  .split_enable(1'b1),
  .lower_owned_mask(tensor_lower_owned_mask[BANK_NUM-1:0]),
  .upper_bank_req(other_bank_req[BANK_NUM-1:0]),
  .upper_bank_we(other_bank_we[BANK_NUM-1:0]),
  .upper_bank_addr(other_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0]),
  .upper_bank_wdata(other_bank_wdata[BANK_NUM*DATA_WIDTH-1:0]),
  .upper_bank_wstrb(other_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0]),
  .lower_bank_req(lower_bank_req[BANK_NUM-1:0]),
  .lower_bank_we(lower_bank_we[BANK_NUM-1:0]),
  .lower_bank_addr(lower_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0]),
  .lower_bank_wdata(lower_bank_wdata[BANK_NUM*DATA_WIDTH-1:0]),
  .lower_bank_wstrb(lower_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0]),
  .bank_rdata(bank_rdata[BANK_NUM*DATA_WIDTH-1:0]),
  .bank_rvalid(bank_rvalid_unused[BANK_NUM-1:0])
);

endmodule
