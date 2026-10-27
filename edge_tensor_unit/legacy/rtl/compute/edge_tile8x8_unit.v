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

module edge_tile8x8_unit #(parameter WIDE_PSUM=0)(
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
  output_bf16_o,
  wide_enable_i, psum_fp32_i, output_fp32_o
);

input wide_enable_i;
input [255:0] psum_fp32_i;
output [255:0] output_fp32_o;
wire [255:0] dot_fp32;
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

// Per row, each local multiplier lane stores only {sign,decoded_sig[7:0]}.
// The true exponent fields are mirrored separately in the row's exp-max
// cluster, so the local payload banks are 8*9 rather than 8*16 bits.
reg [71:0]  weight_buf0 [0:7];
reg [71:0]  weight_buf1 [0:7];
reg [63:0]  weight_exp_buf0 [0:7];
reg [63:0]  weight_exp_buf1 [0:7];
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
reg [127:0] psum_d6;
reg [127:0] scale_d0;
reg [127:0] scale_d1;
reg [127:0] scale_d2;
reg [127:0] scale_d3;
reg [127:0] scale_d4;
reg [127:0] scale_d5;
reg [127:0] scale_d6;
reg         scale_enable_d0;
reg         scale_enable_d1;
reg         scale_enable_d2;
reg         scale_enable_d3;
reg         scale_enable_d4;
reg         scale_enable_d5;
reg         scale_enable_d6;
reg [127:0] scaled_psum_d0;
reg [127:0] scaled_psum_d1;
reg [127:0] output_reg;
reg         output_valid_q;

wire [127:0] weight_row [0:7];
wire [63:0]  weight_exp_row [0:7];
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

