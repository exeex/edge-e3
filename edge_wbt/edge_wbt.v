// Shared writeback/dependency table primitive for one architectural domain.
module edge_wbt #(
  parameter REG_COUNT       = 32,
  parameter REG_INDEX_WIDTH = 5,
  parameter SEQ_ID_WIDTH    = 8,
  parameter EPOCH_WIDTH     = 4,
  parameter ISSUE1_ENABLE   = 1
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,

  input  wire                       issue_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    issue_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     issue_epoch,
  input  wire [REG_INDEX_WIDTH-1:0] issue_src0,
  input  wire                       issue_src0_valid,
  input  wire [REG_INDEX_WIDTH-1:0] issue_src1,
  input  wire                       issue_src1_valid,
  input  wire [REG_INDEX_WIDTH-1:0] issue_src2,
  input  wire                       issue_src2_valid,
  input  wire [REG_INDEX_WIDTH-1:0] issue_dst,
  input  wire                       issue_dst_valid,
  output wire                       issue_ready,
  input  wire                       issue1_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    issue1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     issue1_epoch,
  input  wire [REG_INDEX_WIDTH-1:0] issue1_src0,
  input  wire                       issue1_src0_valid,
  input  wire [REG_INDEX_WIDTH-1:0] issue1_src1,
  input  wire                       issue1_src1_valid,
  input  wire [REG_INDEX_WIDTH-1:0] issue1_src2,
  input  wire                       issue1_src2_valid,
  input  wire [REG_INDEX_WIDTH-1:0] issue1_dst,
  input  wire                       issue1_dst_valid,
  output wire                       issue1_ready,
  output wire                       src_ready,
  output wire                       dst_reserve_ready,
  output wire                       dependency_stall,

  input  wire                       complete_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    complete_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     complete_epoch,
  input  wire [REG_INDEX_WIDTH-1:0] complete_dst,
  input  wire                       complete2_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    complete2_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     complete2_epoch,
  input  wire [REG_INDEX_WIDTH-1:0] complete2_dst,
  input  wire                       complete3_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    complete3_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     complete3_epoch,
  input  wire [REG_INDEX_WIDTH-1:0] complete3_dst,
  input  wire                       complete4_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    complete4_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     complete4_epoch,
  input  wire [REG_INDEX_WIDTH-1:0] complete4_dst,

  input  wire                       redirect_kill_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    redirect_kill_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     redirect_kill_epoch,

  output wire [REG_COUNT-1:0]       debug_busy
);

  reg [REG_COUNT-1:0] busy;
  reg [SEQ_ID_WIDTH-1:0] busy_seq_id [0:REG_COUNT-1];
  reg [EPOCH_WIDTH-1:0] busy_epoch [0:REG_COUNT-1];

  function seq_is_younger;
    input [SEQ_ID_WIDTH-1:0] candidate;
    input [SEQ_ID_WIDTH-1:0] boundary;
    reg [SEQ_ID_WIDTH-1:0] distance;
    begin
      distance = candidate - boundary;
      seq_is_younger = (distance != {SEQ_ID_WIDTH{1'b0}}) &&
                       !distance[SEQ_ID_WIDTH-1];
    end
  endfunction

  wire src0_blocked;
  wire src1_blocked;
  wire src2_blocked;
  wire src0_released;
  wire src1_released;
  wire src2_released;
  wire dst_released;
  wire dst_blocked;
  wire issue0_fire;
  wire issue1_src0_blocked;
  wire issue1_src1_blocked;
  wire issue1_src2_blocked;
  wire issue1_dst_blocked;
  wire issue1_src0_released;
  wire issue1_src1_released;
  wire issue1_src2_released;
  wire issue1_dst_released;
  wire issue1_depends_on_issue0;
  wire issue1_waw_issue0;
  wire issue1_src_ready;
  wire issue1_dst_reserve_ready;

  assign src0_released = issue_src0_valid &&
                         ((complete_valid &&
                           (complete_dst == issue_src0) &&
                           (busy_seq_id[issue_src0] == complete_seq_id) &&
                           (busy_epoch[issue_src0] == complete_epoch)) ||
                          (complete2_valid &&
                           (complete2_dst == issue_src0) &&
                           (busy_seq_id[issue_src0] == complete2_seq_id) &&
                           (busy_epoch[issue_src0] == complete2_epoch)) ||
                          (complete3_valid &&
                           (complete3_dst == issue_src0) &&
                           (busy_seq_id[issue_src0] == complete3_seq_id) &&
                           (busy_epoch[issue_src0] == complete3_epoch)) ||
                          (complete4_valid &&
                           (complete4_dst == issue_src0) &&
                           (busy_seq_id[issue_src0] == complete4_seq_id) &&
                           (busy_epoch[issue_src0] == complete4_epoch)));
  assign src1_released = issue_src1_valid &&
                         ((complete_valid &&
                           (complete_dst == issue_src1) &&
                           (busy_seq_id[issue_src1] == complete_seq_id) &&
                           (busy_epoch[issue_src1] == complete_epoch)) ||
                          (complete2_valid &&
                           (complete2_dst == issue_src1) &&
                           (busy_seq_id[issue_src1] == complete2_seq_id) &&
                           (busy_epoch[issue_src1] == complete2_epoch)) ||
                          (complete3_valid &&
                           (complete3_dst == issue_src1) &&
                           (busy_seq_id[issue_src1] == complete3_seq_id) &&
                           (busy_epoch[issue_src1] == complete3_epoch)) ||
                          (complete4_valid &&
                           (complete4_dst == issue_src1) &&
                           (busy_seq_id[issue_src1] == complete4_seq_id) &&
                           (busy_epoch[issue_src1] == complete4_epoch)));
  assign src2_released = issue_src2_valid &&
                         ((complete_valid &&
                           (complete_dst == issue_src2) &&
                           (busy_seq_id[issue_src2] == complete_seq_id) &&
                           (busy_epoch[issue_src2] == complete_epoch)) ||
                          (complete2_valid &&
                           (complete2_dst == issue_src2) &&
                           (busy_seq_id[issue_src2] == complete2_seq_id) &&
                           (busy_epoch[issue_src2] == complete2_epoch)) ||
                          (complete3_valid &&
                           (complete3_dst == issue_src2) &&
                           (busy_seq_id[issue_src2] == complete3_seq_id) &&
                           (busy_epoch[issue_src2] == complete3_epoch)) ||
                          (complete4_valid &&
                           (complete4_dst == issue_src2) &&
                           (busy_seq_id[issue_src2] == complete4_seq_id) &&
                          (busy_epoch[issue_src2] == complete4_epoch)));
  assign dst_released = issue_dst_valid &&
                        ((complete_valid &&
                          (complete_dst == issue_dst) &&
                          (busy_seq_id[issue_dst] == complete_seq_id) &&
                          (busy_epoch[issue_dst] == complete_epoch)) ||
                         (complete2_valid &&
                          (complete2_dst == issue_dst) &&
                          (busy_seq_id[issue_dst] == complete2_seq_id) &&
                          (busy_epoch[issue_dst] == complete2_epoch)) ||
                         (complete3_valid &&
                          (complete3_dst == issue_dst) &&
                          (busy_seq_id[issue_dst] == complete3_seq_id) &&
                          (busy_epoch[issue_dst] == complete3_epoch)) ||
                         (complete4_valid &&
                          (complete4_dst == issue_dst) &&
                          (busy_seq_id[issue_dst] == complete4_seq_id) &&
                          (busy_epoch[issue_dst] == complete4_epoch)));
  assign src0_blocked = issue_src0_valid && busy[issue_src0] && !src0_released;
  assign src1_blocked = issue_src1_valid && busy[issue_src1] && !src1_released;
  assign src2_blocked = issue_src2_valid && busy[issue_src2] && !src2_released;
  assign dst_blocked = issue_dst_valid && busy[issue_dst] && !dst_released;
  assign issue0_fire = issue_valid && issue_ready && issue_dst_valid;

  assign issue1_src0_released = ISSUE1_ENABLE && issue1_src0_valid &&
                                ((complete_valid &&
                                  (complete_dst == issue1_src0) &&
                                  (busy_seq_id[issue1_src0] == complete_seq_id) &&
                                  (busy_epoch[issue1_src0] == complete_epoch)) ||
                                 (complete2_valid &&
                                  (complete2_dst == issue1_src0) &&
                                  (busy_seq_id[issue1_src0] == complete2_seq_id) &&
                                  (busy_epoch[issue1_src0] == complete2_epoch)) ||
                                 (complete3_valid &&
                                  (complete3_dst == issue1_src0) &&
                                  (busy_seq_id[issue1_src0] == complete3_seq_id) &&
                                  (busy_epoch[issue1_src0] == complete3_epoch)) ||
                                 (complete4_valid &&
                                  (complete4_dst == issue1_src0) &&
                                  (busy_seq_id[issue1_src0] == complete4_seq_id) &&
                                  (busy_epoch[issue1_src0] == complete4_epoch)));
  assign issue1_src1_released = ISSUE1_ENABLE && issue1_src1_valid &&
                                ((complete_valid &&
                                  (complete_dst == issue1_src1) &&
                                  (busy_seq_id[issue1_src1] == complete_seq_id) &&
                                  (busy_epoch[issue1_src1] == complete_epoch)) ||
                                 (complete2_valid &&
                                  (complete2_dst == issue1_src1) &&
                                  (busy_seq_id[issue1_src1] == complete2_seq_id) &&
                                  (busy_epoch[issue1_src1] == complete2_epoch)) ||
                                 (complete3_valid &&
                                  (complete3_dst == issue1_src1) &&
                                  (busy_seq_id[issue1_src1] == complete3_seq_id) &&
                                  (busy_epoch[issue1_src1] == complete3_epoch)) ||
                                 (complete4_valid &&
                                  (complete4_dst == issue1_src1) &&
                                  (busy_seq_id[issue1_src1] == complete4_seq_id) &&
                                  (busy_epoch[issue1_src1] == complete4_epoch)));
  assign issue1_src2_released = ISSUE1_ENABLE && issue1_src2_valid &&
                                ((complete_valid &&
                                  (complete_dst == issue1_src2) &&
                                  (busy_seq_id[issue1_src2] == complete_seq_id) &&
                                  (busy_epoch[issue1_src2] == complete_epoch)) ||
                                 (complete2_valid &&
                                  (complete2_dst == issue1_src2) &&
                                  (busy_seq_id[issue1_src2] == complete2_seq_id) &&
                                  (busy_epoch[issue1_src2] == complete2_epoch)) ||
                                 (complete3_valid &&
                                  (complete3_dst == issue1_src2) &&
                                  (busy_seq_id[issue1_src2] == complete3_seq_id) &&
                                  (busy_epoch[issue1_src2] == complete3_epoch)) ||
                                 (complete4_valid &&
                                  (complete4_dst == issue1_src2) &&
                                  (busy_seq_id[issue1_src2] == complete4_seq_id) &&
                                 (busy_epoch[issue1_src2] == complete4_epoch)));
  assign issue1_dst_released = ISSUE1_ENABLE && issue1_dst_valid &&
    ((complete_valid && (complete_dst == issue1_dst) &&
      (busy_seq_id[issue1_dst] == complete_seq_id) &&
      (busy_epoch[issue1_dst] == complete_epoch)) ||
     (complete2_valid && (complete2_dst == issue1_dst) &&
      (busy_seq_id[issue1_dst] == complete2_seq_id) &&
      (busy_epoch[issue1_dst] == complete2_epoch)) ||
     (complete3_valid && (complete3_dst == issue1_dst) &&
      (busy_seq_id[issue1_dst] == complete3_seq_id) &&
      (busy_epoch[issue1_dst] == complete3_epoch)) ||
     (complete4_valid && (complete4_dst == issue1_dst) &&
      (busy_seq_id[issue1_dst] == complete4_seq_id) &&
      (busy_epoch[issue1_dst] == complete4_epoch)));
  assign issue1_src0_blocked = ISSUE1_ENABLE && issue1_src0_valid && busy[issue1_src0] &&
                               !issue1_src0_released;
  assign issue1_src1_blocked = ISSUE1_ENABLE && issue1_src1_valid && busy[issue1_src1] &&
                               !issue1_src1_released;
  assign issue1_src2_blocked = ISSUE1_ENABLE && issue1_src2_valid && busy[issue1_src2] &&
                               !issue1_src2_released;
  assign issue1_depends_on_issue0 =
    ISSUE1_ENABLE && issue0_fire &&
    issue_dst_valid &&
    ((issue1_src0_valid && (issue1_src0 == issue_dst)) ||
     (issue1_src1_valid && (issue1_src1 == issue_dst)) ||
     (issue1_src2_valid && (issue1_src2 == issue_dst)));
  assign issue1_waw_issue0 = ISSUE1_ENABLE && issue0_fire && issue1_dst_valid &&
                             issue_dst_valid &&
                             (issue1_dst == issue_dst);
  assign issue1_dst_blocked = ISSUE1_ENABLE && issue1_dst_valid &&
                              ((busy[issue1_dst] && !issue1_dst_released) ||
                               issue1_waw_issue0);

  assign src_ready = !(src0_blocked || src1_blocked || src2_blocked);
  assign dst_reserve_ready = !dst_blocked;
  assign dependency_stall = !src_ready || !dst_reserve_ready;
  assign issue_ready = !dependency_stall;
  assign issue1_src_ready = !(issue1_src0_blocked ||
                              issue1_src1_blocked ||
                              issue1_src2_blocked ||
                              issue1_depends_on_issue0);
  assign issue1_dst_reserve_ready = !issue1_dst_blocked;
  assign issue1_ready = ISSUE1_ENABLE && issue1_src_ready && issue1_dst_reserve_ready;
  assign debug_busy = busy;

  integer i;
  reg killed;
  reg issue_this_entry;
  reg issue1_this_entry;
  reg complete0_this_entry;
  reg complete1_this_entry;
  reg complete2_this_entry;
  reg complete3_this_entry;
  reg complete_this_entry;
  reg complete_issue0_this_entry;
  reg complete_issue1_this_entry;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      busy <= {REG_COUNT{1'b0}};
      for (i = 0; i < REG_COUNT; i = i + 1) begin
        busy_seq_id[i] <= {SEQ_ID_WIDTH{1'b0}};
        busy_epoch[i] <= {EPOCH_WIDTH{1'b0}};
      end
    end else begin
      for (i = 0; i < REG_COUNT; i = i + 1) begin
        issue_this_entry = issue_valid &&
                           issue_ready &&
                           issue_dst_valid &&
                           (issue_dst == i[REG_INDEX_WIDTH-1:0]);
        issue1_this_entry = ISSUE1_ENABLE && issue1_valid &&
                            issue1_ready &&
                            issue1_dst_valid &&
                            (issue1_dst == i[REG_INDEX_WIDTH-1:0]);
        complete0_this_entry = complete_valid &&
                               (complete_dst == i[REG_INDEX_WIDTH-1:0]) &&
                               busy[i] &&
                               (busy_seq_id[i] == complete_seq_id) &&
                               (busy_epoch[i] == complete_epoch);
        complete1_this_entry = complete2_valid &&
                               (complete2_dst == i[REG_INDEX_WIDTH-1:0]) &&
                               busy[i] &&
                               (busy_seq_id[i] == complete2_seq_id) &&
                               (busy_epoch[i] == complete2_epoch);
        complete2_this_entry = complete3_valid &&
                               (complete3_dst == i[REG_INDEX_WIDTH-1:0]) &&
                               busy[i] &&
                               (busy_seq_id[i] == complete3_seq_id) &&
                               (busy_epoch[i] == complete3_epoch);
        complete3_this_entry = complete4_valid &&
                               (complete4_dst == i[REG_INDEX_WIDTH-1:0]) &&
                               busy[i] &&
                               (busy_seq_id[i] == complete4_seq_id) &&
                               (busy_epoch[i] == complete4_epoch);
        complete_this_entry = complete0_this_entry || complete1_this_entry ||
                              complete2_this_entry || complete3_this_entry;
        complete_issue0_this_entry = issue_this_entry &&
          ((complete_valid && (complete_dst == i[REG_INDEX_WIDTH-1:0]) &&
            (complete_seq_id == issue_seq_id) &&
            (complete_epoch == issue_epoch)) ||
           (complete2_valid && (complete2_dst == i[REG_INDEX_WIDTH-1:0]) &&
            (complete2_seq_id == issue_seq_id) &&
            (complete2_epoch == issue_epoch)) ||
           (complete3_valid && (complete3_dst == i[REG_INDEX_WIDTH-1:0]) &&
            (complete3_seq_id == issue_seq_id) &&
            (complete3_epoch == issue_epoch)) ||
           (complete4_valid && (complete4_dst == i[REG_INDEX_WIDTH-1:0]) &&
            (complete4_seq_id == issue_seq_id) &&
            (complete4_epoch == issue_epoch)));
        complete_issue1_this_entry = issue1_this_entry &&
          ((complete_valid && (complete_dst == i[REG_INDEX_WIDTH-1:0]) &&
            (complete_seq_id == issue1_seq_id) &&
            (complete_epoch == issue1_epoch)) ||
           (complete2_valid && (complete2_dst == i[REG_INDEX_WIDTH-1:0]) &&
            (complete2_seq_id == issue1_seq_id) &&
            (complete2_epoch == issue1_epoch)) ||
           (complete3_valid && (complete3_dst == i[REG_INDEX_WIDTH-1:0]) &&
            (complete3_seq_id == issue1_seq_id) &&
            (complete3_epoch == issue1_epoch)) ||
           (complete4_valid && (complete4_dst == i[REG_INDEX_WIDTH-1:0]) &&
            (complete4_seq_id == issue1_seq_id) &&
            (complete4_epoch == issue1_epoch)));
        killed = redirect_kill_valid &&
                 busy[i] &&
                 (busy_epoch[i] == redirect_kill_epoch) &&
                 seq_is_younger(busy_seq_id[i], redirect_kill_seq_id);

        if (killed) begin
          busy[i] <= 1'b0;
        end else if (issue1_this_entry) begin
          busy[i] <= !complete_issue1_this_entry;
          if (!complete_issue1_this_entry) begin
            busy_seq_id[i] <= issue1_seq_id;
            busy_epoch[i] <= issue1_epoch;
          end
        end else if (issue_this_entry) begin
          busy[i] <= !complete_issue0_this_entry;
          if (!complete_issue0_this_entry) begin
            busy_seq_id[i] <= issue_seq_id;
            busy_epoch[i] <= issue_epoch;
          end
        end else if (complete_this_entry) begin
          busy[i] <= 1'b0;
        end
      end
    end
  end

endmodule
