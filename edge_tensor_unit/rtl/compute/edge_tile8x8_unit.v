// Eight reusable synthesis-friendly BF16 multipliers for the Q8 scale stage.
//
// This follows the vec8dot product representation: sanitize both BF16 inputs,
// multiply two fixed 8-bit significands, and carry a signed 10-bit synthetic
// exponent into a separate normalization stage.  Keeping the product and
// exponent fixed-width avoids the generic 32-bit variable-shift arithmetic
// that previously dominated the scale path after synthesis.
module edge_bf16_mul8_pipe(
  clk,
  rst_b,
  in_valid,
  a_vec_i,
  b_vec_i,
  out_valid,
  y_vec_o
);

input          clk;
input          rst_b;
input          in_valid;
input  [127:0] a_vec_i;
input  [127:0] b_vec_i;
output         out_valid;
output [127:0] y_vec_o;

reg         s0_valid;
reg         s1_valid;
reg [15:0]  s0_a [0:7];
reg [15:0]  s0_b [0:7];
reg [15:0]  s1_product [0:7];
reg         s1_sign [0:7];
reg         s1_zero [0:7];
reg signed [9:0] s1_exp [0:7];

integer lane;
reg [7:0] a_sig_comb;
reg [7:0] b_sig_comb;

assign out_valid = s1_valid;