function [7:0] int8_to_bf16_exp;
  input [7:0] value;
  reg [7:0] mag;
  reg [2:0] msb;
  integer idx;
  begin
    if (value == 8'b0) begin
      int8_to_bf16_exp = 8'b0;
    end else begin
      mag = value[7] ? (~value + 8'b1) : value;
      msb = 3'b0;
      for (idx = 0; idx < 8; idx = idx + 1)
        if (mag[idx]) msb = idx[2:0];
      int8_to_bf16_exp = 8'd127 + {5'b0, msb};
    end
  end
endfunction

function [8:0] int8_to_local_weight;
  input [7:0] value;
  reg sign;
  reg [7:0] mag;
  reg [2:0] msb;
  reg [7:0] normalized;
  integer idx;
  begin
    if (value == 8'b0) begin
      int8_to_local_weight = 9'b0;
    end else begin
      sign = value[7];
      mag = sign ? (~value + 8'b1) : value;
      msb = 3'b0;
      for (idx = 0; idx < 8; idx = idx + 1)
        if (mag[idx]) msb = idx[2:0];
      normalized = mag << (3'd7 - msb);
      int8_to_local_weight = {sign,1'b1,normalized[6:0]};
    end
  end
endfunction

function [127:0] expand_local_weight_row;
  input [71:0] payload;
  integer idx;
  begin
    expand_local_weight_row = 128'b0;
    for (idx = 0; idx < 8; idx = idx + 1)
      expand_local_weight_row[idx*16 +: 16]
        = {payload[idx*9+8], {7'b0,payload[idx*9+7]},
           payload[idx*9 +: 7]};
  end
endfunction

generate
  for (lane = 0; lane < 8; lane = lane + 1) begin : gen_dot8_rows
    assign weight_row[lane][127:0] = expand_local_weight_row(
           weight_active_buf_q ? weight_buf1[lane][71:0]
                               : weight_buf0[lane][71:0]);
    assign weight_exp_row[lane][63:0] =
           weight_active_buf_q ? weight_exp_buf1[lane][63:0]
                               : weight_exp_buf0[lane][63:0];
    assign psum_lane[lane][15:0] = late_psum_mode_i
                                      ? psum_bf16_i[lane*16 +: 16]
                                      : psum_d6[lane*16 +: 16];

    edge_dot8_unit #(.EXTERNAL_WEIGHT_EXP(1)) x_dot8 (
      .clk        (clk),
      .rst_b      (rst_b),
      .in_valid   (compute_valid),
      .bf16_vec_i (input_bf16_i[127:0]),
      .int8_vec_i (64'b0),
      .weight_bf16_mode_i(1'b1),
      .bf16_weight_vec_i(weight_row[lane][127:0]),
      .weight_exp_vec_i(weight_exp_row[lane][63:0]),
      .rsum_enable_i(rsum_enable_i),
      .rsum_first_i(rsum_first_i),
      .rsum_last_i(rsum_last_i),
      .out_valid  (dot_valid[lane]),
      .bf16_o     (dot_bf16[lane][15:0]), .bf22_o(dot_fp32[lane*32+:32])
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
  .in_valid (dot_valid[0] && scale_enable_d6
             && (!late_psum_mode_i || late_psum_valid_i)),
  .a_vec_i  ({dot_bf16[7], dot_bf16[6], dot_bf16[5], dot_bf16[4],
              dot_bf16[3], dot_bf16[2], dot_bf16[1], dot_bf16[0]}),
  .b_vec_i  (scale_d6[127:0]),
  .out_valid(scaled_mul_valid),
  .y_vec_o  (scaled_mul_bf16[127:0])
);

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    weight_buf0[0] <= 72'b0; weight_exp_buf0[0] <= 64'b0;
    weight_buf0[1] <= 72'b0; weight_exp_buf0[1] <= 64'b0;
    weight_buf0[2] <= 72'b0; weight_exp_buf0[2] <= 64'b0;
    weight_buf0[3] <= 72'b0; weight_exp_buf0[3] <= 64'b0;
    weight_buf0[4] <= 72'b0; weight_exp_buf0[4] <= 64'b0;
    weight_buf0[5] <= 72'b0; weight_exp_buf0[5] <= 64'b0;
    weight_buf0[6] <= 72'b0; weight_exp_buf0[6] <= 64'b0;
    weight_buf0[7] <= 72'b0; weight_exp_buf0[7] <= 64'b0;
    weight_buf1[0] <= 72'b0; weight_exp_buf1[0] <= 64'b0;
    weight_buf1[1] <= 72'b0; weight_exp_buf1[1] <= 64'b0;
    weight_buf1[2] <= 72'b0; weight_exp_buf1[2] <= 64'b0;
    weight_buf1[3] <= 72'b0; weight_exp_buf1[3] <= 64'b0;
    weight_buf1[4] <= 72'b0; weight_exp_buf1[4] <= 64'b0;
    weight_buf1[5] <= 72'b0; weight_exp_buf1[5] <= 64'b0;
    weight_buf1[6] <= 72'b0; weight_exp_buf1[6] <= 64'b0;
    weight_buf1[7] <= 72'b0; weight_exp_buf1[7] <= 64'b0;
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
    psum_d6 <= 128'b0;
    scale_d0 <= 128'b0;
    scale_d1 <= 128'b0;
    scale_d2 <= 128'b0;
    scale_d3 <= 128'b0;
    scale_d4 <= 128'b0;
    scale_d5 <= 128'b0;
    scale_d6 <= 128'b0;
    scale_enable_d0 <= 1'b0;
    scale_enable_d1 <= 1'b0;
    scale_enable_d2 <= 1'b0;
    scale_enable_d3 <= 1'b0;
    scale_enable_d4 <= 1'b0;
    scale_enable_d5 <= 1'b0;
    scale_enable_d6 <= 1'b0;
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
            weight_buf1[load_lane][weight_fill_bf16_beat*9 +: 9]
              <= {weight_fill_data[load_lane*16+15],
                  (weight_fill_data[load_lane*16+7 +: 8] != 0),
                  weight_fill_data[load_lane*16 +: 7]};
            weight_exp_buf1[load_lane][weight_fill_bf16_beat*8 +: 8]
              <= weight_fill_data[load_lane*16+7 +: 8];
          end else begin
            weight_buf1[load_lane][weight_fill_pair_idx*18 +: 9]
              <= int8_to_local_weight(weight_fill_data[load_lane*16 +: 8]);
            weight_buf1[load_lane][weight_fill_pair_idx*18 + 9 +: 9]
              <= int8_to_local_weight(weight_fill_data[load_lane*16+8 +: 8]);
            weight_exp_buf1[load_lane][weight_fill_pair_idx*16 +: 8]
              <= int8_to_bf16_exp(weight_fill_data[load_lane*16 +: 8]);
            weight_exp_buf1[load_lane][weight_fill_pair_idx*16 + 8 +: 8]
              <= int8_to_bf16_exp(weight_fill_data[load_lane*16+8 +: 8]);
          end
        end
      end else begin
        for (load_lane = 0; load_lane < 8; load_lane = load_lane + 1) begin
          if (weight_fill_bf16_mode) begin
            weight_buf0[load_lane][weight_fill_bf16_beat*9 +: 9]
              <= {weight_fill_data[load_lane*16+15],
                  (weight_fill_data[load_lane*16+7 +: 8] != 0),
                  weight_fill_data[load_lane*16 +: 7]};
            weight_exp_buf0[load_lane][weight_fill_bf16_beat*8 +: 8]
              <= weight_fill_data[load_lane*16+7 +: 8];
          end else begin
            weight_buf0[load_lane][weight_fill_pair_idx*18 +: 9]
              <= int8_to_local_weight(weight_fill_data[load_lane*16 +: 8]);
            weight_buf0[load_lane][weight_fill_pair_idx*18 + 9 +: 9]
              <= int8_to_local_weight(weight_fill_data[load_lane*16+8 +: 8]);
            weight_exp_buf0[load_lane][weight_fill_pair_idx*16 +: 8]
              <= int8_to_bf16_exp(weight_fill_data[load_lane*16 +: 8]);
            weight_exp_buf0[load_lane][weight_fill_pair_idx*16 + 8 +: 8]
              <= int8_to_bf16_exp(weight_fill_data[load_lane*16+8 +: 8]);
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
    psum_d6 <= psum_d5[127:0];
    scale_d0 <= scale_bf16_i[127:0];
    scale_d1 <= scale_d0[127:0];
    scale_d2 <= scale_d1[127:0];
    scale_d3 <= scale_d2[127:0];
    scale_d4 <= scale_d3[127:0];
    scale_d5 <= scale_d4[127:0];
    scale_d6 <= scale_d5[127:0];
    scale_enable_d0 <= scale_enable_i;
    scale_enable_d1 <= scale_enable_d0;
    scale_enable_d2 <= scale_enable_d1;
    scale_enable_d3 <= scale_enable_d2;
    scale_enable_d4 <= scale_enable_d3;
    scale_enable_d5 <= scale_enable_d4;
    scale_enable_d6 <= scale_enable_d5;

    scaled_psum_d0 <= late_psum_mode_i ? psum_bf16_i[127:0]
                         : psum_d6[127:0];
    scaled_psum_d1 <= scaled_psum_d0[127:0];

    output_valid_q <= (dot_valid[0] && !scale_enable_d6
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

// Preserve standalone legacy compositions without adding a source dependency.
generate if(WIDE_PSUM)begin: GEN_WIDE_POST
edge_tensor_scale_psum8 x_post_shared(
 .clk(clk),.rst_b(rst_b),.dot_valid(dot_valid[0]),
 .dot_bf16({dot_bf16[7],dot_bf16[6],dot_bf16[5],dot_bf16[4],dot_bf16[3],dot_bf16[2],dot_bf16[1],dot_bf16[0]}),
 .dot_fp32_i(dot_fp32),.wide_enable_i(wide_enable_i),.psum_fp32_i(psum_fp32_i),
 .late_psum_mode_i(late_psum_mode_i),.late_psum_valid_i(late_psum_valid_i),
 .psum_bf16_i(psum_bf16_i),.scale_enable_i(scale_enable_i),.scale_bf16_i(scale_bf16_i),
 .rsum_enable_i(rsum_enable_i),.dot_ready_o(dot_ready_o),.out_valid(output_valid),
 .output_bf16_o(output_bf16_o),.output_fp32_o(output_fp32_o));
end else begin: GEN_LEGACY_POST
 assign output_valid=output_valid_q;
 assign output_bf16_o=output_reg;
 assign dot_ready_o=dot_valid[0];
 for(genvar ol=0;ol<8;ol=ol+1)begin
  assign output_fp32_o[ol*32+:32]={output_reg[ol*16+:16],16'b0};
 end
end endgenerate
endmodule
