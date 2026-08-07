// Yosys/Xilinx synthesis view for the I-cache tag RAM.
module edge_ifu_icache_tag_array #(
  parameter TAG_WIDTH = 24,
  parameter LINES = 1024
) (
  input  wire                     clk,
  input  wire                     rst_b,
  input  wire                     write_valid,
  input  wire [$clog2(LINES)-1:0] write_index,
  input  wire [TAG_WIDTH-1:0]     write_tag,
  input  wire                     write_valid_bit,
  input  wire                     clear_valid,
  input  wire [$clog2(LINES)-1:0] clear_index,
  input  wire [$clog2(LINES)-1:0] read_index,
  output wire [TAG_WIDTH-1:0]     read_tag,
  output wire                     read_valid_bit
);

  wire tag_write_valid = write_valid || clear_valid;
  wire [$clog2(LINES)-1:0] tag_addr =
    clear_valid ? clear_index :
    write_valid ? write_index : read_index;
  wire [TAG_WIDTH-1:0] tag_wdata =
    clear_valid ? {TAG_WIDTH{1'b0}} : write_tag[TAG_WIDTH-1:0];

  reg valid_q [0:LINES-1];

  fpga_ram #(
    .DATAWIDTH(TAG_WIDTH),
    .ADDRWIDTH($clog2(LINES))
  ) tag_ram (
    .PortAClk(clk),
    .PortAAddr(tag_addr),
    .PortADataIn(tag_wdata),
    .PortAWriteEnable(tag_write_valid),
    .PortADataOut(read_tag)
  );

  assign read_valid_bit = valid_q[read_index];

  integer valid_i;
  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      for (valid_i = 0; valid_i < LINES; valid_i = valid_i + 1) begin
        valid_q[valid_i] = 1'b0;
      end
    end else if (clear_valid) begin
      valid_q[clear_index] <= 1'b0;
    end else if (write_valid) begin
      valid_q[write_index] <= write_valid_bit;
    end
  end

endmodule
