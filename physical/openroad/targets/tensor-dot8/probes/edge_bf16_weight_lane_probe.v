// BF16 multiply-lane physical probe with two lane-local weight registers.
// Bank write and active-bank selection are owned entirely by external control.
module edge_bf16_weight_lane_probe (
  input         clk,
  input         rst_b,

  input         in_valid_i,
  input  [7:0]  activation_sig_i,

  input         wld_en_i,
  input         wld_bank_i,
  input  [15:0] wld_weight_i,
  input         active_bank_i,

  output reg        out_valid_o,
  output reg [15:0] product_o,
  output reg [8:0]  weight_meta_o
);

reg        valid_q;
reg [7:0]  activation_sig_q;
reg [15:0] weight_a_q;
reg [15:0] weight_b_q;

wire [15:0] active_weight = active_bank_i ? weight_b_q : weight_a_q;
wire [7:0] active_weight_sig = {1'b1, active_weight[6:0]};

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    valid_q         <= 1'b0;
    activation_sig_q <= 8'b0;
    weight_a_q      <= 16'b0;
    weight_b_q      <= 16'b0;
    out_valid_o     <= 1'b0;
    product_o       <= 16'b0;
    weight_meta_o   <= 9'b0;
  end else begin
    valid_q          <= in_valid_i;
    activation_sig_q <= activation_sig_i;

    if (wld_en_i) begin
      if (wld_bank_i)
        weight_b_q <= wld_weight_i;
      else
        weight_a_q <= wld_weight_i;
    end

    out_valid_o   <= valid_q;
    product_o     <= activation_sig_q * active_weight_sig;
    weight_meta_o <= {active_weight[15], active_weight[14:7]};
  end
end

endmodule
