module edge_dtcm_bank_pair_slice(
  clk,
  dma_addr,
  dma_rdata,
  dma_req,
  dma_rvalid,
  dma_we,
  dma_wdata,
  dma_wstrb,
  lsu_addr,
  lsu_rdata,
  lsu_req,
  lsu_rvalid,
  lsu_we,
  lsu_wdata,
  lsu_wstrb,
  tensor_iopsum_addr,
  tensor_iopsum_rdata,
  tensor_iopsum_req,
  tensor_iopsum_rvalid,
  tensor_iopsum_we,
  tensor_iopsum_wdata,
  tensor_iopsum_wstrb,
  tensor_wld_addr,
  tensor_wld_rdata,
  tensor_wld_req,
  tensor_wld_rvalid,
  tensor_wld_we,
  tensor_wld_wdata,
  tensor_wld_wstrb,
  win_dma_grant,
  win_lsu_grant,
  win_tensor_iopsum_grant,
  win_tensor_wld_grant
);

parameter DATA_WIDTH      = 128;
parameter HALF_WIDTH      = 64;
parameter BYTE_WIDTH      = DATA_WIDTH / 8;
parameter HALF_BYTE_WIDTH = HALF_WIDTH / 8;
parameter ADDR_WIDTH      = 14;
parameter BANK_INDEX_WIDTH = 4;
parameter SEGMENT_NUM     = 1;
parameter SEGMENT_INDEX_WIDTH = 1;
parameter SRAM_ADDR_WIDTH = 10;

input                         clk;
input  [ADDR_WIDTH-1:0]       dma_addr;
input                         dma_req;
input                         dma_we;
input  [DATA_WIDTH-1:0]       dma_wdata;
input  [BYTE_WIDTH-1:0]       dma_wstrb;
input  [ADDR_WIDTH-1:0]       lsu_addr;
input                         lsu_req;
input                         lsu_we;
input  [DATA_WIDTH-1:0]       lsu_wdata;
input  [BYTE_WIDTH-1:0]       lsu_wstrb;
input  [ADDR_WIDTH-1:0]       tensor_iopsum_addr;
input                         tensor_iopsum_req;
input                         tensor_iopsum_we;
input  [DATA_WIDTH-1:0]       tensor_iopsum_wdata;
input  [BYTE_WIDTH-1:0]       tensor_iopsum_wstrb;
input  [ADDR_WIDTH-1:0]       tensor_wld_addr;
input                         tensor_wld_req;
input                         tensor_wld_we;
input  [DATA_WIDTH-1:0]       tensor_wld_wdata;
input  [BYTE_WIDTH-1:0]       tensor_wld_wstrb;
output [DATA_WIDTH-1:0]       dma_rdata;
output                        dma_rvalid;
output [DATA_WIDTH-1:0]       lsu_rdata;
output                        lsu_rvalid;
output [DATA_WIDTH-1:0]       tensor_iopsum_rdata;
output                        tensor_iopsum_rvalid;
output [DATA_WIDTH-1:0]       tensor_wld_rdata;
output                        tensor_wld_rvalid;
output                        win_dma_grant;
output                        win_lsu_grant;
output                        win_tensor_iopsum_grant;
output                        win_tensor_wld_grant;

wire                         pair_req;
wire                         pair_we;
wire [DATA_WIDTH-1:0]        pair_wdata;
wire [BYTE_WIDTH-1:0]        pair_wstrb;
wire [ADDR_WIDTH-1:0]        pair_addr;
wire [SRAM_ADDR_WIDTH-1:0]   sram_addr;
wire [SEGMENT_INDEX_WIDTH-1:0] pair_segment;
wire [HALF_WIDTH-1:0]        low_rdata [0:SEGMENT_NUM-1];
wire [HALF_WIDTH-1:0]        high_rdata [0:SEGMENT_NUM-1];
wire [HALF_WIDTH-1:0]        low_wen;
wire [HALF_WIDTH-1:0]        high_wen;
wire [DATA_WIDTH-1:0]        pair_rdata;
wire [SEGMENT_NUM-1:0]       segment_req;
reg                          rsp_dma;
reg                          rsp_lsu;
reg                          rsp_tensor_iopsum;
reg                          rsp_tensor_wld;
reg [SEGMENT_INDEX_WIDTH-1:0] rsp_segment;
reg [DATA_WIDTH-1:0]         pair_rdata_mux;

genvar wen_i;
genvar seg_i;
integer rdata_i;

assign pair_addr[ADDR_WIDTH-1:0] =
       win_tensor_iopsum_grant ? tensor_iopsum_addr[ADDR_WIDTH-1:0]
     : win_dma_grant           ? dma_addr[ADDR_WIDTH-1:0]
     : win_tensor_wld_grant    ? tensor_wld_addr[ADDR_WIDTH-1:0]
                               : lsu_addr[ADDR_WIDTH-1:0];