function [15:0] sanitize_bf16;
  input [15:0] value;
  begin
    if ((value[14:7] == 8'hff) && (value[6:0] != 7'b0))
      sanitize_bf16 = 16'h0000;
    else if ((value[14:0] == 15'h7f80))
      sanitize_bf16 = value[15] ? 16'hff7f : 16'h7f7f;
    else
      sanitize_bf16 = value;
  end
endfunction

function [3:0] msb_index16;
  input [15:0] value;
  integer idx;
  begin
    msb_index16 = 4'b0;
    for (idx = 0; idx < 16; idx = idx + 1)
      if (value[idx])
        msb_index16 = idx[3:0];
  end
endfunction

// Fixed cases are intentional.  They infer the same bounded mux structure as
// vec8dot's coarse/fine alignment rather than a 32-bit barrel shifter.
function [15:0] rshift_rne16_fixed;
  input [15:0] value;
  input [4:0] amount;
  reg [15:0] quotient;
  reg guard_bit;
  reg sticky_bit;
  begin
    quotient = 16'b0;
    guard_bit = 1'b0;
    sticky_bit = 1'b0;
    case (amount)
      5'd0: quotient = value;
      5'd1: begin quotient = value >> 1; guard_bit = value[0]; end
      5'd2: begin quotient = value >> 2; guard_bit = value[1]; sticky_bit = |value[0:0]; end
      5'd3: begin quotient = value >> 3; guard_bit = value[2]; sticky_bit = |value[1:0]; end
      5'd4: begin quotient = value >> 4; guard_bit = value[3]; sticky_bit = |value[2:0]; end
      5'd5: begin quotient = value >> 5; guard_bit = value[4]; sticky_bit = |value[3:0]; end
      5'd6: begin quotient = value >> 6; guard_bit = value[5]; sticky_bit = |value[4:0]; end
      5'd7: begin quotient = value >> 7; guard_bit = value[6]; sticky_bit = |value[5:0]; end
      5'd8: begin quotient = value >> 8; guard_bit = value[7]; sticky_bit = |value[6:0]; end
      5'd9: begin quotient = value >> 9; guard_bit = value[8]; sticky_bit = |value[7:0]; end
      5'd10: begin quotient = value >> 10; guard_bit = value[9]; sticky_bit = |value[8:0]; end
      5'd11: begin quotient = value >> 11; guard_bit = value[10]; sticky_bit = |value[9:0]; end
      5'd12: begin quotient = value >> 12; guard_bit = value[11]; sticky_bit = |value[10:0]; end
      5'd13: begin quotient = value >> 13; guard_bit = value[12]; sticky_bit = |value[11:0]; end
      5'd14: begin quotient = value >> 14; guard_bit = value[13]; sticky_bit = |value[12:0]; end
      5'd15: begin quotient = value >> 15; guard_bit = value[14]; sticky_bit = |value[13:0]; end
      5'd16: begin quotient = 16'b0; guard_bit = value[15]; sticky_bit = |value[14:0]; end
      default: begin quotient = 16'b0; guard_bit = 1'b0; sticky_bit = |value; end
    endcase
    rshift_rne16_fixed = quotient
                       + {15'b0,
                          (guard_bit && (sticky_bit || quotient[0]))};
  end
endfunction

function [15:0] lshift_product_fixed;
  input [15:0] value;
  input [3:0] amount;
  begin
    case (amount)
      4'd0: lshift_product_fixed = value;
      4'd1: lshift_product_fixed = value << 1;
      4'd2: lshift_product_fixed = value << 2;
      4'd3: lshift_product_fixed = value << 3;
      4'd4: lshift_product_fixed = value << 4;
      4'd5: lshift_product_fixed = value << 5;
      4'd6: lshift_product_fixed = value << 6;
      4'd7: lshift_product_fixed = value << 7;
      4'd8: lshift_product_fixed = value << 8;
      4'd9: lshift_product_fixed = value << 9;
      4'd10: lshift_product_fixed = value << 10;
      4'd11: lshift_product_fixed = value << 11;
      4'd12: lshift_product_fixed = value << 12;
      4'd13: lshift_product_fixed = value << 13;
      4'd14: lshift_product_fixed = value << 14;
      default: lshift_product_fixed = value << 15;
    endcase
  end
endfunction

function [15:0] normalize_product_to_bf16;
  input [15:0] product;
  input signed [9:0] product_exp;
  input sign;
  input force_zero;
  reg [3:0] msb;
  reg signed [9:0] exp_field;
  reg signed [9:0] sub_shift;
  reg [15:0] rounded_right;
  reg [15:0] rounded_left;
  reg [8:0] sig_rounded;
  reg [4:0] right_amount;
  begin
    msb = msb_index16(product);
    // Match vec8dot's synthetic exponent convention exactly.  product_exp
    // already contains both biased BF16 exponents minus 134.
    exp_field = product_exp + $signed({6'b0, msb}) - 10'sd7;
    // A subnormal BF16 fraction unit is 2^-133.  Since product_exp uses
    // vec8dot's biased convention, the integer product shifts by exp-1.
    sub_shift = product_exp - 10'sd1;
    rounded_right = 16'b0;
    rounded_left = 16'b0;
    sig_rounded = 9'b0;
    right_amount = 5'b0;

    if (force_zero || product == 16'b0) begin
      normalize_product_to_bf16 = 16'h0000;
    end else if (exp_field >= 10'sd255) begin
      normalize_product_to_bf16 = sign ? 16'hff7f : 16'h7f7f;
    end else if (exp_field > 10'sd0) begin
      if (msb >= 4'd7) begin
        right_amount = {1'b0, msb} - 5'd7;
        rounded_right = rshift_rne16_fixed(product, right_amount);
        sig_rounded = rounded_right[8:0];
      end else begin
        rounded_left = lshift_product_fixed(product,
                                             {1'b0, (3'd7 - msb[2:0])});
        sig_rounded = rounded_left[8:0];
      end

      if (sig_rounded[8]) begin
        sig_rounded = {1'b0, sig_rounded[8:1]};
        exp_field = exp_field + 10'sd1;
      end

      if (exp_field >= 10'sd255)
        normalize_product_to_bf16 = sign ? 16'hff7f : 16'h7f7f;
      else
        normalize_product_to_bf16 = {sign, exp_field[7:0],
                                     sig_rounded[6:0]};
    end else begin
      if (sub_shift >= 10'sd0) begin
        rounded_left = lshift_product_fixed(product, sub_shift[3:0]);
        sig_rounded = rounded_left[8:0];
      end else if (sub_shift <= -10'sd17) begin
        sig_rounded = 9'b0;
      end else begin
        right_amount = (~sub_shift[4:0]) + 5'd1;
        rounded_right = rshift_rne16_fixed(product, right_amount);
        sig_rounded = rounded_right[8:0];
      end

      if (sig_rounded >= 9'd128)
        normalize_product_to_bf16 = {sign, 8'h01, 7'h00};
      else
        normalize_product_to_bf16 = {sign, 8'h00,
                                     sig_rounded[6:0]};
    end
  end
endfunction

genvar output_lane;
generate
  for (output_lane = 0; output_lane < 8; output_lane = output_lane + 1) begin : gen_output
    assign y_vec_o[output_lane*16 +: 16] = normalize_product_to_bf16(
        s1_product[output_lane], s1_exp[output_lane],
        s1_sign[output_lane], s1_zero[output_lane]);
  end
endgenerate

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    s0_valid <= 1'b0;
    s1_valid <= 1'b0;
    for (lane = 0; lane < 8; lane = lane + 1) begin
      s0_a[lane] <= 16'b0;
      s0_b[lane] <= 16'b0;
      s1_product[lane] <= 16'b0;
      s1_sign[lane] <= 1'b0;
      s1_zero[lane] <= 1'b1;
      s1_exp[lane] <= 10'sd0;
    end
  end else begin
    s0_valid <= in_valid;
    s1_valid <= s0_valid;
    if (in_valid) begin
      for (lane = 0; lane < 8; lane = lane + 1) begin
        s0_a[lane] <= sanitize_bf16(a_vec_i[lane*16 +: 16]);
        s0_b[lane] <= sanitize_bf16(b_vec_i[lane*16 +: 16]);
      end
    end
    if (s0_valid) begin
      for (lane = 0; lane < 8; lane = lane + 1) begin
      a_sig_comb = (s0_a[lane][14:7] == 8'b0)
                 ? {1'b0, s0_a[lane][6:0]}
                 : {1'b1, s0_a[lane][6:0]};
      b_sig_comb = (s0_b[lane][14:7] == 8'b0)
                 ? {1'b0, s0_b[lane][6:0]}
                 : {1'b1, s0_b[lane][6:0]};
      s1_product[lane] <= a_sig_comb * b_sig_comb;
      s1_sign[lane] <= s0_a[lane][15] ^ s0_b[lane][15];
      s1_zero[lane] <= (s0_a[lane][14:0] == 15'b0)
                    || (s0_b[lane][14:0] == 15'b0);
      s1_exp[lane] <= $signed({2'b0, (s0_a[lane][14:7] == 0)
                                      ? 8'd1 : s0_a[lane][14:7]})
                    + $signed({2'b0, (s0_b[lane][14:7] == 0)
                                      ? 8'd1 : s0_b[lane][14:7]})
                    - 10'sd134;
      end
    end
  end
end

endmodule

// 8x8 BF16 x INT8 tensor row block with BF16 partial-sum input.
//
// Interfaces are sized for two 64-bit SRAM banks per stream:
//   input_bf16_i  : 8 BF16 activations, 128 bits
//   psum_bf16_i   : 8 BF16 partial sums, 128 bits
//   output_bf16_o : 8 BF16 updated sums, 128 bits
//
// Weights are filled through a decoupled 128-bit stream into an internal
// double buffer. The fill stream supplies one logical tile; this module owns
// which physical buffer is filled and when a pending tile becomes active.
// I8 fill consumes two signed bytes per row on each of four beats and converts
// both values to BF16. BF16 fill consumes one BF16 value per row on each of
// eight sequential beats. Both modes populate the same 8x8 BF16 buffers.

module edge_tile8x8_unit(
  clk,
  rst_b,
  compute_valid,
  late_psum_mode_i,
  late_psum_valid_i,
  input_bf16_i,
  psum_bf16_i,
  scale_enable_i,
  scale_bf16_i,
  rsum_enable_i,
  rsum_first_i,
  rsum_last_i,
  weight_fill_bf16_mode_i,
  weight_fill_start,
  weight_fill_start_ready,
  weight_fill_valid,
  weight_fill_ready,
  weight_fill_pair_idx,
  weight_fill_data,
  weight_fill_last,
  weight_activate,
  weight_activate_ready,
  weight_fill_busy,
  weight_active_valid,
  weight_pending_valid,
  dot_ready_o,
  output_valid,
  output_bf16_o
);

input          clk;
input          rst_b;
input          compute_valid;
input          late_psum_mode_i;
input          late_psum_valid_i;
input  [127:0] input_bf16_i;
input  [127:0] psum_bf16_i;
input          scale_enable_i;
input  [127:0] scale_bf16_i;
input          rsum_enable_i;
input          rsum_first_i;
input          rsum_last_i;
input          weight_fill_bf16_mode_i;
input          weight_fill_start;
output         weight_fill_start_ready;
input          weight_fill_valid;
output         weight_fill_ready;
input  [1:0]   weight_fill_pair_idx;
input  [127:0] weight_fill_data;
input          weight_fill_last;
input          weight_activate;
output         weight_activate_ready;
output         weight_fill_busy;
output         weight_active_valid;
output         weight_pending_valid;
output         dot_ready_o;
output         output_valid;
output [127:0] output_bf16_o;

reg [127:0] weight_buf0 [0:7];
reg [127:0] weight_buf1 [0:7];
reg         weight_active_buf_q;
reg         weight_active_valid_q;
reg         weight_fill_buf_q;
reg         weight_pending_buf_q;
reg         weight_fill_busy_q;
reg         weight_pending_valid_q;
reg [3:0]   weight_fill_done_mask_q;
reg         weight_fill_bf16_mode_q;
reg [2:0]   weight_fill_beat_q;
reg [127:0] psum_d0;
reg [127:0] psum_d1;
reg [127:0] psum_d2;
reg [127:0] psum_d3;
reg [127:0] psum_d4;
reg [127:0] psum_d5;
reg [127:0] scale_d0;
reg [127:0] scale_d1;
reg [127:0] scale_d2;
reg [127:0] scale_d3;
reg [127:0] scale_d4;
reg [127:0] scale_d5;
reg         scale_enable_d0;
reg         scale_enable_d1;
reg         scale_enable_d2;
reg         scale_enable_d3;
reg         scale_enable_d4;
reg         scale_enable_d5;
reg [127:0] scaled_psum_d0;
reg [127:0] scaled_psum_d1;
reg [127:0] output_reg;
reg         output_valid_q;

wire [127:0] weight_row [0:7];
wire [15:0]  dot_bf16 [0:7];
wire [15:0]  psum_lane [0:7];
wire [15:0]  sum_lane [0:7];
wire [15:0]  scaled_sum_lane [0:7];
wire         dot_valid [0:7];
wire         scaled_mul_valid;
wire [127:0] scaled_mul_bf16;
wire [3:0]   weight_fill_pair_bit;
wire [3:0]   weight_fill_base_mask;
wire [3:0]   weight_fill_done_mask_next;
wire         weight_fill_start_accept;
wire         weight_fill_stream_active;
wire         weight_fill_accept;
wire         weight_fill_complete;
wire         weight_fill_buf_sel;
wire         weight_fill_bf16_mode;
wire [2:0]   weight_fill_bf16_beat;

genvar lane;
integer load_lane;

assign weight_fill_start_ready = !weight_fill_busy_q &&
                                 !weight_pending_valid_q;
assign weight_fill_start_accept = weight_fill_start && weight_fill_start_ready;
assign weight_fill_stream_active = weight_fill_busy_q || weight_fill_start_accept;
assign weight_fill_ready = weight_fill_stream_active;
assign weight_activate_ready = weight_pending_valid_q || weight_fill_complete;
assign weight_fill_busy = weight_fill_busy_q;
assign weight_active_valid = weight_active_valid_q;
assign weight_pending_valid = weight_pending_valid_q;
assign dot_ready_o = dot_valid[0];
assign output_valid = output_valid_q;
assign output_bf16_o[127:0] = output_reg[127:0];
assign weight_fill_buf_sel = weight_fill_start_accept ? !weight_active_buf_q
                                                      : weight_fill_buf_q;
assign weight_fill_bf16_mode = weight_fill_start_accept
                             ? weight_fill_bf16_mode_i
                             : weight_fill_bf16_mode_q;
assign weight_fill_bf16_beat = weight_fill_start_accept
                             ? 3'b0 : weight_fill_beat_q;
assign weight_fill_pair_bit[3:0] = 4'b0001 << weight_fill_pair_idx[1:0];
assign weight_fill_base_mask[3:0] =
    weight_fill_start_accept ? 4'b0 : weight_fill_done_mask_q[3:0];
assign weight_fill_done_mask_next[3:0] =
    weight_fill_accept
    ? (weight_fill_base_mask[3:0] | weight_fill_pair_bit[3:0])
    : weight_fill_base_mask[3:0];
assign weight_fill_accept = weight_fill_valid && weight_fill_ready;
assign weight_fill_complete =
    weight_fill_accept
    && (weight_fill_last
        || (weight_fill_bf16_mode
            ? (weight_fill_bf16_beat == 3'd7)
            : (weight_fill_done_mask_next[3:0] == 4'hf)));

function [15:0] int8_to_bf16;
  input [7:0] value;
  reg sign;
  reg [7:0] mag;
  reg [2:0] msb;
  reg [7:0] normalized;
  integer idx;
  begin
    if (value == 8'b0) begin
      int8_to_bf16 = 16'b0;
    end else begin
      sign = value[7];
      mag = sign ? (~value + 8'b1) : value;
      msb = 3'b0;
      for (idx = 0; idx < 8; idx = idx + 1)
        if (mag[idx])
          msb = idx[2:0];
      normalized = mag << (3'd7 - msb);
      int8_to_bf16 = {sign, (8'd127 + {5'b0, msb}), normalized[6:0]};
    end
  end
endfunction

generate
  for (lane = 0; lane < 8; lane = lane + 1) begin : gen_dot8_rows
    assign weight_row[lane][127:0] =
           weight_active_buf_q ? weight_buf1[lane][127:0]
                               : weight_buf0[lane][127:0];
    assign psum_lane[lane][15:0] = late_psum_mode_i
                                      ? psum_bf16_i[lane*16 +: 16]
                                      : psum_d5[lane*16 +: 16];

    edge_dot8_unit x_dot8 (
      .clk        (clk),
      .rst_b      (rst_b),
      .in_valid   (compute_valid),
      .bf16_vec_i (input_bf16_i[127:0]),
      .int8_vec_i (64'b0),
      .weight_bf16_mode_i(1'b1),
      .bf16_weight_vec_i(weight_row[lane][127:0]),
      .rsum_enable_i(rsum_enable_i),
      .rsum_first_i(rsum_first_i),
      .rsum_last_i(rsum_last_i),
      .out_valid  (dot_valid[lane]),
      .bf16_o     (dot_bf16[lane][15:0])
    );

    edge_psum x_psum_add (
      .a_raw(dot_bf16[lane][15:0]),
      .b_raw(psum_lane[lane][15:0]),
      .y    (sum_lane[lane][15:0])
    );

    edge_psum x_scaled_psum_add (
      .a_raw(scaled_mul_bf16[lane*16 +: 16]),
      .b_raw(scaled_psum_d1[lane*16 +: 16]),
      .y    (scaled_sum_lane[lane][15:0])
    );
  end
endgenerate

// Scale mode uses the same fixed-width product/exponent representation as
// vec8dot.  Its two internal stages preserve the wrapper's existing one-cycle
// two-cycle latency difference from bypass while remaining full-rate. The mode only
// changes after the compute pipeline drains, so the shorter bypass path cannot
// overtake an older scaled operation.
edge_bf16_mul8_pipe x_scale_mul (
  .clk      (clk),
  .rst_b    (rst_b),
  .in_valid (dot_valid[0] && scale_enable_d5
             && (!late_psum_mode_i || late_psum_valid_i)),
  .a_vec_i  ({dot_bf16[7], dot_bf16[6], dot_bf16[5], dot_bf16[4],
              dot_bf16[3], dot_bf16[2], dot_bf16[1], dot_bf16[0]}),
  .b_vec_i  (scale_d5[127:0]),
  .out_valid(scaled_mul_valid),
  .y_vec_o  (scaled_mul_bf16[127:0])
);

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    weight_buf0[0] <= 128'b0;
    weight_buf0[1] <= 128'b0;
    weight_buf0[2] <= 128'b0;
    weight_buf0[3] <= 128'b0;
    weight_buf0[4] <= 128'b0;
    weight_buf0[5] <= 128'b0;
    weight_buf0[6] <= 128'b0;
    weight_buf0[7] <= 128'b0;
    weight_buf1[0] <= 128'b0;
    weight_buf1[1] <= 128'b0;
    weight_buf1[2] <= 128'b0;
    weight_buf1[3] <= 128'b0;
    weight_buf1[4] <= 128'b0;
    weight_buf1[5] <= 128'b0;
    weight_buf1[6] <= 128'b0;
    weight_buf1[7] <= 128'b0;
    weight_active_buf_q <= 1'b0;
    weight_active_valid_q <= 1'b0;
    weight_fill_buf_q <= 1'b1;
    weight_pending_buf_q <= 1'b0;
    weight_fill_busy_q <= 1'b0;
    weight_pending_valid_q <= 1'b0;
    weight_fill_done_mask_q[3:0] <= 4'b0;
    weight_fill_bf16_mode_q <= 1'b0;
    weight_fill_beat_q <= 3'b0;
    psum_d0 <= 128'b0;
    psum_d1 <= 128'b0;
    psum_d2 <= 128'b0;
    psum_d3 <= 128'b0;
    psum_d4 <= 128'b0;
    psum_d5 <= 128'b0;
    scale_d0 <= 128'b0;
    scale_d1 <= 128'b0;
    scale_d2 <= 128'b0;
    scale_d3 <= 128'b0;
    scale_d4 <= 128'b0;
    scale_d5 <= 128'b0;
    scale_enable_d0 <= 1'b0;
    scale_enable_d1 <= 1'b0;
    scale_enable_d2 <= 1'b0;
    scale_enable_d3 <= 1'b0;
    scale_enable_d4 <= 1'b0;
    scale_enable_d5 <= 1'b0;
    scaled_psum_d0 <= 128'b0;
    scaled_psum_d1 <= 128'b0;
    output_reg <= 128'b0;
    output_valid_q <= 1'b0;
  end else begin
    if (weight_fill_start_accept) begin
      weight_fill_buf_q <= !weight_active_buf_q;
      weight_fill_done_mask_q[3:0] <= 4'b0;
      weight_fill_bf16_mode_q <= weight_fill_bf16_mode_i;
      weight_fill_beat_q <= 3'b0;
      weight_fill_busy_q <= 1'b1;
      weight_pending_valid_q <= 1'b0;
    end

    if (weight_fill_accept) begin
      if (weight_fill_buf_sel) begin
        for (load_lane = 0; load_lane < 8; load_lane = load_lane + 1) begin
          if (weight_fill_bf16_mode) begin
            weight_buf1[load_lane][{weight_fill_bf16_beat, 4'b0} +: 16]
              <= weight_fill_data[load_lane*16 +: 16];
          end else begin
            weight_buf1[load_lane][{weight_fill_pair_idx[1:0], 5'b0} +: 16]
              <= int8_to_bf16(weight_fill_data[load_lane*16 +: 8]);
            weight_buf1[load_lane][{weight_fill_pair_idx[1:0], 5'b0}
                                   + 16 +: 16]
              <= int8_to_bf16(weight_fill_data[load_lane*16 + 8 +: 8]);
          end
        end
      end else begin
        for (load_lane = 0; load_lane < 8; load_lane = load_lane + 1) begin
          if (weight_fill_bf16_mode) begin
            weight_buf0[load_lane][{weight_fill_bf16_beat, 4'b0} +: 16]
              <= weight_fill_data[load_lane*16 +: 16];
          end else begin
            weight_buf0[load_lane][{weight_fill_pair_idx[1:0], 5'b0} +: 16]
              <= int8_to_bf16(weight_fill_data[load_lane*16 +: 8]);
            weight_buf0[load_lane][{weight_fill_pair_idx[1:0], 5'b0}
                                   + 16 +: 16]
              <= int8_to_bf16(weight_fill_data[load_lane*16 + 8 +: 8]);
          end
        end
      end
      weight_fill_done_mask_q[3:0] <= weight_fill_done_mask_next[3:0];
      if (weight_fill_bf16_mode && !weight_fill_complete)
        weight_fill_beat_q <= weight_fill_bf16_beat + 3'd1;
      if (weight_fill_complete) begin
        weight_fill_busy_q <= 1'b0;
        weight_pending_valid_q <= 1'b1;
        weight_pending_buf_q <= weight_fill_buf_sel;
      end
    end

    if (weight_activate && weight_activate_ready) begin
      weight_active_buf_q <= weight_fill_complete ? weight_fill_buf_sel
                                                  : weight_pending_buf_q;
      weight_active_valid_q <= 1'b1;
      weight_pending_valid_q <= 1'b0;
    end

    psum_d0 <= psum_bf16_i[127:0];
    psum_d1 <= psum_d0[127:0];
    psum_d2 <= psum_d1[127:0];
    psum_d3 <= psum_d2[127:0];
    psum_d4 <= psum_d3[127:0];
    psum_d5 <= psum_d4[127:0];
    scale_d0 <= scale_bf16_i[127:0];
    scale_d1 <= scale_d0[127:0];
    scale_d2 <= scale_d1[127:0];
    scale_d3 <= scale_d2[127:0];
    scale_d4 <= scale_d3[127:0];
    scale_d5 <= scale_d4[127:0];
    scale_enable_d0 <= scale_enable_i;
    scale_enable_d1 <= scale_enable_d0;
    scale_enable_d2 <= scale_enable_d1;
    scale_enable_d3 <= scale_enable_d2;
    scale_enable_d4 <= scale_enable_d3;
    scale_enable_d5 <= scale_enable_d4;

    scaled_psum_d0 <= late_psum_mode_i ? psum_bf16_i[127:0]
                                       : psum_d5[127:0];
    scaled_psum_d1 <= scaled_psum_d0[127:0];

    output_valid_q <= (dot_valid[0] && !scale_enable_d5
                       && (!late_psum_mode_i || late_psum_valid_i))
                      || scaled_mul_valid;
    if (scaled_mul_valid) begin
      output_reg[15:0]    <= scaled_sum_lane[0][15:0];
      output_reg[31:16]   <= scaled_sum_lane[1][15:0];
      output_reg[47:32]   <= scaled_sum_lane[2][15:0];
      output_reg[63:48]   <= scaled_sum_lane[3][15:0];
      output_reg[79:64]   <= scaled_sum_lane[4][15:0];
      output_reg[95:80]   <= scaled_sum_lane[5][15:0];
      output_reg[111:96]  <= scaled_sum_lane[6][15:0];
      output_reg[127:112] <= scaled_sum_lane[7][15:0];
    end else begin
      output_reg[15:0]    <= rsum_enable_i ? dot_bf16[0] : sum_lane[0];
      output_reg[31:16]   <= rsum_enable_i ? dot_bf16[1] : sum_lane[1];
      output_reg[47:32]   <= rsum_enable_i ? dot_bf16[2] : sum_lane[2];
      output_reg[63:48]   <= rsum_enable_i ? dot_bf16[3] : sum_lane[3];
      output_reg[79:64]   <= rsum_enable_i ? dot_bf16[4] : sum_lane[4];
      output_reg[95:80]   <= rsum_enable_i ? dot_bf16[5] : sum_lane[5];
      output_reg[111:96]  <= rsum_enable_i ? dot_bf16[6] : sum_lane[6];
      output_reg[127:112] <= rsum_enable_i ? dot_bf16[7] : sum_lane[7];
    end
  end
end

endmodule
