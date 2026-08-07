// Maintained IFU post-fetch frontend boundary.
// Owns 64-bit refill tokenization and predecode/dispatch as one replaceable block.
module edge_ifu_predecode_frontend #(
  parameter PC_WIDTH = 40,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter CAPTURE_SLOTS = 8,
  parameter CAPTURE_ID_WIDTH = 3,
  parameter REG_INDEX_WIDTH = 5,
  parameter PRODUCER_TAG_WIDTH = 16,
  parameter REF_COUNT_WIDTH = 4,
  parameter EDGE64_LENGTH_MARKER = 7'b0111111
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,
  input  wire                         fetch_valid,
  output wire                         fetch_ready,
  input  wire [PC_WIDTH-1:0]          fetch_block_pc,
  input  wire                         fetch_first_word,
  input  wire [63:0]                  fetch_bits,
  input  wire [EPOCH_WIDTH-1:0]       fetch_epoch,

  input  wire                         redirect_flush_valid,
  input  wire [EPOCH_WIDTH-1:0]       redirect_new_epoch,

  input  wire                         scalar0_ready,
  output wire                         scalar0_valid,
  output wire [PC_WIDTH-1:0]          scalar0_pc,
  output wire [31:0]                  scalar0_inst,
  output wire [SEQ_ID_WIDTH-1:0]      scalar0_seq_id,
  output wire [EPOCH_WIDTH-1:0]       scalar0_epoch,
  output wire                         scalar0_is_pseudo,
  output wire [2:0]                   scalar0_pseudo_kind,
  output wire                         scalar0_def_valid,
  output wire                         scalar0_def_domain,
  output wire [REG_INDEX_WIDTH-1:0]   scalar0_def_dst_reg,
  output wire                         scalar0_def_bank,

  input  wire                         scalar1_ready,
  output wire                         scalar1_valid,
  output wire [PC_WIDTH-1:0]          scalar1_pc,
  output wire [31:0]                  scalar1_inst,
  output wire [SEQ_ID_WIDTH-1:0]      scalar1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       scalar1_epoch,
  output wire                         scalar1_is_pseudo,
  output wire [2:0]                   scalar1_pseudo_kind,
  output wire                         scalar1_def_valid,
  output wire [REG_INDEX_WIDTH-1:0]   scalar1_def_dst_reg,
  output wire                         scalar1_def_bank,

  input  wire                         accel_command_ready,
  input  wire                         reverse_snapshot_alloc_ready,
  input  wire                         reverse_snapshot_alloc_id,
  output wire                         reverse_snapshot_alloc_valid,
  output wire [SEQ_ID_WIDTH-1:0]      reverse_snapshot_alloc_seq_id,
  output wire [EPOCH_WIDTH-1:0]       reverse_snapshot_alloc_epoch,
  output wire                         debug_token0_valid,
  output wire [1:0]                   debug_token0_kind,
  output wire [31:0]                  debug_token0_inst32,
  output wire                         accel_command_valid,
  output wire                         accel_command_is_tensor,
  output wire [63:0]                  accel_command_inst64,
  output wire [SEQ_ID_WIDTH-1:0]      accel_command_seq_id,
  output wire [EPOCH_WIDTH-1:0]       accel_command_epoch,
  output wire [2:0]                   accel_command_capture_count,
  output wire                         accel_command_n_capture_valid,
  output wire [CAPTURE_ID_WIDTH-1:0]  accel_command_n_capture_id,
  output wire                         accel_command_n_capture_bank,
  output wire [PRODUCER_TAG_WIDTH-1:0] accel_command_n_producer_tag,
  output wire [REG_INDEX_WIDTH-1:0]   accel_command_n_src_gpr,
  output wire                         accel_command_base_capture_valid,
  output wire [CAPTURE_ID_WIDTH-1:0]  accel_command_base_capture_id,
  output wire                         accel_command_base_capture_bank,
  output wire [PRODUCER_TAG_WIDTH-1:0] accel_command_base_producer_tag,
  output wire [REG_INDEX_WIDTH-1:0]   accel_command_base_src_gpr
);

  wire token0_valid;
  wire token_ready;
  wire [1:0] token_consume_count;
  wire [1:0] token0_kind;
  wire [3:0] token0_len_bytes;
  wire [PC_WIDTH-1:0] token0_pc;
  wire [31:0] token0_inst32;
  wire [63:0] token0_inst64;
  wire [SEQ_ID_WIDTH-1:0] token0_seq_id;
  wire [EPOCH_WIDTH-1:0] token0_epoch;
  wire token1_valid;
  wire [1:0] token1_kind;
  wire [3:0] token1_len_bytes;
  wire [PC_WIDTH-1:0] token1_pc;
  wire [31:0] token1_inst32;
  wire [63:0] token1_inst64;
  wire [SEQ_ID_WIDTH-1:0] token1_seq_id;
  wire [EPOCH_WIDTH-1:0] token1_epoch;

  assign debug_token0_valid = token0_valid;
  assign debug_token0_kind = token0_kind;
  assign debug_token0_inst32 = token0_inst32;

  localparam [1:0] TOKEN_KIND_SCALAR = 2'd0;
  localparam [1:0] TOKEN_KIND_ACCEL = 2'd1;
  localparam [1:0] TOKEN_KIND_TENSOR = 2'd2;

  reg [31:0] parcel_inst_q [0:3];
  reg [PC_WIDTH-1:0] parcel_pc_q [0:3];
  reg [EPOCH_WIDTH-1:0] parcel_epoch_q [0:3];
  reg [1:0] parcel_head_q;
  reg [2:0] parcel_count_q;
  reg [SEQ_ID_WIDTH-1:0] next_seq_id_q;

  wire [1:0] token0_high_idx = parcel_head_q + 2'd1;
  wire token0_is_64b = parcel_inst_q[parcel_head_q][6:0] == EDGE64_LENGTH_MARKER;
  wire token0_has_high_word = parcel_count_q >= 3'd2;
  wire [1:0] token0_words = token0_is_64b ? 2'd2 : 2'd1;
  wire [2:0] token0_words_wide = {1'b0, token0_words};
  wire [1:0] token1_idx = parcel_head_q + token0_words;
  wire [1:0] token1_high_idx = token1_idx + 2'd1;
  wire token1_is_64b = parcel_inst_q[token1_idx][6:0] == EDGE64_LENGTH_MARKER;
  wire token1_has_high_word = parcel_count_q >= (token0_words_wide + 3'd2);
  wire [1:0] token1_words = token1_is_64b ? 2'd2 : 2'd1;
  wire [2:0] token1_needed_words = token0_words_wide + {1'b0, token1_words};

  assign token0_valid = (parcel_count_q != 3'd0) &&
                        (parcel_count_q >= token0_words_wide);
  assign token0_kind = !(token0_is_64b && token0_has_high_word) ?
                       TOKEN_KIND_SCALAR :
                       (parcel_inst_q[token0_high_idx][7] ? TOKEN_KIND_TENSOR :
                                                          TOKEN_KIND_ACCEL);
  assign token0_len_bytes = token0_is_64b ? 4'd8 : 4'd4;
  assign token0_pc = parcel_pc_q[parcel_head_q];
  assign token0_inst32 = parcel_inst_q[parcel_head_q];
  assign token0_inst64 = token0_is_64b ?
                         {parcel_inst_q[token0_high_idx], parcel_inst_q[parcel_head_q]} :
                         {32'd0, parcel_inst_q[parcel_head_q]};
  assign token0_seq_id = next_seq_id_q;
  assign token0_epoch = parcel_epoch_q[parcel_head_q];

  assign token1_valid = token0_valid && (parcel_count_q >= token1_needed_words);
  assign token1_kind = !(token1_is_64b && token1_has_high_word) ?
                       TOKEN_KIND_SCALAR :
                       (parcel_inst_q[token1_high_idx][7] ? TOKEN_KIND_TENSOR :
                                                          TOKEN_KIND_ACCEL);
  assign token1_len_bytes = token1_is_64b ? 4'd8 : 4'd4;
  assign token1_pc = parcel_pc_q[token1_idx];
  assign token1_inst32 = parcel_inst_q[token1_idx];
  assign token1_inst64 = token1_is_64b ?
                         {parcel_inst_q[token1_high_idx], parcel_inst_q[token1_idx]} :
                         {32'd0, parcel_inst_q[token1_idx]};
  assign token1_seq_id = next_seq_id_q + {{(SEQ_ID_WIDTH-1){1'b0}}, 1'b1};
  assign token1_epoch = parcel_epoch_q[token1_idx];

  wire [1:0] consumed_tokens =
    (token_consume_count == 2'd2 && token1_valid) ? 2'd2 :
    ((token_consume_count != 2'd0 && token0_valid) ? 2'd1 : 2'd0);
  wire [2:0] consumed_words = (consumed_tokens == 2'd2) ? token1_needed_words :
                              ((consumed_tokens == 2'd1) ? token0_words_wide : 3'd0);
  wire [2:0] incoming_words = fetch_first_word ? 3'd1 : 3'd2;
  wire [3:0] parcel_free_slots = 4 - parcel_count_q;
  assign fetch_ready = fetch_valid ? (parcel_free_slots >= {1'b0, incoming_words}) :
                                     (parcel_free_slots >= 2);

  wire fetch_fire = fetch_valid && fetch_ready;
  wire [1:0] parcel_tail = parcel_head_q + parcel_count_q[1:0];
  integer parcel_i;
  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      parcel_head_q <= 2'd0;
      parcel_count_q <= 3'd0;
      next_seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
      for (parcel_i = 0; parcel_i < 4; parcel_i = parcel_i + 1) begin
        parcel_inst_q[parcel_i] <= 32'd0;
        parcel_pc_q[parcel_i] <= {PC_WIDTH{1'b0}};
        parcel_epoch_q[parcel_i] <= {EPOCH_WIDTH{1'b0}};
      end
    end else if (redirect_flush_valid) begin
      parcel_head_q <= 2'd0;
      parcel_count_q <= 3'd0;
      next_seq_id_q <= {{(SEQ_ID_WIDTH-EPOCH_WIDTH){1'b0}}, redirect_new_epoch};
    end else begin
      if (consumed_tokens != 2'd0) begin
        parcel_head_q <= parcel_head_q + consumed_words[1:0];
        next_seq_id_q <= next_seq_id_q +
                         {{(SEQ_ID_WIDTH-2){1'b0}}, consumed_tokens};
      end

      if (fetch_fire) begin
        if (fetch_first_word) begin
          parcel_inst_q[parcel_tail] <= fetch_bits[63:32];
          parcel_pc_q[parcel_tail] <=
            fetch_block_pc + {{(PC_WIDTH-3){1'b0}}, 3'd4};
          parcel_epoch_q[parcel_tail] <= fetch_epoch;
        end else begin
          parcel_inst_q[parcel_tail] <= fetch_bits[31:0];
          parcel_pc_q[parcel_tail] <= fetch_block_pc;
          parcel_epoch_q[parcel_tail] <= fetch_epoch;
          parcel_inst_q[parcel_tail + 2'd1] <= fetch_bits[63:32];
          parcel_pc_q[parcel_tail + 2'd1] <=
            fetch_block_pc + {{(PC_WIDTH-3){1'b0}}, 3'd4};
          parcel_epoch_q[parcel_tail + 2'd1] <= fetch_epoch;
        end
      end

      parcel_count_q <= parcel_count_q - consumed_words +
                        (fetch_fire ? incoming_words : 3'd0);
    end
  end

  edge_predecoder #(
    .PC_WIDTH(PC_WIDTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .CAPTURE_SLOTS(CAPTURE_SLOTS),
    .CAPTURE_ID_WIDTH(CAPTURE_ID_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .PRODUCER_TAG_WIDTH(PRODUCER_TAG_WIDTH),
    .REF_COUNT_WIDTH(REF_COUNT_WIDTH),
    .EDGE64_LENGTH_MARKER(EDGE64_LENGTH_MARKER)
  ) predecode (
    .forever_cpuclk(forever_cpuclk), .cpurst_b(cpurst_b),
    .scalar_def_valid(1'b0), .scalar_def_domain(1'b0),
    .scalar_def_dst_reg({REG_INDEX_WIDTH{1'b0}}),
    .scalar_def_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .scalar_def_epoch({EPOCH_WIDTH{1'b0}}),
    .decoded_valid(1'b0), .decoded_ready(),
    .decoded_seq_id({SEQ_ID_WIDTH{1'b0}}), .decoded_epoch({EPOCH_WIDTH{1'b0}}),
    .decoded_is_tensor(1'b0), .decoded_capture_count(3'd0),
    .decoded_src0_domain(1'b0), .decoded_src0_reg({REG_INDEX_WIDTH{1'b0}}),
    .decoded_src0_is_n_capture(1'b0),
    .raw_valid(1'b0), .raw_ready(), .raw_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .raw_epoch({EPOCH_WIDTH{1'b0}}), .raw_inst64(64'd0), .raw_is_64b(1'b0),
    .window_valid(1'b0), .window_ready(), .window_bits(64'd0),
    .window_bytes_valid(8'd0),
    .window_lane0_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .window_lane1_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .window_epoch({EPOCH_WIDTH{1'b0}}),
    .token0_valid(token0_valid), .token_ready(token_ready),
    .token_consume_count(token_consume_count),
    .token0_kind(token0_kind), .token0_len_bytes(token0_len_bytes),
    .token0_pc(token0_pc), .token0_inst32(token0_inst32),
    .token0_inst64(token0_inst64), .token0_seq_id(token0_seq_id),
    .token0_epoch(token0_epoch), .token1_valid(token1_valid),
    .token1_kind(token1_kind), .token1_len_bytes(token1_len_bytes),
    .token1_pc(token1_pc), .token1_inst32(token1_inst32),
    .token1_inst64(token1_inst64), .token1_seq_id(token1_seq_id),
    .token1_epoch(token1_epoch),
    .window_scalar_valid(scalar0_valid), .window_scalar_ready(scalar0_ready),
    .window_scalar_pc(scalar0_pc), .window_scalar_inst(scalar0_inst),
    .window_scalar_seq_id(scalar0_seq_id), .window_scalar_epoch(scalar0_epoch),
    .window_scalar_is_pseudo(scalar0_is_pseudo),
    .window_scalar_pseudo_kind(scalar0_pseudo_kind),
    .window_scalar_def_valid(scalar0_def_valid),
    .window_scalar_def_domain(scalar0_def_domain),
    .window_scalar_def_dst_reg(scalar0_def_dst_reg),
    .window_scalar_def_bank(scalar0_def_bank),
    .window_scalar1_valid(scalar1_valid), .window_scalar1_ready(scalar1_ready),
    .window_scalar1_pc(scalar1_pc), .window_scalar1_inst(scalar1_inst),
    .window_scalar1_seq_id(scalar1_seq_id), .window_scalar1_epoch(scalar1_epoch),
    .window_scalar1_is_pseudo(scalar1_is_pseudo),
    .window_scalar1_pseudo_kind(scalar1_pseudo_kind),
    .window_scalar1_def_valid(scalar1_def_valid),
    .window_scalar1_def_dst_reg(scalar1_def_dst_reg),
    .window_scalar1_def_bank(scalar1_def_bank),
    .consumer_release_valid(1'b0), .consumer_release_domain(1'b0),
    .consumer_release_capture_id({CAPTURE_ID_WIDTH{1'b0}}),
    .consumer_release_capture_bank(1'b0),
    .redirect_flush_valid(redirect_flush_valid),
    .redirect_new_epoch(redirect_new_epoch),
    .loop_predict_valid(), .loop_predict_target(), .loop_predict_fallthrough(),
    .loop_predict_seq_id(), .loop_predict_epoch(),
    .command_valid(), .command_is_tensor(), .command_seq_id(), .command_epoch(),
    .command_capture_count(), .command_capture_id0(), .command_capture_bank0(),
    .command_n_capture_valid(), .command_n_capture_id(), .command_n_capture_bank(),
    .command_producer_tag0(),
    .accel_command_ready(accel_command_ready),
    .reverse_snapshot_alloc_ready(reverse_snapshot_alloc_ready),
    .reverse_snapshot_alloc_id(reverse_snapshot_alloc_id),
    .reverse_snapshot_alloc_valid(reverse_snapshot_alloc_valid),
    .reverse_snapshot_alloc_seq_id(reverse_snapshot_alloc_seq_id),
    .reverse_snapshot_alloc_epoch(reverse_snapshot_alloc_epoch),
    .accel_command_valid(accel_command_valid),
    .accel_command_is_tensor(accel_command_is_tensor),
    .accel_command_inst64(accel_command_inst64),
    .accel_command_seq_id(accel_command_seq_id),
    .accel_command_epoch(accel_command_epoch),
    .accel_command_capture_count(accel_command_capture_count),
    .accel_command_n_capture_valid(accel_command_n_capture_valid),
    .accel_command_n_capture_id(accel_command_n_capture_id),
    .accel_command_n_capture_bank(accel_command_n_capture_bank),
    .accel_command_n_producer_tag(accel_command_n_producer_tag),
    .accel_command_n_src_gpr(accel_command_n_src_gpr),
    .accel_command_base_capture_valid(accel_command_base_capture_valid),
    .accel_command_base_capture_id(accel_command_base_capture_id),
    .accel_command_base_capture_bank(accel_command_base_capture_bank),
    .accel_command_base_producer_tag(accel_command_base_producer_tag),
    .accel_command_base_src_gpr(accel_command_base_src_gpr),
    .accel_decode_is_accel(), .accel_decode_needs_base_gpr(),
    .debug_slot_owned(), .debug_bank_owned_flat(), .debug_bank_ref_count_flat(),
    .debug_slot_ref_count_flat(), .debug_mapping_valid()
  );

endmodule
