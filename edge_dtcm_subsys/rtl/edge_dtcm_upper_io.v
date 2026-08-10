module edge_dtcm_upper_io(
  clk,
  cpurst_b,
  phase,
  blocked_bank_mask,
  req,
  req_we,
  req_addr,
  req_wdata,
  req_wstrb,
  ready,
  rvalid,
  rdata,
  bank_req,
  bank_we,
  bank0,
  bank1,
  bank1_valid,
  bank_addr,
  bank_wdata,
  bank_wstrb,
  bank_rdata,
  active_mask
);

parameter ADDR_WIDTH       = 14;
parameter DATA_WIDTH       = 64;
parameter BYTE_WIDTH       = DATA_WIDTH / 8;
parameter LANES            = 2;
parameter CLIENT_DATA_WIDTH = LANES * DATA_WIDTH;
parameter CLIENT_BYTE_WIDTH = LANES * BYTE_WIDTH;
parameter BANK_NUM         = 16;
parameter BANK_INDEX_WIDTH = 4;
parameter SRAM_ADDR_WIDTH  = 10;
parameter [2:0] FIXED_CHANNEL = 3'd0;
parameter ALLOW_WRITE      = 1;

input                              clk;
input                              cpurst_b;
input  [BANK_INDEX_WIDTH-1:0]      phase;
input  [BANK_NUM-1:0]              blocked_bank_mask;
input                              req;
input                              req_we;
input  [ADDR_WIDTH-1:0]            req_addr;
input  [CLIENT_DATA_WIDTH-1:0]     req_wdata;
input  [CLIENT_BYTE_WIDTH-1:0]     req_wstrb;
output                             ready;
output                             rvalid;
output [CLIENT_DATA_WIDTH-1:0]     rdata;
output                             bank_req;
output                             bank_we;
output [BANK_INDEX_WIDTH-1:0]      bank0;
output [BANK_INDEX_WIDTH-1:0]      bank1;
output                             bank1_valid;
output [SRAM_ADDR_WIDTH-1:0]       bank_addr;
output [CLIENT_DATA_WIDTH-1:0]     bank_wdata;
output [CLIENT_BYTE_WIDTH-1:0]     bank_wstrb;
input  [BANK_NUM*DATA_WIDTH-1:0]   bank_rdata;
output [BANK_NUM-1:0]              active_mask;

wire [BANK_NUM-1:0]                bank0_mask;
wire [BANK_NUM-1:0]                bank1_mask;
wire [BANK_NUM-1:0]                request_mask;
wire [2:0]                         phase_pair;
wire [2:0]                         target_pair;
wire                               phase_match;
wire                               banks_available;
wire                               request_legal;
wire                               fire;
reg                                rvalid_q;
reg  [BANK_INDEX_WIDTH-1:0]        rsp_bank0_q;
reg  [BANK_INDEX_WIDTH-1:0]        rsp_bank1_q;

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

function [DATA_WIDTH-1:0] select_bank_data;
  input [BANK_NUM*DATA_WIDTH-1:0] data;
  input [BANK_INDEX_WIDTH-1:0] bank;
begin
  select_bank_data[DATA_WIDTH-1:0] =
      data[bank*DATA_WIDTH +: DATA_WIDTH];
end
endfunction

assign bank0[BANK_INDEX_WIDTH-1:0] = req_addr[BANK_INDEX_WIDTH-1:0];
assign bank1[BANK_INDEX_WIDTH-1:0] =
    bank0[BANK_INDEX_WIDTH-1:0] + {{BANK_INDEX_WIDTH-1{1'b0}}, 1'b1};
assign bank1_valid = (LANES == 2);
assign bank_addr[SRAM_ADDR_WIDTH-1:0] =
    req_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign bank_wdata[CLIENT_DATA_WIDTH-1:0] = req_wdata[CLIENT_DATA_WIDTH-1:0];
assign bank_wstrb[CLIENT_BYTE_WIDTH-1:0] = req_wstrb[CLIENT_BYTE_WIDTH-1:0];

assign bank0_mask[BANK_NUM-1:0] = one_bank_mask(bank0[BANK_INDEX_WIDTH-1:0]);
assign bank1_mask[BANK_NUM-1:0] = one_bank_mask(bank1[BANK_INDEX_WIDTH-1:0]);
assign request_mask[BANK_NUM-1:0] =
    bank0_mask[BANK_NUM-1:0]
  | (bank1_valid ? bank1_mask[BANK_NUM-1:0] : {BANK_NUM{1'b0}});
assign active_mask[BANK_NUM-1:0] =
    req ? request_mask[BANK_NUM-1:0] : {BANK_NUM{1'b0}};

assign phase_pair[2:0] = phase[BANK_INDEX_WIDTH-1:1];
assign target_pair[2:0] = bank0[BANK_INDEX_WIDTH-1:1];
assign phase_match = (FIXED_CHANNEL[2:0] + phase_pair[2:0])
                  == target_pair[2:0];
assign banks_available =
    (request_mask[BANK_NUM-1:0] & blocked_bank_mask[BANK_NUM-1:0])
    == {BANK_NUM{1'b0}};
assign request_legal = !req_we || (ALLOW_WRITE != 0);
assign fire = req && request_legal && phase_match && banks_available;
assign ready = fire;
assign bank_req = fire;
assign bank_we = req_we;

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    rvalid_q <= 1'b0;
    rsp_bank0_q <= {BANK_INDEX_WIDTH{1'b0}};
    rsp_bank1_q <= {BANK_INDEX_WIDTH{1'b0}};
  end else begin
    rvalid_q <= fire && !req_we;
    if (fire && !req_we) begin
      rsp_bank0_q <= bank0[BANK_INDEX_WIDTH-1:0];
      rsp_bank1_q <= bank1[BANK_INDEX_WIDTH-1:0];
    end
  end
end

assign rvalid = rvalid_q;

generate
  if (LANES == 1) begin: SINGLE_LANE_RDATA
    wire unused_rsp_bank1;
    assign unused_rsp_bank1 = |rsp_bank1_q[BANK_INDEX_WIDTH-1:0];
    assign rdata[DATA_WIDTH-1:0] =
        select_bank_data(bank_rdata[BANK_NUM*DATA_WIDTH-1:0], rsp_bank0_q);
  end else begin: PAIR_RDATA
    assign rdata[DATA_WIDTH-1:0] =
        select_bank_data(bank_rdata[BANK_NUM*DATA_WIDTH-1:0], rsp_bank0_q);
    assign rdata[2*DATA_WIDTH-1:DATA_WIDTH] =
        select_bank_data(bank_rdata[BANK_NUM*DATA_WIDTH-1:0], rsp_bank1_q);
  end
endgenerate

endmodule
