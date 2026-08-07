// First SoC scalar memory backend behind edge_lsu_top.
module edge_dcache #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH  = 4,
  parameter VALUE_WIDTH  = 64,
  parameter ICACHE_BYTES = 16384,
  parameter DCACHE_BYTES = 16384,
  parameter LINE_BYTES   = 64,
  parameter LOAD_LATENCY = 1,
`ifdef EDGE_DCACHE_REGISTERED_LOOKUP
  parameter LOOKUP_REGISTERED = 1,
`else
  parameter LOOKUP_REGISTERED = 0,
`endif
`ifdef EDGE_DCACHE_HYBRID_LOOKUP
  parameter LOOKUP_HYBRID = 1
`else
  parameter LOOKUP_HYBRID = 0
`endif
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,
  input  wire                       redirect_kill_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    redirect_kill_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     redirect_kill_epoch,

  input  wire                       backend_load_pause,
  input  wire                       backend_store_pause,

  input  wire                       lsu_load_req_valid,
  output wire                       lsu_load_req_ready,
  input  wire [SEQ_ID_WIDTH-1:0]    lsu_load_req_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     lsu_load_req_epoch,
  input  wire [VALUE_WIDTH-1:0]     lsu_load_req_addr,
  input  wire [1:0]                 lsu_load_req_size,
  input  wire                       lsu_load_req_signed,
  input  wire                       lsu_load_req1_valid,
  output wire                       lsu_load_req1_ready,
  input  wire [SEQ_ID_WIDTH-1:0]    lsu_load_req1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     lsu_load_req1_epoch,
  input  wire [VALUE_WIDTH-1:0]     lsu_load_req1_addr,
  input  wire [1:0]                 lsu_load_req1_size,
  input  wire                       lsu_load_req1_signed,

  output wire                       lsu_load_resp_valid,
  output wire [SEQ_ID_WIDTH-1:0]    lsu_load_resp_seq_id,
  output wire [EPOCH_WIDTH-1:0]     lsu_load_resp_epoch,
  output wire                       lsu_load_resp_error,
  output wire [VALUE_WIDTH-1:0]     lsu_load_resp_value,

  input  wire                       lsu_store_req_valid,
  output wire                       lsu_store_req_ready,
  input  wire [SEQ_ID_WIDTH-1:0]    lsu_store_req_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     lsu_store_req_epoch,
  input  wire [VALUE_WIDTH-1:0]     lsu_store_req_addr,
  input  wire [1:0]                 lsu_store_req_size,
  input  wire [VALUE_WIDTH-1:0]     lsu_store_req_data,
  input  wire [(VALUE_WIDTH/8)-1:0] lsu_store_req_wstrb,
  input  wire                       lsu_store_req1_valid,
  output wire                       lsu_store_req1_ready,
  input  wire [SEQ_ID_WIDTH-1:0]    lsu_store_req1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     lsu_store_req1_epoch,
  input  wire [VALUE_WIDTH-1:0]     lsu_store_req1_addr,
  input  wire [1:0]                 lsu_store_req1_size,
  input  wire [VALUE_WIDTH-1:0]     lsu_store_req1_data,
  input  wire [(VALUE_WIDTH/8)-1:0] lsu_store_req1_wstrb,

  input  wire                       cache_op_valid,
  output wire                       cache_op_ready,
  input  wire                       cache_op_is_va,
  input  wire [1:0]                 cache_op_kind,
  input  wire [VALUE_WIDTH-1:0]     cache_op_addr,
  input  wire [SEQ_ID_WIDTH-1:0]    cache_op_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     cache_op_epoch,
  output wire                       cache_op_complete_valid,
  output wire [SEQ_ID_WIDTH-1:0]    cache_op_complete_seq_id,
  output wire [EPOCH_WIDTH-1:0]     cache_op_complete_epoch,

  output wire                       clean_wb_valid,
  input  wire                       clean_wb_ready,
  output wire [VALUE_WIDTH-1:0]     clean_wb_addr,
  output wire [127:0]               clean_wb_data,
  output wire                       clean_wb_last,
  input  wire                       clean_wb_complete,

  output wire                       refill_req_valid,
  input  wire                       refill_req_ready,
  output wire [VALUE_WIDTH-1:0]     refill_req_addr,
  input  wire                       refill_resp_valid,
  output wire                       refill_resp_ready,
  input  wire [127:0]               refill_resp_data,
  input  wire                       refill_resp_last,
  input  wire                       refill_resp_error,

  output wire [31:0]                debug_icache_bytes,
  output wire [31:0]                debug_dcache_bytes,
  output wire                       debug_load_pending,
  output wire                       debug_load_miss_pending,
  output wire                       debug_store_fire,
  output wire                       store_predict_phase,
  output wire                       store_predict_mem_active,
  output wire                       store_predict_backend_blocked,
  output wire                       debug_cache_op_fire,
  output wire [1:0]                 debug_cache_op_kind,
  output wire                       debug_cache_op_is_va
);

  localparam VALUE_BYTES = VALUE_WIDTH / 8;
  localparam WORDS = DCACHE_BYTES / VALUE_BYTES;
  localparam LINES = DCACHE_BYTES / LINE_BYTES;
  localparam WORD_INDEX_WIDTH = (WORDS <= 2) ? 1 : $clog2(WORDS);
  localparam BYTE_OFFSET_WIDTH = (VALUE_BYTES <= 2) ? 1 : $clog2(VALUE_BYTES);
  localparam LINE_OFFSET_WIDTH = (LINE_BYTES <= 2) ? 1 : $clog2(LINE_BYTES);
  localparam LINE_INDEX_WIDTH = (LINES <= 2) ? 1 : $clog2(LINES);
  localparam TAG_WIDTH = VALUE_WIDTH - LINE_OFFSET_WIDTH - LINE_INDEX_WIDTH;
  localparam LATENCY_WIDTH = (LOAD_LATENCY <= 1) ? 1 : $clog2(LOAD_LATENCY + 1);
  localparam LINE_WORDS = LINE_BYTES / VALUE_BYTES;
  localparam CLEAN_BEATS = LINE_BYTES / 16;
  localparam CLEAN_BEAT_INDEX_WIDTH =
    (CLEAN_BEATS <= 2) ? 1 : $clog2(CLEAN_BEATS);
  localparam [CLEAN_BEAT_INDEX_WIDTH-1:0] CLEAN_LAST_BEAT =
    CLEAN_BEATS - 1;
  localparam LOOKUP_LANE_WIDTH = SEQ_ID_WIDTH + EPOCH_WIDTH + VALUE_WIDTH + 3;
  localparam LOOKUP_BUNDLE_WIDTH = 2*LOOKUP_LANE_WIDTH + 1;
  localparam LOOKUP_SIGNED0_BIT = 0;
  localparam LOOKUP_SIZE0_LSB = 1;
  localparam LOOKUP_ADDR0_LSB = 3;
  localparam LOOKUP_EPOCH0_LSB = LOOKUP_ADDR0_LSB + VALUE_WIDTH;
  localparam LOOKUP_SEQ0_LSB = LOOKUP_EPOCH0_LSB + EPOCH_WIDTH;
  localparam LOOKUP_SIGNED1_BIT = LOOKUP_LANE_WIDTH;
  localparam LOOKUP_SIZE1_LSB = LOOKUP_LANE_WIDTH + 1;
  localparam LOOKUP_ADDR1_LSB = LOOKUP_LANE_WIDTH + 3;
  localparam LOOKUP_EPOCH1_LSB = LOOKUP_ADDR1_LSB + VALUE_WIDTH;
  localparam LOOKUP_SEQ1_LSB = LOOKUP_EPOCH1_LSB + EPOCH_WIDTH;
  localparam LOOKUP_LANE1_VALID_BIT = 2*LOOKUP_LANE_WIDTH;

  reg clean_writeback_req_q;
  reg [VALUE_WIDTH-1:0] clean_writeback_addr_q;
  reg [LINE_INDEX_WIDTH-1:0] clean_writeback_line_index_q;
  reg [TAG_WIDTH-1:0] clean_writeback_tag_q;
  reg clean_immediate_complete_valid_q;
  reg [SEQ_ID_WIDTH-1:0] clean_immediate_complete_seq_id_q;
  reg [EPOCH_WIDTH-1:0] clean_immediate_complete_epoch_q;
  reg clean_wb_complete_valid_q;
  reg [SEQ_ID_WIDTH-1:0] clean_wb_seq_id_q;
  reg [EPOCH_WIDTH-1:0] clean_wb_epoch_q;
  reg clean_wb_active_q;
  reg clean_wb_wait_complete_q;
  reg clean_wb_for_refill_q;
  reg clean_wb_for_cache_op_q;
  reg clean_wb_invalidate_q;
  reg mshr_store_refill_q;
  reg [CLEAN_BEAT_INDEX_WIDTH-1:0] clean_wb_beat_q;
  reg [VALUE_WIDTH-1:0] clean_wb_base_addr_q;
  reg [LINE_INDEX_WIDTH-1:0] clean_wb_line_index_q;
  reg phase_q;
  reg hit_read_valid_q;
  reg [1:0] hit_read_slot_q;
  reg hit_read1_valid_q;
  reg [1:0] hit_read1_slot_q;
  reg clean_wb_data_valid_q;
  reg [127:0] clean_wb_data_q;

  wire load_fire;
  wire load1_fire;
  wire store_fire;
  wire store1_fire;
  wire store_metadata_hit;
  wire store_dirty_conflict;
  wire store_dirty_conflict_start;
  wire store_refill_miss;
  wire store_miss_refill_fire;
  wire load_metadata_hit;
  wire load_dirty_conflict;
  wire load_dirty_conflict_fire;
  wire load_hit_fire;
  wire load1_hit_fire;
  wire load_miss_fire;
  wire cache_op_fire;
  wire cache_op_va_fire;
  wire cache_op_clean_va_fire;
  wire cache_op_invalidate_va_fire;
  wire cache_op_metadata_hit;
  wire cache_op_clean_dirty_hit;
  wire clean_wb_busy;
  wire clean_wb_complete_fire;
  wire metadata_write_valid;
  wire [WORD_INDEX_WIDTH-1:0] load_word_index;
  wire [WORD_INDEX_WIDTH-1:0] store_word_index;
  wire [WORD_INDEX_WIDTH-1:0] load1_word_index;
  wire [WORD_INDEX_WIDTH-1:0] store1_word_index;
  wire [LINE_INDEX_WIDTH-1:0] load_line_index;
  wire [LINE_INDEX_WIDTH-1:0] store_line_index;
  wire [LINE_INDEX_WIDTH-1:0] load1_line_index;
  wire [LINE_INDEX_WIDTH-1:0] store1_line_index;
  wire [LINE_INDEX_WIDTH-1:0] cache_op_line_index;
  wire [LINE_INDEX_WIDTH-1:0] metadata_read_index;
  wire [LINE_INDEX_WIDTH-1:0] metadata_write_index;
  wire [TAG_WIDTH-1:0] load_tag;
  wire [TAG_WIDTH-1:0] store_tag;
  wire [TAG_WIDTH-1:0] load1_tag;
  wire [TAG_WIDTH-1:0] store1_tag;
  wire [TAG_WIDTH-1:0] cache_op_tag;
  wire [TAG_WIDTH-1:0] metadata_write_tag;
  wire metadata_write_valid_bit;
  wire metadata_write_dirty_bit;
  wire [VALUE_WIDTH-1:0] data_read_word;
  wire [TAG_WIDTH-1:0] metadata_read_tag;
  wire metadata_read_valid;
  wire metadata_read_dirty;
  wire [TAG_WIDTH-1:0] dirty_victim_tag;
  wire [LINE_INDEX_WIDTH-1:0] dirty_victim_line_index;
  wire [VALUE_WIDTH-1:0] dirty_victim_base_addr;
  wire clean_wb_fire;
  wire clean_wb_done;
  wire [CLEAN_BEAT_INDEX_WIDTH-1:0] req_load_beat_index;
  wire [CLEAN_BEAT_INDEX_WIDTH-1:0] store_beat_index;
  wire [CLEAN_BEAT_INDEX_WIDTH-1:0] req_load1_beat_index;
  wire [CLEAN_BEAT_INDEX_WIDTH-1:0] store1_beat_index;
  wire req_load_word_is_hi;
  wire store_word_is_hi;
  wire req_load1_word_is_hi;
  wire store1_word_is_hi;
  wire load_backend_blocked;
  wire lookup_empty;
  wire lookup_push_ready;
  wire [1:0] lookup_count;
  wire lookup_valid;
  wire lookup_ready;
  wire lookup1_ready;
  wire lookup1_valid;
  wire [SEQ_ID_WIDTH-1:0] lookup_seq_id;
  wire [EPOCH_WIDTH-1:0] lookup_epoch;
  wire [VALUE_WIDTH-1:0] lookup_addr;
  wire [1:0] lookup_size;
  wire lookup_signed;
  wire [SEQ_ID_WIDTH-1:0] lookup1_seq_id;
  wire [EPOCH_WIDTH-1:0] lookup1_epoch;
  wire [VALUE_WIDTH-1:0] lookup1_addr;
  wire [1:0] lookup1_size;
  wire lookup1_signed;
  wire lookup_pop;
  wire lookup_park;
  wire pair_lookup_ready;
  wire pair_lookup1_ready;
  wire registered_select_valid;
  wire registered_select_index;
  wire registered_select_hit;
  wire registered_park0;
  wire registered_classify_valid;
  wire registered_classify_index;
  wire [VALUE_WIDTH-1:0] registered_classify_addr;
  wire registered_candidate0_valid;
  wire registered_candidate0_classified;
  wire registered_candidate0_hit;
  wire registered_candidate0_dirty;
  wire [TAG_WIDTH-1:0] registered_candidate0_dirty_tag;
  wire [LOOKUP_BUNDLE_WIDTH-1:0] registered_candidate0_bundle;
  wire registered_candidate1_valid;
  wire registered_candidate1_classified;
  wire registered_candidate1_hit;
  wire registered_candidate1_dirty;
  wire [TAG_WIDTH-1:0] registered_candidate1_dirty_tag;
  wire [LOOKUP_BUNDLE_WIDTH-1:0] registered_candidate1_bundle;
  wire registered_oldest_index;
  wire registered_candidate0_phase_match;
  wire registered_candidate1_phase_match;
  wire registered_miss_ready;
  wire registered_metadata_hit;
  wire registered_dirty_conflict;
  wire hybrid_bypass;
  wire hybrid_lane1_replay;
  wire hybrid_pair_wait;
  wire lookup_buffered;
  wire lookup_debug_bypass;
  wire lookup_debug_push_fire;
  wire lookup_debug_parked;
  wire lookup_debug_phase_wait;
  wire load_hit_queue_accept;
  wire load_hit_queue_fire;
  wire hit_under_miss_fire;
  wire hit_queue_alloc_ready;
  wire hit_queue_buffered_alloc_ready;
  wire [1:0] hit_queue_alloc_slot;
  wire hit_queue_alloc1_ready;
  wire hit_queue_buffered_alloc1_ready;
  wire [1:0] hit_queue_alloc1_slot;
  wire hit_queue_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] hit_queue_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] hit_queue_complete_epoch;
  wire [VALUE_WIDTH-1:0] hit_queue_complete_addr;
  wire [1:0] hit_queue_complete_size;
  wire hit_queue_complete_signed;
  wire [VALUE_WIDTH-1:0] hit_queue_complete_word;
  wire [2:0] hit_queue_count;
  wire store_backend_blocked;
  wire load1_same_line;
  wire store1_same_line;
  wire data_lsu_valid;
  wire data_lsu_write;
  wire [LINE_INDEX_WIDTH-1:0] data_lsu_line_index;
  wire [CLEAN_BEAT_INDEX_WIDTH-1:0] data_lsu_beat_index;
  wire data_lsu_word_hi;
  wire [63:0] data_lsu_wdata;
  wire [7:0] data_lsu_wstrb;
  wire data_lsu_rvalid;
  wire [63:0] data_lsu_rdata;
  wire data_lsu1_valid;
  wire data_lsu1_write;
  wire [LINE_INDEX_WIDTH-1:0] data_lsu1_line_index;
  wire [CLEAN_BEAT_INDEX_WIDTH-1:0] data_lsu1_beat_index;
  wire data_lsu1_word_hi;
  wire [63:0] data_lsu1_wdata;
  wire [7:0] data_lsu1_wstrb;
  wire data_lsu1_rvalid;
  wire [63:0] data_lsu1_rdata;
  wire clean_wb_read_valid;
  wire refill_data_write_valid;
  wire data_mem_valid;
  wire data_mem_ready;
  wire data_mem_write;
  wire [LINE_INDEX_WIDTH-1:0] data_mem_line_index;
  wire [CLEAN_BEAT_INDEX_WIDTH-1:0] data_mem_beat_index;
  wire [127:0] data_mem_wdata;
  wire [15:0] data_mem_wstrb;
  wire data_mem_rvalid;
  wire [127:0] data_mem_rdata;
  wire mshr_miss_ready;
  wire mshr_active;
  wire mshr_complete;
  wire mshr_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] mshr_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] mshr_complete_epoch;
  wire [VALUE_WIDTH-1:0] mshr_complete_addr;
  wire [1:0] mshr_complete_size;
  wire mshr_complete_signed;
  wire mshr_complete_error;
  wire [VALUE_WIDTH-1:0] mshr_complete_word;
  wire [VALUE_WIDTH-1:0] mshr_active_addr;
  wire [LINE_INDEX_WIDTH-1:0] mshr_line_index;
  wire [TAG_WIDTH-1:0] mshr_tag;
  wire [CLEAN_BEAT_INDEX_WIDTH-1:0] mshr_refill_beat;
  wire mshr_refill_store_valid;
  wire [127:0] mshr_refill_store_data;

  assign clean_wb_busy = clean_wb_active_q || clean_wb_wait_complete_q;
  assign clean_wb_complete_fire = clean_wb_complete && clean_wb_wait_complete_q;
  assign lookup_buffered = LOOKUP_REGISTERED || LOOKUP_HYBRID;
  assign hybrid_bypass = LOOKUP_HYBRID && lookup_empty &&
                         lsu_load_req_valid;
  assign hybrid_lane1_replay = hybrid_bypass && load_fire && lookup1_valid &&
                               !load1_fire;
  assign hybrid_pair_wait = hybrid_bypass && lookup1_valid &&
    load_metadata_hit && load1_same_line &&
    (!data_mem_valid || (lookup1_addr[4] == phase_q)) &&
    (lookup1_addr[4:3] != lookup_addr[4:3]) && !hit_queue_alloc1_ready;
  assign registered_classify_valid = lookup_buffered && !hybrid_bypass &&
    ((registered_candidate0_valid && !registered_candidate0_classified) ||
     (registered_candidate1_valid && !registered_candidate1_classified));
  assign registered_classify_index =
    registered_candidate0_valid && !registered_candidate0_classified ? 1'b0 :
    1'b1;
  assign registered_classify_addr = registered_classify_index ?
    registered_candidate1_bundle[LOOKUP_ADDR0_LSB +: VALUE_WIDTH] :
    registered_candidate0_bundle[LOOKUP_ADDR0_LSB +: VALUE_WIDTH];
  assign registered_metadata_hit = metadata_read_valid &&
    metadata_read_tag == registered_classify_addr[
      LINE_OFFSET_WIDTH + LINE_INDEX_WIDTH +: TAG_WIDTH];
  assign registered_dirty_conflict = metadata_read_valid &&
    metadata_read_dirty && !registered_metadata_hit;
  assign registered_miss_ready = !backend_load_pause && !clean_wb_busy &&
    mshr_miss_ready;
  assign registered_candidate0_phase_match =
    (!data_mem_valid ||
     registered_candidate0_bundle[LOOKUP_ADDR0_LSB + 4] == phase_q) &&
    !backend_load_pause && !clean_wb_busy &&
    (!mshr_active ||
     (
      registered_candidate0_bundle[
        LOOKUP_ADDR0_LSB + LINE_OFFSET_WIDTH +: LINE_INDEX_WIDTH] !=
        mshr_line_index && !mshr_complete));
  assign registered_candidate1_phase_match =
    (!data_mem_valid ||
     registered_candidate1_bundle[LOOKUP_ADDR0_LSB + 4] == phase_q) &&
    !backend_load_pause && !clean_wb_busy &&
    (!mshr_active ||
     (
      registered_candidate1_bundle[
        LOOKUP_ADDR0_LSB + LINE_OFFSET_WIDTH +: LINE_INDEX_WIDTH] !=
        mshr_line_index && !mshr_complete));
  assign cache_op_complete_valid =
    clean_immediate_complete_valid_q || clean_wb_complete_valid_q;
  assign cache_op_complete_seq_id = clean_immediate_complete_valid_q ?
    clean_immediate_complete_seq_id_q : clean_wb_seq_id_q;
  assign cache_op_complete_epoch = clean_immediate_complete_valid_q ?
    clean_immediate_complete_epoch_q : clean_wb_epoch_q;
  assign load_hit_queue_accept =
    hit_queue_alloc_ready && load_metadata_hit &&
    (!mshr_active ||
     ((load_line_index != mshr_line_index) && !mshr_complete));
  assign load_backend_blocked =
    backend_load_pause || clean_wb_busy ||
    (load_metadata_hit ? !load_hit_queue_accept :
     !mshr_miss_ready);
  assign lsu_load_req_ready = lookup_push_ready;
  assign lsu_load_req1_ready = lsu_load_req_ready && lsu_load_req_valid;
  assign store_metadata_hit =
    metadata_read_valid &&
    (metadata_read_tag[TAG_WIDTH-1:0] == store_tag[TAG_WIDTH-1:0]);
  assign store_dirty_conflict =
    lsu_store_req_valid && !lsu_load_req_valid &&
    metadata_read_valid && metadata_read_dirty && !store_metadata_hit;
  assign store_dirty_conflict_start =
    store_dirty_conflict && !clean_wb_busy && !mshr_active &&
    !backend_store_pause;
  assign store_refill_miss =
    lsu_store_req_valid && !lsu_load_req_valid &&
    !store_metadata_hit &&
    (metadata_read_valid || lsu_store_req_size != 2'b11);
  assign store_miss_refill_fire =
    store_refill_miss && !store_dirty_conflict &&
    !backend_store_pause && !clean_wb_busy && !mshr_active &&
    lookup_empty && !registered_classify_valid && mshr_miss_ready;
  assign store_backend_blocked =
    backend_store_pause || clean_wb_busy || lsu_load_req_valid ||
    mshr_active || !lookup_empty || registered_classify_valid ||
    store_dirty_conflict || store_refill_miss;
  assign load1_same_line =
    (load1_line_index == load_line_index) &&
    (load1_tag[TAG_WIDTH-1:0] == load_tag[TAG_WIDTH-1:0]);
  assign store1_same_line =
    (store1_line_index == store_line_index) &&
    (store1_tag[TAG_WIDTH-1:0] == store_tag[TAG_WIDTH-1:0]);
  assign lookup_ready = lookup_buffered ?
    (hybrid_bypass ? (pair_lookup_ready && !hybrid_pair_wait) :
                     registered_select_valid) :
    pair_lookup_ready;
  assign lookup1_ready = lookup_buffered ?
    (hybrid_bypass ? pair_lookup1_ready :
      (lookup1_valid && lookup_valid && registered_select_hit &&
       hit_queue_buffered_alloc1_ready && load1_same_line &&
       (!data_mem_valid || (lookup1_addr[4] == phase_q)) &&
       (lookup1_addr[4:3] != lookup_addr[4:3]))) : pair_lookup1_ready;
  assign load_fire = lookup_valid && lookup_ready;
  assign load_hit_queue_fire = load_fire && load_metadata_hit;
  // Simulation-visible classification retained for the hit-under-miss report.
  assign hit_under_miss_fire = load_hit_queue_fire && mshr_active;
  assign load1_fire = lookup1_valid && lookup1_ready;
  assign load_metadata_hit = lookup_buffered && !hybrid_bypass ?
    registered_select_hit :
    (metadata_read_valid &&
     (metadata_read_tag[TAG_WIDTH-1:0] == load_tag[TAG_WIDTH-1:0]));
  assign load_dirty_conflict =
    lookup_buffered && !hybrid_bypass ?
      (lookup_valid && (registered_select_index ?
        registered_candidate1_dirty : registered_candidate0_dirty)) :
      (lookup_valid && metadata_read_valid && metadata_read_dirty &&
       (metadata_read_tag[TAG_WIDTH-1:0] != load_tag[TAG_WIDTH-1:0]));
  assign load_dirty_conflict_fire = load_fire && load_dirty_conflict;
  assign load_hit_fire = load_fire && load_metadata_hit;
  assign load1_hit_fire = load1_fire && load_hit_fire;
  assign load_miss_fire = load_fire && !load_metadata_hit;
  assign lookup_pop = load_fire;
  assign lookup_park = lookup_buffered ? registered_park0 :
    (lookup_valid && !load_metadata_hit &&
     !mshr_miss_ready);
  assign store_fire = lsu_store_req_valid && lsu_store_req_ready;
  assign store1_fire = lsu_store_req1_valid && lsu_store_req1_ready;
  assign cache_op_ready =
    !store_fire && !clean_wb_busy && !mshr_active &&
    (hit_queue_count == 3'd0) && lookup_empty;
  assign cache_op_fire = cache_op_valid && cache_op_ready;
  assign cache_op_va_fire = cache_op_fire && cache_op_is_va;
  assign cache_op_clean_va_fire = cache_op_va_fire && cache_op_kind[0];
  assign cache_op_invalidate_va_fire =
    cache_op_va_fire && cache_op_kind[1];
  assign cache_op_metadata_hit =
    cache_op_va_fire &&
    metadata_read_valid &&
    (metadata_read_tag[TAG_WIDTH-1:0] == cache_op_tag[TAG_WIDTH-1:0]);
  assign cache_op_clean_dirty_hit =
    cache_op_clean_va_fire && cache_op_metadata_hit && metadata_read_dirty;
  wire pending_resp_valid = mshr_complete_valid && !mshr_store_refill_q;
  assign lsu_load_resp_valid =
    pending_resp_valid || hit_queue_complete_valid;
  assign lsu_load_resp_seq_id = pending_resp_valid ? mshr_complete_seq_id :
                                                     hit_queue_complete_seq_id;
  assign lsu_load_resp_epoch = pending_resp_valid ? mshr_complete_epoch :
                                                    hit_queue_complete_epoch;
  assign lsu_load_resp_error = pending_resp_valid && mshr_complete_error;
  assign lsu_load_resp_value = pending_resp_valid ? format_load_value(
    mshr_complete_word,
    mshr_complete_addr[BYTE_OFFSET_WIDTH-1:0],
    mshr_complete_size,
    mshr_complete_signed
  ) : format_load_value(
    hit_queue_complete_word,
    hit_queue_complete_addr[BYTE_OFFSET_WIDTH-1:0],
    hit_queue_complete_size,
    hit_queue_complete_signed
  );
  assign load_word_index =
    lookup_addr[BYTE_OFFSET_WIDTH +: WORD_INDEX_WIDTH];
  assign store_word_index =
    lsu_store_req_addr[BYTE_OFFSET_WIDTH +: WORD_INDEX_WIDTH];
  assign load1_word_index =
    lookup1_addr[BYTE_OFFSET_WIDTH +: WORD_INDEX_WIDTH];
  assign store1_word_index =
    lsu_store_req1_addr[BYTE_OFFSET_WIDTH +: WORD_INDEX_WIDTH];
  assign load_line_index =
    lookup_addr[LINE_OFFSET_WIDTH +: LINE_INDEX_WIDTH];
  assign store_line_index =
    lsu_store_req_addr[LINE_OFFSET_WIDTH +: LINE_INDEX_WIDTH];
  assign load1_line_index =
    lookup1_addr[LINE_OFFSET_WIDTH +: LINE_INDEX_WIDTH];
  assign store1_line_index =
    lsu_store_req1_addr[LINE_OFFSET_WIDTH +: LINE_INDEX_WIDTH];
  assign cache_op_line_index =
    cache_op_addr[LINE_OFFSET_WIDTH +: LINE_INDEX_WIDTH];
  assign load_tag =
    lookup_addr[LINE_OFFSET_WIDTH + LINE_INDEX_WIDTH +: TAG_WIDTH];
  assign store_tag =
    lsu_store_req_addr[LINE_OFFSET_WIDTH + LINE_INDEX_WIDTH +: TAG_WIDTH];
  assign load1_tag =
    lookup1_addr[LINE_OFFSET_WIDTH + LINE_INDEX_WIDTH +: TAG_WIDTH];
  assign store1_tag =
    lsu_store_req1_addr[LINE_OFFSET_WIDTH + LINE_INDEX_WIDTH +: TAG_WIDTH];
  assign cache_op_tag =
    cache_op_addr[LINE_OFFSET_WIDTH + LINE_INDEX_WIDTH +: TAG_WIDTH];
  assign mshr_line_index =
    mshr_active_addr[LINE_OFFSET_WIDTH +: LINE_INDEX_WIDTH];
  assign mshr_tag = mshr_active_addr[
    LINE_OFFSET_WIDTH + LINE_INDEX_WIDTH +: TAG_WIDTH];
  assign metadata_read_index =
    cache_op_valid && cache_op_is_va ? cache_op_line_index :
    lookup_buffered && registered_classify_valid ?
      registered_classify_addr[LINE_OFFSET_WIDTH +: LINE_INDEX_WIDTH] :
    (lsu_store_req_valid && !lsu_load_req_valid) ?
      store_line_index :
      load_line_index;
  assign metadata_write_valid =
    store_fire ||
    (cache_op_invalidate_va_fire && cache_op_metadata_hit) ||
    clean_wb_complete_fire ||
    (mshr_complete && !mshr_complete_error);
  assign metadata_write_index =
    cache_op_invalidate_va_fire ? cache_op_line_index :
    mshr_complete ? mshr_line_index :
    clean_wb_complete_fire ? clean_wb_line_index_q :
    store_line_index;
  assign metadata_write_tag =
    cache_op_invalidate_va_fire ? cache_op_tag :
    mshr_complete ? mshr_tag :
    clean_wb_complete_fire ? clean_writeback_tag_q :
    store_tag;
  assign metadata_write_valid_bit =
    (cache_op_invalidate_va_fire ||
     (clean_wb_complete_fire && clean_wb_invalidate_q)) ? 1'b0 : 1'b1;
  assign metadata_write_dirty_bit =
    (cache_op_invalidate_va_fire || clean_wb_complete_fire ||
     mshr_complete) ? 1'b0 : 1'b1;
  assign debug_icache_bytes = ICACHE_BYTES;
  assign debug_dcache_bytes = DCACHE_BYTES;
  assign debug_load_pending = mshr_active || (hit_queue_count != 3'd0);
  assign debug_load_miss_pending = mshr_active;
  assign debug_store_fire = store_fire;
  assign store_predict_phase = phase_q;
  assign store_predict_mem_active = data_mem_valid;
  assign store_predict_backend_blocked = store_backend_blocked;
  assign debug_cache_op_fire = cache_op_fire;
  assign debug_cache_op_kind = cache_op_kind[1:0];
  assign debug_cache_op_is_va = cache_op_is_va;
  assign clean_wb_valid = clean_wb_active_q && clean_wb_data_valid_q;
  assign clean_wb_addr =
    clean_wb_base_addr_q +
    {{(VALUE_WIDTH-CLEAN_BEAT_INDEX_WIDTH-4){1'b0}},
     clean_wb_beat_q, 4'b0000};
  assign clean_wb_data[127:0] = clean_wb_data_q[127:0];
  assign clean_wb_last =
    clean_wb_beat_q == CLEAN_LAST_BEAT;
  assign clean_wb_fire = clean_wb_valid && clean_wb_ready;
  assign clean_wb_done = clean_wb_fire && clean_wb_last;
  assign dirty_victim_line_index = store_dirty_conflict ?
    store_line_index : load_line_index;
  assign dirty_victim_tag = store_dirty_conflict ? metadata_read_tag :
    (lookup_buffered && !hybrid_bypass) ?
    (registered_select_index ? registered_candidate1_dirty_tag :
                               registered_candidate0_dirty_tag) :
    metadata_read_tag;
  assign dirty_victim_base_addr = {
    dirty_victim_tag[TAG_WIDTH-1:0],
    dirty_victim_line_index[LINE_INDEX_WIDTH-1:0],
    {LINE_OFFSET_WIDTH{1'b0}}
  };
  assign req_load_beat_index =
    lookup_addr[4 +: CLEAN_BEAT_INDEX_WIDTH];
  assign store_beat_index =
    lsu_store_req_addr[4 +: CLEAN_BEAT_INDEX_WIDTH];
  assign req_load1_beat_index =
    lookup1_addr[4 +: CLEAN_BEAT_INDEX_WIDTH];
  assign store1_beat_index =
    lsu_store_req1_addr[4 +: CLEAN_BEAT_INDEX_WIDTH];
  assign req_load_word_is_hi = lookup_addr[3];
  assign store_word_is_hi = lsu_store_req_addr[3];
  assign req_load1_word_is_hi = lookup1_addr[3];
  assign store1_word_is_hi = lsu_store_req1_addr[3];
  assign data_lsu_valid = load_hit_fire || store_fire;
  assign data_lsu_write = store_fire;
  assign data_lsu_line_index = store_fire ? store_line_index : load_line_index;
  assign data_lsu_beat_index = store_fire ? store_beat_index : req_load_beat_index;
  assign data_lsu_word_hi = store_fire ? store_word_is_hi : req_load_word_is_hi;
  assign data_lsu_wdata = lsu_store_req_data;
  assign data_lsu_wstrb = lsu_store_req_wstrb;
  assign data_read_word = data_lsu_rdata;
  assign data_lsu1_valid = load1_hit_fire || store1_fire;
  assign data_lsu1_write = store1_fire;
  assign data_lsu1_line_index = store1_fire ? store1_line_index : load1_line_index;
  assign data_lsu1_beat_index = store1_fire ? store1_beat_index : req_load1_beat_index;
  assign data_lsu1_word_hi = store1_fire ? store1_word_is_hi : req_load1_word_is_hi;
  assign data_lsu1_wdata = lsu_store_req1_data;
  assign data_lsu1_wstrb = lsu_store_req1_wstrb;
  assign clean_wb_read_valid = clean_wb_active_q && !clean_wb_data_valid_q;
  assign refill_data_write_valid = mshr_refill_store_valid;
  assign data_mem_valid = clean_wb_read_valid || refill_data_write_valid;
  assign data_mem_write = refill_data_write_valid && !clean_wb_read_valid;
  assign data_mem_line_index = clean_wb_read_valid ?
    clean_wb_line_index_q : mshr_line_index;
  assign data_mem_beat_index = clean_wb_read_valid ?
    clean_wb_beat_q : mshr_refill_beat;
  assign data_mem_wdata = mshr_refill_store_data;
  assign data_mem_wstrb = 16'hffff;

  edge_dcache_pair_predictor #(
    .VALUE_WIDTH(VALUE_WIDTH)
  ) pair_predictor (
    .phase(phase_q),
    .mem_active(data_mem_valid),
    .load0_valid(lookup_valid),
    .load0_addr(lookup_addr),
    .load1_valid(lookup1_valid),
    .load1_addr(lookup1_addr),
    .load_metadata_hit(load_metadata_hit),
    .load_dirty_conflict(load_dirty_conflict),
    .load_backend_blocked(load_backend_blocked),
    .load1_same_line(load1_same_line && hit_queue_alloc1_ready),
    .load0_ready(pair_lookup_ready),
    .load1_ready(pair_lookup1_ready),
    .load1_same_bank_conflict(),
    .store0_valid(lsu_store_req_valid),
    .store0_addr(lsu_store_req_addr),
    .store1_valid(lsu_store_req1_valid),
    .store1_addr(lsu_store_req1_addr),
    .store_backend_blocked(store_backend_blocked),
    .store1_same_line(store1_same_line),
    .store0_ready(lsu_store_req_ready),
    .store1_ready(lsu_store_req1_ready),
    .store1_same_bank_conflict()
  );

  generate
    if (!LOOKUP_REGISTERED && !LOOKUP_HYBRID) begin : gen_fallthrough_lookup
      edge_dcache_lookup_buffer #(
        .SEQ_ID_WIDTH(SEQ_ID_WIDTH), .EPOCH_WIDTH(EPOCH_WIDTH),
        .VALUE_WIDTH(VALUE_WIDTH)
      ) lookup_buffer (
        .clk(forever_cpuclk), .reset_b(cpurst_b),
        .redirect_valid(redirect_kill_valid),
        .redirect_seq_id(redirect_kill_seq_id),
        .redirect_epoch(redirect_kill_epoch),
        .push_valid(lsu_load_req_valid), .push_ready(lookup_push_ready),
        .push_seq_id(lsu_load_req_seq_id), .push_epoch(lsu_load_req_epoch),
        .push_addr(lsu_load_req_addr), .push_size(lsu_load_req_size),
        .push_signed(lsu_load_req_signed),
        .push1_valid(lsu_load_req1_valid && lsu_load_req1_ready),
        .push1_seq_id(lsu_load_req1_seq_id),
        .push1_epoch(lsu_load_req1_epoch), .push1_addr(lsu_load_req1_addr),
        .push1_size(lsu_load_req1_size),
        .push1_signed(lsu_load_req1_signed),
        .lookup_valid(lookup_valid), .lookup_seq_id(lookup_seq_id),
        .lookup_epoch(lookup_epoch), .lookup_addr(lookup_addr),
        .lookup_size(lookup_size), .lookup_signed(lookup_signed),
        .lookup1_valid(lookup1_valid), .lookup1_seq_id(lookup1_seq_id),
        .lookup1_epoch(lookup1_epoch), .lookup1_addr(lookup1_addr),
        .lookup1_size(lookup1_size), .lookup1_signed(lookup1_signed),
        .lookup_pop(lookup_pop), .lookup1_pop(load1_fire),
        .lookup_park(lookup_park),
        .retry_parked(mshr_miss_ready),
        .empty(lookup_empty), .count(lookup_count)
      );
      assign registered_candidate0_valid = 1'b0;
      assign registered_candidate0_classified = 1'b0;
      assign registered_candidate0_hit = 1'b0;
      assign registered_candidate0_dirty = 1'b0;
      assign registered_candidate0_dirty_tag = {TAG_WIDTH{1'b0}};
      assign registered_candidate0_bundle = {LOOKUP_BUNDLE_WIDTH{1'b0}};
      assign registered_candidate1_valid = 1'b0;
      assign registered_candidate1_classified = 1'b0;
      assign registered_candidate1_hit = 1'b0;
      assign registered_candidate1_dirty = 1'b0;
      assign registered_candidate1_dirty_tag = {TAG_WIDTH{1'b0}};
      assign registered_candidate1_bundle = {LOOKUP_BUNDLE_WIDTH{1'b0}};
      assign registered_oldest_index = 1'b0;
      assign lookup_debug_bypass = lookup_buffer.bypass;
      assign lookup_debug_push_fire = lookup_buffer.push_fire;
      assign lookup_debug_parked = lookup_buffer.parked_q[0] ||
                                   lookup_buffer.parked_q[1];
      assign lookup_debug_phase_wait = lookup_valid && load_metadata_hit &&
        !load_backend_blocked && data_mem_valid && lookup_addr[4] != phase_q;
    end else begin : gen_registered_lookup
      edge_dcache_registered_lookup_buffer #(
        .SEQ_ID_WIDTH(SEQ_ID_WIDTH), .EPOCH_WIDTH(EPOCH_WIDTH),
        .VALUE_WIDTH(VALUE_WIDTH),
        .LINE_OFFSET_WIDTH(LINE_OFFSET_WIDTH),
        .LINE_INDEX_WIDTH(LINE_INDEX_WIDTH),
        .BUNDLE_WIDTH(LOOKUP_BUNDLE_WIDTH)
      ) registered_lookup_buffer (
        .clk(forever_cpuclk), .reset_b(cpurst_b),
        .redirect_valid(redirect_kill_valid),
        .redirect_seq_id(redirect_kill_seq_id),
        .redirect_epoch(redirect_kill_epoch),
        .push_valid(lsu_load_req_valid &&
                    (!(hybrid_bypass && load_fire) || hybrid_lane1_replay)),
        .push_ready(lookup_push_ready),
        .push_seq_id(hybrid_lane1_replay ? lsu_load_req1_seq_id :
                                          lsu_load_req_seq_id),
        .push_epoch(hybrid_lane1_replay ? lsu_load_req1_epoch :
                                         lsu_load_req_epoch),
        .push_addr(hybrid_lane1_replay ? lsu_load_req1_addr :
                                        lsu_load_req_addr),
        .push_size(hybrid_lane1_replay ? lsu_load_req1_size :
                                        lsu_load_req_size),
        .push_signed(hybrid_lane1_replay ? lsu_load_req1_signed :
                                          lsu_load_req_signed),
        .push_classified(hybrid_bypass),
        .push_hit(load_metadata_hit),
        .push_dirty_conflict(load_dirty_conflict),
        .push_dirty_tag(metadata_read_tag),
        .push1_valid(!hybrid_lane1_replay && lsu_load_req1_valid &&
                     lsu_load_req1_ready),
        .push1_seq_id(lsu_load_req1_seq_id),
        .push1_epoch(lsu_load_req1_epoch), .push1_addr(lsu_load_req1_addr),
        .push1_size(lsu_load_req1_size),
        .push1_signed(lsu_load_req1_signed),
        .classify_valid(registered_classify_valid),
        .classify_index(registered_classify_index),
        .classify_hit(registered_metadata_hit),
        .classify_dirty_conflict(registered_dirty_conflict),
        .classify_dirty_tag(metadata_read_tag),
        .invalidate_classification(metadata_write_valid),
        .pop_valid(load_fire && !hybrid_bypass),
        .pop_index(registered_select_index),
        .pop_lane1(load1_fire),
        .candidate0_valid(registered_candidate0_valid),
        .candidate0_classified(registered_candidate0_classified),
        .candidate0_hit(registered_candidate0_hit),
        .candidate0_dirty_conflict(registered_candidate0_dirty),
        .candidate0_dirty_tag(registered_candidate0_dirty_tag),
        .candidate0_bundle(registered_candidate0_bundle),
        .candidate1_valid(registered_candidate1_valid),
        .candidate1_classified(registered_candidate1_classified),
        .candidate1_hit(registered_candidate1_hit),
        .candidate1_dirty_conflict(registered_candidate1_dirty),
        .candidate1_dirty_tag(registered_candidate1_dirty_tag),
        .candidate1_bundle(registered_candidate1_bundle),
        .oldest_index(registered_oldest_index),
        .empty(lookup_empty), .count(lookup_count)
      );
      assign lookup_valid = hybrid_bypass ? lsu_load_req_valid :
                                            registered_select_valid;
      assign lookup_seq_id = hybrid_bypass ? lsu_load_req_seq_id :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_SEQ0_LSB +: SEQ_ID_WIDTH] :
        registered_candidate0_bundle[LOOKUP_SEQ0_LSB +: SEQ_ID_WIDTH];
      assign lookup_epoch = hybrid_bypass ? lsu_load_req_epoch :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_EPOCH0_LSB +: EPOCH_WIDTH] :
        registered_candidate0_bundle[LOOKUP_EPOCH0_LSB +: EPOCH_WIDTH];
      assign lookup_addr = hybrid_bypass ? lsu_load_req_addr :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_ADDR0_LSB +: VALUE_WIDTH] :
        registered_candidate0_bundle[LOOKUP_ADDR0_LSB +: VALUE_WIDTH];
      assign lookup_size = hybrid_bypass ? lsu_load_req_size :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_SIZE0_LSB +: 2] :
        registered_candidate0_bundle[LOOKUP_SIZE0_LSB +: 2];
      assign lookup_signed = hybrid_bypass ? lsu_load_req_signed :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_SIGNED0_BIT] :
        registered_candidate0_bundle[LOOKUP_SIGNED0_BIT];
      assign lookup1_valid = hybrid_bypass ? lsu_load_req1_valid :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_LANE1_VALID_BIT] :
        registered_candidate0_bundle[LOOKUP_LANE1_VALID_BIT];
      assign lookup1_seq_id = hybrid_bypass ? lsu_load_req1_seq_id :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_SEQ1_LSB +: SEQ_ID_WIDTH] :
        registered_candidate0_bundle[LOOKUP_SEQ1_LSB +: SEQ_ID_WIDTH];
      assign lookup1_epoch = hybrid_bypass ? lsu_load_req1_epoch :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_EPOCH1_LSB +: EPOCH_WIDTH] :
        registered_candidate0_bundle[LOOKUP_EPOCH1_LSB +: EPOCH_WIDTH];
      assign lookup1_addr = hybrid_bypass ? lsu_load_req1_addr :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_ADDR1_LSB +: VALUE_WIDTH] :
        registered_candidate0_bundle[LOOKUP_ADDR1_LSB +: VALUE_WIDTH];
      assign lookup1_size = hybrid_bypass ? lsu_load_req1_size :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_SIZE1_LSB +: 2] :
        registered_candidate0_bundle[LOOKUP_SIZE1_LSB +: 2];
      assign lookup1_signed = hybrid_bypass ? lsu_load_req1_signed :
        registered_select_index ?
        registered_candidate1_bundle[LOOKUP_SIGNED1_BIT] :
        registered_candidate0_bundle[LOOKUP_SIGNED1_BIT];
      assign lookup_debug_bypass = hybrid_bypass && load_fire;
      assign lookup_debug_push_fire = lsu_load_req_valid && lookup_push_ready &&
                                      !(hybrid_bypass && load_fire);
      assign lookup_debug_parked = registered_park0;
      assign lookup_debug_phase_wait =
        (registered_candidate0_valid && registered_candidate0_classified &&
         registered_candidate0_hit &&
         !registered_candidate0_phase_match) ||
        (registered_candidate1_valid && registered_candidate1_classified &&
         registered_candidate1_hit &&
         !registered_candidate1_phase_match);
    end
  endgenerate

  edge_dcache_lookup_scheduler lookup_scheduler (
    .oldest_index(registered_oldest_index),
    .candidate0_valid(registered_candidate0_valid),
    .candidate0_classified(registered_candidate0_classified),
    .candidate0_hit(registered_candidate0_hit),
    .candidate0_phase_match(registered_candidate0_phase_match),
    .candidate1_valid(registered_candidate1_valid),
    .candidate1_classified(registered_candidate1_classified),
    .candidate1_hit(registered_candidate1_hit),
    .candidate1_phase_match(registered_candidate1_phase_match),
    .hit_ready(hit_queue_buffered_alloc_ready),
    .miss_ready(registered_miss_ready),
    .select_valid(registered_select_valid),
    .select_index(registered_select_index),
    .select_hit(registered_select_hit),
    .park_candidate0(registered_park0)
  );

  edge_dcache_mshr #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .LINE_OFFSET_WIDTH(LINE_OFFSET_WIDTH),
    .BEAT_INDEX_WIDTH(CLEAN_BEAT_INDEX_WIDTH)
  ) mshr (
    .forever_cpuclk(forever_cpuclk), .cpurst_b(cpurst_b),
    .redirect_valid(redirect_kill_valid),
    .redirect_seq_id(redirect_kill_seq_id),
    .redirect_epoch(redirect_kill_epoch),
    .miss_valid(load_miss_fire || store_miss_refill_fire),
    .miss_ready(mshr_miss_ready),
    .miss_addr(store_miss_refill_fire ? lsu_store_req_addr : lookup_addr),
    .miss_seq_id(store_miss_refill_fire ? lsu_store_req_seq_id :
                                          lookup_seq_id),
    .miss_epoch(store_miss_refill_fire ? lsu_store_req_epoch : lookup_epoch),
    .miss_size(store_miss_refill_fire ? lsu_store_req_size : lookup_size),
    .miss_signed(store_miss_refill_fire ? 1'b0 : lookup_signed),
    .miss_wait_writeback(store_miss_refill_fire ? 1'b0 :
                                                  load_dirty_conflict),
    .miss_allocate(),
    .victim_writeback_complete(clean_wb_complete_fire &&
                               clean_wb_for_refill_q),
    .refill_req_valid(refill_req_valid),
    .refill_req_ready(refill_req_ready),
    .refill_req_addr(refill_req_addr),
    .refill_resp_valid(refill_resp_valid),
    .refill_resp_ready(refill_resp_ready),
    .refill_resp_data(refill_resp_data),
    .refill_resp_last(refill_resp_last),
    .refill_resp_error(refill_resp_error),
    .refill_store_ready(data_mem_ready),
    .refill_store_valid(mshr_refill_store_valid),
    .refill_store_beat(mshr_refill_beat),
    .refill_store_data(mshr_refill_store_data),
    .complete(mshr_complete), .complete_valid(mshr_complete_valid),
    .complete_seq_id(mshr_complete_seq_id),
    .complete_epoch(mshr_complete_epoch),
    .complete_addr(mshr_complete_addr),
    .complete_size(mshr_complete_size),
    .complete_signed(mshr_complete_signed),
    .complete_error(mshr_complete_error),
    .complete_word(mshr_complete_word),
    .active(mshr_active), .refill_active(),
    .active_addr(mshr_active_addr), .active_beat()
  );

  edge_dcache_hit_queue #(
    .DEPTH(4),
    .PTR_WIDTH(2),
    .COUNT_WIDTH(3),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .LOAD_LATENCY(LOAD_LATENCY),
    .LATENCY_WIDTH(LATENCY_WIDTH)
  ) hit_queue (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .redirect_valid(redirect_kill_valid),
    .redirect_seq_id(redirect_kill_seq_id),
    .redirect_epoch(redirect_kill_epoch),
    .alloc0_valid(load_hit_queue_fire),
    .alloc0_ready(hit_queue_alloc_ready),
    .alloc0_buffered_ready(hit_queue_buffered_alloc_ready),
    .alloc0_slot(hit_queue_alloc_slot),
    .alloc0_seq_id(lookup_seq_id),
    .alloc0_epoch(lookup_epoch),
    .alloc0_addr(lookup_addr),
    .alloc0_size(lookup_size),
    .alloc0_signed(lookup_signed),
    .alloc1_valid(load1_hit_fire),
    .alloc1_ready(hit_queue_alloc1_ready),
    .alloc1_buffered_ready(hit_queue_buffered_alloc1_ready),
    .alloc1_slot(hit_queue_alloc1_slot),
    .alloc1_seq_id(lookup1_seq_id),
    .alloc1_epoch(lookup1_epoch),
    .alloc1_addr(lookup1_addr),
    .alloc1_size(lookup1_size),
    .alloc1_signed(lookup1_signed),
    .capture0_valid(data_lsu_rvalid && hit_read_valid_q),
    .capture0_slot(hit_read_slot_q),
    .capture0_word(data_read_word),
    .capture1_valid(data_lsu1_rvalid && hit_read1_valid_q),
    .capture1_slot(hit_read1_slot_q),
    .capture1_word(data_lsu1_rdata),
    .complete_valid(hit_queue_complete_valid),
    .complete_ready(!pending_resp_valid),
    .complete_seq_id(hit_queue_complete_seq_id),
    .complete_epoch(hit_queue_complete_epoch),
    .complete_addr(hit_queue_complete_addr),
    .complete_size(hit_queue_complete_size),
    .complete_signed(hit_queue_complete_signed),
    .complete_word(hit_queue_complete_word),
    .debug_count(hit_queue_count)
  );

  edge_dcache_banked_data_array #(
    .LINE_COUNT(LINES),
    .LINE_INDEX_WIDTH(LINE_INDEX_WIDTH)
  ) data_array (
    .clk(forever_cpuclk),
    .reset_b(cpurst_b),
    .phase(phase_q),
    .lsu0_valid(data_lsu_valid),
    .lsu0_ready(),
    .lsu0_write(data_lsu_write),
    .lsu0_line_index(data_lsu_line_index),
    .lsu0_beat_index(data_lsu_beat_index),
    .lsu0_word_hi(data_lsu_word_hi),
    .lsu0_wdata(data_lsu_wdata),
    .lsu0_wstrb(data_lsu_wstrb),
    .lsu0_rvalid(data_lsu_rvalid),
    .lsu0_rdata(data_lsu_rdata),
    .lsu1_valid(data_lsu1_valid),
    .lsu1_ready(),
    .lsu1_write(data_lsu1_write),
    .lsu1_line_index(data_lsu1_line_index),
    .lsu1_beat_index(data_lsu1_beat_index),
    .lsu1_word_hi(data_lsu1_word_hi),
    .lsu1_wdata(data_lsu1_wdata),
    .lsu1_wstrb(data_lsu1_wstrb),
    .lsu1_rvalid(data_lsu1_rvalid),
    .lsu1_rdata(data_lsu1_rdata),
    .mem_valid(data_mem_valid),
    .mem_ready(data_mem_ready),
    .mem_write(data_mem_write),
    .mem_line_index(data_mem_line_index),
    .mem_beat_index(data_mem_beat_index),
    .mem_wdata(data_mem_wdata),
    .mem_wstrb(data_mem_wstrb),
    .mem_rvalid(data_mem_rvalid),
    .mem_rdata(data_mem_rdata)
  );

  edge_dcache_tag_array #(
    .TAG_WIDTH(TAG_WIDTH),
    .LINES(LINES)
  ) tag_array (
    .clk(forever_cpuclk),
    .write_valid(metadata_write_valid),
    .write_index(metadata_write_index),
    .write_tag(metadata_write_tag),
    .write_valid_bit(metadata_write_valid_bit),
    .read_index(metadata_read_index),
    .read_tag(metadata_read_tag),
    .read_valid_bit(metadata_read_valid)
  );

  edge_dcache_dirty_array #(
    .LINES(LINES)
  ) dirty_array (
    .clk(forever_cpuclk),
    .write_valid(metadata_write_valid),
    .write_index(metadata_write_index),
    .write_dirty_bit(metadata_write_dirty_bit),
    .read_index(metadata_read_index),
    .read_dirty_bit(metadata_read_dirty)
  );

  function [VALUE_WIDTH-1:0] format_load_value;
    input [VALUE_WIDTH-1:0] word;
    input [BYTE_OFFSET_WIDTH-1:0] byte_offset;
    input [1:0] size;
    input load_signed;
    reg [VALUE_WIDTH-1:0] shifted;
    reg [7:0] byte_value;
    reg [15:0] half_value;
    reg [31:0] word_value;
    begin
      shifted = word >> {byte_offset, 3'b000};
      byte_value = shifted[7:0];
      half_value = shifted[15:0];
      word_value = shifted[31:0];
      case (size)
        2'b00: format_load_value = load_signed ?
               {{(VALUE_WIDTH-8){byte_value[7]}}, byte_value} :
               {{(VALUE_WIDTH-8){1'b0}}, byte_value};
        2'b01: format_load_value = load_signed ?
               {{(VALUE_WIDTH-16){half_value[15]}}, half_value} :
               {{(VALUE_WIDTH-16){1'b0}}, half_value};
        2'b10: format_load_value = load_signed ?
               {{(VALUE_WIDTH-32){word_value[31]}}, word_value} :
               {{(VALUE_WIDTH-32){1'b0}}, word_value};
        default: format_load_value = shifted;
      endcase
    end
  endfunction

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      clean_writeback_req_q <= 1'b0;
      clean_writeback_addr_q <= {VALUE_WIDTH{1'b0}};
      clean_writeback_line_index_q <= {LINE_INDEX_WIDTH{1'b0}};
      clean_writeback_tag_q <= {TAG_WIDTH{1'b0}};
      clean_immediate_complete_valid_q <= 1'b0;
      clean_immediate_complete_seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
      clean_immediate_complete_epoch_q <= {EPOCH_WIDTH{1'b0}};
      clean_wb_complete_valid_q <= 1'b0;
      clean_wb_seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
      clean_wb_epoch_q <= {EPOCH_WIDTH{1'b0}};
      clean_wb_active_q <= 1'b0;
      clean_wb_wait_complete_q <= 1'b0;
      clean_wb_for_refill_q <= 1'b0;
      clean_wb_for_cache_op_q <= 1'b0;
      clean_wb_invalidate_q <= 1'b0;
      mshr_store_refill_q <= 1'b0;
      clean_wb_beat_q <= {CLEAN_BEAT_INDEX_WIDTH{1'b0}};
      clean_wb_base_addr_q <= {VALUE_WIDTH{1'b0}};
      clean_wb_line_index_q <= {LINE_INDEX_WIDTH{1'b0}};
      phase_q <= 1'b0;
      hit_read_valid_q <= 1'b0;
      hit_read_slot_q <= 2'b00;
      hit_read1_valid_q <= 1'b0;
      hit_read1_slot_q <= 2'b00;
      clean_wb_data_valid_q <= 1'b0;
      clean_wb_data_q <= 128'b0;
    end else begin
      phase_q <= ~phase_q;
      clean_immediate_complete_valid_q <= cache_op_fire && !cache_op_clean_dirty_hit;
      clean_wb_complete_valid_q <=
        clean_wb_complete_fire && clean_wb_for_cache_op_q;
      if (store_miss_refill_fire) begin
        mshr_store_refill_q <= 1'b1;
      end else if (mshr_complete) begin
        mshr_store_refill_q <= 1'b0;
      end
      if (cache_op_fire && !cache_op_clean_dirty_hit) begin
        clean_immediate_complete_seq_id_q <= cache_op_seq_id;
        clean_immediate_complete_epoch_q <= cache_op_epoch;
      end

      clean_writeback_req_q <= cache_op_clean_dirty_hit ||
                               load_dirty_conflict_fire ||
                               store_dirty_conflict_start;
      if (cache_op_clean_dirty_hit) begin
        clean_writeback_addr_q <= cache_op_addr;
        clean_writeback_line_index_q <= cache_op_line_index;
        clean_writeback_tag_q <= cache_op_tag;
        clean_wb_seq_id_q <= cache_op_seq_id;
        clean_wb_epoch_q <= cache_op_epoch;
      end else if (load_dirty_conflict_fire) begin
        clean_writeback_addr_q <= dirty_victim_base_addr;
        clean_writeback_line_index_q <= load_line_index;
        clean_writeback_tag_q <= dirty_victim_tag;
      end else if (store_dirty_conflict_start) begin
        clean_writeback_addr_q <= dirty_victim_base_addr;
        clean_writeback_line_index_q <= store_line_index;
        clean_writeback_tag_q <= metadata_read_tag;
      end

      if (!clean_wb_active_q &&
          (cache_op_clean_dirty_hit || load_dirty_conflict_fire ||
           store_dirty_conflict_start)) begin
        clean_wb_active_q <= 1'b1;
        clean_wb_for_refill_q <= load_dirty_conflict_fire;
        clean_wb_for_cache_op_q <= cache_op_clean_dirty_hit;
        clean_wb_invalidate_q <= cache_op_clean_dirty_hit &&
                                 cache_op_invalidate_va_fire;
        clean_wb_beat_q <= {CLEAN_BEAT_INDEX_WIDTH{1'b0}};
        clean_wb_base_addr_q <= cache_op_clean_dirty_hit ?
          (cache_op_addr & ~{{(VALUE_WIDTH-LINE_OFFSET_WIDTH){1'b0}},
                             {LINE_OFFSET_WIDTH{1'b1}}}) :
          dirty_victim_base_addr;
        clean_wb_line_index_q <= cache_op_clean_dirty_hit ?
          cache_op_line_index : dirty_victim_line_index;
      end else if (clean_wb_done) begin
        clean_wb_active_q <= 1'b0;
        clean_wb_wait_complete_q <= 1'b1;
        clean_wb_data_valid_q <= 1'b0;
      end else if (clean_wb_complete_fire) begin
        clean_wb_wait_complete_q <= 1'b0;
        clean_wb_for_refill_q <= 1'b0;
        clean_wb_for_cache_op_q <= 1'b0;
        clean_wb_invalidate_q <= 1'b0;
      end else if (clean_wb_fire) begin
        clean_wb_data_valid_q <= 1'b0;
        clean_wb_beat_q <= clean_wb_beat_q +
          {{(CLEAN_BEAT_INDEX_WIDTH-1){1'b0}}, 1'b1};
      end
      if (data_mem_rvalid) begin
        clean_wb_data_valid_q <= 1'b1;
        clean_wb_data_q <= data_mem_rdata;
      end

      if (load_hit_queue_fire) begin
        hit_read_valid_q <= 1'b1;
        hit_read_slot_q <= hit_queue_alloc_slot;
      end else if (data_lsu_rvalid && hit_read_valid_q) begin
        hit_read_valid_q <= 1'b0;
      end
      if (load1_hit_fire) begin
        hit_read1_valid_q <= 1'b1;
        hit_read1_slot_q <= hit_queue_alloc1_slot;
      end else if (data_lsu1_rvalid && hit_read1_valid_q) begin
        hit_read1_valid_q <= 1'b0;
      end
    end
  end

`ifdef IVERILOG_SIM
  initial begin
    if (VALUE_WIDTH != 64) begin
      $display("EDGE_DCACHE CONFIG FAIL: VALUE_WIDTH must be 64");
      $finish;
    end
    if ((ICACHE_BYTES != (16 * 1024)) && (ICACHE_BYTES != (32 * 1024))) begin
      $display("EDGE_DCACHE CONFIG FAIL: ICACHE_BYTES must be 16KB or 32KB");
      $finish;
    end
    if ((DCACHE_BYTES != (16 * 1024)) && (DCACHE_BYTES != (32 * 1024))) begin
      $display("EDGE_DCACHE CONFIG FAIL: DCACHE_BYTES must be 16KB or 32KB");
      $finish;
    end
    if (LINE_BYTES != 64) begin
      $display("EDGE_DCACHE CONFIG FAIL: LINE_BYTES must be 64");
      $finish;
    end
  end
`endif

  wire unused_store = |{lsu_store_req_seq_id, lsu_store_req_epoch,
                        lsu_store_req_size};
  wire unused_metadata = |{load_tag, clean_writeback_req_q,
                           clean_writeback_addr_q,
                           clean_writeback_line_index_q,
                           clean_writeback_tag_q};
  wire unused_cache_op = |{cache_op_seq_id, cache_op_epoch, refill_resp_last};

endmodule
