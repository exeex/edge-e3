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
  bank_rvalid,
  phase_ready
);

parameter BANK_NUM        = 16;
parameter BANK_INDEX_WIDTH = 4;
parameter ADDR_WIDTH      = 10;
parameter DATA_WIDTH      = 64;
parameter BYTE_WIDTH      = DATA_WIDTH / 8;
parameter SEGMENT_NUM     = 1;
parameter SPLIT_MODE      = 0;
parameter SRAM_H4         = 0;
parameter WIDE_H4         = 0;

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
output phase_ready;
wire [BANK_NUM-1:0] bank_rvalid;
wire [BANK_NUM-1:0] selected_req, selected_we;
wire [BANK_NUM*ADDR_WIDTH-1:0] selected_addr;
wire [BANK_NUM*DATA_WIDTH-1:0] selected_data;
wire [BANK_NUM*BYTE_WIDTH-1:0] selected_strb;
wire [BANK_NUM*DATA_WIDTH-1:0] bank_rdata;
wire [BANK_NUM-1:0]           effective_bank_req;
wire                          unused_split_enable;

assign unused_split_enable = split_enable;

genvar bank_i;
genvar byte_i;
genvar segment_i;

generate if (!WIDE_H4) begin: LEGACY_PHASE
always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b)
    phase[BANK_INDEX_WIDTH-1:0] <= {BANK_INDEX_WIDTH{1'b0}};
  else
    phase[BANK_INDEX_WIDTH-1:0] <= phase[BANK_INDEX_WIDTH-1:0]
                                 + {{BANK_INDEX_WIDTH-2{1'b0}}, 2'd2};
end
end endgenerate

generate
  if (WIDE_H4) begin: WIDE_STORAGE
    edge_dtcm_h4_wide_bank_direct x_direct (
      .clk(clk), .cpurst_b(cpurst_b), .phase_ready(phase_ready), .phase(phase),
      .bank_req(selected_req), .bank_we(selected_we), .bank_addr(selected_addr),
      .bank_wdata(selected_data), .bank_wstrb(selected_strb),
      .bank_rvalid(bank_rvalid), .bank_rdata(bank_rdata));
  end else if (SRAM_H4 != 0) begin: H4_STORAGE
    edge_dtcm_h4_wrapper x_wrapper (
      .clk(clk), .cpurst_b(cpurst_b), .pair_phase(phase[3:1]),
      .phase_ready(phase_ready), .bank_req(selected_req),
      .bank_we(selected_we), .bank_addr(selected_addr),
      .bank_wdata(selected_data), .bank_wstrb(selected_strb),
      .bank_rdata(bank_rdata), .bank_rvalid(bank_rvalid));
`ifndef SYNTHESIS
    initial if (BANK_NUM != 16 || DATA_WIDTH != 64 || ADDR_WIDTH != 10 || SEGMENT_NUM != 1)
      $fatal(1, "H4 DTCM requires 16 x 64-bit banks, 1024 rows");
`endif
  end else begin: INFERRED_VALID
    reg [BANK_NUM-1:0] valid_q;
    always @(posedge clk or negedge cpurst_b)
      if (!cpurst_b) valid_q <= 0;
      else valid_q <= effective_bank_req;
    assign bank_rvalid = valid_q;
    assign phase_ready = cpurst_b;
  end
endgenerate

generate
  for (bank_i = 0; bank_i < BANK_NUM; bank_i = bank_i + 1) begin: BANK
    wire [DATA_WIDTH-1:0] bank_wen;
    wire local_req;
    wire local_we;
    wire [ADDR_WIDTH-1:0] local_addr;
    wire [DATA_WIDTH-1:0] local_wdata;
    wire [BYTE_WIDTH-1:0] local_wstrb;
    wire [SEGMENT_NUM*DATA_WIDTH-1:0] segment_rdata;
    localparam PHYSICAL_ADDR_WIDTH = ADDR_WIDTH - ((SEGMENT_NUM <= 1) ? 0 : $clog2(SEGMENT_NUM));

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

    assign selected_req[bank_i] = local_req;
    assign selected_we[bank_i] = local_we;
    assign selected_addr[bank_i*ADDR_WIDTH +: ADDR_WIDTH] = local_addr;
    assign selected_data[bank_i*DATA_WIDTH +: DATA_WIDTH] = local_wdata;
    assign selected_strb[bank_i*BYTE_WIDTH +: BYTE_WIDTH] = local_wstrb;

    if (SRAM_H4 == 0) begin: INFERRED_STORAGE
      for (byte_i = 0; byte_i < BYTE_WIDTH; byte_i = byte_i + 1) begin: WEN
        assign bank_wen[byte_i*8 +: 8] =
            local_wstrb[byte_i] ? 8'h00 : 8'hff;
      end

      if (SEGMENT_NUM == 1) begin: ONE_SEGMENT_RDATA
        assign bank_rdata[bank_i*DATA_WIDTH +: DATA_WIDTH] =
            segment_rdata[DATA_WIDTH-1:0];
      end else begin: MANY_SEGMENT_RDATA
        reg [$clog2(SEGMENT_NUM)-1:0] read_segment_q;
        always @(posedge clk or negedge cpurst_b) begin
          if (!cpurst_b)
            read_segment_q <= 0;
          else if (local_req && !local_we)
            read_segment_q <=
                local_addr[ADDR_WIDTH-1 -: $clog2(SEGMENT_NUM)];
        end
        assign bank_rdata[bank_i*DATA_WIDTH +: DATA_WIDTH] =
            segment_rdata[read_segment_q*DATA_WIDTH +: DATA_WIDTH];
      end

      for (segment_i = 0; segment_i < SEGMENT_NUM; segment_i = segment_i + 1) begin: SEGMENT
        wire segment_select;
        if (SEGMENT_NUM == 1) begin: ONE_SEGMENT
          assign segment_select = 1'b1;
        end else begin: MANY_SEGMENTS
          assign segment_select =
              local_addr[ADDR_WIDTH-1 -: $clog2(SEGMENT_NUM)] == segment_i;
        end
        edge_dtcm_spsram_1024x64 #(
          .ADDR_WIDTH(PHYSICAL_ADDR_WIDTH),
          .DATA_WIDTH(DATA_WIDTH)
        ) x_sram (
          .A    (local_addr[PHYSICAL_ADDR_WIDTH-1:0]),
          .CEN  (!(local_req && segment_select)),
          .CLK  (clk),
          .D    (local_wdata[DATA_WIDTH-1:0]),
          .GWEN (!local_we),
          .Q    (segment_rdata[segment_i*DATA_WIDTH +: DATA_WIDTH]),
          .WEN  (bank_wen[DATA_WIDTH-1:0])
        );
      end
    end
  end
endgenerate

endmodule
