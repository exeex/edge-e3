// E3 product adapter between the backend-neutral RV64 LSU memory I/O and DTCM.
module edge_lsu_dtcm_adapter #(
  parameter ADDR_WIDTH = 40,
  parameter DTCM_ADDR_WIDTH = 16,
  parameter DATA_WIDTH = 64
) (
  input  wire [ADDR_WIDTH-1:0]          mem_addr,
  input  wire                           mem_req,
  input  wire                           mem_we,
  input  wire [DATA_WIDTH-1:0]          mem_wdata,
  input  wire [(DATA_WIDTH/8)-1:0]      mem_wstrb,
  output wire [DATA_WIDTH-1:0]          mem_rdata,
  output wire                           mem_ready,
  output wire                           mem_rvalid,
  input  wire                           mem_store_block,
  input  wire [ADDR_WIDTH-1:0]          dtcm_base,
  output wire [DTCM_ADDR_WIDTH-1:0]     dtcm_addr,
  output wire                           dtcm_req,
  output wire                           dtcm_we,
  output wire [DATA_WIDTH-1:0]          dtcm_wdata,
  output wire [(DATA_WIDTH/8)-1:0]      dtcm_wstrb,
  input  wire [DATA_WIDTH-1:0]          dtcm_rdata,
  input  wire                           dtcm_ready,
  input  wire                           dtcm_rvalid,
  output wire                           asic_store_block
);

  wire [ADDR_WIDTH-1:0] byte_offset = mem_addr - dtcm_base;

  assign dtcm_addr = byte_offset[DTCM_ADDR_WIDTH+2:3];
  assign dtcm_req = mem_req;
  assign dtcm_we = mem_we;
  assign dtcm_wdata = mem_wdata;
  assign dtcm_wstrb = mem_wstrb;
  assign mem_rdata = dtcm_rdata;
  assign mem_ready = dtcm_ready;
  assign mem_rvalid = dtcm_rvalid;
  assign asic_store_block = mem_store_block;

endmodule