assign pair_segment[SEGMENT_INDEX_WIDTH-1:0] =
       (SEGMENT_NUM == 1)
       ? {SEGMENT_INDEX_WIDTH{1'b0}}
       : pair_addr[ADDR_WIDTH-1:ADDR_WIDTH-SEGMENT_INDEX_WIDTH];
assign sram_addr[SRAM_ADDR_WIDTH-1:0] =
       pair_addr[BANK_INDEX_WIDTH+SRAM_ADDR_WIDTH-1:BANK_INDEX_WIDTH];

generate
  for (wen_i = 0; wen_i < HALF_WIDTH; wen_i = wen_i + 1) begin: WEN_EXPAND
    assign low_wen[wen_i] = !pair_wstrb[wen_i / 8];
    assign high_wen[wen_i] =
           !pair_wstrb[HALF_BYTE_WIDTH + (wen_i / 8)];
  end
endgenerate

edge_dtcm_bank_pair_local_arb #(
  .DATA_WIDTH(DATA_WIDTH),
  .BYTE_WIDTH(BYTE_WIDTH)
) x_edge_dtcm_bank_pair_local_arb (
  .dma_req                 (dma_req),
  .dma_we                  (dma_we),
  .dma_wdata               (dma_wdata[DATA_WIDTH-1:0]),
  .dma_wstrb               (dma_wstrb[BYTE_WIDTH-1:0]),
  .lsu_req                 (lsu_req),
  .lsu_we                  (lsu_we),
  .lsu_wdata               (lsu_wdata[DATA_WIDTH-1:0]),
  .lsu_wstrb               (lsu_wstrb[BYTE_WIDTH-1:0]),
  .pair_req                (pair_req),
  .pair_we                 (pair_we),
  .pair_wdata              (pair_wdata[DATA_WIDTH-1:0]),
  .pair_wstrb              (pair_wstrb[BYTE_WIDTH-1:0]),
  .tensor_iopsum_req       (tensor_iopsum_req),
  .tensor_iopsum_we        (tensor_iopsum_we),
  .tensor_iopsum_wdata     (tensor_iopsum_wdata[DATA_WIDTH-1:0]),
  .tensor_iopsum_wstrb     (tensor_iopsum_wstrb[BYTE_WIDTH-1:0]),
  .tensor_wld_req          (tensor_wld_req),
  .tensor_wld_we           (tensor_wld_we),
  .tensor_wld_wdata        (tensor_wld_wdata[DATA_WIDTH-1:0]),
  .tensor_wld_wstrb        (tensor_wld_wstrb[BYTE_WIDTH-1:0]),
  .win_dma_grant           (win_dma_grant),
  .win_lsu_grant           (win_lsu_grant),
  .win_tensor_iopsum_grant (win_tensor_iopsum_grant),
  .win_tensor_wld_grant    (win_tensor_wld_grant)
);

generate
  for (seg_i = 0; seg_i < SEGMENT_NUM; seg_i = seg_i + 1) begin: SEGMENT
    assign segment_req[seg_i] =
           pair_req
        && ((SEGMENT_NUM == 1)
            || (pair_segment[SEGMENT_INDEX_WIDTH-1:0]
                == seg_i[SEGMENT_INDEX_WIDTH-1:0]));

    edge_dtcm_spsram_1024x64 x_edge_dtcm_sram_low(
      .A    (sram_addr[SRAM_ADDR_WIDTH-1:0]),
      .CEN  (!segment_req[seg_i]),
      .CLK  (clk),
      .D    (pair_wdata[HALF_WIDTH-1:0]),
      .GWEN (!pair_we),
      .Q    (low_rdata[seg_i][HALF_WIDTH-1:0]),
      .WEN  (low_wen[HALF_WIDTH-1:0])
    );

    edge_dtcm_spsram_1024x64 x_edge_dtcm_sram_high(
      .A    (sram_addr[SRAM_ADDR_WIDTH-1:0]),
      .CEN  (!segment_req[seg_i]),
      .CLK  (clk),
      .D    (pair_wdata[DATA_WIDTH-1:HALF_WIDTH]),
      .GWEN (!pair_we),
      .Q    (high_rdata[seg_i][HALF_WIDTH-1:0]),
      .WEN  (high_wen[HALF_WIDTH-1:0])
    );
  end
endgenerate

always @(posedge clk) begin
  if (pair_req)
    rsp_segment[SEGMENT_INDEX_WIDTH-1:0] <=
      pair_segment[SEGMENT_INDEX_WIDTH-1:0];
  rsp_tensor_iopsum <= win_tensor_iopsum_grant && !tensor_iopsum_we;
  rsp_dma <= win_dma_grant && !dma_we;
  rsp_tensor_wld <= win_tensor_wld_grant && !tensor_wld_we;
  rsp_lsu <= win_lsu_grant && !lsu_we;
end

always @(*) begin
  pair_rdata_mux[DATA_WIDTH-1:0] = {DATA_WIDTH{1'b0}};
  for (rdata_i = 0; rdata_i < SEGMENT_NUM; rdata_i = rdata_i + 1) begin
    if (rsp_segment[SEGMENT_INDEX_WIDTH-1:0]
        == rdata_i[SEGMENT_INDEX_WIDTH-1:0])
      pair_rdata_mux[DATA_WIDTH-1:0] =
        {high_rdata[rdata_i][HALF_WIDTH-1:0],
         low_rdata[rdata_i][HALF_WIDTH-1:0]};
  end
end

assign pair_rdata[DATA_WIDTH-1:0] =
       pair_rdata_mux[DATA_WIDTH-1:0];
assign tensor_iopsum_rdata[DATA_WIDTH-1:0] = pair_rdata[DATA_WIDTH-1:0];
assign dma_rdata[DATA_WIDTH-1:0] = pair_rdata[DATA_WIDTH-1:0];
assign tensor_wld_rdata[DATA_WIDTH-1:0] = pair_rdata[DATA_WIDTH-1:0];
assign lsu_rdata[DATA_WIDTH-1:0] = pair_rdata[DATA_WIDTH-1:0];
assign tensor_iopsum_rvalid = rsp_tensor_iopsum;
assign dma_rvalid = rsp_dma;
assign tensor_wld_rvalid = rsp_tensor_wld;
assign lsu_rvalid = rsp_lsu;

endmodule
