// In-order retire queue with two-wide allocate and two-wide retire.
module edge_retire_sync #(
  parameter DEPTH        = 8,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH  = 4,
  parameter KIND_WIDTH   = 2
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,

  input  wire                         alloc0_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      alloc0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       alloc0_epoch,
  input  wire [KIND_WIDTH-1:0]        alloc0_kind,
  input  wire                         alloc0_serializing,
  input  wire                         alloc1_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      alloc1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       alloc1_epoch,
  input  wire [KIND_WIDTH-1:0]        alloc1_kind,
  input  wire                         alloc1_serializing,
  output wire                         alloc_ready,

  input  wire                         complete0_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      complete0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       complete0_epoch,
  input  wire                         complete1_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      complete1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       complete1_epoch,
  input  wire                         complete2_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      complete2_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       complete2_epoch,
  input  wire                         complete3_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      complete3_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       complete3_epoch,
  input  wire                         complete4_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      complete4_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       complete4_epoch,
  input  wire                         complete5_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      complete5_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       complete5_epoch,
  input  wire                         complete6_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      complete6_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       complete6_epoch,

  input  wire                         redirect_kill_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      redirect_kill_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       redirect_kill_epoch,

  output wire                         retire0_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire0_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire0_epoch,
  output wire [KIND_WIDTH-1:0]        retire0_kind,
  output wire                         retire1_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire1_epoch,
  output wire [KIND_WIDTH-1:0]        retire1_kind

