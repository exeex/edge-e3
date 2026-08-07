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
  lsu_rvalid,
  lsu_we,
  lsu_wdata,
  lsu_wstrb,
  sld_addr,
  sld_rdata,
  sld_ready,
  sld_req,
  sld_rvalid,
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
wire                     other_lsu_bank_req;
wire                     other_lsu_bank_we;
wire [BANK_INDEX_WIDTH-1:0] other_lsu_bank;
wire [SRAM_ADDR_WIDTH-1:0] other_lsu_bank_addr;
wire [DATA_WIDTH-1:0]    other_lsu_bank_wdata;
wire [BYTE_WIDTH-1:0]    other_lsu_bank_wstrb;
wire [DATA_WIDTH-1:0]    other_lsu_bank_rdata;
wire                     other_dma_pair_req;
wire                     other_dma_pair_we;
wire [BANK_INDEX_WIDTH-1:0] other_dma_pair_bank0;
wire [BANK_INDEX_WIDTH-1:0] other_dma_pair_bank1;
wire [SRAM_ADDR_WIDTH-1:0] other_dma_pair_addr;
wire [DMA_DATA_WIDTH-1:0] other_dma_pair_wdata;
wire [DMA_BYTE_WIDTH-1:0] other_dma_pair_wstrb;
wire [DMA_DATA_WIDTH-1:0] other_dma_pair_rdata;
wire                     other_sld_pair_req;
wire [BANK_INDEX_WIDTH-1:0] other_sld_pair_bank0;
wire [BANK_INDEX_WIDTH-1:0] other_sld_pair_bank1;
wire [SRAM_ADDR_WIDTH-1:0] other_sld_pair_addr;
wire [DMA_DATA_WIDTH-1:0] other_sld_pair_rdata;
wire [BANK_NUM*DATA_WIDTH-1:0] bank_rdata;
wire [BANK_NUM-1:0]      bank_rvalid_unused;
wire [BANK_INDEX_WIDTH-1:0] bank16_phase_unused;
wire                     other_conflict_unused;
wire                     unused_lease_inputs;
reg  [BANK_INDEX_WIDTH-1:0] other_lsu_rsp_bank_q;
reg  [BANK_INDEX_WIDTH-1:0] other_dma_rsp_bank0_q;
reg  [BANK_INDEX_WIDTH-1:0] other_dma_rsp_bank1_q;
reg  [BANK_INDEX_WIDTH-1:0] other_sld_rsp_bank0_q;
reg  [BANK_INDEX_WIDTH-1:0] other_sld_rsp_bank1_q;

genvar                    other_bank_gen_i;

function [DATA_WIDTH-1:0] bank_data;
  input [BANK_NUM*DATA_WIDTH-1:0] data;
  input [BANK_INDEX_WIDTH-1:0] bank;
begin
  bank_data[DATA_WIDTH-1:0] = data[bank*DATA_WIDTH +: DATA_WIDTH];
end
endfunction

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
    tensor_native_bank_req[BANK_NUM-1:0] | actu_bank_req[BANK_NUM-1:0];
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
assign other_lsu_bank_rdata[DATA_WIDTH-1:0] =
    bank_data(bank_rdata[BANK_NUM*DATA_WIDTH-1:0], other_lsu_rsp_bank_q);
assign other_dma_pair_rdata[DMA_DATA_WIDTH-1:0] =
    {bank_data(bank_rdata[BANK_NUM*DATA_WIDTH-1:0], other_dma_rsp_bank1_q),
     bank_data(bank_rdata[BANK_NUM*DATA_WIDTH-1:0], other_dma_rsp_bank0_q)};
