// Yosys/Xilinx synthesis view for the I-cache data array.
// Keeps the RTL module interface but uses a synchronous SRAM shape so Yosys
// infers RAMB resources instead of flattening the cache into LUTs.
module edge_ifu_icache_data_array #(
  parameter LINE_BITS = 128,
  parameter LINES = 1024
) (
  input  wire                     clk,
  input  wire                     write_valid,
  input  wire [$clog2(LINES)-1:0] write_index,
  input  wire [LINE_BITS-1:0]     write_data,
  input  wire [$clog2(LINES)-1:0] read_index,
  output wire [LINE_BITS-1:0]     read_data
);

  fpga_ram #(
    .DATAWIDTH(LINE_BITS),
    .ADDRWIDTH($clog2(LINES))
  ) data_ram (
    .PortAClk(clk),
    .PortAAddr(write_valid ? write_index : read_index),
    .PortADataIn(write_data),
    .PortAWriteEnable(write_valid),
    .PortADataOut(read_data)
  );

endmodule
