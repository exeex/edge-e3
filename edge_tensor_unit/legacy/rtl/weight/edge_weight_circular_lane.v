// One format-agnostic packed-weight lane.
//
// Storage is physically four 16-bit words.  Narrower 8-bit and 4-bit weight
// elements remain packed; their interpretation belongs to the consumer.
module edge_weight_circular_lane(
  clk,
  rst_b,
  write_valid_i,
  write_enable_i,
  write_data_i,
  read_data_o
);

input         clk;
input         rst_b;
input         write_valid_i;
input  [3:0]  write_enable_i;
input  [63:0] write_data_i;
output [63:0] read_data_o;

reg [63:0] storage_q;
integer word_i;

assign read_data_o = storage_q;

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    storage_q <= 64'b0;
  end else if (write_valid_i) begin
    for (word_i = 0; word_i < 4; word_i = word_i + 1)
      if (write_enable_i[word_i])
        storage_q[word_i*16 +: 16] <= write_data_i[word_i*16 +: 16];
  end
end

endmodule
