// Yosys/Xilinx synthesis view for the D-cache tag RAM.
module edge_dcache_tag_array #(
  parameter TAG_WIDTH = 50,
  parameter LINES = 256
) (
  input  wire                     clk,
  input  wire                     write_valid,
  input  wire [$clog2(LINES)-1:0] write_index,
  input  wire [TAG_WIDTH-1:0]     write_tag,
  input  wire                     write_valid_bit,
  input  wire [$clog2(LINES)-1:0] read_index,
  output wire [TAG_WIDTH-1:0]     read_tag,
  output reg                      read_valid_bit
);

  reg valid_q [0:LINES-1];

  fpga_ram #(
    .DATAWIDTH(TAG_WIDTH),
    .ADDRWIDTH($clog2(LINES))
  ) tag_ram (
    .PortAClk(clk),
    .PortAAddr(write_valid ? write_index : read_index),
    .PortADataIn(write_tag[TAG_WIDTH-1:0]),
    .PortAWriteEnable(write_valid),
    .PortADataOut(read_tag)
  );

  always @(posedge clk) begin
    read_valid_bit <= valid_q[read_index];
    if (write_valid) begin
      valid_q[write_index] <= write_valid_bit;
    end
  end

endmodule
