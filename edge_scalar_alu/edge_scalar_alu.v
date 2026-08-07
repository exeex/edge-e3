// Scalar ALU wrapper for the Edge scalar pipe.
module edge_scalar_alu #(
  parameter PC_WIDTH        = 40,
  parameter SEQ_ID_WIDTH    = 8,
  parameter EPOCH_WIDTH     = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter VALUE_WIDTH     = 64,
  parameter OP_WIDTH        = 4,
  parameter MUL_LATENCY     = 2,
  parameter DIV_LATENCY     = 8
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,

  input  wire                         alu_issue_valid,
  output wire                         alu_issue_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      alu_issue_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       alu_issue_epoch,
  input  wire [OP_WIDTH-1:0]          alu_issue_op,
  input  wire [PC_WIDTH-1:0]          alu_issue_pc,
  input  wire [REG_INDEX_WIDTH-1:0]   alu_issue_rd,
  input  wire                         alu_issue_rd_bank,
  input  wire                         alu_issue_rd_valid,
  input  wire [VALUE_WIDTH-1:0]       alu_issue_src0_value,
  input  wire [VALUE_WIDTH-1:0]       alu_issue_src1_value,
  input  wire [VALUE_WIDTH-1:0]       alu_issue_imm,
  input  wire [VALUE_WIDTH-1:0]       alu_issue_branch_imm,
  input  wire [VALUE_WIDTH-1:0]       alu_issue_jal_imm,
  input  wire [2:0]                   alu_issue_funct3,
  input  wire                         alu_issue_funct7_bit5,
  input  wire                         alu_issue_funct7_is_m,
  input  wire [5:0]                   alu_issue_shamt,
  input  wire [4:0]                   alu_issue_shamt32,

  input  wire                         alu_issue1_valid,
  output wire                         alu_issue1_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      alu_issue1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       alu_issue1_epoch,
  input  wire [OP_WIDTH-1:0]          alu_issue1_op,
  input  wire [PC_WIDTH-1:0]          alu_issue1_pc,
  input  wire [REG_INDEX_WIDTH-1:0]   alu_issue1_rd,
  input  wire                         alu_issue1_rd_bank,
  input  wire                         alu_issue1_rd_valid,
  input  wire [VALUE_WIDTH-1:0]       alu_issue1_src0_value,
  input  wire [VALUE_WIDTH-1:0]       alu_issue1_src1_value,
  input  wire [VALUE_WIDTH-1:0]       alu_issue1_imm,
  input  wire [2:0]                   alu_issue1_funct3,
  input  wire                         alu_issue1_funct7_bit5,
  input  wire                         alu_issue1_funct7_is_m,
  input  wire [5:0]                   alu_issue1_shamt,
  input  wire [4:0]                   alu_issue1_shamt32,

  output wire [VALUE_WIDTH-1:0]       alu_issue_fast_result,
  output wire                         alu_issue_control_valid,
  output wire                         alu_issue_control_taken,
  output wire [PC_WIDTH-1:0]          alu_issue_control_target,

  output wire                         alu_complete_valid,
  output wire [SEQ_ID_WIDTH-1:0]      alu_complete_seq_id,
  output wire [EPOCH_WIDTH-1:0]       alu_complete_epoch,
  output wire [REG_INDEX_WIDTH-1:0]   alu_complete_rd,
  output wire                         alu_complete_rd_bank,
  output wire                         alu_complete_rd_valid,
  output wire [VALUE_WIDTH-1:0]       alu_complete_value,
  output wire                         alu_complete_control_valid,
  output wire                         alu_complete_control_taken,
  output wire [PC_WIDTH-1:0]          alu_complete_control_target
  ,
  output wire                         fast_complete_valid,
  output wire [SEQ_ID_WIDTH-1:0]      fast_complete_seq_id,
  output wire [EPOCH_WIDTH-1:0]       fast_complete_epoch,
  output wire [REG_INDEX_WIDTH-1:0]   fast_complete_rd,
  output wire                         fast_complete_rd_bank,
  output wire                         fast_complete_rd_valid,
  output wire [VALUE_WIDTH-1:0]       fast_complete_value,
  output wire                         fast1_complete_valid,
  output wire [SEQ_ID_WIDTH-1:0]      fast1_complete_seq_id,
  output wire [EPOCH_WIDTH-1:0]       fast1_complete_epoch,
  output wire [REG_INDEX_WIDTH-1:0]   fast1_complete_rd,
  output wire                         fast1_complete_rd_bank,
  output wire                         fast1_complete_rd_valid,
  output wire [VALUE_WIDTH-1:0]       fast1_complete_value,
  output wire                         m_complete_valid_o,
  output wire [SEQ_ID_WIDTH-1:0]      m_complete_seq_id_o,
  output wire [EPOCH_WIDTH-1:0]       m_complete_epoch_o,
  output wire [REG_INDEX_WIDTH-1:0]   m_complete_rd_o,
  output wire                         m_complete_rd_bank_o,
  output wire                         m_complete_rd_valid_o,
  output wire [VALUE_WIDTH-1:0]       m_complete_value_o,
  output wire                         m_issue_ready_o,
  output wire                         mul_issue_ready_o,
  output wire                         div_issue_ready_o
);

  localparam [OP_WIDTH-1:0] ALU_OP_OP     = 4'd1;
  localparam [OP_WIDTH-1:0] ALU_OP_OP32   = 4'd3;
  localparam [OP_WIDTH-1:0] ALU_OP_JAL    = 4'd6;
  localparam [OP_WIDTH-1:0] ALU_OP_JALR   = 4'd7;
  localparam [OP_WIDTH-1:0] ALU_OP_BRANCH = 4'd8;

  wire issue_is_m;
  wire issue1_is_m;
  wire fast_select_issue1;
  wire m_select_issue1;
  wire fast_accept;
  wire fast1_accept;
  wire m_issue_valid;
  wire m_issue_ready;
  wire mul_issue_ready;
  wire div_issue_ready;
  wire fast_is_control;
  wire fast_branch_taken;
  wire [PC_WIDTH-1:0] fast_branch_target;
  wire [VALUE_WIDTH-1:0] fast_result;
  wire [VALUE_WIDTH-1:0] fast1_result;
  wire m_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] m_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] m_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] m_complete_rd;
  wire m_complete_rd_bank;
  wire m_complete_rd_valid;
  wire [VALUE_WIDTH-1:0] m_complete_value;

  reg fast_complete_valid_r;
  reg [SEQ_ID_WIDTH-1:0] fast_complete_seq_id_r;
  reg [EPOCH_WIDTH-1:0] fast_complete_epoch_r;
  reg [REG_INDEX_WIDTH-1:0] fast_complete_rd_r;
  reg fast_complete_rd_bank_r;
  reg fast_complete_rd_valid_r;
  reg [VALUE_WIDTH-1:0] fast_complete_value_r;
  reg fast_complete_control_valid_r;
  reg fast_complete_control_taken_r;
  reg [PC_WIDTH-1:0] fast_complete_control_target_r;
  reg fast1_complete_valid_r;
  reg [SEQ_ID_WIDTH-1:0] fast1_complete_seq_id_r;
  reg [EPOCH_WIDTH-1:0] fast1_complete_epoch_r;
  reg [REG_INDEX_WIDTH-1:0] fast1_complete_rd_r;
  reg fast1_complete_rd_bank_r;
  reg fast1_complete_rd_valid_r;
  reg [VALUE_WIDTH-1:0] fast1_complete_value_r;

  assign issue_is_m = ((alu_issue_op == ALU_OP_OP) ||
                       (alu_issue_op == ALU_OP_OP32)) &&
                      alu_issue_funct7_is_m;
  assign issue1_is_m = ((alu_issue1_op == ALU_OP_OP) ||
                        (alu_issue1_op == ALU_OP_OP32)) &&
                       alu_issue1_funct7_is_m;
  assign alu_issue_ready = issue_is_m ? m_issue_ready : 1'b1;
  assign alu_issue1_ready = issue1_is_m ? m_issue_ready : 1'b1;
  assign fast_select_issue1 = alu_issue_valid && issue_is_m &&
                              alu_issue1_valid && !issue1_is_m;
  assign m_select_issue1 = alu_issue1_valid && issue1_is_m;
  assign fast_accept = (alu_issue_valid && !issue_is_m) ||
                       fast_select_issue1;
  assign fast1_accept = alu_issue_valid && !issue_is_m &&
                        alu_issue1_valid && !issue1_is_m;
  assign m_issue_valid = (alu_issue_valid && issue_is_m) || m_select_issue1;
  assign fast_is_control = (alu_issue_op == ALU_OP_BRANCH) ||
                           (alu_issue_op == ALU_OP_JAL) ||
                           (alu_issue_op == ALU_OP_JALR);
  assign alu_issue_fast_result = fast_result;
  assign alu_issue_control_valid = fast_accept && fast_is_control;
  assign alu_issue_control_taken = fast_branch_taken;
  assign alu_issue_control_target = fast_branch_target;

  assign fast_complete_valid = fast_complete_valid_r;
  assign fast_complete_seq_id = fast_complete_seq_id_r;
  assign fast_complete_epoch = fast_complete_epoch_r;
  assign fast_complete_rd = fast_complete_rd_r;
  assign fast_complete_rd_bank = fast_complete_rd_bank_r;
  assign fast_complete_rd_valid = fast_complete_rd_valid_r;
  assign fast_complete_value = fast_complete_value_r;
  assign fast1_complete_valid = fast1_complete_valid_r;
  assign fast1_complete_seq_id = fast1_complete_seq_id_r;
  assign fast1_complete_epoch = fast1_complete_epoch_r;
  assign fast1_complete_rd = fast1_complete_rd_r;
  assign fast1_complete_rd_bank = fast1_complete_rd_bank_r;
  assign fast1_complete_rd_valid = fast1_complete_rd_valid_r;
  assign fast1_complete_value = fast1_complete_value_r;
  assign m_complete_valid_o = m_complete_valid;
  assign m_complete_seq_id_o = m_complete_seq_id;
  assign m_complete_epoch_o = m_complete_epoch;
  assign m_complete_rd_o = m_complete_rd;
  assign m_complete_rd_bank_o = m_complete_rd_bank;
  assign m_complete_rd_valid_o = m_complete_rd_valid;
  assign m_complete_value_o = m_complete_value;
  assign m_issue_ready_o = m_issue_ready;
  assign mul_issue_ready_o = mul_issue_ready;
  assign div_issue_ready_o = div_issue_ready;

  assign alu_complete_valid = fast_complete_valid_r || m_complete_valid;
  assign alu_complete_seq_id = m_complete_valid ? m_complete_seq_id :
                                                  fast_complete_seq_id_r;
  assign alu_complete_epoch = m_complete_valid ? m_complete_epoch :
                                                 fast_complete_epoch_r;
  assign alu_complete_rd = m_complete_valid ? m_complete_rd :
                                              fast_complete_rd_r;
  assign alu_complete_rd_bank = m_complete_valid ? m_complete_rd_bank :
                                                     fast_complete_rd_bank_r;
  assign alu_complete_rd_valid = m_complete_valid ? m_complete_rd_valid :
                                                    fast_complete_rd_valid_r;
  assign alu_complete_value = m_complete_valid ? m_complete_value :
                                                 fast_complete_value_r;
  assign alu_complete_control_valid = fast_complete_valid_r &&
                                      fast_complete_control_valid_r;
  assign alu_complete_control_taken = fast_complete_control_taken_r;
  assign alu_complete_control_target = fast_complete_control_target_r;

  edge_scalar_fast_alu #(
    .PC_WIDTH(PC_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .OP_WIDTH(OP_WIDTH)
  ) fast_alu (
    .fast_issue_op(fast_select_issue1 ? alu_issue1_op : alu_issue_op),
    .fast_issue_pc(fast_select_issue1 ? alu_issue1_pc : alu_issue_pc),
    .fast_issue_src0_value(fast_select_issue1 ? alu_issue1_src0_value : alu_issue_src0_value),
    .fast_issue_src1_value(fast_select_issue1 ? alu_issue1_src1_value : alu_issue_src1_value),
    .fast_issue_imm(fast_select_issue1 ? alu_issue1_imm : alu_issue_imm),
    .fast_issue_funct3(fast_select_issue1 ? alu_issue1_funct3 : alu_issue_funct3),
    .fast_issue_funct7_bit5(fast_select_issue1 ? alu_issue1_funct7_bit5 : alu_issue_funct7_bit5),
    .fast_issue_funct7_is_m(fast_select_issue1 ? alu_issue1_funct7_is_m : alu_issue_funct7_is_m),
    .fast_issue_shamt(fast_select_issue1 ? alu_issue1_shamt : alu_issue_shamt),
    .fast_issue_shamt32(fast_select_issue1 ? alu_issue1_shamt32 : alu_issue_shamt32),
    .fast_result(fast_result)
  );

  edge_scalar_fast_alu #(
    .PC_WIDTH(PC_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .OP_WIDTH(OP_WIDTH)
  ) fast_alu_lane1 (
    .fast_issue_op(alu_issue1_op),
    .fast_issue_pc(alu_issue1_pc),
    .fast_issue_src0_value(alu_issue1_src0_value),
    .fast_issue_src1_value(alu_issue1_src1_value),
    .fast_issue_imm(alu_issue1_imm),
    .fast_issue_funct3(alu_issue1_funct3),
    .fast_issue_funct7_bit5(alu_issue1_funct7_bit5),
    .fast_issue_funct7_is_m(alu_issue1_funct7_is_m),
    .fast_issue_shamt(alu_issue1_shamt),
    .fast_issue_shamt32(alu_issue1_shamt32),
    .fast_result(fast1_result)
  );

  edge_scalar_branch #(
    .PC_WIDTH(PC_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .OP_WIDTH(OP_WIDTH)
  ) scalar_branch (
    .branch_issue_op(alu_issue_op),
    .branch_issue_pc(alu_issue_pc),
    .branch_issue_src0_value(alu_issue_src0_value),
    .branch_issue_src1_value(alu_issue_src1_value),
    .branch_issue_imm(alu_issue_imm),
    .branch_issue_branch_imm(alu_issue_branch_imm),
    .branch_issue_jal_imm(alu_issue_jal_imm),
    .branch_issue_funct3(alu_issue_funct3),
    .branch_taken(fast_branch_taken),
    .branch_target(fast_branch_target)
  );

  edge_scalar_muldiv #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .OP_WIDTH(OP_WIDTH),
    .MUL_LATENCY(MUL_LATENCY),
    .DIV_LATENCY(DIV_LATENCY)
  ) scalar_muldiv (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .m_issue_valid(m_issue_valid),
    .m_issue_ready(m_issue_ready),
    .mul_issue_ready_o(mul_issue_ready),
    .div_issue_ready_o(div_issue_ready),
    .m_issue_seq_id(m_select_issue1 ? alu_issue1_seq_id : alu_issue_seq_id),
    .m_issue_epoch(m_select_issue1 ? alu_issue1_epoch : alu_issue_epoch),
    .m_issue_op(m_select_issue1 ? alu_issue1_op : alu_issue_op),
    .m_issue_rd(m_select_issue1 ? alu_issue1_rd : alu_issue_rd),
    .m_issue_rd_bank(m_select_issue1 ? alu_issue1_rd_bank : alu_issue_rd_bank),
    .m_issue_rd_valid(m_select_issue1 ? alu_issue1_rd_valid : alu_issue_rd_valid),
    .m_issue_src0_value(m_select_issue1 ? alu_issue1_src0_value : alu_issue_src0_value),
    .m_issue_src1_value(m_select_issue1 ? alu_issue1_src1_value : alu_issue_src1_value),
    .m_issue_funct3(m_select_issue1 ? alu_issue1_funct3 : alu_issue_funct3),
    .m_complete_valid(m_complete_valid),
    .m_complete_seq_id(m_complete_seq_id),
    .m_complete_epoch(m_complete_epoch),
    .m_complete_rd(m_complete_rd),
    .m_complete_rd_bank(m_complete_rd_bank),
    .m_complete_rd_valid(m_complete_rd_valid),
    .m_complete_value(m_complete_value)
  );

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      fast_complete_valid_r <= 1'b0;
      fast_complete_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      fast_complete_epoch_r <= {EPOCH_WIDTH{1'b0}};
      fast_complete_rd_r <= {REG_INDEX_WIDTH{1'b0}};
      fast_complete_rd_bank_r <= 1'b0;
      fast_complete_rd_valid_r <= 1'b0;
      fast_complete_value_r <= {VALUE_WIDTH{1'b0}};
      fast_complete_control_valid_r <= 1'b0;
      fast_complete_control_taken_r <= 1'b0;
      fast_complete_control_target_r <= {PC_WIDTH{1'b0}};
      fast1_complete_valid_r <= 1'b0;
      fast1_complete_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      fast1_complete_epoch_r <= {EPOCH_WIDTH{1'b0}};
      fast1_complete_rd_r <= {REG_INDEX_WIDTH{1'b0}};
      fast1_complete_rd_bank_r <= 1'b0;
      fast1_complete_rd_valid_r <= 1'b0;
      fast1_complete_value_r <= {VALUE_WIDTH{1'b0}};
    end else begin
      fast_complete_valid_r <= 1'b0;
      fast1_complete_valid_r <= 1'b0;
      if (fast_accept) begin
        fast_complete_valid_r <= 1'b1;
        fast_complete_seq_id_r <= fast_select_issue1 ? alu_issue1_seq_id : alu_issue_seq_id;
        fast_complete_epoch_r <= fast_select_issue1 ? alu_issue1_epoch : alu_issue_epoch;
        fast_complete_rd_r <= fast_select_issue1 ? alu_issue1_rd : alu_issue_rd;
        fast_complete_rd_bank_r <= fast_select_issue1 ? alu_issue1_rd_bank : alu_issue_rd_bank;
        fast_complete_rd_valid_r <= fast_select_issue1 ? alu_issue1_rd_valid : alu_issue_rd_valid;
        fast_complete_value_r <= fast_result;
        fast_complete_control_valid_r <= fast_is_control;
        fast_complete_control_taken_r <= fast_branch_taken;
        fast_complete_control_target_r <= fast_branch_target;
      end
      if (fast1_accept) begin
        fast1_complete_valid_r <= 1'b1;
        fast1_complete_seq_id_r <= alu_issue1_seq_id;
        fast1_complete_epoch_r <= alu_issue1_epoch;
        fast1_complete_rd_r <= alu_issue1_rd;
        fast1_complete_rd_bank_r <= alu_issue1_rd_bank;
        fast1_complete_rd_valid_r <= alu_issue1_rd_valid;
        fast1_complete_value_r <= fast1_result;
      end
    end
  end

endmodule