assign other_sld_pair_rdata[DMA_DATA_WIDTH-1:0] =
    {bank_data(bank_rdata[BANK_NUM*DATA_WIDTH-1:0], other_sld_rsp_bank1_q),
     bank_data(bank_rdata[BANK_NUM*DATA_WIDTH-1:0], other_sld_rsp_bank0_q)};

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
  .external_busy_mask(tensor_lower_owned_mask[BANK_NUM-1:0]),
  .phase(bank16_phase_unused[BANK_INDEX_WIDTH-1:0]),
  .dma_addr(dma_addr[ADDR_WIDTH-1:0]),
  .dma_rdata(dma_rdata[DMA_DATA_WIDTH-1:0]),
  .dma_ready(dma_ready),
  .dma_req(dma_req),
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
  .lsu_bank_req(other_lsu_bank_req),
  .lsu_bank_we(other_lsu_bank_we),
  .lsu_bank(other_lsu_bank[BANK_INDEX_WIDTH-1:0]),
  .lsu_bank_addr(other_lsu_bank_addr[SRAM_ADDR_WIDTH-1:0]),
  .lsu_bank_wdata(other_lsu_bank_wdata[DATA_WIDTH-1:0]),
  .lsu_bank_wstrb(other_lsu_bank_wstrb[BYTE_WIDTH-1:0]),
  .lsu_bank_rdata(other_lsu_bank_rdata[DATA_WIDTH-1:0]),
  .dma_pair_req(other_dma_pair_req),
  .dma_pair_we(other_dma_pair_we),
  .dma_pair_bank0(other_dma_pair_bank0[BANK_INDEX_WIDTH-1:0]),
  .dma_pair_bank1(other_dma_pair_bank1[BANK_INDEX_WIDTH-1:0]),
  .dma_pair_addr(other_dma_pair_addr[SRAM_ADDR_WIDTH-1:0]),
  .dma_pair_wdata(other_dma_pair_wdata[DMA_DATA_WIDTH-1:0]),
  .dma_pair_wstrb(other_dma_pair_wstrb[DMA_BYTE_WIDTH-1:0]),
  .dma_pair_rdata(other_dma_pair_rdata[DMA_DATA_WIDTH-1:0]),
  .sld_addr(sld_addr[ADDR_WIDTH-1:0]),
  .sld_rdata(sld_rdata[DMA_DATA_WIDTH-1:0]),
  .sld_ready(sld_ready),
  .sld_req(sld_req),
  .sld_rvalid(sld_rvalid),
  .sld_pair_req(other_sld_pair_req),
  .sld_pair_bank0(other_sld_pair_bank0[BANK_INDEX_WIDTH-1:0]),
  .sld_pair_bank1(other_sld_pair_bank1[BANK_INDEX_WIDTH-1:0]),
  .sld_pair_addr(other_sld_pair_addr[SRAM_ADDR_WIDTH-1:0]),
  .sld_pair_rdata(other_sld_pair_rdata[DMA_DATA_WIDTH-1:0]),
  .active_mask(),
  .bank16_conflict(other_conflict_unused)
);

