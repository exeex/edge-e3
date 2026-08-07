module edge_dtcm_bank16_raw_fabric(
  clk,
  cpurst_b,
  phase,
  bank_req,
  bank_we,
  bank_addr,
  bank_wdata,
  bank_wstrb,
  split_enable,
  lower_owned_mask,
  upper_bank_req,
  upper_bank_we,
  upper_bank_addr,
  upper_bank_wdata,
  upper_bank_wstrb,
  lower_bank_req,
  lower_bank_we,
  lower_bank_addr,
  lower_bank_wdata,
  lower_bank_wstrb,
  bank_rdata,
  bank_rvalid
);

parameter BANK_NUM        = 16;
parameter BANK_INDEX_WIDTH = 4;
parameter ADDR_WIDTH      = 10;
parameter DATA_WIDTH      = 64;
parameter BYTE_WIDTH      = DATA_WIDTH / 8;
parameter SPLIT_MODE      = 0;

input                         clk;
input                         cpurst_b;
output [BANK_INDEX_WIDTH-1:0] phase;
input  [BANK_NUM-1:0]         bank_req;
input  [BANK_NUM-1:0]         bank_we;
input  [BANK_NUM*ADDR_WIDTH-1:0] bank_addr;
input  [BANK_NUM*DATA_WIDTH-1:0] bank_wdata;
input  [BANK_NUM*BYTE_WIDTH-1:0] bank_wstrb;
input                         split_enable;
input  [BANK_NUM-1:0]         lower_owned_mask;
input  [BANK_NUM-1:0]         upper_bank_req;
input  [BANK_NUM-1:0]         upper_bank_we;
input  [BANK_NUM*ADDR_WIDTH-1:0] upper_bank_addr;
input  [BANK_NUM*DATA_WIDTH-1:0] upper_bank_wdata;
input  [BANK_NUM*BYTE_WIDTH-1:0] upper_bank_wstrb;
input  [BANK_NUM-1:0]         lower_bank_req;
input  [BANK_NUM-1:0]         lower_bank_we;
input  [BANK_NUM*ADDR_WIDTH-1:0] lower_bank_addr;
input  [BANK_NUM*DATA_WIDTH-1:0] lower_bank_wdata;
input  [BANK_NUM*BYTE_WIDTH-1:0] lower_bank_wstrb;
output [BANK_NUM*DATA_WIDTH-1:0] bank_rdata;
output [BANK_NUM-1:0]         bank_rvalid;

reg [BANK_INDEX_WIDTH-1:0]    phase;
reg [BANK_NUM-1:0]            bank_rvalid;
wire [BANK_NUM*DATA_WIDTH-1:0] bank_rdata;
wire [BANK_NUM-1:0]           effective_bank_req;
wire                          unused_split_enable;

assign unused_split_enable = split_enable;

genvar bank_i;
genvar byte_i;

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b)
    phase[BANK_INDEX_WIDTH-1:0] <= {BANK_INDEX_WIDTH{1'b0}};
  else
    phase[BANK_INDEX_WIDTH-1:0] <= phase[BANK_INDEX_WIDTH-1:0]
                                 + {{BANK_INDEX_WIDTH-2{1'b0}}, 2'd2};
end

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b)
    bank_rvalid[BANK_NUM-1:0] <= {BANK_NUM{1'b0}};
  else
    bank_rvalid[BANK_NUM-1:0] <= effective_bank_req[BANK_NUM-1:0];
end

generate
  for (bank_i = 0; bank_i < BANK_NUM; bank_i = bank_i + 1) begin: BANK
    wire [DATA_WIDTH-1:0] bank_wen;
    wire local_req;
    wire local_we;
    wire [ADDR_WIDTH-1:0] local_addr;
    wire [DATA_WIDTH-1:0] local_wdata;
    wire [BYTE_WIDTH-1:0] local_wstrb;

    if (SPLIT_MODE != 0) begin: SPLIT_BANK
      wire use_lower;

      assign use_lower = lower_owned_mask[bank_i];
      assign local_req = use_lower ? lower_bank_req[bank_i]
                                   : upper_bank_req[bank_i];
      assign local_we = use_lower ? lower_bank_we[bank_i]
                                  : upper_bank_we[bank_i];
      assign local_addr[ADDR_WIDTH-1:0] =
          use_lower ? lower_bank_addr[bank_i*ADDR_WIDTH +: ADDR_WIDTH]
                    : upper_bank_addr[bank_i*ADDR_WIDTH +: ADDR_WIDTH];
      assign local_wdata[DATA_WIDTH-1:0] =
          use_lower ? lower_bank_wdata[bank_i*DATA_WIDTH +: DATA_WIDTH]
                    : upper_bank_wdata[bank_i*DATA_WIDTH +: DATA_WIDTH];
      assign local_wstrb[BYTE_WIDTH-1:0] =
          use_lower ? lower_bank_wstrb[bank_i*BYTE_WIDTH +: BYTE_WIDTH]
                    : upper_bank_wstrb[bank_i*BYTE_WIDTH +: BYTE_WIDTH];
    end else begin: LEGACY_BANK
      wire unused_split_inputs;

      assign unused_split_inputs = lower_owned_mask[bank_i]
                                || upper_bank_req[bank_i]
                                || upper_bank_we[bank_i]
                                || lower_bank_req[bank_i]
                                || lower_bank_we[bank_i]
                                || (|upper_bank_addr[bank_i*ADDR_WIDTH +: ADDR_WIDTH])
                                || (|upper_bank_wdata[bank_i*DATA_WIDTH +: DATA_WIDTH])
                                || (|upper_bank_wstrb[bank_i*BYTE_WIDTH +: BYTE_WIDTH])
                                || (|lower_bank_addr[bank_i*ADDR_WIDTH +: ADDR_WIDTH])
                                || (|lower_bank_wdata[bank_i*DATA_WIDTH +: DATA_WIDTH])
                                || (|lower_bank_wstrb[bank_i*BYTE_WIDTH +: BYTE_WIDTH]);
      assign local_req = bank_req[bank_i];
      assign local_we = bank_we[bank_i];
      assign local_addr[ADDR_WIDTH-1:0] =
          bank_addr[bank_i*ADDR_WIDTH +: ADDR_WIDTH];
      assign local_wdata[DATA_WIDTH-1:0] =
          bank_wdata[bank_i*DATA_WIDTH +: DATA_WIDTH];
      assign local_wstrb[BYTE_WIDTH-1:0] =
          bank_wstrb[bank_i*BYTE_WIDTH +: BYTE_WIDTH];
    end

    assign effective_bank_req[bank_i] = local_req && !local_we;

    for (byte_i = 0; byte_i < BYTE_WIDTH; byte_i = byte_i + 1) begin: WEN
      assign bank_wen[byte_i*8 +: 8] =
          local_wstrb[byte_i] ? 8'h00 : 8'hff;
    end

    edge_dtcm_spsram_1024x64 #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
    ) x_sram (
      .A    (local_addr[ADDR_WIDTH-1:0]),
      .CEN  (!local_req),
      .CLK  (clk),
      .D    (local_wdata[DATA_WIDTH-1:0]),
      .GWEN (!local_we),
      .Q    (bank_rdata[bank_i*DATA_WIDTH +: DATA_WIDTH]),
      .WEN  (bank_wen[DATA_WIDTH-1:0])
    );
  end
endgenerate

endmodule
