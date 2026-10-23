// Shared E3 post-dot pipeline; weight transport does not own arithmetic timing.
module edge_tensor_scale_psum8(
  input wire clk, input wire rst_b,
  input wire dot_valid, input wire [127:0] dot_bf16,
  input wire late_psum_mode_i, input wire late_psum_valid_i,
  input wire [127:0] psum_bf16_i, input wire scale_enable_i,
  input wire [127:0] scale_bf16_i, input wire rsum_enable_i,
  output wire dot_ready_o, output wire out_valid,
  output wire [127:0] output_bf16_o
);
wire scaled_mul_valid;
wire [127:0] scaled_mul_bf16;
wire [15:0] bypass_sum_lane [0:7];
wire [15:0] scaled_sum_lane [0:7];
wire [15:0] selected_bypass_lane [0:7];
reg [127:0] psum_d0, psum_d1, psum_d2, psum_d3, psum_d4, psum_d5, psum_d6;
reg [127:0] scale_d0, scale_d1, scale_d2, scale_d3, scale_d4, scale_d5, scale_d6;
reg scale_enable_d0, scale_enable_d1, scale_enable_d2;
reg scale_enable_d3, scale_enable_d4, scale_enable_d5, scale_enable_d6;
reg [127:0] scaled_psum_d0, scaled_psum_d1;
reg [127:0] output_q;
reg output_valid_q;

assign out_valid = output_valid_q;
assign dot_ready_o = dot_valid;
assign output_bf16_o = output_q;

edge_bf16_mul8_pipe x_scale_mul (
  .clk(clk), .rst_b(rst_b),
  .in_valid(dot_valid && scale_enable_d6
            && (!late_psum_mode_i || late_psum_valid_i)),
  .a_vec_i(dot_bf16), .b_vec_i(scale_d6),
  .out_valid(scaled_mul_valid), .y_vec_o(scaled_mul_bf16)
);

generate
  genvar lane_g;
  for (lane_g=0; lane_g<8; lane_g=lane_g+1) begin : GEN_SUM
    edge_psum x_bypass_add (
      .a_raw(dot_bf16[lane_g*16 +: 16]),
      .b_raw(late_psum_mode_i ? psum_bf16_i[lane_g*16 +: 16]
                              : psum_d6[lane_g*16 +: 16]),
      .y(bypass_sum_lane[lane_g])
    );
    assign selected_bypass_lane[lane_g] = rsum_enable_i
                                           ? dot_bf16[lane_g*16 +: 16]
                                           : bypass_sum_lane[lane_g];
    edge_psum x_scaled_add (
      .a_raw(scaled_mul_bf16[lane_g*16 +: 16]),
      .b_raw(scaled_psum_d1[lane_g*16 +: 16]),
      .y(scaled_sum_lane[lane_g])
    );
  end
endgenerate

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    psum_d0<=0; psum_d1<=0; psum_d2<=0; psum_d3<=0; psum_d4<=0; psum_d5<=0; psum_d6<=0;
    scale_d0<=0; scale_d1<=0; scale_d2<=0; scale_d3<=0; scale_d4<=0; scale_d5<=0; scale_d6<=0;
    scale_enable_d0<=0; scale_enable_d1<=0; scale_enable_d2<=0;
    scale_enable_d3<=0; scale_enable_d4<=0; scale_enable_d5<=0; scale_enable_d6<=0;
    scaled_psum_d0<=0; scaled_psum_d1<=0;
    output_q<=0; output_valid_q<=0;
  end else begin
    psum_d0<=psum_bf16_i; psum_d1<=psum_d0; psum_d2<=psum_d1;
    psum_d3<=psum_d2; psum_d4<=psum_d3; psum_d5<=psum_d4; psum_d6<=psum_d5;
    scale_d0<=scale_bf16_i; scale_d1<=scale_d0; scale_d2<=scale_d1;
    scale_d3<=scale_d2; scale_d4<=scale_d3; scale_d5<=scale_d4; scale_d6<=scale_d5;
    scale_enable_d0<=scale_enable_i; scale_enable_d1<=scale_enable_d0;
    scale_enable_d2<=scale_enable_d1; scale_enable_d3<=scale_enable_d2;
    scale_enable_d4<=scale_enable_d3; scale_enable_d5<=scale_enable_d4;
    scale_enable_d6<=scale_enable_d5;
    scaled_psum_d0<=late_psum_mode_i ? psum_bf16_i : psum_d6;
    scaled_psum_d1<=scaled_psum_d0;

    output_valid_q <= (dot_valid && !scale_enable_d6
                       && (!late_psum_mode_i || late_psum_valid_i))
                      || scaled_mul_valid;
    if (scaled_mul_valid)
      output_q <= {scaled_sum_lane[7], scaled_sum_lane[6],
                   scaled_sum_lane[5], scaled_sum_lane[4],
                   scaled_sum_lane[3], scaled_sum_lane[2],
                   scaled_sum_lane[1], scaled_sum_lane[0]};
    else if (dot_valid && !scale_enable_d5)
      output_q <= {selected_bypass_lane[7], selected_bypass_lane[6],
                   selected_bypass_lane[5], selected_bypass_lane[4],
                   selected_bypass_lane[3], selected_bypass_lane[2],
                   selected_bypass_lane[1], selected_bypass_lane[0]};
  end
end
endmodule
