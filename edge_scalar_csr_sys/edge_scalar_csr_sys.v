// Single-cycle scalar CSR/system/fence placeholder execute unit.
module edge_scalar_csr_sys #(
  parameter SEQ_ID_WIDTH    = 8,
  parameter EPOCH_WIDTH     = 4,
  parameter REG_INDEX_WIDTH = 5
) (
  input  wire                         sys_issue_valid,
  output wire                         sys_issue_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      sys_issue_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       sys_issue_epoch,
  input  wire                         sys_issue_is_fence,
  input  wire                         sys_issue_fence_i,
  input  wire [2:0]                   sys_issue_funct3,
  input  wire [11:0]                  sys_issue_csr,
  input  wire [REG_INDEX_WIDTH-1:0]   sys_issue_rd,
  input  wire [REG_INDEX_WIDTH-1:0]   sys_issue_rs1,

  output wire                         sys_complete_valid,
  output wire [SEQ_ID_WIDTH-1:0]      sys_complete_seq_id,
  output wire [EPOCH_WIDTH-1:0]       sys_complete_epoch,
  output wire                         system_placeholder_valid,
  output wire [2:0]                   system_placeholder_funct3,
  output wire [11:0]                  system_placeholder_csr,
  output wire [REG_INDEX_WIDTH-1:0]   system_placeholder_rd,
  output wire [REG_INDEX_WIDTH-1:0]   system_placeholder_rs1,
  output wire                         fence_placeholder_valid,
  output wire                         fence_placeholder_i
);

  assign sys_issue_ready = 1'b1;
  assign sys_complete_valid = sys_issue_valid && sys_issue_ready;
  assign sys_complete_seq_id = sys_issue_seq_id;
  assign sys_complete_epoch = sys_issue_epoch;

  assign system_placeholder_valid = sys_complete_valid && !sys_issue_is_fence;
  assign system_placeholder_funct3 = sys_issue_funct3;
  assign system_placeholder_csr = sys_issue_csr;
  assign system_placeholder_rd = sys_issue_rd;
  assign system_placeholder_rs1 = sys_issue_rs1;

  assign fence_placeholder_valid = sys_complete_valid && sys_issue_is_fence;
  assign fence_placeholder_i = sys_issue_fence_i;

endmodule
