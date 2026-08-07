// Yosys/Xilinx synthesis view for the 4-bank D-cache data array.
module edge_dcache_banked_data_array #(
  parameter LINE_COUNT       = 256,
  parameter LINE_INDEX_WIDTH = (LINE_COUNT <= 2) ? 1 : $clog2(LINE_COUNT),
  parameter ROW_COUNT        = LINE_COUNT * 2,
  parameter ROW_INDEX_WIDTH  = (ROW_COUNT <= 2) ? 1 : $clog2(ROW_COUNT)
) (
  input  wire                         clk,
  input  wire                         reset_b,
  input  wire                         phase,

  input  wire                         lsu0_valid,
  output wire                         lsu0_ready,
  input  wire                         lsu0_write,
  input  wire [LINE_INDEX_WIDTH-1:0]  lsu0_line_index,
  input  wire [1:0]                   lsu0_beat_index,
  input  wire                         lsu0_word_hi,
  input  wire [63:0]                  lsu0_wdata,
  input  wire [7:0]                   lsu0_wstrb,
  output reg                          lsu0_rvalid,
  output reg  [63:0]                  lsu0_rdata,

  input  wire                         lsu1_valid,
  output wire                         lsu1_ready,
  input  wire                         lsu1_write,
  input  wire [LINE_INDEX_WIDTH-1:0]  lsu1_line_index,
  input  wire [1:0]                   lsu1_beat_index,
  input  wire                         lsu1_word_hi,
  input  wire [63:0]                  lsu1_wdata,
  input  wire [7:0]                   lsu1_wstrb,
  output reg                          lsu1_rvalid,
  output reg  [63:0]                  lsu1_rdata,

  input  wire                         mem_valid,
  output wire                         mem_ready,
  input  wire                         mem_write,
  input  wire [LINE_INDEX_WIDTH-1:0]  mem_line_index,
  input  wire [1:0]                   mem_beat_index,
  input  wire [127:0]                 mem_wdata,
  input  wire [15:0]                  mem_wstrb,
  output reg                          mem_rvalid,
  output reg  [127:0]                 mem_rdata
);

  wire lsu0_half = lsu0_beat_index[0];
  wire lsu1_half = lsu1_beat_index[0];
  wire lsu0_bank_hi = lsu0_word_hi;
  wire lsu1_bank_hi = lsu1_word_hi;
  wire lsu_bank_conflict =
    lsu0_valid && lsu1_valid &&
    (lsu0_half == lsu1_half) &&
    (lsu0_bank_hi == lsu1_bank_hi);
  wire mem_half = mem_beat_index[0];
  wire lsu0_fire = lsu0_valid && lsu0_ready;
  wire lsu1_fire = lsu1_valid && lsu1_ready;
  wire mem_fire = mem_valid && mem_ready;
  wire [ROW_INDEX_WIDTH-1:0] lsu0_row_index = {lsu0_line_index, lsu0_beat_index[1]};
  wire [ROW_INDEX_WIDTH-1:0] lsu1_row_index = {lsu1_line_index, lsu1_beat_index[1]};
  wire [ROW_INDEX_WIDTH-1:0] mem_row_index = {mem_line_index, mem_beat_index[1]};

  assign lsu0_ready = !mem_valid || (lsu0_half == phase);
  assign lsu1_ready = (!mem_valid || (lsu1_half == phase)) &&
                      !lsu_bank_conflict;
  assign mem_ready = (mem_half != phase);

  wire [3:0] lsu0_bank_sel = {
    lsu0_half && lsu0_bank_hi,
    lsu0_half && !lsu0_bank_hi,
    !lsu0_half && lsu0_bank_hi,
    !lsu0_half && !lsu0_bank_hi
  };
  wire [3:0] lsu1_bank_sel = {
    lsu1_half && lsu1_bank_hi,
    lsu1_half && !lsu1_bank_hi,
    !lsu1_half && lsu1_bank_hi,
    !lsu1_half && !lsu1_bank_hi
  };

  wire [63:0] bank0_rdata;
  wire [63:0] bank1_rdata;
  wire [63:0] bank2_rdata;
  wire [63:0] bank3_rdata;
  wire [7:0]  bank0_wstrb;
  wire [7:0]  bank1_wstrb;
  wire [7:0]  bank2_wstrb;
  wire [7:0]  bank3_wstrb;
  reg  [1:0]  lsu0_rbank_q;
  reg  [1:0]  lsu1_rbank_q;
  reg         mem_rhalf_q;

  wire bank0_we = (lsu0_fire && lsu0_write && lsu0_bank_sel[0]) ||
                  (lsu1_fire && lsu1_write && lsu1_bank_sel[0]) ||
                  (mem_fire && mem_write && !mem_half);
  wire bank1_we = (lsu0_fire && lsu0_write && lsu0_bank_sel[1]) ||
                  (lsu1_fire && lsu1_write && lsu1_bank_sel[1]) ||
                  (mem_fire && mem_write && !mem_half);
  wire bank2_we = (lsu0_fire && lsu0_write && lsu0_bank_sel[2]) ||
                  (lsu1_fire && lsu1_write && lsu1_bank_sel[2]) ||
                  (mem_fire && mem_write && mem_half);
  wire bank3_we = (lsu0_fire && lsu0_write && lsu0_bank_sel[3]) ||
                  (lsu1_fire && lsu1_write && lsu1_bank_sel[3]) ||
                  (mem_fire && mem_write && mem_half);

  wire [ROW_INDEX_WIDTH-1:0] bank0_addr =
    (lsu0_fire && lsu0_bank_sel[0]) ? lsu0_row_index :
    (lsu1_fire && lsu1_bank_sel[0]) ? lsu1_row_index :
    (mem_fire && !mem_half) ? mem_row_index : {ROW_INDEX_WIDTH{1'b0}};
  wire [ROW_INDEX_WIDTH-1:0] bank1_addr =
    (lsu0_fire && lsu0_bank_sel[1]) ? lsu0_row_index :
    (lsu1_fire && lsu1_bank_sel[1]) ? lsu1_row_index :
    (mem_fire && !mem_half) ? mem_row_index : {ROW_INDEX_WIDTH{1'b0}};
  wire [ROW_INDEX_WIDTH-1:0] bank2_addr =
    (lsu0_fire && lsu0_bank_sel[2]) ? lsu0_row_index :
    (lsu1_fire && lsu1_bank_sel[2]) ? lsu1_row_index :
    (mem_fire && mem_half) ? mem_row_index : {ROW_INDEX_WIDTH{1'b0}};
  wire [ROW_INDEX_WIDTH-1:0] bank3_addr =
    (lsu0_fire && lsu0_bank_sel[3]) ? lsu0_row_index :
    (lsu1_fire && lsu1_bank_sel[3]) ? lsu1_row_index :
    (mem_fire && mem_half) ? mem_row_index : {ROW_INDEX_WIDTH{1'b0}};

  wire [63:0] bank0_wdata =
    (lsu0_fire && lsu0_write && lsu0_bank_sel[0]) ? lsu0_wdata :
    (lsu1_fire && lsu1_write && lsu1_bank_sel[0]) ? lsu1_wdata :
    mem_wdata[63:0];
  wire [63:0] bank1_wdata =
    (lsu0_fire && lsu0_write && lsu0_bank_sel[1]) ? lsu0_wdata :
    (lsu1_fire && lsu1_write && lsu1_bank_sel[1]) ? lsu1_wdata :
    mem_wdata[127:64];
  wire [63:0] bank2_wdata =
    (lsu0_fire && lsu0_write && lsu0_bank_sel[2]) ? lsu0_wdata :
    (lsu1_fire && lsu1_write && lsu1_bank_sel[2]) ? lsu1_wdata :
    mem_wdata[63:0];
  wire [63:0] bank3_wdata =
    (lsu0_fire && lsu0_write && lsu0_bank_sel[3]) ? lsu0_wdata :
    (lsu1_fire && lsu1_write && lsu1_bank_sel[3]) ? lsu1_wdata :
    mem_wdata[127:64];

  assign bank0_wstrb =
    (lsu0_fire && lsu0_write && lsu0_bank_sel[0]) ? lsu0_wstrb :
    (lsu1_fire && lsu1_write && lsu1_bank_sel[0]) ? lsu1_wstrb :
    mem_wstrb[7:0];
  assign bank1_wstrb =
    (lsu0_fire && lsu0_write && lsu0_bank_sel[1]) ? lsu0_wstrb :
    (lsu1_fire && lsu1_write && lsu1_bank_sel[1]) ? lsu1_wstrb :
    mem_wstrb[15:8];
  assign bank2_wstrb =
    (lsu0_fire && lsu0_write && lsu0_bank_sel[2]) ? lsu0_wstrb :
    (lsu1_fire && lsu1_write && lsu1_bank_sel[2]) ? lsu1_wstrb :
    mem_wstrb[7:0];
  assign bank3_wstrb =
    (lsu0_fire && lsu0_write && lsu0_bank_sel[3]) ? lsu0_wstrb :
    (lsu1_fire && lsu1_write && lsu1_bank_sel[3]) ? lsu1_wstrb :
    mem_wstrb[15:8];

  genvar byte_idx;
  generate
    for (byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin : gen_byte_rams
      fpga_ram #(.DATAWIDTH(8), .ADDRWIDTH(ROW_INDEX_WIDTH)) bank0_ram (
        .PortAClk(clk),
        .PortAAddr(bank0_addr),
        .PortADataIn(bank0_wdata[byte_idx*8 +: 8]),
        .PortAWriteEnable(bank0_we && bank0_wstrb[byte_idx]),
        .PortADataOut(bank0_rdata[byte_idx*8 +: 8])
      );
      fpga_ram #(.DATAWIDTH(8), .ADDRWIDTH(ROW_INDEX_WIDTH)) bank1_ram (
        .PortAClk(clk),
        .PortAAddr(bank1_addr),
        .PortADataIn(bank1_wdata[byte_idx*8 +: 8]),
        .PortAWriteEnable(bank1_we && bank1_wstrb[byte_idx]),
        .PortADataOut(bank1_rdata[byte_idx*8 +: 8])
      );
      fpga_ram #(.DATAWIDTH(8), .ADDRWIDTH(ROW_INDEX_WIDTH)) bank2_ram (
        .PortAClk(clk),
        .PortAAddr(bank2_addr),
        .PortADataIn(bank2_wdata[byte_idx*8 +: 8]),
        .PortAWriteEnable(bank2_we && bank2_wstrb[byte_idx]),
        .PortADataOut(bank2_rdata[byte_idx*8 +: 8])
      );
      fpga_ram #(.DATAWIDTH(8), .ADDRWIDTH(ROW_INDEX_WIDTH)) bank3_ram (
        .PortAClk(clk),
        .PortAAddr(bank3_addr),
        .PortADataIn(bank3_wdata[byte_idx*8 +: 8]),
        .PortAWriteEnable(bank3_we && bank3_wstrb[byte_idx]),
        .PortADataOut(bank3_rdata[byte_idx*8 +: 8])
      );
    end
  endgenerate

  always @(posedge clk or negedge reset_b) begin
    if (!reset_b) begin
      lsu0_rvalid <= 1'b0;
      lsu0_rdata <= 64'b0;
      lsu1_rvalid <= 1'b0;
      lsu1_rdata <= 64'b0;
      mem_rvalid <= 1'b0;
      mem_rdata <= 128'b0;
      lsu0_rbank_q <= 2'b0;
      lsu1_rbank_q <= 2'b0;
      mem_rhalf_q <= 1'b0;
    end else begin
      lsu0_rvalid <= lsu0_fire && !lsu0_write;
      lsu1_rvalid <= lsu1_fire && !lsu1_write;
      mem_rvalid <= mem_fire && !mem_write;
      lsu0_rbank_q <= {lsu0_half, lsu0_bank_hi};
      lsu1_rbank_q <= {lsu1_half, lsu1_bank_hi};
      mem_rhalf_q <= mem_half;

      case (lsu0_rbank_q)
        2'b00: lsu0_rdata <= bank0_rdata;
        2'b01: lsu0_rdata <= bank1_rdata;
        2'b10: lsu0_rdata <= bank2_rdata;
        default: lsu0_rdata <= bank3_rdata;
      endcase
      case (lsu1_rbank_q)
        2'b00: lsu1_rdata <= bank0_rdata;
        2'b01: lsu1_rdata <= bank1_rdata;
        2'b10: lsu1_rdata <= bank2_rdata;
        default: lsu1_rdata <= bank3_rdata;
      endcase
      mem_rdata <= mem_rhalf_q ?
        {bank3_rdata, bank2_rdata} :
        {bank1_rdata, bank0_rdata};
    end
  end

endmodule
