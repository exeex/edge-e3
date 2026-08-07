module edge_dtcm_bank_pair_local_arb(
  dma_req,
  dma_we,
  dma_wdata,
  dma_wstrb,
  lsu_req,
  lsu_we,
  lsu_wdata,
  lsu_wstrb,
  pair_req,
  pair_we,
  pair_wdata,
  pair_wstrb,
  tensor_iopsum_req,
  tensor_iopsum_we,
  tensor_iopsum_wdata,
  tensor_iopsum_wstrb,
  tensor_wld_req,
  tensor_wld_we,
  tensor_wld_wdata,
  tensor_wld_wstrb,
  win_dma_grant,
  win_lsu_grant,
  win_tensor_iopsum_grant,
  win_tensor_wld_grant
);

parameter DATA_WIDTH = 128;
parameter BYTE_WIDTH = DATA_WIDTH / 8;

input                    dma_req;
input                    dma_we;
input  [DATA_WIDTH-1:0]  dma_wdata;
input  [BYTE_WIDTH-1:0]  dma_wstrb;
input                    lsu_req;
input                    lsu_we;
input  [DATA_WIDTH-1:0]  lsu_wdata;
input  [BYTE_WIDTH-1:0]  lsu_wstrb;
input                    tensor_iopsum_req;
input                    tensor_iopsum_we;
input  [DATA_WIDTH-1:0]  tensor_iopsum_wdata;
input  [BYTE_WIDTH-1:0]  tensor_iopsum_wstrb;
input                    tensor_wld_req;
input                    tensor_wld_we;
input  [DATA_WIDTH-1:0]  tensor_wld_wdata;
input  [BYTE_WIDTH-1:0]  tensor_wld_wstrb;

output                   pair_req;
output                   pair_we;
output [DATA_WIDTH-1:0]  pair_wdata;
output [BYTE_WIDTH-1:0]  pair_wstrb;
output                   win_dma_grant;
output                   win_lsu_grant;
output                   win_tensor_iopsum_grant;
output                   win_tensor_wld_grant;

wire select_tensor;
wire select_non_tensor;
wire select_dma;
wire select_dma_rest;
wire select_wld;
wire select_lsu;
wire rest_we;
wire non_tensor_we;
wire [DATA_WIDTH-1:0] rest_wdata;
wire [DATA_WIDTH-1:0] non_tensor_wdata;
wire [BYTE_WIDTH-1:0] rest_wstrb;
wire [BYTE_WIDTH-1:0] non_tensor_wstrb;

assign select_tensor = tensor_iopsum_req;
assign select_non_tensor = !select_tensor
                         && (dma_req || tensor_wld_req || lsu_req);
assign select_dma = select_non_tensor && dma_req;
assign select_dma_rest = select_non_tensor && !select_dma
                       && (tensor_wld_req || lsu_req);
assign select_wld = select_dma_rest && tensor_wld_req;
assign select_lsu = select_dma_rest && !select_wld && lsu_req;

assign rest_we = select_wld ? tensor_wld_we : lsu_we;
assign rest_wdata[DATA_WIDTH-1:0] =
       select_wld ? tensor_wld_wdata[DATA_WIDTH-1:0]
                  : lsu_wdata[DATA_WIDTH-1:0];
assign rest_wstrb[BYTE_WIDTH-1:0] =
       select_wld ? tensor_wld_wstrb[BYTE_WIDTH-1:0]
                  : lsu_wstrb[BYTE_WIDTH-1:0];

assign non_tensor_we = select_dma ? dma_we : rest_we;
assign non_tensor_wdata[DATA_WIDTH-1:0] =
       select_dma ? dma_wdata[DATA_WIDTH-1:0]
                  : rest_wdata[DATA_WIDTH-1:0];
assign non_tensor_wstrb[BYTE_WIDTH-1:0] =
       select_dma ? dma_wstrb[BYTE_WIDTH-1:0]
                  : rest_wstrb[BYTE_WIDTH-1:0];

assign pair_req = select_tensor || select_dma || select_wld || select_lsu;
assign pair_we =
       select_tensor ? tensor_iopsum_we : non_tensor_we;
assign pair_wdata[DATA_WIDTH-1:0] =
       select_tensor ? tensor_iopsum_wdata[DATA_WIDTH-1:0]
                     : non_tensor_wdata[DATA_WIDTH-1:0];
assign pair_wstrb[BYTE_WIDTH-1:0] =
       select_tensor ? tensor_iopsum_wstrb[BYTE_WIDTH-1:0]
                     : non_tensor_wstrb[BYTE_WIDTH-1:0];

assign win_tensor_iopsum_grant = select_tensor;
assign win_dma_grant = select_dma;
assign win_tensor_wld_grant = select_wld;
assign win_lsu_grant = select_lsu;

endmodule