`ifdef EDGE_DEBUG
  ,
  output wire [DEPTH-1:0]             debug_valid,
  output wire [DEPTH-1:0]             debug_done,
  output wire [31:0]                  debug_count
`endif
);

  localparam PTR_WIDTH = $clog2(DEPTH);
  localparam COUNT_WIDTH = $clog2(DEPTH + 1);
  localparam [COUNT_WIDTH:0] DEPTH_COUNT = DEPTH;
  localparam [COUNT_WIDTH:0] ALLOC_READY_MARGIN =
    {{(COUNT_WIDTH-1){1'b0}}, 2'd2};

  reg [DEPTH-1:0] valid;
  reg [DEPTH-1:0] done;
  reg [DEPTH-1:0] serializing;
  reg [SEQ_ID_WIDTH-1:0] seq_id [0:DEPTH-1];
  reg [EPOCH_WIDTH-1:0] epoch [0:DEPTH-1];
  reg [KIND_WIDTH-1:0] kind [0:DEPTH-1];
  reg [PTR_WIDTH-1:0] head;
  reg [PTR_WIDTH-1:0] tail;
  reg [COUNT_WIDTH-1:0] count;

  wire [PTR_WIDTH-1:0] head1;
  wire [PTR_WIDTH-1:0] tail1;
  assign head1 = head + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
  assign tail1 = tail + {{(PTR_WIDTH-1){1'b0}}, 1'b1};

  wire head_ready;
  wire head1_ready;
  assign head_ready = !redirect_kill_valid &&
                      (count != {COUNT_WIDTH{1'b0}}) &&
                      valid[head] &&
                      done[head];
  assign head1_ready = !redirect_kill_valid &&
                       (count > {{(COUNT_WIDTH-2){1'b0}}, 2'd1}) &&
                       valid[head1] &&
                       done[head1];

  assign retire0_valid = head_ready;
  assign retire0_seq_id = seq_id[head];
  assign retire0_epoch = epoch[head];
  assign retire0_kind = kind[head];
  assign retire1_valid = head_ready && !serializing[head] && head1_ready;
  assign retire1_seq_id = seq_id[head1];
  assign retire1_epoch = epoch[head1];
  assign retire1_kind = kind[head1];

  wire [1:0] retire_count;
  wire head_hole;
  wire [1:0] head_advance_count;
  wire [1:0] alloc_count;
  wire [1:0] accepted_alloc_count;
  wire [PTR_WIDTH-1:0] head_advance_ptr;
  wire [COUNT_WIDTH:0] free_after_retire;
  wire tail_slot_available;
  wire tail1_slot_available;
  reg queue_compact;
  reg [PTR_WIDTH-1:0] compact_scan_ptr;
  integer compact_scan_index;
  assign retire_count = retire1_valid ? 2'd2 : (retire0_valid ? 2'd1 : 2'd0);
  assign head_hole = !redirect_kill_valid &&
                     (count != {COUNT_WIDTH{1'b0}}) && !valid[head];
  assign head_advance_count = head_hole ? 2'd1 : retire_count;
  assign alloc_count = alloc0_valid ? (alloc1_valid ? 2'd2 : 2'd1) : 2'd0;
  assign accepted_alloc_count = alloc_ready ? alloc_count : 2'd0;
  assign head_advance_ptr = {{(PTR_WIDTH-2){1'b0}}, head_advance_count};
  assign free_after_retire = DEPTH_COUNT -
                             {1'b0, count} +
                             {{(COUNT_WIDTH-1){1'b0}}, retire_count};
  assign tail_slot_available = !valid[tail] ||
                               (retire0_valid && tail == head) ||
                               (retire1_valid && tail == head1);
  assign tail1_slot_available = !valid[tail1] ||
                                (retire0_valid && tail1 == head) ||
                                (retire1_valid && tail1 == head1);
  always @* begin
    queue_compact = 1'b1;
    for (compact_scan_index = 0; compact_scan_index < DEPTH;
         compact_scan_index = compact_scan_index + 1) begin
      compact_scan_ptr = head + compact_scan_index[PTR_WIDTH-1:0];
      if (compact_scan_index < count && !valid[compact_scan_ptr])
        queue_compact = 1'b0;
    end
    if (tail != head + count[PTR_WIDTH-1:0])
      queue_compact = 1'b0;
  end
  assign alloc_ready = !redirect_kill_valid &&
                       (free_after_retire >= ALLOC_READY_MARGIN) &&
                       queue_compact &&
                       tail_slot_available && tail1_slot_available;
`ifdef EDGE_DEBUG
  assign debug_valid = valid;
  assign debug_done = done;
  assign debug_count = {{(32-COUNT_WIDTH){1'b0}}, count};
`endif

  function complete_matches;
    input [SEQ_ID_WIDTH-1:0] entry_seq_id;
    input [EPOCH_WIDTH-1:0] entry_epoch;
    begin
      complete_matches = (complete0_valid &&
                          (complete0_seq_id == entry_seq_id) &&
                          (complete0_epoch == entry_epoch)) ||
                         (complete1_valid &&
                          (complete1_seq_id == entry_seq_id) &&
                          (complete1_epoch == entry_epoch)) ||
                         (complete2_valid &&
                          (complete2_seq_id == entry_seq_id) &&
                         (complete2_epoch == entry_epoch)) ||
                         (complete3_valid &&
                          (complete3_seq_id == entry_seq_id) &&
                          (complete3_epoch == entry_epoch)) ||
                         (complete4_valid &&
                          (complete4_seq_id == entry_seq_id) &&
                          (complete4_epoch == entry_epoch)) ||
                         (complete5_valid &&
                          (complete5_seq_id == entry_seq_id) &&
                          (complete5_epoch == entry_epoch)) ||
                         (complete6_valid &&
                          (complete6_seq_id == entry_seq_id) &&
                          (complete6_epoch == entry_epoch));
    end
  endfunction

  function killed_by_redirect;
    input entry_valid;
    input [SEQ_ID_WIDTH-1:0] entry_seq_id;
    input [EPOCH_WIDTH-1:0] entry_epoch;
    reg [SEQ_ID_WIDTH-1:0] seq_distance;
    begin
      seq_distance = entry_seq_id - redirect_kill_seq_id;
      killed_by_redirect = redirect_kill_valid &&
                           entry_valid &&
                           (entry_epoch == redirect_kill_epoch) &&
                           (seq_distance != {SEQ_ID_WIDTH{1'b0}}) &&
                           !seq_distance[SEQ_ID_WIDTH-1];
    end
  endfunction

  integer i;
  reg [COUNT_WIDTH-1:0] killed_count;
  reg [PTR_WIDTH-1:0] killed_tail_count;
  reg [PTR_WIDTH-1:0] tail_scan_ptr;
  reg tail_scan_active;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      valid <= {DEPTH{1'b0}};
      done <= {DEPTH{1'b0}};
      serializing <= {DEPTH{1'b0}};
      head <= {PTR_WIDTH{1'b0}};
      tail <= {PTR_WIDTH{1'b0}};
      count <= {COUNT_WIDTH{1'b0}};
      for (i = 0; i < DEPTH; i = i + 1) begin
        seq_id[i] <= {SEQ_ID_WIDTH{1'b0}};
        epoch[i] <= {EPOCH_WIDTH{1'b0}};
        kind[i] <= {KIND_WIDTH{1'b0}};
      end
    end else begin
      killed_count = {COUNT_WIDTH{1'b0}};
      killed_tail_count = {PTR_WIDTH{1'b0}};
      tail_scan_active = 1'b1;
      for (i = 0; i < DEPTH; i = i + 1) begin
        if (valid[i] && complete_matches(seq_id[i], epoch[i])) begin
          done[i] <= 1'b1;
        end
        if (killed_by_redirect(valid[i], seq_id[i], epoch[i])) begin
          valid[i] <= 1'b0;
          done[i] <= 1'b0;
          serializing[i] <= 1'b0;
          killed_count = killed_count + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        end
        tail_scan_ptr = tail - i[PTR_WIDTH-1:0] -
                        {{(PTR_WIDTH-1){1'b0}}, 1'b1};
        if (tail_scan_active &&
            killed_by_redirect(valid[tail_scan_ptr],
                               seq_id[tail_scan_ptr],
                               epoch[tail_scan_ptr])) begin
          killed_tail_count = killed_tail_count + 1'b1;
        end else begin
          tail_scan_active = 1'b0;
        end
      end

      if (retire0_valid) begin
        valid[head] <= 1'b0;
        done[head] <= 1'b0;
        serializing[head] <= 1'b0;
      end
      if (retire1_valid) begin
        valid[head1] <= 1'b0;
        done[head1] <= 1'b0;
        serializing[head1] <= 1'b0;
      end

      if (alloc_ready && alloc0_valid) begin
        valid[tail] <= 1'b1;
        done[tail] <= complete_matches(alloc0_seq_id, alloc0_epoch);
        serializing[tail] <= alloc0_serializing;
        seq_id[tail] <= alloc0_seq_id;
        epoch[tail] <= alloc0_epoch;
        kind[tail] <= alloc0_kind;
      end
      if (alloc_ready && alloc0_valid && alloc1_valid) begin
        valid[tail1] <= 1'b1;
        done[tail1] <= complete_matches(alloc1_seq_id, alloc1_epoch);
        serializing[tail1] <= alloc1_serializing;
        seq_id[tail1] <= alloc1_seq_id;
        epoch[tail1] <= alloc1_epoch;
        kind[tail1] <= alloc1_kind;
      end

      head <= head + head_advance_ptr;
      tail <= tail +
              {{(PTR_WIDTH-2){1'b0}}, accepted_alloc_count} -
              killed_tail_count;
      count <= count - {{(COUNT_WIDTH-2){1'b0}}, retire_count} +
               {{(COUNT_WIDTH-2){1'b0}}, accepted_alloc_count} -
               killed_count;
    end
  end

endmodule