generate
  for (other_bank_gen_i = 0; other_bank_gen_i < BANK_NUM;
       other_bank_gen_i = other_bank_gen_i + 1) begin: OTHER_MERGE_BANK
    wire bank_is_lsu;
    wire bank_is_dma0;
    wire bank_is_dma1;
    wire bank_is_sld0;
    wire bank_is_sld1;

    assign bank_is_lsu =
        other_lsu_bank[BANK_INDEX_WIDTH-1:0]
        == other_bank_gen_i[BANK_INDEX_WIDTH-1:0];
    assign bank_is_dma0 =
        other_dma_pair_bank0[BANK_INDEX_WIDTH-1:0]
        == other_bank_gen_i[BANK_INDEX_WIDTH-1:0];
    assign bank_is_dma1 =
        other_dma_pair_bank1[BANK_INDEX_WIDTH-1:0]
        == other_bank_gen_i[BANK_INDEX_WIDTH-1:0];
    assign bank_is_sld0 =
        other_sld_pair_bank0[BANK_INDEX_WIDTH-1:0]
        == other_bank_gen_i[BANK_INDEX_WIDTH-1:0];
    assign bank_is_sld1 =
        other_sld_pair_bank1[BANK_INDEX_WIDTH-1:0]
        == other_bank_gen_i[BANK_INDEX_WIDTH-1:0];

    // Fixed-channel clients are pair-disjoint in a cycle.
    assign other_bank_req[other_bank_gen_i] =
        (other_lsu_bank_req && bank_is_lsu)
     || (other_dma_pair_req && (bank_is_dma0 || bank_is_dma1))
     || (other_sld_pair_req && (bank_is_sld0 || bank_is_sld1));
    assign other_bank_we[other_bank_gen_i] =
        other_lsu_bank_req && bank_is_lsu
        ? other_lsu_bank_we
      : other_dma_pair_req && (bank_is_dma0 || bank_is_dma1)
        ? other_dma_pair_we
        : 1'b0;
    assign other_bank_addr[other_bank_gen_i*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] =
        other_lsu_bank_req && bank_is_lsu
        ? other_lsu_bank_addr[SRAM_ADDR_WIDTH-1:0]
      : other_dma_pair_req && (bank_is_dma0 || bank_is_dma1)
        ? other_dma_pair_addr[SRAM_ADDR_WIDTH-1:0]
        : other_sld_pair_addr[SRAM_ADDR_WIDTH-1:0];
    assign other_bank_wdata[other_bank_gen_i*DATA_WIDTH +: DATA_WIDTH] =
        other_lsu_bank_req && bank_is_lsu
        ? other_lsu_bank_wdata[DATA_WIDTH-1:0]
      : other_dma_pair_req && bank_is_dma0
          ? other_dma_pair_wdata[DATA_WIDTH-1:0]
      : other_dma_pair_req && bank_is_dma1
          ? other_dma_pair_wdata[DMA_DATA_WIDTH-1:DATA_WIDTH]
          : {DATA_WIDTH{1'b0}};
    assign other_bank_wstrb[other_bank_gen_i*BYTE_WIDTH +: BYTE_WIDTH] =
        other_lsu_bank_req && bank_is_lsu
        ? other_lsu_bank_wstrb[BYTE_WIDTH-1:0]
      : other_dma_pair_req && bank_is_dma0
          ? other_dma_pair_wstrb[BYTE_WIDTH-1:0]
      : other_dma_pair_req && bank_is_dma1
          ? other_dma_pair_wstrb[DMA_BYTE_WIDTH-1:BYTE_WIDTH]
          : {BYTE_WIDTH{1'b0}};
  end
endgenerate

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    other_lsu_rsp_bank_q <= {BANK_INDEX_WIDTH{1'b0}};
    other_dma_rsp_bank0_q <= {BANK_INDEX_WIDTH{1'b0}};
    other_dma_rsp_bank1_q <= {BANK_INDEX_WIDTH{1'b0}};
    other_sld_rsp_bank0_q <= {BANK_INDEX_WIDTH{1'b0}};
    other_sld_rsp_bank1_q <= {BANK_INDEX_WIDTH{1'b0}};
  end else begin
    if (other_lsu_bank_req && !other_lsu_bank_we)
      other_lsu_rsp_bank_q <= other_lsu_bank[BANK_INDEX_WIDTH-1:0];
    if (other_dma_pair_req && !other_dma_pair_we) begin
      other_dma_rsp_bank0_q <= other_dma_pair_bank0[BANK_INDEX_WIDTH-1:0];
      other_dma_rsp_bank1_q <= other_dma_pair_bank1[BANK_INDEX_WIDTH-1:0];
    end
    if (other_sld_pair_req) begin
      other_sld_rsp_bank0_q <= other_sld_pair_bank0[BANK_INDEX_WIDTH-1:0];
      other_sld_rsp_bank1_q <= other_sld_pair_bank1[BANK_INDEX_WIDTH-1:0];
    end
  end
end

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
