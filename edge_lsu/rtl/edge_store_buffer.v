// First-slice ordered store buffer for Edge scalar LSU.
module edge_store_buffer #(
  parameter DEPTH          = 8,
  parameter SEQ_ID_WIDTH   = 8,
  parameter EPOCH_WIDTH    = 4,
  parameter VALUE_WIDTH    = 64,
  parameter COUNT_WIDTH    = 4,
  parameter ENABLE_COMMITTED_DRAIN = 0
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,
  input  wire                         edge_dtcm_enable,
  input  wire [VALUE_WIDTH-1:0]       edge_dtcm_base,
  input  wire [VALUE_WIDTH-1:0]       edge_dtcm_mask,
  input  wire [SEQ_ID_WIDTH-1:0]      dtcm_pending_query_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       dtcm_pending_query_epoch,

  input  wire                         enqueue_valid,
  output wire                         enqueue_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      enqueue_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       enqueue_epoch,
  input  wire [VALUE_WIDTH-1:0]       enqueue_addr,
  input  wire [1:0]                   enqueue_size,
  input  wire [VALUE_WIDTH-1:0]       enqueue_data,
  input  wire [(VALUE_WIDTH/8)-1:0]   enqueue_wstrb,
  input  wire                         enqueue1_valid,
  output wire                         enqueue1_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      enqueue1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       enqueue1_epoch,
  input  wire [VALUE_WIDTH-1:0]       enqueue1_addr,
  input  wire [1:0]                   enqueue1_size,
  input  wire [VALUE_WIDTH-1:0]       enqueue1_data,
  input  wire [(VALUE_WIDTH/8)-1:0]   enqueue1_wstrb,

  input  wire                         commit0_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      commit0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       commit0_epoch,
  input  wire                         commit1_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      commit1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       commit1_epoch,

  output wire                         drain_valid,
  input  wire                         drain_ready,
  output wire [SEQ_ID_WIDTH-1:0]      drain_seq_id,
  output wire [EPOCH_WIDTH-1:0]       drain_epoch,
  output wire [VALUE_WIDTH-1:0]       drain_addr,
  output wire [1:0]                   drain_size,
  output wire [VALUE_WIDTH-1:0]       drain_data,
  output wire [(VALUE_WIDTH/8)-1:0]   drain_wstrb,
  output wire                         drain1_valid,
  input  wire                         drain1_ready,
  output wire [SEQ_ID_WIDTH-1:0]      drain1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       drain1_epoch,
  output wire [VALUE_WIDTH-1:0]       drain1_addr,
  output wire [1:0]                   drain1_size,
  output wire [VALUE_WIDTH-1:0]       drain1_data,
  output wire [(VALUE_WIDTH/8)-1:0]   drain1_wstrb,

  input  wire                         flush_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      flush_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       flush_epoch,

  output wire [COUNT_WIDTH-1:0]       debug_count,
  output wire [COUNT_WIDTH-1:0]       debug_committed_count,
  output wire                         debug_dtcm_pending
);

  localparam PTR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
  localparam [COUNT_WIDTH-1:0] DEPTH_COUNT = DEPTH[COUNT_WIDTH-1:0];
  localparam [PTR_WIDTH-1:0] LAST_PTR = DEPTH[PTR_WIDTH-1:0] -
                                        {{(PTR_WIDTH-1){1'b0}}, 1'b1};

  reg [SEQ_ID_WIDTH-1:0] seq_q [0:DEPTH-1];
  reg [EPOCH_WIDTH-1:0] epoch_q [0:DEPTH-1];
  reg [VALUE_WIDTH-1:0] addr_q [0:DEPTH-1];
  reg [1:0] size_q [0:DEPTH-1];
  reg [VALUE_WIDTH-1:0] data_q [0:DEPTH-1];
  reg [(VALUE_WIDTH/8)-1:0] wstrb_q [0:DEPTH-1];
  reg [PTR_WIDTH-1:0] head_q;
  reg [PTR_WIDTH-1:0] tail_q;
  reg [COUNT_WIDTH-1:0] count_q;
  reg [COUNT_WIDTH-1:0] committed_count_q;
  reg [COUNT_WIDTH-1:0] flush_keep_count;
  reg [COUNT_WIDTH-1:0] flush_base_count;
  reg [PTR_WIDTH-1:0] flush_scan_ptr;
  reg [PTR_WIDTH-1:0] flush_tail_ptr;
  reg flush_stop;
  reg [PTR_WIDTH-1:0] commit_base_ptr;

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

  wire drain_fire;
  wire drain1_fire;
  wire enqueue_fire;
  wire enqueue1_fire;
  wire [PTR_WIDTH-1:0] head_next;
  wire [PTR_WIDTH-1:0] head_plus_one;
  wire [PTR_WIDTH-1:0] head_plus_two;
  wire [PTR_WIDTH-1:0] tail_next;
  wire [PTR_WIDTH-1:0] tail_plus_one;
  wire [COUNT_WIDTH-1:0] free_count;
  wire [COUNT_WIDTH-1:0] free_after_drain;
  wire [COUNT_WIDTH-1:0] drain_count;
  wire [COUNT_WIDTH-1:0] uncommitted_count;
  wire [PTR_WIDTH-1:0] commit_second_ptr;
  wire commit0_matches_first;
  wire commit1_matches_first;
  wire commit1_matches_second;
  wire commit_first_match;
  wire commit_second_match;
  wire [1:0] commit_count;
  wire [COUNT_WIDTH:0] commit_count_ext;
  wire [COUNT_WIDTH:0] drain_count_ext;
  wire [COUNT_WIDTH:0] drain_eligible_count;
  wire [COUNT_WIDTH:0] committed_after_activity;
  reg dtcm_pending_comb;
  reg [PTR_WIDTH-1:0] dtcm_scan_ptr;

  assign uncommitted_count = count_q - committed_count_q;
  assign commit_second_ptr = (commit_base_ptr == LAST_PTR) ?
                             {PTR_WIDTH{1'b0}} :
                             (commit_base_ptr +
                              {{(PTR_WIDTH-1){1'b0}}, 1'b1});
  assign commit0_matches_first = ENABLE_COMMITTED_DRAIN &&
                                 (uncommitted_count != {COUNT_WIDTH{1'b0}}) &&
                                 commit0_valid &&
                                 (seq_q[commit_base_ptr] == commit0_seq_id) &&
                                 (epoch_q[commit_base_ptr] == commit0_epoch);
  assign commit1_matches_first = ENABLE_COMMITTED_DRAIN &&
                                 (uncommitted_count != {COUNT_WIDTH{1'b0}}) &&
                                 commit1_valid &&
                                 (seq_q[commit_base_ptr] == commit1_seq_id) &&
                                 (epoch_q[commit_base_ptr] == commit1_epoch);
  assign commit1_matches_second = ENABLE_COMMITTED_DRAIN &&
                                  (uncommitted_count >= 2) &&
                                  commit0_matches_first &&
                                  commit1_valid &&
                                  (seq_q[commit_second_ptr] == commit1_seq_id) &&
                                  (epoch_q[commit_second_ptr] == commit1_epoch);
  assign commit_first_match = commit0_matches_first || commit1_matches_first;
  assign commit_second_match = commit1_matches_second;
  assign commit_count = commit_second_match ? 2'd2 :
                        (commit_first_match ? 2'd1 : 2'd0);
  assign commit_count_ext = {{(COUNT_WIDTH-1){1'b0}}, commit_count};
  assign drain_count_ext = {1'b0, drain_count};
  assign drain_eligible_count = ENABLE_COMMITTED_DRAIN ?
                                ({1'b0, committed_count_q} + commit_count_ext) :
                                {1'b0, count_q};
  assign drain_valid = (count_q != {COUNT_WIDTH{1'b0}}) &&
                       (drain_eligible_count != {(COUNT_WIDTH+1){1'b0}});
  assign drain_fire = drain_valid && drain_ready;
  assign drain1_valid = (count_q >= {{(COUNT_WIDTH-2){1'b0}}, 2'd2}) &&
                         (drain_eligible_count >= 2) && drain_valid;
  assign drain1_fire = drain_fire && drain1_valid && drain1_ready;
  assign free_count = DEPTH_COUNT - count_q;
  assign drain_count = drain1_fire ?
                       {{(COUNT_WIDTH-2){1'b0}}, 2'd2} :
                       {{(COUNT_WIDTH-1){1'b0}}, drain_fire};
  assign committed_after_activity = {1'b0, committed_count_q} +
                                    commit_count_ext - drain_count_ext;
  assign free_after_drain = free_count + drain_count;
  assign enqueue_ready = (free_after_drain != {COUNT_WIDTH{1'b0}});
  assign enqueue1_ready = enqueue_valid ? (free_after_drain >= 2) :
                                           (free_after_drain != {COUNT_WIDTH{1'b0}});
  assign enqueue_fire = enqueue_valid && enqueue_ready;
  assign enqueue1_fire = enqueue1_valid && enqueue1_ready;

  assign drain_seq_id = seq_q[head_q];
  assign drain_epoch = epoch_q[head_q];
  assign drain_addr = addr_q[head_q];
  assign drain_size = size_q[head_q];
  assign drain_data = data_q[head_q];
  assign drain_wstrb = wstrb_q[head_q];
  assign drain1_seq_id = seq_q[head_plus_one];
  assign drain1_epoch = epoch_q[head_plus_one];
  assign drain1_addr = addr_q[head_plus_one];
  assign drain1_size = size_q[head_plus_one];
  assign drain1_data = data_q[head_plus_one];
  assign drain1_wstrb = wstrb_q[head_plus_one];
  assign debug_count = count_q;
  assign debug_committed_count = ENABLE_COMMITTED_DRAIN ?
                                 committed_count_q : count_q;
  assign debug_dtcm_pending = dtcm_pending_comb;

  integer dtcm_scan_i;
  always @(*) begin
    dtcm_pending_comb = 1'b0;
    dtcm_scan_ptr = head_q;
    for (dtcm_scan_i = 0; dtcm_scan_i < DEPTH;
         dtcm_scan_i = dtcm_scan_i + 1) begin
      if ((dtcm_scan_i < committed_count_q) &&
          edge_dtcm_enable &&
          (epoch_q[dtcm_scan_ptr] == dtcm_pending_query_epoch) &&
          !seq_is_younger(seq_q[dtcm_scan_ptr],
                          dtcm_pending_query_seq_id) &&
          ((addr_q[dtcm_scan_ptr] & edge_dtcm_mask) ==
           (edge_dtcm_base & edge_dtcm_mask))) begin
        dtcm_pending_comb = 1'b1;
      end
      if (dtcm_scan_i < committed_count_q) begin
        dtcm_scan_ptr = (dtcm_scan_ptr == LAST_PTR) ?
                        {PTR_WIDTH{1'b0}} :
                        (dtcm_scan_ptr +
                         {{(PTR_WIDTH-1){1'b0}}, 1'b1});
      end
    end
  end

  integer commit_scan_i;
  always @(*) begin
    commit_base_ptr = head_q;
    for (commit_scan_i = 0; commit_scan_i < DEPTH;
         commit_scan_i = commit_scan_i + 1) begin
      if (commit_scan_i < committed_count_q) begin
        commit_base_ptr = (commit_base_ptr == LAST_PTR) ?
                          {PTR_WIDTH{1'b0}} :
                          (commit_base_ptr +
                           {{(PTR_WIDTH-1){1'b0}}, 1'b1});
      end
    end
  end

  assign head_next = (head_q == LAST_PTR) ?
                     {PTR_WIDTH{1'b0}} :
                     (head_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1});
  assign head_plus_one = head_next;
  assign head_plus_two = (head_plus_one == LAST_PTR) ?
                         {PTR_WIDTH{1'b0}} :
                         (head_plus_one + {{(PTR_WIDTH-1){1'b0}}, 1'b1});
  assign tail_next = (tail_q == LAST_PTR) ?
                     {PTR_WIDTH{1'b0}} :
                     (tail_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1});
  assign tail_plus_one = (tail_next == LAST_PTR) ?
                         {PTR_WIDTH{1'b0}} :
                         (tail_next + {{(PTR_WIDTH-1){1'b0}}, 1'b1});

  integer i;
  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      head_q <= {PTR_WIDTH{1'b0}};
      tail_q <= {PTR_WIDTH{1'b0}};
      count_q <= {COUNT_WIDTH{1'b0}};
      committed_count_q <= {COUNT_WIDTH{1'b0}};
      for (i = 0; i < DEPTH; i = i + 1) begin
        seq_q[i] <= {SEQ_ID_WIDTH{1'b0}};
        epoch_q[i] <= {EPOCH_WIDTH{1'b0}};
        addr_q[i] <= {VALUE_WIDTH{1'b0}};
        size_q[i] <= 2'b00;
        data_q[i] <= {VALUE_WIDTH{1'b0}};
        wstrb_q[i] <= {(VALUE_WIDTH/8){1'b0}};
      end
    end else if (flush_valid) begin
      flush_scan_ptr = drain1_fire ? head_plus_two :
                       drain_fire ? head_next : head_q;
      flush_base_count = drain_fire ?
                         (count_q - drain_count) :
                         count_q;
      if (flush_seq_id == {SEQ_ID_WIDTH{1'b0}}) begin
        head_q <= flush_scan_ptr;
        tail_q <= flush_scan_ptr;
        count_q <= {COUNT_WIDTH{1'b0}};
        committed_count_q <= {COUNT_WIDTH{1'b0}};
      end else begin
        flush_keep_count = {COUNT_WIDTH{1'b0}};
        flush_tail_ptr = flush_scan_ptr;
        flush_stop = 1'b0;
        for (i = 0; i < DEPTH; i = i + 1) begin
          if ((i < flush_base_count) && !flush_stop) begin
            if ((epoch_q[flush_scan_ptr] == flush_epoch) &&
                seq_is_younger(seq_q[flush_scan_ptr], flush_seq_id)) begin
              flush_stop = 1'b1;
            end else begin
              flush_keep_count = flush_keep_count +
                                 {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
              flush_tail_ptr = (flush_scan_ptr == LAST_PTR) ?
                               {PTR_WIDTH{1'b0}} :
                               (flush_scan_ptr +
                                {{(PTR_WIDTH-1){1'b0}}, 1'b1});
              flush_scan_ptr = (flush_scan_ptr == LAST_PTR) ?
                               {PTR_WIDTH{1'b0}} :
                               (flush_scan_ptr +
                                {{(PTR_WIDTH-1){1'b0}}, 1'b1});
            end
          end
        end
        count_q <= flush_keep_count;
        committed_count_q <=
          (committed_after_activity > {1'b0, flush_keep_count}) ?
          flush_keep_count : committed_after_activity[COUNT_WIDTH-1:0];
        tail_q <= flush_tail_ptr;
        head_q <= drain1_fire ? head_plus_two :
                  drain_fire ? head_next : head_q;
      end
    end else begin
      committed_count_q <= committed_after_activity[COUNT_WIDTH-1:0];
      if (enqueue_fire) begin
        seq_q[tail_q] <= enqueue_seq_id;
        epoch_q[tail_q] <= enqueue_epoch;
        addr_q[tail_q] <= enqueue_addr;
        size_q[tail_q] <= enqueue_size;
        data_q[tail_q] <= enqueue_data;
        wstrb_q[tail_q] <= enqueue_wstrb;
      end

      if (enqueue1_fire) begin
        seq_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_seq_id;
        epoch_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_epoch;
        addr_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_addr;
        size_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_size;
        data_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_data;
        wstrb_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_wstrb;
      end

      if (enqueue_fire && enqueue1_fire) begin
        tail_q <= tail_plus_one;
      end else if (enqueue_fire || enqueue1_fire) begin
        tail_q <= tail_next;
      end

      if (drain_fire) begin
        head_q <= drain1_fire ? head_plus_two : head_next;
      end

      case ({enqueue_fire, enqueue1_fire, drain_fire})
        3'b100,
        3'b010: count_q <= count_q + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        3'b110: count_q <= count_q + {{(COUNT_WIDTH-2){1'b0}}, 2'd2};
        3'b001: count_q <= drain1_fire ?
                            (count_q - {{(COUNT_WIDTH-2){1'b0}}, 2'd2}) :
                            (count_q - {{(COUNT_WIDTH-1){1'b0}}, 1'b1});
        3'b101,
        3'b011: count_q <= drain1_fire ?
                            (count_q - {{(COUNT_WIDTH-1){1'b0}}, 1'b1}) :
                            count_q;
        3'b111: count_q <= drain1_fire ?
                            count_q :
                            (count_q + {{(COUNT_WIDTH-1){1'b0}}, 1'b1});
        default: count_q <= count_q;
      endcase
    end
  end

endmodule
