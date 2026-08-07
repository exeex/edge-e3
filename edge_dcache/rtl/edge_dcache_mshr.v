// One-entry D-cache primary miss and refill controller.
module edge_dcache_mshr #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter VALUE_WIDTH = 64,
  parameter LINE_OFFSET_WIDTH = 6,
  parameter BEAT_INDEX_WIDTH = 2
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,
  input  wire                       redirect_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    redirect_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     redirect_epoch,

  input  wire                       miss_valid,
  output wire                       miss_ready,
  input  wire [VALUE_WIDTH-1:0]     miss_addr,
  input  wire [SEQ_ID_WIDTH-1:0]    miss_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     miss_epoch,
  input  wire [1:0]                 miss_size,
  input  wire                       miss_signed,
  input  wire                       miss_wait_writeback,
  output wire                       miss_allocate,

  input  wire                       victim_writeback_complete,

  output wire                       refill_req_valid,
  input  wire                       refill_req_ready,
  output wire [VALUE_WIDTH-1:0]     refill_req_addr,
  input  wire                       refill_resp_valid,
  output wire                       refill_resp_ready,
  input  wire [127:0]               refill_resp_data,
  input  wire                       refill_resp_last,
  input  wire                       refill_resp_error,
  input  wire                       refill_store_ready,
  output wire                       refill_store_valid,
  output wire [BEAT_INDEX_WIDTH-1:0] refill_store_beat,
  output wire [127:0]               refill_store_data,

  output wire                       complete,
  output wire                       complete_valid,
  output wire [SEQ_ID_WIDTH-1:0]    complete_seq_id,
  output wire [EPOCH_WIDTH-1:0]     complete_epoch,
  output wire [VALUE_WIDTH-1:0]     complete_addr,
  output wire [1:0]                 complete_size,
  output wire                       complete_signed,
  output wire                       complete_error,
  output wire [VALUE_WIDTH-1:0]     complete_word,

  output wire                       active,
  output wire                       refill_active,
  output wire [VALUE_WIDTH-1:0]     active_addr,
  output wire [BEAT_INDEX_WIDTH-1:0] active_beat
);

  reg valid_q;
  reg stale_q;
  reg wait_writeback_q;
  reg refill_req_valid_q;
  reg refill_active_q;
  reg complete_q;
  reg refill_error_q;
  reg [SEQ_ID_WIDTH-1:0] seq_id_q;
  reg [EPOCH_WIDTH-1:0] epoch_q;
  reg [VALUE_WIDTH-1:0] addr_q;
  reg [1:0] size_q;
  reg signed_q;
  reg [BEAT_INDEX_WIDTH-1:0] beat_q;
  reg [VALUE_WIDTH-1:0] selected_word_q;

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

  wire killed_now = redirect_valid && valid_q &&
    epoch_q == redirect_epoch && seq_is_younger(seq_id_q, redirect_seq_id);
  wire miss_killed_on_allocate = redirect_valid &&
    miss_epoch == redirect_epoch &&
    seq_is_younger(miss_seq_id, redirect_seq_id);
  wire miss_fire = miss_valid && miss_ready;
  wire refill_req_fire = refill_req_valid && refill_req_ready;
  wire refill_resp_fire = refill_resp_valid && refill_resp_ready;
  wire requested_beat = beat_q ==
    addr_q[4 +: BEAT_INDEX_WIDTH];
  wire requested_word_hi = addr_q[3];

  assign miss_ready = !valid_q;
  assign miss_allocate = miss_fire;
  assign refill_req_valid = refill_req_valid_q;
  assign refill_req_addr = addr_q &
    ~{{(VALUE_WIDTH-LINE_OFFSET_WIDTH){1'b0}},
      {LINE_OFFSET_WIDTH{1'b1}}};
  assign refill_resp_ready = refill_active_q && refill_store_ready;
  assign refill_store_valid = refill_resp_valid && refill_active_q &&
                              !refill_error_q && !refill_resp_error;
  assign refill_store_beat = beat_q;
  assign refill_store_data = refill_resp_data;
  assign complete = complete_q;
  assign complete_valid = complete_q && !stale_q && !killed_now;
  assign complete_seq_id = seq_id_q;
  assign complete_epoch = epoch_q;
  assign complete_addr = addr_q;
  assign complete_size = size_q;
  assign complete_signed = signed_q;
  assign complete_error = refill_error_q;
  assign complete_word = selected_word_q;
  assign active = valid_q;
  assign refill_active = refill_active_q;
  assign active_addr = addr_q;
  assign active_beat = beat_q;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      valid_q <= 1'b0;
      stale_q <= 1'b0;
      wait_writeback_q <= 1'b0;
      refill_req_valid_q <= 1'b0;
      refill_active_q <= 1'b0;
      complete_q <= 1'b0;
      refill_error_q <= 1'b0;
      seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
      epoch_q <= {EPOCH_WIDTH{1'b0}};
      addr_q <= {VALUE_WIDTH{1'b0}};
      size_q <= 2'b00;
      signed_q <= 1'b0;
      beat_q <= {BEAT_INDEX_WIDTH{1'b0}};
      selected_word_q <= {VALUE_WIDTH{1'b0}};
    end else begin
      complete_q <= 1'b0;
      if (killed_now)
        stale_q <= 1'b1;

      if (complete_q) begin
        valid_q <= 1'b0;
        stale_q <= 1'b0;
      end

      if (miss_fire) begin
        valid_q <= 1'b1;
        stale_q <= miss_killed_on_allocate;
        wait_writeback_q <= miss_wait_writeback;
        refill_req_valid_q <= !miss_wait_writeback;
        refill_active_q <= 1'b0;
        refill_error_q <= 1'b0;
        seq_id_q <= miss_seq_id;
        epoch_q <= miss_epoch;
        addr_q <= miss_addr;
        size_q <= miss_size;
        signed_q <= miss_signed;
        beat_q <= {BEAT_INDEX_WIDTH{1'b0}};
      end

      if (victim_writeback_complete && valid_q && wait_writeback_q) begin
        wait_writeback_q <= 1'b0;
        refill_req_valid_q <= 1'b1;
      end

      if (refill_req_fire) begin
        refill_req_valid_q <= 1'b0;
        refill_active_q <= 1'b1;
        beat_q <= {BEAT_INDEX_WIDTH{1'b0}};
      end

      if (refill_resp_fire) begin
        if (refill_resp_error)
          refill_error_q <= 1'b1;
        if (requested_beat)
          selected_word_q <= requested_word_hi ? refill_resp_data[127:64] :
                                                   refill_resp_data[63:0];
        if (refill_resp_last) begin
          refill_active_q <= 1'b0;
          complete_q <= 1'b1;
        end else begin
          beat_q <= beat_q + {{(BEAT_INDEX_WIDTH-1){1'b0}}, 1'b1};
        end
      end
    end
  end
endmodule
