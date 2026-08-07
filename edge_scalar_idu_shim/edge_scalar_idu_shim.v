// Minimal scalar IDU boundary shim for Edge dual-stream frontend work.
module edge_scalar_idu_shim #(
  parameter PC_WIDTH        = 40,
  parameter SEQ_ID_WIDTH    = 8,
  parameter EPOCH_WIDTH     = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter PSEUDO_WIDTH    = 3
) (
  input  wire                       scalar_valid,
  output wire                       scalar_ready,
  input  wire [PC_WIDTH-1:0]        scalar_pc,
  input  wire [31:0]                scalar_inst,
  input  wire                       scalar_len,
  input  wire                       scalar_is_pseudo,
  input  wire [PSEUDO_WIDTH-1:0]    scalar_pseudo_kind,
  input  wire [SEQ_ID_WIDTH-1:0]    scalar_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     scalar_epoch,

  input  wire                       downstream_ready,
  output wire                       issue_valid,
  output wire [PC_WIDTH-1:0]        issue_pc,
  output wire [31:0]                issue_inst,
  output wire                       issue_len,
  output wire                       issue_is_pseudo,
  output wire [PSEUDO_WIDTH-1:0]    issue_pseudo_kind,
  output wire [SEQ_ID_WIDTH-1:0]    issue_seq_id,
  output wire [EPOCH_WIDTH-1:0]     issue_epoch,

  output wire                       scalar_def_valid,
  output wire                       scalar_def_domain,
  output wire [REG_INDEX_WIDTH-1:0] scalar_def_dst_reg,
  output wire [SEQ_ID_WIDTH-1:0]    scalar_def_seq_id,
  output wire [EPOCH_WIDTH-1:0]     scalar_def_epoch,

  output wire                       scalar_control_valid,
  output wire [SEQ_ID_WIDTH-1:0]    scalar_control_seq_id,
  output wire [EPOCH_WIDTH-1:0]     scalar_control_epoch,

  output wire                       decode_illegal
);

  localparam [6:0] OPCODE_LOAD     = 7'b0000011;
  localparam [6:0] OPCODE_LOAD_FP  = 7'b0000111;
  localparam [6:0] OPCODE_MISC_MEM = 7'b0001111;
  localparam [6:0] OPCODE_OP_IMM   = 7'b0010011;
  localparam [6:0] OPCODE_AUIPC    = 7'b0010111;
  localparam [6:0] OPCODE_OP_IMM32 = 7'b0011011;
  localparam [6:0] OPCODE_STORE    = 7'b0100011;
  localparam [6:0] OPCODE_STORE_FP = 7'b0100111;
  localparam [6:0] OPCODE_OP       = 7'b0110011;
  localparam [6:0] OPCODE_LUI      = 7'b0110111;
  localparam [6:0] OPCODE_OP32     = 7'b0111011;
  localparam [6:0] OPCODE_MADD     = 7'b1000011;
  localparam [6:0] OPCODE_MSUB     = 7'b1000111;
  localparam [6:0] OPCODE_NMSUB    = 7'b1001011;
  localparam [6:0] OPCODE_NMADD    = 7'b1001111;
  localparam [6:0] OPCODE_OP_FP    = 7'b1010011;
  localparam [6:0] OPCODE_BRANCH   = 7'b1100011;
  localparam [6:0] OPCODE_JALR     = 7'b1100111;
  localparam [6:0] OPCODE_JAL      = 7'b1101111;
  localparam [6:0] OPCODE_SYSTEM   = 7'b1110011;
  localparam [2:0] PSEUDO_ACCEL_GETCSR = 3'd3;

  wire [6:0] opcode;
  wire [2:0] funct3;
  wire [REG_INDEX_WIDTH-1:0] rd;
  wire op_fp_writes_gpr;
  wire op_fp_writes_fpr;

  assign opcode = scalar_inst[6:0];
  assign funct3 = scalar_inst[14:12];
  assign rd = scalar_inst[11:7];
  assign op_fp_writes_gpr = (opcode == OPCODE_OP_FP) &&
                            ((scalar_inst[31:27] == 5'b10100) ||
                             (scalar_inst[31:27] == 5'b11000) ||
                             (scalar_inst[31:27] == 5'b11100));
  assign op_fp_writes_fpr = (opcode == OPCODE_OP_FP) &&
                            !op_fp_writes_gpr;

  wire gpr_dst_opcode;
  assign gpr_dst_opcode =
       (opcode == OPCODE_LOAD)
    || (opcode == OPCODE_OP_IMM)
    || (opcode == OPCODE_AUIPC)
    || (opcode == OPCODE_OP_IMM32)
    || (opcode == OPCODE_OP)
    || (opcode == OPCODE_LUI)
    || (opcode == OPCODE_OP32)
    || (opcode == OPCODE_JALR)
    || (opcode == OPCODE_JAL)
    || op_fp_writes_gpr
    || ((opcode == OPCODE_SYSTEM) && (funct3 != 3'b000));

  wire fpr_dst_opcode;
  assign fpr_dst_opcode =
       (opcode == OPCODE_LOAD_FP)
    || (opcode == OPCODE_MADD)
    || (opcode == OPCODE_MSUB)
    || (opcode == OPCODE_NMSUB)
    || (opcode == OPCODE_NMADD)
    || op_fp_writes_fpr;

  wire known_scalar_opcode;
  assign known_scalar_opcode =
       gpr_dst_opcode
    || fpr_dst_opcode
    || (opcode == OPCODE_STORE)
    || (opcode == OPCODE_STORE_FP)
    || (opcode == OPCODE_BRANCH)
    || (opcode == OPCODE_MISC_MEM)
    || ((opcode == OPCODE_SYSTEM) && (funct3 == 3'b000));

  assign scalar_ready = downstream_ready;

  wire issue_fire;
  assign issue_fire = scalar_valid && scalar_ready;

  assign issue_valid = issue_fire;
  assign issue_pc = scalar_pc;
  assign issue_inst = scalar_inst;
  assign issue_len = scalar_len;
  assign issue_is_pseudo = scalar_is_pseudo;
  assign issue_pseudo_kind = scalar_pseudo_kind;
  assign issue_seq_id = scalar_seq_id;
  assign issue_epoch = scalar_epoch;

  assign scalar_def_valid = issue_fire &&
                            ((!scalar_is_pseudo &&
                              (fpr_dst_opcode ||
                               (gpr_dst_opcode &&
                                (rd != {REG_INDEX_WIDTH{1'b0}})))) ||
                             (scalar_is_pseudo &&
                              (scalar_pseudo_kind == PSEUDO_ACCEL_GETCSR) &&
                              (rd != {REG_INDEX_WIDTH{1'b0}})));
  assign scalar_def_domain = !scalar_is_pseudo && fpr_dst_opcode;
  assign scalar_def_dst_reg = rd;
  assign scalar_def_seq_id = scalar_seq_id;
  assign scalar_def_epoch = scalar_epoch;

  assign scalar_control_valid = issue_fire &&
                                !scalar_is_pseudo &&
                                ((opcode == OPCODE_BRANCH) ||
                                 (opcode == OPCODE_JALR) ||
                                 (opcode == OPCODE_JAL));
  assign scalar_control_seq_id = scalar_seq_id;
  assign scalar_control_epoch = scalar_epoch;

  assign decode_illegal = scalar_valid && !scalar_is_pseudo && !known_scalar_opcode;

endmodule
