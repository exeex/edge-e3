module edge_bf16_sig_mul_probe_tb;
reg clk = 0;
reg rst_b = 0;
reg in_valid = 0;
reg [7:0] lhs_sig_i = 0;
reg [7:0] rhs_sig_i = 0;
wire out_valid;
wire [15:0] product_o;

edge_bf16_sig_mul_probe dut (.*);
always #5 clk = ~clk;

task check_mul;
  input [7:0] lhs;
  input [7:0] rhs;
  begin
    @(negedge clk);
    in_valid = 1;
    lhs_sig_i = lhs;
    rhs_sig_i = rhs;
    @(negedge clk);
    in_valid = 0;
    @(negedge clk);
    if (!out_valid || product_o !== lhs * rhs) begin
      $display("FAIL lhs=%0d rhs=%0d product=%0d valid=%b",
               lhs, rhs, product_o, out_valid);
      $finish;
    end
  end
endtask

initial begin
  repeat (2) @(negedge clk);
  rst_b = 1;
  check_mul(8'h80, 8'h80);
  check_mul(8'hff, 8'hff);
  check_mul(8'h81, 8'h7f);
  check_mul(8'h00, 8'hfe);
  $display("PASS edge_bf16_sig_mul_probe");
  $finish;
end
endmodule
