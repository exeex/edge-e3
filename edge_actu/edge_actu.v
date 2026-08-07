`timescale 1ns/1ps

module edge_actu #(
  parameter PIPE_STAGES = 9
) (
  input  wire        forever_cpuclk,
  input  wire        cpurst_b,

  input  wire        in_valid,
  output wire        in_ready,
  input  wire [2:0]  in_mode,
  input  wire [31:0] in_value,
  input  wire [31:0] in_softmax_max,
  input  wire        softmax_sum_clear,

  output wire        out_valid,
  output wire [2:0]  out_mode,
  output wire [31:0] out_value,
  output wire        softmax_sum_valid,
  output wire [31:0] softmax_sum_value
);

localparam [2:0] EDGE_ACTU_MODE_EXP_ONLY = 3'd0;
localparam [2:0] EDGE_ACTU_MODE_RCP_ONLY = 3'd1;
localparam [2:0] EDGE_ACTU_MODE_SIGMOID  = 3'd2;
localparam [2:0] EDGE_ACTU_MODE_SILU     = 3'd3;
localparam [2:0] EDGE_ACTU_MODE_TANH     = 3'd4;
localparam [2:0] EDGE_ACTU_MODE_SOFTMAX  = 3'd5;
localparam [2:0] EDGE_ACTU_MODE_RSQRT    = 3'd6;
localparam [2:0] EDGE_ACTU_MODE_SOFTMAX_NORMALIZE = 3'd7;
localparam integer NONLINEAR_LATENCY = 4;
localparam integer POST_STAGES = PIPE_STAGES - NONLINEAR_LATENCY;

reg [POST_STAGES-1:0] valid_pipe;
reg [2:0]             mode_pipe [0:POST_STAGES-1];
reg [31:0]            value_pipe [0:POST_STAGES-1];
reg [2:0]             nonlinear_mode_pipe [0:NONLINEAR_LATENCY-1];
reg [31:0]            nonlinear_x_pipe [0:NONLINEAR_LATENCY-1];
reg [31:0]            nonlinear_exp_pipe [0:NONLINEAR_LATENCY-1];

integer stage;
wire   input_fire;
wire [31:0] exp_input_bits;
wire [31:0] exp_lut_bits;
wire [31:0] exp_internal_bits;
wire [31:0] rcp_input_bits;
wire [31:0] rsqrt_input_bits;
wire [31:0] rcp_lut_bits;
wire [31:0] rcp_internal_bits;
wire [31:0] exp_result_bits;
wire [31:0] rcp_result_bits;
wire [31:0] sigmoid_result_bits;
wire [31:0] silu_result_bits;
wire [31:0] tanh_result_bits;
wire [31:0] softmax_result_bits;
wire [31:0] softmax_normalize_bits;
wire [31:0] softmax_sum_next_bits;
wire [31:0] stage0_result_bits;
wire [31:0] neg_abs_bits;
wire [31:0] neg_abs_x2_bits;
wire [31:0] softmax_delta_bits;
wire [31:0] fused_den_bits;
wire [31:0] sigmoid_neg_bits;
wire [31:0] sigmoid_bits;
wire [31:0] silu_product_bits;
wire [31:0] tanh_one_minus_bits;
wire [31:0] tanh_abs_bits;
wire [31:0] tanh_signed_bits;
wire        fused_sigmoid_like;
wire        fused_tanh_like;
wire        nonlinear_out_valid;
wire [31:0] nonlinear_out_bits;
wire [2:0]  aligned_mode;
wire [31:0] aligned_x_bits;
wire [31:0] aligned_exp_bits;
wire [31:0] aligned_exp_internal_bits;
wire [31:0] aligned_rcp_internal_bits;
reg  [31:0] softmax_sum_q;

assign in_ready = cpurst_b;
assign input_fire = in_valid && in_ready;
assign out_valid = valid_pipe[POST_STAGES-1];
assign out_mode = mode_pipe[POST_STAGES-1];
assign out_value = value_pipe[POST_STAGES-1];

function [31:0] bf16_round_bits;
  input [31:0] bits;
  reg [15:0] rounded;
  begin
    if ((bits[30:23] == 8'hff) && (bits[22:0] != 23'b0)) begin
      rounded = 16'h7fc0;
    end else begin
      rounded = bits[31:16] + {15'b0, (bits[15] && (|bits[14:0] || bits[16]))};
      if ((rounded == 16'h0000) && bits[31])
        rounded = 16'h8000;
    end
    bf16_round_bits = {rounded, 16'h0000};
  end
endfunction

function [31:0] bf22_round_bits;
  input [31:0] bits;
  reg [31:0] rounded_bits;
  reg [31:0] bias;
  begin
    if ((bits[30:23] == 8'hff) && (bits[22:0] != 23'b0)) begin
      bf22_round_bits = 32'h7fc0_0000;
    end else begin
      bias = 32'h0000_01ff + {31'b0, bits[10]};
      rounded_bits = (bits + bias) & 32'hffff_fc00;
      bf22_round_bits = rounded_bits;
    end
  end
endfunction

function [26:0] rshift_sticky27;
  input [26:0] value;
  input integer shift;
  reg sticky;
  begin
    if (shift <= 0) begin
      rshift_sticky27 = value;
    end else if (shift >= 27) begin
      rshift_sticky27 = {|value, 26'b0};
    end else begin
      sticky = |(value & ((27'b1 << shift) - 27'b1));
      rshift_sticky27 = (value >> shift) | {26'b0, sticky};
    end
  end
endfunction

function [31:0] fp32_pack_from_grs;
  input        sign;
  input signed [11:0] exp_unbiased;
  input [26:0] sig_grs;
  reg [23:0] main;
  reg guard_bit;
  reg round_bit;
  reg sticky_bit;
  reg increment;
  reg [24:0] rounded;
  reg signed [11:0] packed_exp_unbiased;
  reg signed [12:0] biased_exp;
  begin
    if (sig_grs == 27'b0 || exp_unbiased < -12'sd126) begin
      fp32_pack_from_grs = {sign, 31'b0};
    end else begin
      main = sig_grs[26:3];
      guard_bit = sig_grs[2];
      round_bit = sig_grs[1];
      sticky_bit = sig_grs[0];
      increment = guard_bit && (round_bit || sticky_bit || main[0]);
      rounded = {1'b0, main} + {24'b0, increment};
      packed_exp_unbiased = exp_unbiased + {11'b0, rounded[24]};
      biased_exp = packed_exp_unbiased + 13'sd127;
      if (biased_exp >= 13'sd255)
        fp32_pack_from_grs = {sign, 8'hfe, 23'h7fffff};
      else if (biased_exp <= 13'sd0)
        fp32_pack_from_grs = {sign, 31'b0};
      else
        fp32_pack_from_grs = {sign, biased_exp[7:0],
                              rounded[24] ? rounded[23:1] : rounded[22:0]};
    end
  end
endfunction

function [31:0] fp32_add_bits;
  input [31:0] a_bits;
  input [31:0] b_bits;
  reg        sign_a;
  reg        sign_b;
  reg [7:0]  exp_a_bits;
  reg [7:0]  exp_b_bits;
  reg [23:0] sig_a;
  reg [23:0] sig_b;
  reg signed [11:0] exp_a;
  reg signed [11:0] exp_b;
  reg        large_sign;
  reg        small_sign;
  reg signed [11:0] large_exp;
  reg [26:0] large_sig;
  reg [26:0] small_sig;
  reg [27:0] add_sig;
  reg [26:0] norm_sig;
  integer shift_amt;
  integer norm_count;
  begin
    sign_a = a_bits[31];
    sign_b = b_bits[31];
    exp_a_bits = a_bits[30:23];
    exp_b_bits = b_bits[30:23];
    sig_a = (exp_a_bits == 8'b0) ? {1'b0, a_bits[22:0]} :
                                      {1'b1, a_bits[22:0]};
    sig_b = (exp_b_bits == 8'b0) ? {1'b0, b_bits[22:0]} :
                                      {1'b1, b_bits[22:0]};
    exp_a = (exp_a_bits == 8'b0) ? -12'sd126 : ({4'b0, exp_a_bits} - 12'sd127);
    exp_b = (exp_b_bits == 8'b0) ? -12'sd126 : ({4'b0, exp_b_bits} - 12'sd127);

    if (a_bits[30:0] == 31'b0) begin
      fp32_add_bits = b_bits;
    end else if (b_bits[30:0] == 31'b0) begin
      fp32_add_bits = a_bits;
    end else if (exp_a_bits == 8'hff || exp_b_bits == 8'hff) begin
      fp32_add_bits = 32'h7fc0_0000;
    end else begin
      if ((exp_b > exp_a) || ((exp_b == exp_a) && (sig_b > sig_a))) begin
        large_sign = sign_b;
        small_sign = sign_a;
        large_exp = exp_b;
        large_sig = {sig_b, 3'b0};
        shift_amt = $signed({{20{exp_b[11]}}, exp_b}) -
                    $signed({{20{exp_a[11]}}, exp_a});
        small_sig = rshift_sticky27({sig_a, 3'b0}, shift_amt);
      end else begin
        large_sign = sign_a;
        small_sign = sign_b;
        large_exp = exp_a;
        large_sig = {sig_a, 3'b0};
        shift_amt = $signed({{20{exp_a[11]}}, exp_a}) -
                    $signed({{20{exp_b[11]}}, exp_b});
        small_sig = rshift_sticky27({sig_b, 3'b0}, shift_amt);
      end

      if (large_sign == small_sign) begin
        add_sig = {1'b0, large_sig} + {1'b0, small_sig};
        if (add_sig[27]) begin
          norm_sig = {add_sig[27:2], |add_sig[1:0]};
          large_exp = large_exp + 12'sd1;
        end else begin
          norm_sig = add_sig[26:0];
        end
        fp32_add_bits = fp32_pack_from_grs(large_sign, large_exp, norm_sig);
      end else begin
        if (large_sig == small_sig) begin
          fp32_add_bits = 32'b0;
        end else begin
          norm_sig = large_sig - small_sig;
          for (norm_count = 0; norm_count < 24; norm_count = norm_count + 1) begin
            if (!norm_sig[26] && (large_exp > -12'sd126)) begin
              norm_sig = norm_sig << 1;
              large_exp = large_exp - 12'sd1;
            end
          end
          fp32_add_bits = fp32_pack_from_grs(large_sign, large_exp, norm_sig);
        end
      end
    end
  end
endfunction

function [31:0] fp32_sub_bits;
  input [31:0] a_bits;
  input [31:0] b_bits;
  begin
    fp32_sub_bits = fp32_add_bits(a_bits, {~b_bits[31], b_bits[30:0]});
  end
endfunction

function [31:0] fp32_mul_bits;
  input [31:0] a_bits;
  input [31:0] b_bits;
  reg        sign_z;
  reg [7:0]  exp_a_bits;
  reg [7:0]  exp_b_bits;
  reg [23:0] sig_a;
  reg [23:0] sig_b;
  reg signed [11:0] exp_a;
  reg signed [11:0] exp_b;
  reg signed [11:0] exp_z;
  reg [47:0] product;
  reg [26:0] sig_grs;
  begin
    sign_z = a_bits[31] ^ b_bits[31];
    exp_a_bits = a_bits[30:23];
    exp_b_bits = b_bits[30:23];
    if (a_bits[30:0] == 31'b0 || b_bits[30:0] == 31'b0) begin
      fp32_mul_bits = {sign_z, 31'b0};
    end else if (exp_a_bits == 8'hff || exp_b_bits == 8'hff) begin
      fp32_mul_bits = 32'h7fc0_0000;
    end else begin
      sig_a = (exp_a_bits == 8'b0) ? {1'b0, a_bits[22:0]} :
                                      {1'b1, a_bits[22:0]};
      sig_b = (exp_b_bits == 8'b0) ? {1'b0, b_bits[22:0]} :
                                      {1'b1, b_bits[22:0]};
      exp_a = (exp_a_bits == 8'b0) ? -12'sd126 : ({4'b0, exp_a_bits} - 12'sd127);
      exp_b = (exp_b_bits == 8'b0) ? -12'sd126 : ({4'b0, exp_b_bits} - 12'sd127);
      product = sig_a * sig_b;
      if (product[47]) begin
        exp_z = exp_a + exp_b + 12'sd1;
        sig_grs = {product[47:24], product[23], product[22], |product[21:0]};
      end else begin
        exp_z = exp_a + exp_b;
        sig_grs = {product[46:23], product[22], product[21], |product[20:0]};
      end
      fp32_mul_bits = fp32_pack_from_grs(sign_z, exp_z, sig_grs);
    end
  end
endfunction

function [31:0] neg_abs_scale_bits;
  input [31:0] bits;
  input        scale_x2;
  reg [7:0] exp_bits;
  begin
    exp_bits = bits[30:23];
    if (bits[30:0] == 31'b0) begin
      neg_abs_scale_bits = 32'h8000_0000;
    end else if (scale_x2 && exp_bits < 8'hfe) begin
      neg_abs_scale_bits = {1'b1, exp_bits + 8'd1, bits[22:0]};
    end else if (scale_x2) begin
      neg_abs_scale_bits = 32'hff80_0000;
    end else begin
      neg_abs_scale_bits = {1'b1, bits[30:0]};
    end
  end
endfunction

edge_actu_exp_lut2base_split x_exp_lut (
  .value_bits(exp_input_bits),
  .exp_bits(exp_lut_bits)
);

edge_actu_rcp_rsqrt_pipe x_rcp_rsqrt (
  .clk(forever_cpuclk),
  .cpurst_b(cpurst_b),
  .in_valid(input_fire),
  .in_rsqrt(in_mode == EDGE_ACTU_MODE_RSQRT),
  .in_value(rcp_input_bits),
  .out_valid(nonlinear_out_valid),
  .out_value(nonlinear_out_bits)
);

assign fused_sigmoid_like = (in_mode == EDGE_ACTU_MODE_SIGMOID) ||
                            (in_mode == EDGE_ACTU_MODE_SILU);
assign fused_tanh_like = (in_mode == EDGE_ACTU_MODE_TANH);
assign neg_abs_bits = neg_abs_scale_bits(in_value, 1'b0);
assign neg_abs_x2_bits = neg_abs_scale_bits(in_value, 1'b1);
assign softmax_delta_bits = fp32_sub_bits(in_value, in_softmax_max);
assign exp_input_bits = (in_mode == EDGE_ACTU_MODE_SOFTMAX) ? softmax_delta_bits :
                        (fused_tanh_like ? neg_abs_x2_bits :
                         (fused_sigmoid_like ? neg_abs_bits : in_value));
assign exp_internal_bits = bf22_round_bits(exp_lut_bits);
assign fused_den_bits = bf22_round_bits(fp32_add_bits(32'h3f80_0000,
                                                          exp_internal_bits));
assign rsqrt_input_bits = fp32_add_bits(in_value, in_softmax_max);
assign rcp_input_bits = (in_mode == EDGE_ACTU_MODE_RCP_ONLY) ? in_value :
                        ((in_mode == EDGE_ACTU_MODE_RSQRT) ? rsqrt_input_bits :
                        ((in_mode == EDGE_ACTU_MODE_SOFTMAX_NORMALIZE) ?
                         in_softmax_max :
                         fused_den_bits));
assign aligned_mode = nonlinear_mode_pipe[NONLINEAR_LATENCY-1];
assign aligned_x_bits = nonlinear_x_pipe[NONLINEAR_LATENCY-1];
assign aligned_exp_bits = nonlinear_exp_pipe[NONLINEAR_LATENCY-1];
assign aligned_exp_internal_bits = bf22_round_bits(aligned_exp_bits);
assign aligned_rcp_internal_bits = bf22_round_bits(nonlinear_out_bits);
assign rcp_lut_bits = nonlinear_out_bits;
assign rcp_internal_bits = aligned_rcp_internal_bits;
assign sigmoid_neg_bits = bf22_round_bits(fp32_mul_bits(aligned_exp_internal_bits,
                                                            aligned_rcp_internal_bits));
assign sigmoid_bits = aligned_x_bits[31] ? sigmoid_neg_bits :
                       aligned_rcp_internal_bits;
assign silu_product_bits = bf22_round_bits(fp32_mul_bits(
                            bf22_round_bits(aligned_x_bits), sigmoid_bits));
assign tanh_one_minus_bits = bf22_round_bits(fp32_sub_bits(32'h3f80_0000,
                                                               aligned_exp_internal_bits));
assign tanh_abs_bits = bf22_round_bits(fp32_mul_bits(tanh_one_minus_bits,
                                                         aligned_rcp_internal_bits));
assign tanh_signed_bits = aligned_x_bits[31] ? {1'b1, tanh_abs_bits[30:0]} :
                          tanh_abs_bits;
assign exp_result_bits = bf16_round_bits(aligned_exp_bits);
assign rcp_result_bits = bf16_round_bits(nonlinear_out_bits);
assign sigmoid_result_bits = bf16_round_bits(sigmoid_bits);
assign silu_result_bits = bf16_round_bits(silu_product_bits);
assign tanh_result_bits = bf16_round_bits(tanh_signed_bits);
assign softmax_result_bits = bf16_round_bits(aligned_exp_bits);
assign softmax_normalize_bits = bf16_round_bits(fp32_mul_bits(
                                  aligned_x_bits, nonlinear_out_bits));
assign softmax_sum_next_bits = fp32_add_bits(softmax_sum_q,
                                             aligned_exp_internal_bits);
assign softmax_sum_valid = nonlinear_out_valid &&
                           (aligned_mode == EDGE_ACTU_MODE_SOFTMAX);
assign softmax_sum_value = softmax_sum_next_bits;
assign stage0_result_bits = (aligned_mode == EDGE_ACTU_MODE_EXP_ONLY) ? exp_result_bits :
                            ((aligned_mode == EDGE_ACTU_MODE_RCP_ONLY) ? rcp_result_bits :
                             ((aligned_mode == EDGE_ACTU_MODE_SIGMOID) ? sigmoid_result_bits :
                              ((aligned_mode == EDGE_ACTU_MODE_SILU) ? silu_result_bits :
                               ((aligned_mode == EDGE_ACTU_MODE_TANH) ? tanh_result_bits :
                                ((aligned_mode == EDGE_ACTU_MODE_SOFTMAX) ? softmax_result_bits :
                                 ((aligned_mode == EDGE_ACTU_MODE_RSQRT) ? rcp_result_bits :
                                  ((aligned_mode == EDGE_ACTU_MODE_SOFTMAX_NORMALIZE) ?
                                   softmax_normalize_bits : 32'b0)))))));

always @(posedge forever_cpuclk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    softmax_sum_q <= 32'b0;
    valid_pipe <= {POST_STAGES{1'b0}};
    for (stage = 0; stage < POST_STAGES; stage = stage + 1) begin
      mode_pipe[stage] <= 3'b0;
      value_pipe[stage] <= 32'b0;
    end
    for (stage = 0; stage < NONLINEAR_LATENCY; stage = stage + 1) begin
      nonlinear_mode_pipe[stage] <= 3'b0;
      nonlinear_x_pipe[stage] <= 32'b0;
      nonlinear_exp_pipe[stage] <= 32'b0;
    end
  end else begin
    if (softmax_sum_clear)
      softmax_sum_q <= 32'b0;
    else if (softmax_sum_valid)
      softmax_sum_q <= softmax_sum_next_bits;
    nonlinear_mode_pipe[0] <= in_mode;
    nonlinear_x_pipe[0] <= in_value;
    nonlinear_exp_pipe[0] <= exp_lut_bits;
    for (stage = 1; stage < NONLINEAR_LATENCY; stage = stage + 1) begin
      nonlinear_mode_pipe[stage] <= nonlinear_mode_pipe[stage - 1];
      nonlinear_x_pipe[stage] <= nonlinear_x_pipe[stage - 1];
      nonlinear_exp_pipe[stage] <= nonlinear_exp_pipe[stage - 1];
    end

    valid_pipe[0] <= nonlinear_out_valid;
    mode_pipe[0] <= aligned_mode;
    value_pipe[0] <= stage0_result_bits;

    for (stage = 1; stage < POST_STAGES; stage = stage + 1) begin
      valid_pipe[stage] <= valid_pipe[stage - 1];
      mode_pipe[stage] <= mode_pipe[stage - 1];
      value_pipe[stage] <= value_pipe[stage - 1];
    end
  end
end

endmodule
