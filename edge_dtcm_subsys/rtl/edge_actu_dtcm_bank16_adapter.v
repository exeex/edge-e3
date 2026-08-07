module edge_actu_dtcm_bank16_adapter(
  clk,
  cpurst_b,
  lower_owned_mask,
  rd_req,
  rd_ready,
  rd_addr,
  rd_rvalid,
  rd_rdata,
  wr_req,
  wr_ready,
  wr_addr,
  wr_wdata,
  wr_wstrb,
  bank_req,
  bank_we,
  bank_addr,
  bank_wdata,
  bank_wstrb,
  bank_rdata,
  active_mask
);

parameter ADDR_WIDTH       = 14;
parameter DATA_WIDTH       = 64;
parameter BYTE_WIDTH       = DATA_WIDTH / 8;
parameter BEAT_WIDTH       = 128;
parameter BEAT_BYTE_WIDTH  = BEAT_WIDTH / 8;
parameter BANK_NUM         = 16;
parameter BANK_INDEX_WIDTH = 4;
parameter SRAM_ADDR_WIDTH  = 10;

input                         clk;
input                         cpurst_b;
input  [BANK_NUM-1:0]         lower_owned_mask;
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
output [BANK_NUM-1:0]         active_mask;

wire [ADDR_WIDTH-1:0]         req_addr;
wire                          req_valid;
wire                          req_we;
wire [BANK_INDEX_WIDTH-1:0]   bank0;
wire [BANK_INDEX_WIDTH-1:0]   bank1;
wire [SRAM_ADDR_WIDTH-1:0]    sram_addr;
wire [BANK_NUM-1:0]           beat_mask;
wire                          lower_match;
wire                          fire;
reg                           rd_rvalid_q;
reg  [BANK_INDEX_WIDTH-1:0]   rd_bank0_q;
reg  [BANK_INDEX_WIDTH-1:0]   rd_bank1_q;

genvar bank_i;

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

function [DATA_WIDTH-1:0] bank_data;
  input [BANK_NUM*DATA_WIDTH-1:0] data;
  input [BANK_INDEX_WIDTH-1:0] bank;
begin
  bank_data[DATA_WIDTH-1:0] = data[bank*DATA_WIDTH +: DATA_WIDTH];
end
endfunction

assign req_valid = wr_req || rd_req;
assign req_we = wr_req;
assign req_addr[ADDR_WIDTH-1:0] =
    wr_req ? wr_addr[ADDR_WIDTH-1:0] : rd_addr[ADDR_WIDTH-1:0];
assign bank0[BANK_INDEX_WIDTH-1:0] =
    req_addr[BANK_INDEX_WIDTH-1:0];
assign bank1[BANK_INDEX_WIDTH-1:0] =
    req_addr[BANK_INDEX_WIDTH-1:0] + {{BANK_INDEX_WIDTH-1{1'b0}}, 1'b1};
assign sram_addr[SRAM_ADDR_WIDTH-1:0] =
    req_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign beat_mask[BANK_NUM-1:0] =
    one_bank_mask(bank0[BANK_INDEX_WIDTH-1:0])
  | one_bank_mask(bank1[BANK_INDEX_WIDTH-1:0]);
assign lower_match =
    (beat_mask[BANK_NUM-1:0] & lower_owned_mask[BANK_NUM-1:0])
    == beat_mask[BANK_NUM-1:0];
assign fire = req_valid && lower_match;

assign rd_ready = rd_req && !wr_req && lower_match;
assign wr_ready = wr_req && lower_match;
assign active_mask[BANK_NUM-1:0] =
    req_valid ? beat_mask[BANK_NUM-1:0] : {BANK_NUM{1'b0}};

generate
  for (bank_i = 0; bank_i < BANK_NUM; bank_i = bank_i + 1) begin: BANK
    wire is_bank0;
    wire is_bank1;

    assign is_bank0 = bank0[BANK_INDEX_WIDTH-1:0]
                   == bank_i[BANK_INDEX_WIDTH-1:0];
    assign is_bank1 = bank1[BANK_INDEX_WIDTH-1:0]
                   == bank_i[BANK_INDEX_WIDTH-1:0];
    assign bank_req[bank_i] = fire && (is_bank0 || is_bank1);
    assign bank_we[bank_i] = req_we;
    assign bank_addr[bank_i*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] =
        sram_addr[SRAM_ADDR_WIDTH-1:0];
    assign bank_wdata[bank_i*DATA_WIDTH +: DATA_WIDTH] =
        is_bank0 ? wr_wdata[DATA_WIDTH-1:0]
                 : wr_wdata[BEAT_WIDTH-1:DATA_WIDTH];
    assign bank_wstrb[bank_i*BYTE_WIDTH +: BYTE_WIDTH] =
        is_bank0 ? wr_wstrb[BYTE_WIDTH-1:0]
                 : wr_wstrb[BEAT_BYTE_WIDTH-1:BYTE_WIDTH];
  end
endgenerate

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    rd_rvalid_q <= 1'b0;
    rd_bank0_q <= {BANK_INDEX_WIDTH{1'b0}};
    rd_bank1_q <= {BANK_INDEX_WIDTH{1'b0}};
  end else begin
    rd_rvalid_q <= fire && !req_we;
    if (fire && !req_we) begin
      rd_bank0_q <= bank0[BANK_INDEX_WIDTH-1:0];
      rd_bank1_q <= bank1[BANK_INDEX_WIDTH-1:0];
    end
  end
end

assign rd_rvalid = rd_rvalid_q;
assign rd_rdata[BEAT_WIDTH-1:0] =
    {bank_data(bank_rdata[BANK_NUM*DATA_WIDTH-1:0], rd_bank1_q),
     bank_data(bank_rdata[BANK_NUM*DATA_WIDTH-1:0], rd_bank0_q)};

endmodule
