`timescale 1ns/1ps

module edge_cmpu_bf16_relation (
  input  wire [15:0] a,
  input  wire [15:0] b,
  output wire        a_nan,
  output wire        b_nan,
  output wire        unordered,
  output wire        lt,
  output wire        eq,
  output wire        gt
);

wire a_zero = (a[14:0] == 15'b0);
wire b_zero = (b[14:0] == 15'b0);
wire ordered_eq = (a == b) || (a_zero && b_zero);
reg ordered_lt;

assign a_nan = (a[14:7] == 8'hff) && (a[6:0] != 7'b0);
assign b_nan = (b[14:7] == 8'hff) && (b[6:0] != 7'b0);
assign unordered = a_nan || b_nan;
assign eq = !unordered && ordered_eq;
assign lt = !unordered && !ordered_eq && ordered_lt;
assign gt = !unordered && !ordered_eq && !ordered_lt;

always @* begin
  if (a[15] != b[15])
    ordered_lt = a[15];
  else if (a[15])
    ordered_lt = (a > b);
  else
    ordered_lt = (a < b);
end

endmodule
