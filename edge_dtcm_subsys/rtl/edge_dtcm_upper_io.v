module edge_dtcm_upper_io(
  clk,
  cpurst_b,
  phase,
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
  rsp_bank0,
  rsp_bank1,
  rsp_bank0_rdata,
  rsp_bank1_rdata
);

parameter ADDR_WIDTH       = 14;
parameter DATA_WIDTH       = 64;
parameter BYTE_WIDTH       = DATA_WIDTH / 8;
parameter LANES            = 2;
parameter CLIENT_DATA_WIDTH = LANES * DATA_WIDTH;
parameter CLIENT_BYTE_WIDTH = LANES * BYTE_WIDTH;
parameter BANK_INDEX_WIDTH = 4;
parameter SRAM_ADDR_WIDTH  = 10;
parameter [2:0] FIXED_CHANNEL = 3'd0;
parameter ALLOW_WRITE      = 1;

input                              clk;
input                              cpurst_b;
input  [BANK_INDEX_WIDTH-1:0]      phase;
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
output [BANK_INDEX_WIDTH-1:0]      rsp_bank0;
output [BANK_INDEX_WIDTH-1:0]      rsp_bank1;
input  [DATA_WIDTH-1:0]            rsp_bank0_rdata;
input  [DATA_WIDTH-1:0]            rsp_bank1_rdata;

wire [2:0]                         phase_pair;
wire [2:0]                         target_pair;
wire                               phase_match;
wire                               request_legal;
wire                               fire;
reg                                rvalid_q;
reg  [BANK_INDEX_WIDTH-1:0]        rsp_bank0_q;
reg  [BANK_INDEX_WIDTH-1:0]        rsp_bank1_q;

assign bank0[BANK_INDEX_WIDTH-1:0] = req_addr[BANK_INDEX_WIDTH-1:0];
assign bank1[BANK_INDEX_WIDTH-1:0] =
    bank0[BANK_INDEX_WIDTH-1:0] + {{BANK_INDEX_WIDTH-1{1'b0}}, 1'b1};
assign bank1_valid = (LANES == 2);
assign bank_addr[SRAM_ADDR_WIDTH-1:0] =
    req_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign bank_wdata[CLIENT_DATA_WIDTH-1:0] = req_wdata[CLIENT_DATA_WIDTH-1:0];
assign bank_wstrb[CLIENT_BYTE_WIDTH-1:0] = req_wstrb[CLIENT_BYTE_WIDTH-1:0];

assign phase_pair[2:0] = phase[BANK_INDEX_WIDTH-1:1];
assign target_pair[2:0] = bank0[BANK_INDEX_WIDTH-1:1];
assign phase_match = (FIXED_CHANNEL[2:0] + phase_pair[2:0])
                  == target_pair[2:0];
assign request_legal = !req_we || (ALLOW_WRITE != 0);
assign fire = req && request_legal && phase_match;
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
assign rsp_bank0[BANK_INDEX_WIDTH-1:0] = rsp_bank0_q[BANK_INDEX_WIDTH-1:0];
assign rsp_bank1[BANK_INDEX_WIDTH-1:0] = rsp_bank1_q[BANK_INDEX_WIDTH-1:0];

generate
  if (LANES == 1) begin: SINGLE_LANE_RDATA
    wire unused_rsp_bank1;
    assign unused_rsp_bank1 = |rsp_bank1_q[BANK_INDEX_WIDTH-1:0];
    assign rdata[DATA_WIDTH-1:0] = rsp_bank0_rdata[DATA_WIDTH-1:0];
  end else begin: PAIR_RDATA
    assign rdata[DATA_WIDTH-1:0] = rsp_bank0_rdata[DATA_WIDTH-1:0];
    assign rdata[2*DATA_WIDTH-1:DATA_WIDTH] = rsp_bank1_rdata[DATA_WIDTH-1:0];
  end
endgenerate

endmodule
