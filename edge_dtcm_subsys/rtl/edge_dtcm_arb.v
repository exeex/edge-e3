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
  memory_ready,
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

parameter SRAM_H4 = 0;
localparam READ_LATENCY = SRAM_H4 ? 4 : 1;
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

output memory_ready;
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

wire [15:0] six_lower_mask = (16'h0fff << bank16_phase_unused)
                              | (16'h0fff >> (16-bank16_phase_unused));
wire [15:0] shared_load_mask = 16'h0003 <<
    (2 * 3'(bank16_phase_unused[3:1] + 3'd5));
assign tensor_lower_owned_mask = SRAM_H4 ? six_lower_mask :
    (bank16_phase_unused[1] ? 16'hcccc : 16'h3333);
assign tensor_native_bank_rdata[BANK_NUM*DATA_WIDTH-1:0] =
    bank_rdata[BANK_NUM*DATA_WIDTH-1:0];
assign actu_bank_rdata[BANK_NUM*DATA_WIDTH-1:0] =
    bank_rdata[BANK_NUM*DATA_WIDTH-1:0];
assign tensor_native_phase[BANK_INDEX_WIDTH-1:0] =
    bank16_phase_unused[BANK_INDEX_WIDTH-1:0];
generate if (SRAM_H4) begin: SIX_LOWER
  for (genvar b=0; b<BANK_NUM; b=b+1) begin: BANK
    wire shared_load = shared_load_mask[b];
    wire use_actu = actu_bank_req[b];
    assign lower_bank_req[b] = !lsu_store_block &&
        (shared_load ? other_bank_req[b] : tensor_native_bank_req[b] | actu_bank_req[b]);
    assign lower_bank_we[b] = !shared_load &&
        (tensor_native_bank_we[b] | actu_bank_we[b]);
    assign lower_bank_addr[b*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] =
        shared_load ? other_bank_addr[b*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] :
        use_actu ? actu_bank_addr[b*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] :
                   tensor_native_bank_addr[b*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH];
    assign lower_bank_wdata[b*DATA_WIDTH +: DATA_WIDTH] =
        use_actu ? actu_bank_wdata[b*DATA_WIDTH +: DATA_WIDTH] :
                   tensor_native_bank_wdata[b*DATA_WIDTH +: DATA_WIDTH];
    assign lower_bank_wstrb[b*BYTE_WIDTH +: BYTE_WIDTH] =
        shared_load ? {BYTE_WIDTH{1'b0}} :
        use_actu ? actu_bank_wstrb[b*BYTE_WIDTH +: BYTE_WIDTH] :
                   tensor_native_bank_wstrb[b*BYTE_WIDTH +: BYTE_WIDTH];
  end
`ifndef SYNTHESIS
  always @(posedge clk) if (cpurst_b && memory_ready) begin
    if (|(tensor_native_bank_req & actu_bank_req))
      $fatal(1, "tensor/ACTU bank collision");
    if (|((tensor_native_bank_req | actu_bank_req) &
          (~six_lower_mask | shared_load_mask)))
      $fatal(1, "compute request outside reserved lower channels");
  end
`endif
end else begin: LEGACY_LOWER
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
end endgenerate

edge_dtcm_other_bank16_adapter #(
  .LOWER_SIX(SRAM_H4),
  .READ_LATENCY(READ_LATENCY),
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
  .dma_req(dma_req && !lsu_store_block && memory_ready),
  .dma_rvalid(dma_rvalid),
  .dma_we(dma_we),
  .dma_wdata(dma_wdata[DMA_DATA_WIDTH-1:0]),
  .dma_wstrb(dma_wstrb[DMA_BYTE_WIDTH-1:0]),
  .lsu_addr(lsu_addr[ADDR_WIDTH-1:0]),
  .lsu_rdata(lsu_rdata[DATA_WIDTH-1:0]),
  .lsu_ready(lsu_ready),
  .lsu_req(lsu_req && memory_ready),
  .lsu_rvalid(lsu_rvalid),
  .lsu_we(lsu_we),
  .lsu_wdata(lsu_wdata[DATA_WIDTH-1:0]),
  .lsu_wstrb(lsu_wstrb[BYTE_WIDTH-1:0]),
  .sld_addr(sld_addr[ADDR_WIDTH-1:0]),
  .sld_rdata(sld_rdata[DMA_DATA_WIDTH-1:0]),
  .sld_ready(sld_ready),
  .sld_req(sld_req && !lsu_store_block && memory_ready),
  .sld_rvalid(sld_rvalid),
  .wld_addr(wld_addr[ADDR_WIDTH-1:0]),
  .wld_rdata(wld_rdata[DMA_DATA_WIDTH-1:0]),
  .wld_ready(wld_ready),
  .wld_req(wld_req && !lsu_store_block && memory_ready),
  .wld_rvalid(wld_rvalid),
  .upper_bank_req(other_bank_req[BANK_NUM-1:0]),
  .upper_bank_we(other_bank_we[BANK_NUM-1:0]),
  .upper_bank_addr(other_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0]),
  .upper_bank_wdata(other_bank_wdata[BANK_NUM*DATA_WIDTH-1:0]),
  .upper_bank_wstrb(other_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0])
);

edge_dtcm_bank16_raw_fabric #(
  .SRAM_H4(SRAM_H4),
  .BANK_NUM(BANK_NUM),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .ADDR_WIDTH(SRAM_ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .SEGMENT_NUM(SEGMENT_NUM),
  .SPLIT_MODE(1)
) x_raw_fabric (
  .phase_ready(memory_ready),
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
