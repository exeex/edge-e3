// Scalar-order GPR snapshot writer for tensor command operands.
module edge_scalar_snapshot #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter VALUE_WIDTH = 64,
  parameter SNAPSHOT_TARGET_WIDTH = 2
) (
  input  wire                         issue_valid,
  output wire                         issue_ready,
  input  wire [31:0]                  issue_inst,
  input  wire [SEQ_ID_WIDTH-1:0]      issue_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       issue_epoch,

  input  wire                         rs1_ready,
  input  wire [VALUE_WIDTH-1:0]       rs1_value,
  input  wire                         rs2_ready,
  input  wire [VALUE_WIDTH-1:0]       rs2_value,
  input  wire                         rd_ready,
  input  wire [VALUE_WIDTH-1:0]       rd_value,

  input  wire                         snapshot_ready,
  input  wire                         redirect_kill_valid,

  output wire                         snapshot_valid,
  output wire [SNAPSHOT_TARGET_WIDTH-1:0] snapshot_target_o,
  output wire                         snapshot_operand_valid,
  output wire [REG_INDEX_WIDTH-1:0]   snapshot_operand_reg,
  output wire [VALUE_WIDTH-1:0]       snapshot_operand_value,

  output wire                         retire_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire_epoch
);

  wire rs2_selected;
  wire rd_selected;
  wire [2:0] source_mask;
  wire [SNAPSHOT_TARGET_WIDTH-1:0] snapshot_target;
  wire sources_ready;
  wire fire;

  assign source_mask = issue_inst[14:12];
  assign snapshot_target = issue_inst[25 +: SNAPSHOT_TARGET_WIDTH];
  assign rs2_selected = source_mask[1];
  assign rd_selected = source_mask[2];

  assign sources_ready = (source_mask == 3'b000) ||
                         ((source_mask == 3'b001) && rs1_ready) ||
                         ((source_mask == 3'b010) && rs2_ready) ||
                         ((source_mask == 3'b100) && rd_ready);
  assign issue_ready = !redirect_kill_valid &&
                       sources_ready &&
                       snapshot_ready;
  assign fire = issue_valid && issue_ready;

  assign snapshot_valid = fire;
  assign snapshot_target_o = snapshot_target;
  assign snapshot_operand_valid = fire && (source_mask != 3'b000);
  assign snapshot_operand_reg = rd_selected ? issue_inst[11:7] :
                                rs2_selected ? issue_inst[24:20] :
                                               issue_inst[19:15];
  assign snapshot_operand_value = rd_selected ? rd_value :
                                  rs2_selected ? rs2_value : rs1_value;

  assign retire_valid = fire;
  assign retire_seq_id = issue_seq_id;
  assign retire_epoch = issue_epoch;

endmodule
