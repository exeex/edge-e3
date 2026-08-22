// Reusable BF16 physical lane leaf. The two complete BF16 weight banks,
// active-bank select, significand multiply, exponent calculation, and result
// registers are deliberately owned by this one hardening boundary.
module edge_bf16_weight_compute_lane (
  input         clk,
  input         rst_b,
  input         in_valid_i,
  input  [15:0] activation_bf16_i,
  input         wld_en_i,
  input         wld_bank_i,
  input  [15:0] wld_weight_i,
  input         active_bank_i,
  output reg               out_valid_o,
  output reg [15:0]        product_sig_o,
  output reg signed [9:0]  product_exp_o,
  output reg               product_sign_o,
  output reg               product_nonzero_o
);

reg        valid_q;
reg [15:0] activation_bf16_q;

// Both banks are complete local BF16 words. The external controller owns
// write-bank selection and active-bank switching; there is no local swap FSM.
reg [15:0] local_weight_bank_a_q;
reg [15:0] local_weight_bank_b_q;

wire [15:0] active_weight = active_bank_i
                          ? local_weight_bank_b_q
                          : local_weight_bank_a_q;
wire [7:0] activation_exp = activation_bf16_q[14:7];
wire [7:0] weight_exp = active_weight[14:7];
wire [7:0] activation_sig = (activation_exp == 8'b0)
                          ? {1'b0, activation_bf16_q[6:0]}
                          : {1'b1, activation_bf16_q[6:0]};
wire [7:0] weight_sig = (weight_exp == 8'b0)
                      ? {1'b0, active_weight[6:0]}
                      : {1'b1, active_weight[6:0]};
wire signed [9:0] product_exp =
    $signed({2'b0, (activation_exp == 8'b0) ? 8'd1 : activation_exp})
  + $signed({2'b0, (weight_exp == 8'b0) ? 8'd1 : weight_exp})
  - 10'sd134;
wire product_nonzero = (activation_bf16_q[14:0] != 15'b0)
                     && (active_weight[14:0] != 15'b0);

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    valid_q                  <= 1'b0;
    activation_bf16_q        <= 16'b0;
    local_weight_bank_a_q    <= 16'b0;
    local_weight_bank_b_q    <= 16'b0;
    out_valid_o              <= 1'b0;
    product_sig_o            <= 16'b0;
    product_exp_o            <= 10'sd0;
    product_sign_o           <= 1'b0;
    product_nonzero_o        <= 1'b0;
  end else begin
    valid_q           <= in_valid_i;
    activation_bf16_q <= activation_bf16_i;

    if (wld_en_i) begin
      if (wld_bank_i)
        local_weight_bank_b_q <= wld_weight_i;
      else
        local_weight_bank_a_q <= wld_weight_i;
    end

    out_valid_o       <= valid_q;
    product_sig_o     <= activation_sig * weight_sig;
    product_exp_o     <= product_exp;
    product_sign_o    <= activation_bf16_q[15] ^ active_weight[15];
    product_nonzero_o <= product_nonzero;
  end
end

endmodule

// Thin integration wrapper. Dot8/dot16 composition should instantiate the
// lane leaf above, or its hardened abstract, once per compute lane.
module edge_bf16_weight_lane_exp_probe (
  input         clk,
  input         rst_b,
  input         in_valid_i,
  input  [15:0] activation_bf16_i,
  input         wld_en_i,
  input         wld_bank_i,
  input  [15:0] wld_weight_i,
  input         active_bank_i,
  output                    out_valid_o,
  output [15:0]             product_sig_o,
  output signed [9:0]       product_exp_o,
  output                    product_sign_o,
  output                    product_nonzero_o
);

edge_bf16_weight_compute_lane u_lane (
  .clk                  (clk),
  .rst_b                (rst_b),
  .in_valid_i           (in_valid_i),
  .activation_bf16_i    (activation_bf16_i),
  .wld_en_i             (wld_en_i),
  .wld_bank_i           (wld_bank_i),
  .wld_weight_i         (wld_weight_i),
  .active_bank_i        (active_bank_i),
  .out_valid_o          (out_valid_o),
  .product_sig_o        (product_sig_o),
  .product_exp_o        (product_exp_o),
  .product_sign_o       (product_sign_o),
  .product_nonzero_o    (product_nonzero_o)
);

endmodule
