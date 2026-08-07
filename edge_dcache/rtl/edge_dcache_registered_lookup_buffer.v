// Two-entry registered, classified lookup buffer for edge_dcache experiments.
module edge_dcache_registered_lookup_buffer #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter VALUE_WIDTH = 64,
  parameter LINE_OFFSET_WIDTH = 6,
  parameter LINE_INDEX_WIDTH = 8,
  parameter BUNDLE_WIDTH = 2*(SEQ_ID_WIDTH+EPOCH_WIDTH+VALUE_WIDTH+3)+1
) (
  input  wire clk,
  input  wire reset_b,
  input  wire redirect_valid,
  input  wire [SEQ_ID_WIDTH-1:0] redirect_seq_id,
  input  wire [EPOCH_WIDTH-1:0] redirect_epoch,
  input  wire push_valid,
  output wire push_ready,
  input  wire [SEQ_ID_WIDTH-1:0] push_seq_id,
  input  wire [EPOCH_WIDTH-1:0] push_epoch,
  input  wire [VALUE_WIDTH-1:0] push_addr,
  input  wire [1:0] push_size,
  input  wire push_signed,
  input  wire push_classified,
  input  wire push_hit,
  input  wire push_dirty_conflict,
  input  wire [VALUE_WIDTH-LINE_OFFSET_WIDTH-LINE_INDEX_WIDTH-1:0] push_dirty_tag,
  input  wire push1_valid,
  input  wire [SEQ_ID_WIDTH-1:0] push1_seq_id,
  input  wire [EPOCH_WIDTH-1:0] push1_epoch,
  input  wire [VALUE_WIDTH-1:0] push1_addr,
  input  wire [1:0] push1_size,
  input  wire push1_signed,
  input  wire classify_valid,
  input  wire classify_index,
  input  wire classify_hit,
  input  wire classify_dirty_conflict,
  input  wire [VALUE_WIDTH-LINE_OFFSET_WIDTH-LINE_INDEX_WIDTH-1:0] classify_dirty_tag,
  input  wire invalidate_classification,
  input  wire pop_valid,
  input  wire pop_index,
  input  wire pop_lane1,
  output wire candidate0_valid,
  output wire candidate0_classified,
  output wire candidate0_hit,
  output wire candidate0_dirty_conflict,
  output wire [VALUE_WIDTH-LINE_OFFSET_WIDTH-LINE_INDEX_WIDTH-1:0] candidate0_dirty_tag,
  output wire [BUNDLE_WIDTH-1:0] candidate0_bundle,
  output wire candidate1_valid,
  output wire candidate1_classified,
  output wire candidate1_hit,
  output wire candidate1_dirty_conflict,
  output wire [VALUE_WIDTH-LINE_OFFSET_WIDTH-LINE_INDEX_WIDTH-1:0] candidate1_dirty_tag,
  output wire [BUNDLE_WIDTH-1:0] candidate1_bundle,
  output wire oldest_index,
  output wire empty,
  output wire [1:0] count
);
  localparam LANE_WIDTH = SEQ_ID_WIDTH + EPOCH_WIDTH + VALUE_WIDTH + 3;
  localparam TAG_WIDTH = VALUE_WIDTH - LINE_OFFSET_WIDTH - LINE_INDEX_WIDTH;
  localparam SIGNED0_BIT = 0;
  localparam SIZE0_LSB = 1;
  localparam ADDR0_LSB = 3;
  localparam EPOCH0_LSB = ADDR0_LSB + VALUE_WIDTH;
  localparam SEQ0_LSB = EPOCH0_LSB + EPOCH_WIDTH;
  localparam SIGNED1_BIT = LANE_WIDTH;
  localparam SIZE1_LSB = LANE_WIDTH + 1;
  localparam ADDR1_LSB = LANE_WIDTH + 3;
  localparam EPOCH1_LSB = ADDR1_LSB + VALUE_WIDTH;
  localparam SEQ1_LSB = EPOCH1_LSB + EPOCH_WIDTH;
  localparam LANE1_VALID_BIT = 2*LANE_WIDTH;

  reg valid0_q, valid1_q;
  reg classified0_q, classified1_q;
  reg hit0_q, hit1_q;
  reg dirty0_q, dirty1_q;
  reg [TAG_WIDTH-1:0] dirty_tag0_q, dirty_tag1_q;
  reg [TAG_WIDTH-1:0] dirty_tag0_d, dirty_tag1_d;
  reg [BUNDLE_WIDTH-1:0] bundle0_q, bundle1_q;
  reg valid0_d, valid1_d;
  reg classified0_d, classified1_d;
  reg hit0_d, hit1_d;
  reg dirty0_d, dirty1_d;
  reg oldest_q, oldest_d;
  reg push_slot;
  reg promote0, promote1;
  reg clear_lane1_0, clear_lane1_1;

  wire [BUNDLE_WIDTH-1:0] push_bundle = {
    push1_valid, push1_seq_id, push1_epoch, push1_addr, push1_size,
    push1_signed, push_seq_id, push_epoch, push_addr, push_size, push_signed
  };
  wire push_fire = push_valid && push_ready;
  wire kill0 = redirect_valid && valid0_q &&
    bundle0_q[EPOCH0_LSB +: EPOCH_WIDTH] == redirect_epoch &&
    seq_is_younger(bundle0_q[SEQ0_LSB +: SEQ_ID_WIDTH], redirect_seq_id);
  wire kill1 = redirect_valid && valid1_q &&
    bundle1_q[EPOCH0_LSB +: EPOCH_WIDTH] == redirect_epoch &&
    seq_is_younger(bundle1_q[SEQ0_LSB +: SEQ_ID_WIDTH], redirect_seq_id);
  wire kill0_lane1 = redirect_valid && valid0_q &&
    bundle0_q[LANE1_VALID_BIT] &&
    bundle0_q[EPOCH1_LSB +: EPOCH_WIDTH] == redirect_epoch &&
    seq_is_younger(bundle0_q[SEQ1_LSB +: SEQ_ID_WIDTH], redirect_seq_id);
  wire kill1_lane1 = redirect_valid && valid1_q &&
    bundle1_q[LANE1_VALID_BIT] &&
    bundle1_q[EPOCH1_LSB +: EPOCH_WIDTH] == redirect_epoch &&
    seq_is_younger(bundle1_q[SEQ1_LSB +: SEQ_ID_WIDTH], redirect_seq_id);

  assign push_ready = !(valid0_q && valid1_q);
  assign candidate0_valid = valid0_q;
  assign candidate0_classified = classified0_q;
  assign candidate0_hit = hit0_q;
  assign candidate0_dirty_conflict = dirty0_q;
  assign candidate0_dirty_tag = dirty_tag0_q;
  assign candidate0_bundle = bundle0_q;
  assign candidate1_valid = valid1_q;
  assign candidate1_classified = classified1_q;
  assign candidate1_hit = hit1_q;
  assign candidate1_dirty_conflict = dirty1_q;
  assign candidate1_dirty_tag = dirty_tag1_q;
  assign candidate1_bundle = bundle1_q;
  assign oldest_index = oldest_q;
  assign count = {1'b0, valid0_q} + {1'b0, valid1_q};
  assign empty = count == 2'd0;

  function seq_is_younger;
    input [SEQ_ID_WIDTH-1:0] seq_value;
    input [SEQ_ID_WIDTH-1:0] boundary;
    reg [SEQ_ID_WIDTH-1:0] distance;
    begin
      distance = seq_value - boundary;
      seq_is_younger = (distance != {SEQ_ID_WIDTH{1'b0}}) &&
                       !distance[SEQ_ID_WIDTH-1];
    end
  endfunction

  function [BUNDLE_WIDTH-1:0] promote_lane1;
    input [BUNDLE_WIDTH-1:0] bundle;
    begin
      promote_lane1 = {1'b0, {LANE_WIDTH{1'b0}},
        bundle[SEQ1_LSB +: SEQ_ID_WIDTH],
        bundle[EPOCH1_LSB +: EPOCH_WIDTH],
        bundle[ADDR1_LSB +: VALUE_WIDTH], bundle[SIZE1_LSB +: 2],
        bundle[SIGNED1_BIT]};
    end
  endfunction

  always @* begin
    valid0_d = valid0_q; valid1_d = valid1_q;
    classified0_d = classified0_q; classified1_d = classified1_q;
    hit0_d = hit0_q; hit1_d = hit1_q;
    dirty0_d = dirty0_q; dirty1_d = dirty1_q;
    dirty_tag0_d = dirty_tag0_q; dirty_tag1_d = dirty_tag1_q;
    oldest_d = oldest_q;
    push_slot = 1'b0;
    promote0 = 1'b0; promote1 = 1'b0;
    clear_lane1_0 = 1'b0; clear_lane1_1 = 1'b0;

    if (invalidate_classification) begin
      classified0_d = 1'b0;
      classified1_d = 1'b0;
    end else if (classify_valid) begin
      if (classify_index && valid1_d) begin
        classified1_d = 1'b1; hit1_d = classify_hit;
        dirty1_d = classify_dirty_conflict;
        dirty_tag1_d = classify_dirty_tag;
      end else if (!classify_index && valid0_d) begin
        classified0_d = 1'b1; hit0_d = classify_hit;
        dirty0_d = classify_dirty_conflict;
        dirty_tag0_d = classify_dirty_tag;
      end
    end

    if (kill0) begin
      valid0_d = 1'b0; classified0_d = 1'b0;
    end else if (kill0_lane1) begin
      clear_lane1_0 = 1'b1;
    end
    if (kill1) begin
      valid1_d = 1'b0; classified1_d = 1'b0;
    end else if (kill1_lane1) begin
      clear_lane1_1 = 1'b1;
    end

    if (pop_valid) begin
      if (pop_index && valid1_d) begin
        if (bundle1_q[LANE1_VALID_BIT] && !kill1_lane1 && !pop_lane1) begin
          promote1 = 1'b1;
          classified1_d = 1'b0;
        end else begin
          valid1_d = 1'b0; classified1_d = 1'b0;
        end
      end else if (!pop_index && valid0_d) begin
        if (bundle0_q[LANE1_VALID_BIT] && !kill0_lane1 && !pop_lane1) begin
          promote0 = 1'b1;
          classified0_d = 1'b0;
        end else begin
          valid0_d = 1'b0; classified0_d = 1'b0;
        end
      end
    end

    if (valid0_d && !valid1_d)
      oldest_d = 1'b0;
    else if (!valid0_d && valid1_d)
      oldest_d = 1'b1;

    if (push_fire) begin
      if (!valid0_d) begin
        push_slot = 1'b0;
        valid0_d = 1'b1; classified0_d = push_classified;
        hit0_d = push_hit; dirty0_d = push_dirty_conflict;
        dirty_tag0_d = push_dirty_tag;
      end else if (!valid1_d) begin
        push_slot = 1'b1;
        valid1_d = 1'b1; classified1_d = push_classified;
        hit1_d = push_hit; dirty1_d = push_dirty_conflict;
        dirty_tag1_d = push_dirty_tag;
      end
    end
  end

  always @(posedge clk or negedge reset_b) begin
    if (!reset_b) begin
      valid0_q <= 1'b0; valid1_q <= 1'b0;
      classified0_q <= 1'b0; classified1_q <= 1'b0;
      hit0_q <= 1'b0; hit1_q <= 1'b0; dirty0_q <= 1'b0; dirty1_q <= 1'b0;
      dirty_tag0_q <= {TAG_WIDTH{1'b0}};
      dirty_tag1_q <= {TAG_WIDTH{1'b0}};
      oldest_q <= 1'b0;
      bundle0_q <= {BUNDLE_WIDTH{1'b0}};
      bundle1_q <= {BUNDLE_WIDTH{1'b0}};
    end else begin
      valid0_q <= valid0_d; valid1_q <= valid1_d;
      classified0_q <= classified0_d; classified1_q <= classified1_d;
      hit0_q <= hit0_d; hit1_q <= hit1_d;
      dirty0_q <= dirty0_d; dirty1_q <= dirty1_d;
      dirty_tag0_q <= dirty_tag0_d;
      dirty_tag1_q <= dirty_tag1_d;
      oldest_q <= oldest_d;
      if (clear_lane1_0)
        bundle0_q[LANE1_VALID_BIT] <= 1'b0;
      if (clear_lane1_1)
        bundle1_q[LANE1_VALID_BIT] <= 1'b0;
      if (promote0)
        bundle0_q <= promote_lane1(bundle0_q);
      if (promote1)
        bundle1_q <= promote_lane1(bundle1_q);
      if (push_fire && !push_slot)
        bundle0_q <= push_bundle;
      if (push_fire && push_slot)
        bundle1_q <= push_bundle;
    end
  end
endmodule
