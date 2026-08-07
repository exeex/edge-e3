// First-slice FIFO for accepted scalar loads before backend request/response.
module edge_load_queue #(
  parameter DEPTH          = 8,
  parameter SEQ_ID_WIDTH   = 8,
  parameter EPOCH_WIDTH    = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter VALUE_WIDTH    = 64,
  parameter COUNT_WIDTH    = 4
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,

  input  wire                         enqueue_valid,
  output wire                         enqueue_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      enqueue_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       enqueue_epoch,
  input  wire [REG_INDEX_WIDTH-1:0]   enqueue_rd,
  input  wire                         enqueue_bank,
  input  wire                         enqueue_domain,
  input  wire [VALUE_WIDTH-1:0]       enqueue_addr,
  input  wire [1:0]                   enqueue_size,
  input  wire                         enqueue_load_signed,
  input  wire                         enqueue1_valid,
  output wire                         enqueue1_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      enqueue1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       enqueue1_epoch,
  input  wire [REG_INDEX_WIDTH-1:0]   enqueue1_rd,
  input  wire                         enqueue1_bank,
  input  wire                         enqueue1_domain,
  input  wire [VALUE_WIDTH-1:0]       enqueue1_addr,
  input  wire [1:0]                   enqueue1_size,
  input  wire                         enqueue1_load_signed,

  output wire                         request_valid,
  input  wire                         request_ready,
  output wire [SEQ_ID_WIDTH-1:0]      request_seq_id,
  output wire [EPOCH_WIDTH-1:0]       request_epoch,
  output wire [REG_INDEX_WIDTH-1:0]   request_rd,
  output wire                         request_bank,
  output wire                         request_domain,
  output wire [VALUE_WIDTH-1:0]       request_addr,
  output wire [1:0]                   request_size,
  output wire                         request_load_signed,
  output wire                         request1_valid,
  input  wire                         request1_ready,
  output wire [SEQ_ID_WIDTH-1:0]      request1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       request1_epoch,
  output wire [REG_INDEX_WIDTH-1:0]   request1_rd,
  output wire                         request1_bank,
  output wire                         request1_domain,
  output wire [VALUE_WIDTH-1:0]       request1_addr,
  output wire [1:0]                   request1_size,
  output wire                         request1_load_signed,

  input  wire                         backend_issue0_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      backend_issue0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       backend_issue0_epoch,
  input  wire                         backend_issue1_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      backend_issue1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       backend_issue1_epoch,

  input  wire                         complete_valid,
  output wire                         complete_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      complete_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       complete_epoch,
  output reg  [REG_INDEX_WIDTH-1:0]   complete_rd,
  output reg                          complete_bank,
  output reg                          complete_domain,
  output reg  [1:0]                   complete_size,

  input  wire                         flush_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      flush_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       flush_epoch,

  output wire [COUNT_WIDTH-1:0]       debug_count
);

  localparam PTR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
  localparam [COUNT_WIDTH-1:0] DEPTH_COUNT = DEPTH[COUNT_WIDTH-1:0];
  localparam [PTR_WIDTH-1:0] LAST_PTR = DEPTH[PTR_WIDTH-1:0] -
                                        {{(PTR_WIDTH-1){1'b0}}, 1'b1};

  reg [SEQ_ID_WIDTH-1:0] seq_q [0:DEPTH-1];
  reg [EPOCH_WIDTH-1:0] epoch_q [0:DEPTH-1];
  reg [REG_INDEX_WIDTH-1:0] rd_q [0:DEPTH-1];
  reg bank_q [0:DEPTH-1];
  reg domain_q [0:DEPTH-1];
  reg [VALUE_WIDTH-1:0] addr_q [0:DEPTH-1];
  reg [1:0] size_q [0:DEPTH-1];
  reg load_signed_q [0:DEPTH-1];
  reg request_sent_q [0:DEPTH-1];
  reg request_queued_q [0:DEPTH-1];
  reg response_done_q [0:DEPTH-1];
  reg [PTR_WIDTH-1:0] head_q;
  reg [PTR_WIDTH-1:0] tail_q;
  reg [COUNT_WIDTH-1:0] count_q;
  reg [COUNT_WIDTH-1:0] flush_keep_count;
  reg [COUNT_WIDTH-1:0] flush_base_count;
  reg [PTR_WIDTH-1:0] flush_scan_ptr;
  reg [PTR_WIDTH-1:0] flush_tail_ptr;
  reg flush_stop;
  reg [PTR_WIDTH-1:0] complete_scan_ptr;
  reg [PTR_WIDTH-1:0] complete_match_ptr;
  reg complete_match;
  reg [PTR_WIDTH-1:0] backend_scan_ptr;
  reg [PTR_WIDTH-1:0] backend_issue0_ptr;
  reg [PTR_WIDTH-1:0] backend_issue1_ptr;
  reg backend_issue0_match;
  reg backend_issue1_match;

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

  wire request_fire;
  wire request1_fire;
  wire complete_fire;
  wire retire_fire;
  wire enqueue_fire;
  wire enqueue1_fire;
  wire [PTR_WIDTH-1:0] head_next;
  wire [PTR_WIDTH-1:0] tail_next;
  wire [PTR_WIDTH-1:0] tail_plus_one;
  wire [COUNT_WIDTH-1:0] free_count;
  wire [COUNT_WIDTH-1:0] free_after_complete;

  assign request_valid = (count_q != {COUNT_WIDTH{1'b0}}) &&
                         !request_queued_q[head_q];
  assign request_fire = request_valid && request_ready;
  assign request1_valid = (count_q >= {{(COUNT_WIDTH-2){1'b0}}, 2'd2}) &&
                          request_valid &&
                          !request_queued_q[head_next];
  assign request1_fire = request_fire && request1_valid && request1_ready;
  assign complete_ready = complete_match;
  assign complete_fire = complete_valid && complete_ready;
  assign retire_fire = (count_q != {COUNT_WIDTH{1'b0}}) &&
                       (response_done_q[head_q] ||
                        (complete_fire && (complete_match_ptr == head_q)));
  assign free_count = DEPTH_COUNT - count_q;
  assign free_after_complete = free_count +
                               {{(COUNT_WIDTH-1){1'b0}}, retire_fire};
  assign enqueue_ready = (free_after_complete != {COUNT_WIDTH{1'b0}});
  assign enqueue1_ready = enqueue_valid ? (free_after_complete >= 2) :
                                           (free_after_complete != {COUNT_WIDTH{1'b0}});
  assign enqueue_fire = enqueue_valid && enqueue_ready;
  assign enqueue1_fire = enqueue1_valid && enqueue1_ready;

  assign request_seq_id = seq_q[head_q];
  assign request_epoch = epoch_q[head_q];
  assign request_rd = rd_q[head_q];
  assign request_bank = bank_q[head_q];
  assign request_domain = domain_q[head_q];
  assign request_addr = addr_q[head_q];
  assign request_size = size_q[head_q];
  assign request_load_signed = load_signed_q[head_q];
  assign request1_seq_id = seq_q[head_next];
  assign request1_epoch = epoch_q[head_next];
  assign request1_rd = rd_q[head_next];
  assign request1_bank = bank_q[head_next];
  assign request1_domain = domain_q[head_next];
  assign request1_addr = addr_q[head_next];
  assign request1_size = size_q[head_next];
  assign request1_load_signed = load_signed_q[head_next];
  assign debug_count = count_q;

  integer scan_i;
  always @(*) begin
    complete_match = 1'b0;
    complete_match_ptr = head_q;
    complete_rd = {REG_INDEX_WIDTH{1'b0}};
    complete_bank = 1'b0;
    complete_domain = 1'b0;
    complete_size = 2'b00;
    backend_issue0_match = 1'b0;
    backend_issue1_match = 1'b0;
    backend_issue0_ptr = head_q;
    backend_issue1_ptr = head_q;
    backend_scan_ptr = head_q;
    for (scan_i = 0; scan_i < DEPTH; scan_i = scan_i + 1) begin
      if (scan_i < count_q) begin
        if (!backend_issue0_match && !request_sent_q[backend_scan_ptr] &&
            (seq_q[backend_scan_ptr] == backend_issue0_seq_id) &&
            (epoch_q[backend_scan_ptr] == backend_issue0_epoch)) begin
          backend_issue0_match = 1'b1;
          backend_issue0_ptr = backend_scan_ptr;
        end
        if (!backend_issue1_match && !request_sent_q[backend_scan_ptr] &&
            (seq_q[backend_scan_ptr] == backend_issue1_seq_id) &&
            (epoch_q[backend_scan_ptr] == backend_issue1_epoch)) begin
          backend_issue1_match = 1'b1;
          backend_issue1_ptr = backend_scan_ptr;
        end
      end
      backend_scan_ptr = (backend_scan_ptr == LAST_PTR) ?
                         {PTR_WIDTH{1'b0}} :
                         (backend_scan_ptr +
                          {{(PTR_WIDTH-1){1'b0}}, 1'b1});
    end
    complete_scan_ptr = head_q;
    for (scan_i = 0; scan_i < DEPTH; scan_i = scan_i + 1) begin
      if ((scan_i < count_q) && !complete_match &&
          (request_sent_q[complete_scan_ptr] ||
           (backend_issue0_valid && backend_issue0_match &&
            (complete_scan_ptr == backend_issue0_ptr)) ||
           (backend_issue1_valid && backend_issue1_match &&
            (complete_scan_ptr == backend_issue1_ptr))) &&
          !response_done_q[complete_scan_ptr] &&
          (seq_q[complete_scan_ptr] == complete_seq_id) &&
          (epoch_q[complete_scan_ptr] == complete_epoch)) begin
        complete_match = 1'b1;
        complete_match_ptr = complete_scan_ptr;
        complete_rd = rd_q[complete_scan_ptr];
        complete_bank = bank_q[complete_scan_ptr];
        complete_domain = domain_q[complete_scan_ptr];
        complete_size = size_q[complete_scan_ptr];
      end
      complete_scan_ptr = (complete_scan_ptr == LAST_PTR) ?
                          {PTR_WIDTH{1'b0}} :
                          (complete_scan_ptr +
                           {{(PTR_WIDTH-1){1'b0}}, 1'b1});
    end
  end

  assign head_next = (head_q == LAST_PTR) ?
                     {PTR_WIDTH{1'b0}} :
                     (head_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1});
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
      for (i = 0; i < DEPTH; i = i + 1) begin
        seq_q[i] <= {SEQ_ID_WIDTH{1'b0}};
        epoch_q[i] <= {EPOCH_WIDTH{1'b0}};
        rd_q[i] <= {REG_INDEX_WIDTH{1'b0}};
        bank_q[i] <= 1'b0;
        domain_q[i] <= 1'b0;
        addr_q[i] <= {VALUE_WIDTH{1'b0}};
        size_q[i] <= 2'b00;
        load_signed_q[i] <= 1'b0;
        request_sent_q[i] <= 1'b0;
        request_queued_q[i] <= 1'b0;
        response_done_q[i] <= 1'b0;
      end
    end else if (flush_valid) begin
      // Backend acceptance remains real even when the queue shape is updated
      // by a redirect in the same cycle.  Record requests for any preserved
      // prefix entries so they cannot be issued a second time after the flush.
      if (request_fire) begin
        request_queued_q[head_q] <= 1'b1;
      end
      if (request1_fire) begin
        request_queued_q[head_next] <= 1'b1;
      end
      if (backend_issue0_valid && backend_issue0_match)
        request_sent_q[backend_issue0_ptr] <= 1'b1;
      if (backend_issue1_valid && backend_issue1_match)
        request_sent_q[backend_issue1_ptr] <= 1'b1;
      if (complete_fire) begin
        response_done_q[complete_match_ptr] <= 1'b1;
      end
      if (retire_fire) begin
        request_sent_q[head_q] <= 1'b0;
        request_queued_q[head_q] <= 1'b0;
        response_done_q[head_q] <= 1'b0;
      end
      flush_scan_ptr = retire_fire ? head_next : head_q;
      flush_base_count = retire_fire ?
                         (count_q - {{(COUNT_WIDTH-1){1'b0}}, 1'b1}) :
                         count_q;
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
      tail_q <= flush_tail_ptr;
      head_q <= retire_fire ? head_next : head_q;
    end else begin
      if (enqueue_fire) begin
        seq_q[tail_q] <= enqueue_seq_id;
        epoch_q[tail_q] <= enqueue_epoch;
        rd_q[tail_q] <= enqueue_rd;
        bank_q[tail_q] <= enqueue_bank;
        domain_q[tail_q] <= enqueue_domain;
        addr_q[tail_q] <= enqueue_addr;
        size_q[tail_q] <= enqueue_size;
        load_signed_q[tail_q] <= enqueue_load_signed;
        request_sent_q[tail_q] <= 1'b0;
        request_queued_q[tail_q] <= 1'b0;
        response_done_q[tail_q] <= 1'b0;
      end

      if (enqueue1_fire) begin
        seq_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_seq_id;
        epoch_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_epoch;
        rd_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_rd;
        bank_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_bank;
        domain_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_domain;
        addr_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_addr;
        size_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_size;
        load_signed_q[enqueue_fire ? tail_next : tail_q] <= enqueue1_load_signed;
        request_sent_q[enqueue_fire ? tail_next : tail_q] <= 1'b0;
        request_queued_q[enqueue_fire ? tail_next : tail_q] <= 1'b0;
        response_done_q[enqueue_fire ? tail_next : tail_q] <= 1'b0;
      end

      if (enqueue_fire && enqueue1_fire) begin
        tail_q <= tail_plus_one;
      end else if (enqueue_fire || enqueue1_fire) begin
        tail_q <= tail_next;
      end

      if (request_fire) begin
        request_queued_q[head_q] <= 1'b1;
      end
      if (request1_fire) begin
        request_queued_q[head_next] <= 1'b1;
      end
      if (backend_issue0_valid && backend_issue0_match)
        request_sent_q[backend_issue0_ptr] <= 1'b1;
      if (backend_issue1_valid && backend_issue1_match)
        request_sent_q[backend_issue1_ptr] <= 1'b1;

      if (complete_fire) begin
        response_done_q[complete_match_ptr] <= 1'b1;
      end

      if (retire_fire) begin
        request_sent_q[head_q] <= 1'b0;
        request_queued_q[head_q] <= 1'b0;
        response_done_q[head_q] <= 1'b0;
        head_q <= head_next;
      end

      case ({enqueue_fire, enqueue1_fire, retire_fire})
        3'b100,
        3'b010: count_q <= count_q + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        3'b110: count_q <= count_q + {{(COUNT_WIDTH-2){1'b0}}, 2'd2};
        3'b001: count_q <= count_q - {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        3'b101,
        3'b011: count_q <= count_q;
        3'b111: count_q <= count_q + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        default: count_q <= count_q;
      endcase
    end
  end

  wire unused_flush = |{flush_seq_id, flush_epoch};

endmodule
