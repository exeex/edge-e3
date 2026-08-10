`timescale 1ns/1ps

module edge_cmpu (
  input wire clk,
  input wire cpurst_b,
  input wire start_valid,
  output wire start_ready,
  input wire [3:0] start_mode,
  input wire in_valid,
  output wire in_ready,
  input wire [15:0] in_lhs,
  input wire [15:0] in_rhs,
  input wire [7:0] in_mask,
  input wire [15:0] in_index,
  input wire in_last,
  output wire out_valid,
  output wire [15:0] out_value,
  output wire out_is_mask,
  output wire out_last,
  output wire result_valid,
  input wire result_ready,
  output wire [15:0] result_max_value,
  output wire [15:0] result_argmax_idx,
  output wire [15:0] result_min_value,
  output wire [15:0] result_argmin_idx
);

localparam [3:0] MODE_REDUCE_MINMAX = 4'd0;
localparam [3:0] MODE_MIN = 4'd1;
localparam [3:0] MODE_MAX = 4'd2;
localparam [3:0] MODE_SELECT = 4'd3;
localparam [3:0] MODE_CMP_GT = 4'd4;
localparam [3:0] MODE_CMP_GE = 4'd5;
localparam [3:0] MODE_CMP_EQ = 4'd6;
localparam [3:0] MODE_CMP_LE = 4'd7;
localparam [3:0] MODE_CMP_NE = 4'd8;

reg active_q;
reg [3:0] mode_q;
reg out_valid_q;
reg [15:0] out_value_q;
reg out_is_mask_q;
reg out_last_q;
reg result_valid_q;
reg [15:0] result_max_value_q;
reg [15:0] result_argmax_idx_q;
reg [15:0] result_min_value_q;
reg [15:0] result_argmin_idx_q;
reg reduce_seen_any_q;
reg reduce_seen_numeric_q;
reg [15:0] reduce_first_value_q;
reg [15:0] reduce_first_idx_q;
reg [15:0] reduce_max_value_q;
reg [15:0] reduce_argmax_idx_q;
reg [15:0] reduce_min_value_q;
reg [15:0] reduce_argmin_idx_q;

wire is_reduce = (mode_q == MODE_REDUCE_MINMAX);
wire start_fire = start_valid && start_ready;
wire in_fire = in_valid && in_ready;
assign start_ready = !active_q && !result_valid_q;
assign in_ready = active_q;

wire [15:0] rel0_a = is_reduce ? reduce_max_value_q :
                         (mode_q == MODE_SELECT ? 16'b0 : in_lhs);
wire [15:0] rel0_b = is_reduce ? in_lhs :
                         (mode_q == MODE_SELECT ? 16'b0 : in_rhs);
wire rel0_a_nan, rel0_b_nan, rel0_unordered;
wire rel0_lt, rel0_eq, rel0_gt;
edge_cmpu_bf16_relation relation0 (
  .a(rel0_a), .b(rel0_b), .a_nan(rel0_a_nan), .b_nan(rel0_b_nan),
  .unordered(rel0_unordered), .lt(rel0_lt), .eq(rel0_eq), .gt(rel0_gt)
);

wire [15:0] rel1_a = is_reduce ? in_lhs : 16'b0;
wire [15:0] rel1_b = is_reduce ? reduce_min_value_q : 16'b0;
wire rel1_a_nan, rel1_b_nan, rel1_unordered;
wire rel1_lt, rel1_eq, rel1_gt;
edge_cmpu_bf16_relation relation1 (
  .a(rel1_a), .b(rel1_b), .a_nan(rel1_a_nan), .b_nan(rel1_b_nan),
  .unordered(rel1_unordered), .lt(rel1_lt), .eq(rel1_eq), .gt(rel1_gt)
);

wire pair_lhs_nan = rel0_a_nan;
wire pair_rhs_nan = rel0_b_nan;
wire [15:0] pair_min = pair_lhs_nan ? (pair_rhs_nan ? in_lhs : in_rhs) :
                         pair_rhs_nan ? in_lhs :
                         rel0_gt ? in_rhs : in_lhs;
wire [15:0] pair_max = pair_lhs_nan ? (pair_rhs_nan ? in_lhs : in_rhs) :
                         pair_rhs_nan ? in_lhs :
                         rel0_lt ? in_rhs : in_lhs;

reg [15:0] action_value;
reg action_is_mask;
always @* begin
  action_value = 16'b0;
  action_is_mask = 1'b0;
  case (mode_q)
    MODE_MIN: action_value = pair_min;
    MODE_MAX: action_value = pair_max;
    MODE_SELECT: action_value = (in_mask != 0) ? in_rhs : in_lhs;
    MODE_CMP_GT: begin action_value = {15'b0, rel0_gt}; action_is_mask = 1'b1; end
    MODE_CMP_GE: begin action_value = {15'b0, rel0_gt || rel0_eq}; action_is_mask = 1'b1; end
    MODE_CMP_EQ: begin action_value = {15'b0, rel0_eq}; action_is_mask = 1'b1; end
    MODE_CMP_LE: begin action_value = {15'b0, rel0_lt || rel0_eq}; action_is_mask = 1'b1; end
    MODE_CMP_NE: begin action_value = {15'b0, rel0_unordered || !rel0_eq}; action_is_mask = 1'b1; end
    default: begin end
  endcase
end

wire current_numeric = !rel1_a_nan;
wire seed_numeric = current_numeric && !reduce_seen_numeric_q;
wire update_max = current_numeric && reduce_seen_numeric_q && rel0_lt;
wire update_min = current_numeric && reduce_seen_numeric_q && rel1_lt;
wire next_seen_numeric = reduce_seen_numeric_q || current_numeric;
wire [15:0] next_max_value = seed_numeric ? in_lhs :
                                  (update_max ? in_lhs : reduce_max_value_q);
wire [15:0] next_argmax_idx = seed_numeric ? in_index :
                                   (update_max ? in_index : reduce_argmax_idx_q);
wire [15:0] next_min_value = seed_numeric ? in_lhs :
                                  (update_min ? in_lhs : reduce_min_value_q);
wire [15:0] next_argmin_idx = seed_numeric ? in_index :
                                   (update_min ? in_index : reduce_argmin_idx_q);

assign out_valid = out_valid_q;
assign out_value = out_value_q;
assign out_is_mask = out_is_mask_q;
assign out_last = out_last_q;
assign result_valid = result_valid_q;
assign result_max_value = result_max_value_q;
assign result_argmax_idx = result_argmax_idx_q;
assign result_min_value = result_min_value_q;
assign result_argmin_idx = result_argmin_idx_q;

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    active_q <= 1'b0;
    mode_q <= 4'b0;
    out_valid_q <= 1'b0;
    out_value_q <= 16'b0;
    out_is_mask_q <= 1'b0;
    out_last_q <= 1'b0;
    result_valid_q <= 1'b0;
    result_max_value_q <= 16'b0;
    result_argmax_idx_q <= 16'b0;
    result_min_value_q <= 16'b0;
    result_argmin_idx_q <= 16'b0;
    reduce_seen_any_q <= 1'b0;
    reduce_seen_numeric_q <= 1'b0;
    reduce_first_value_q <= 16'b0;
    reduce_first_idx_q <= 16'b0;
    reduce_max_value_q <= 16'b0;
    reduce_argmax_idx_q <= 16'b0;
    reduce_min_value_q <= 16'b0;
    reduce_argmin_idx_q <= 16'b0;
  end else begin
    out_valid_q <= 1'b0;
    if (result_valid_q && result_ready)
      result_valid_q <= 1'b0;
    if (start_fire) begin
      active_q <= 1'b1;
      mode_q <= start_mode;
      reduce_seen_any_q <= 1'b0;
      reduce_seen_numeric_q <= 1'b0;
    end
    if (in_fire) begin
      if (is_reduce) begin
        if (!reduce_seen_any_q) begin
          reduce_seen_any_q <= 1'b1;
          reduce_first_value_q <= in_lhs;
          reduce_first_idx_q <= in_index;
        end
        reduce_seen_numeric_q <= next_seen_numeric;
        reduce_max_value_q <= next_max_value;
        reduce_argmax_idx_q <= next_argmax_idx;
        reduce_min_value_q <= next_min_value;
        reduce_argmin_idx_q <= next_argmin_idx;
        if (in_last) begin
          active_q <= 1'b0;
          result_valid_q <= 1'b1;
          if (next_seen_numeric) begin
            result_max_value_q <= next_max_value;
            result_argmax_idx_q <= next_argmax_idx;
            result_min_value_q <= next_min_value;
            result_argmin_idx_q <= next_argmin_idx;
          end else begin
            result_max_value_q <= reduce_seen_any_q ? reduce_first_value_q : in_lhs;
            result_argmax_idx_q <= reduce_seen_any_q ? reduce_first_idx_q : in_index;
            result_min_value_q <= reduce_seen_any_q ? reduce_first_value_q : in_lhs;
            result_argmin_idx_q <= reduce_seen_any_q ? reduce_first_idx_q : in_index;
          end
        end
      end else begin
        out_valid_q <= 1'b1;
        out_value_q <= action_value;
        out_is_mask_q <= action_is_mask;
        out_last_q <= in_last;
        if (in_last)
          active_q <= 1'b0;
      end
    end
  end
end

wire unused_rel1_b_nan = rel1_b_nan;
wire unused_rel1_unordered = rel1_unordered;
wire unused_rel1_eq = rel1_eq;
wire unused_rel1_gt = rel1_gt;

endmodule
