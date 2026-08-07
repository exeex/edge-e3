`ifndef EDGE_SCALAR_MULDIV_V
`define EDGE_SCALAR_MULDIV_V

// One shared multiply domain plus an independent divide/remainder domain.
(* keep_hierarchy = "yes" *)
module edge_scalar_muldiv #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter VALUE_WIDTH = 64,
  parameter OP_WIDTH = 4,
  parameter MUL_LATENCY = 2,
  parameter DIV_LATENCY = 8
) (
  input wire forever_cpuclk,
  input wire cpurst_b,
  input wire m_issue_valid,
  output wire m_issue_ready,
  output wire mul_issue_ready_o,
  output wire div_issue_ready_o,
  input wire [SEQ_ID_WIDTH-1:0] m_issue_seq_id,
  input wire [EPOCH_WIDTH-1:0] m_issue_epoch,
  input wire [OP_WIDTH-1:0] m_issue_op,
  input wire [REG_INDEX_WIDTH-1:0] m_issue_rd,
  input wire m_issue_rd_bank,
  input wire m_issue_rd_valid,
  input wire [VALUE_WIDTH-1:0] m_issue_src0_value,
  input wire [VALUE_WIDTH-1:0] m_issue_src1_value,
  input wire [2:0] m_issue_funct3,
  output wire m_complete_valid,
  output wire [SEQ_ID_WIDTH-1:0] m_complete_seq_id,
  output wire [EPOCH_WIDTH-1:0] m_complete_epoch,
  output wire [REG_INDEX_WIDTH-1:0] m_complete_rd,
  output wire m_complete_rd_bank,
  output wire m_complete_rd_valid,
  output wire [VALUE_WIDTH-1:0] m_complete_value
);
  localparam [OP_WIDTH-1:0] ALU_OP_OP = 4'd1;

  wire issue_is_divrem = m_issue_funct3[2];
  wire issue_is_word = m_issue_op != ALU_OP_OP;
  wire issue_is_mul_high = !issue_is_word &&
                           (m_issue_funct3[1:0] != 2'b00);
  wire issue_mul_signed_lhs = issue_is_mul_high &&
    ((m_issue_funct3 == 3'b001) || (m_issue_funct3 == 3'b010));
  wire issue_mul_signed_rhs = issue_is_mul_high &&
                              (m_issue_funct3 == 3'b001);
  wire [31:0] issue_src0_word = m_issue_src0_value[31:0];
  wire [31:0] issue_src1_word = m_issue_src1_value[31:0];
  wire [63:0] issue_mul_abs_src0 =
    issue_mul_signed_lhs && m_issue_src0_value[63] ?
    (~m_issue_src0_value + 64'd1) : m_issue_src0_value;
  wire [63:0] issue_mul_abs_src1 =
    issue_mul_signed_rhs && m_issue_src1_value[63] ?
    (~m_issue_src1_value + 64'd1) : m_issue_src1_value;
  wire issue_mul_lh_needed = |issue_mul_abs_src1[63:32];
  wire issue_mul_hl_needed = |issue_mul_abs_src0[63:32];
  wire [2:0] issue_mul_pending_mask = issue_is_word ? 3'b000 :
    (issue_is_mul_high ? 3'b111 :
     {1'b0, issue_mul_hl_needed, issue_mul_lh_needed});
  wire [2:0] issue_mul_partial_count = 3'd1 +
    {2'd0, issue_mul_pending_mask[0]} +
    {2'd0, issue_mul_pending_mask[1]} +
    {2'd0, issue_mul_pending_mask[2]};

  reg mul_busy_r;
  reg [5:0] mul_count_r;
  reg [SEQ_ID_WIDTH-1:0] mul_seq_id_r;
  reg [EPOCH_WIDTH-1:0] mul_epoch_r;
  reg [REG_INDEX_WIDTH-1:0] mul_rd_r;
  reg mul_rd_bank_r;
  reg mul_rd_valid_r;
  reg [63:0] mul_src0_r;
  reg [63:0] mul_src1_r;
  reg [127:0] mul_accum_r;
  reg [2:0] mul_pending_mask_r;
  reg mul_word_r;
  reg mul_high_r;
  reg mul_product_neg_r;
  reg [63:0] mul_product_pipe_r;
  reg [1:0] mul_shift_pipe_r;
  reg mul_valid_pipe_r;
  reg mul_complete_valid_r;
  reg [VALUE_WIDTH-1:0] mul_complete_value_r;

  wire mul_complete_ready;
  wire mul_issue_ready = !mul_busy_r &&
                         (!mul_complete_valid_r || mul_complete_ready);
  wire mul_accept = m_issue_valid && !issue_is_divrem && mul_issue_ready;
  wire [31:0] mul_start_a = issue_is_word ? issue_src0_word :
                                                   issue_mul_abs_src0[31:0];
  wire [31:0] mul_start_b = issue_is_word ? issue_src1_word :
                                                   issue_mul_abs_src1[31:0];
  wire mul_feed_valid = mul_busy_r && |mul_pending_mask_r;
  wire [1:0] mul_feed_select = mul_pending_mask_r[0] ? 2'd1 :
                               (mul_pending_mask_r[1] ? 2'd2 : 2'd3);
  wire [31:0] mul_feed_a = mul_feed_select == 2'd1 ? mul_src0_r[31:0] :
                                                    mul_src0_r[63:32];
  wire [31:0] mul_feed_b = mul_feed_select == 2'd2 ? mul_src1_r[31:0] :
                                                    mul_src1_r[63:32];
  wire [1:0] mul_feed_shift = mul_feed_select == 2'd3 ? 2'd2 : 2'd1;
  wire [31:0] mul_pipe_a = mul_accept ? mul_start_a : mul_feed_a;
  wire [31:0] mul_pipe_b = mul_accept ? mul_start_b : mul_feed_b;
  wire [63:0] mul_partial_product = mul_pipe_a * mul_pipe_b;
  wire [127:0] mul_shifted_product = mul_shift_pipe_r == 2'd0 ?
    {64'd0, mul_product_pipe_r} : mul_shift_pipe_r == 2'd1 ?
    {32'd0, mul_product_pipe_r, 32'd0} :
    {mul_product_pipe_r, 64'd0};
  wire [127:0] mul_accum_next = mul_accum_r +
    (mul_valid_pipe_r ? mul_shifted_product : 128'd0);
  wire [127:0] mul_signed_product = mul_product_neg_r ?
                                    (~mul_accum_next + 128'd1) :
                                    mul_accum_next;
  wire [VALUE_WIDTH-1:0] mul_final_result = mul_word_r ?
    {{32{mul_signed_product[31]}}, mul_signed_product[31:0]} :
    (mul_high_r ? mul_signed_product[127:64] : mul_signed_product[63:0]);

  wire div_issue_ready;
  wire div_complete_valid;
  wire div_complete_ready;
  wire [SEQ_ID_WIDTH-1:0] div_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] div_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] div_complete_rd;
  wire div_complete_rd_bank;
  wire div_complete_rd_valid;
  wire [VALUE_WIDTH-1:0] div_complete_value;

  assign m_issue_ready = issue_is_divrem ? div_issue_ready : mul_issue_ready;
  assign mul_issue_ready_o = mul_issue_ready;
  assign div_issue_ready_o = div_issue_ready;
  assign mul_complete_ready = mul_complete_valid_r;
  assign div_complete_ready = div_complete_valid && !mul_complete_valid_r;
  assign m_complete_valid = mul_complete_valid_r || div_complete_valid;
  assign m_complete_seq_id = mul_complete_valid_r ? mul_seq_id_r :
                                                    div_complete_seq_id;
  assign m_complete_epoch = mul_complete_valid_r ? mul_epoch_r :
                                                   div_complete_epoch;
  assign m_complete_rd = mul_complete_valid_r ? mul_rd_r : div_complete_rd;
  assign m_complete_rd_bank = mul_complete_valid_r ? mul_rd_bank_r :
                                                      div_complete_rd_bank;
  assign m_complete_rd_valid = mul_complete_valid_r ? mul_rd_valid_r :
                                                       div_complete_rd_valid;
  assign m_complete_value = mul_complete_valid_r ? mul_complete_value_r :
                                                   div_complete_value;

  edge_scalar_divrem #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH), .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH), .VALUE_WIDTH(VALUE_WIDTH),
    .OP_WIDTH(OP_WIDTH)
  ) divrem (
    .forever_cpuclk(forever_cpuclk), .cpurst_b(cpurst_b),
    .issue_valid(m_issue_valid && issue_is_divrem),
    .issue_ready(div_issue_ready),
    .issue_seq_id(m_issue_seq_id), .issue_epoch(m_issue_epoch),
    .issue_op(m_issue_op), .issue_rd(m_issue_rd),
    .issue_rd_bank(m_issue_rd_bank), .issue_rd_valid(m_issue_rd_valid),
    .issue_src0_value(m_issue_src0_value),
    .issue_src1_value(m_issue_src1_value), .issue_funct3(m_issue_funct3),
    .complete_valid(div_complete_valid), .complete_ready(div_complete_ready),
    .complete_seq_id(div_complete_seq_id),
    .complete_epoch(div_complete_epoch), .complete_rd(div_complete_rd),
    .complete_rd_bank(div_complete_rd_bank),
    .complete_rd_valid(div_complete_rd_valid),
    .complete_value(div_complete_value)
  );

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      mul_busy_r <= 1'b0;
      mul_count_r <= 6'd0;
      mul_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      mul_epoch_r <= {EPOCH_WIDTH{1'b0}};
      mul_rd_r <= {REG_INDEX_WIDTH{1'b0}};
      mul_rd_bank_r <= 1'b0;
      mul_rd_valid_r <= 1'b0;
      mul_src0_r <= 64'd0;
      mul_src1_r <= 64'd0;
      mul_accum_r <= 128'd0;
      mul_pending_mask_r <= 3'd0;
      mul_word_r <= 1'b0;
      mul_high_r <= 1'b0;
      mul_product_neg_r <= 1'b0;
      mul_product_pipe_r <= 64'd0;
      mul_shift_pipe_r <= 2'd0;
      mul_valid_pipe_r <= 1'b0;
      mul_complete_valid_r <= 1'b0;
      mul_complete_value_r <= {VALUE_WIDTH{1'b0}};
    end else begin
      if (mul_complete_valid_r && mul_complete_ready)
        mul_complete_valid_r <= 1'b0;

      if (mul_busy_r) begin
        mul_accum_r <= mul_accum_next;
        mul_product_pipe_r <= mul_partial_product;
        mul_shift_pipe_r <= mul_feed_shift;
        mul_valid_pipe_r <= mul_feed_valid;
        if (mul_feed_valid) begin
          if (mul_pending_mask_r[0])
            mul_pending_mask_r[0] <= 1'b0;
          else if (mul_pending_mask_r[1])
            mul_pending_mask_r[1] <= 1'b0;
          else
            mul_pending_mask_r[2] <= 1'b0;
        end
        if (mul_count_r <= 6'd1) begin
          mul_busy_r <= 1'b0;
          mul_count_r <= 6'd0;
          mul_complete_valid_r <= 1'b1;
          mul_complete_value_r <= mul_final_result;
        end else begin
          mul_count_r <= mul_count_r - 6'd1;
        end
      end

      if (mul_accept) begin
        mul_busy_r <= 1'b1;
        mul_count_r <= {3'd0, issue_mul_partial_count};
        mul_seq_id_r <= m_issue_seq_id;
        mul_epoch_r <= m_issue_epoch;
        mul_rd_r <= m_issue_rd;
        mul_rd_bank_r <= m_issue_rd_bank;
        mul_rd_valid_r <= m_issue_rd_valid;
        mul_src0_r <= issue_is_word ? {32'd0, issue_src0_word} :
                                      issue_mul_abs_src0;
        mul_src1_r <= issue_is_word ? {32'd0, issue_src1_word} :
                                      issue_mul_abs_src1;
        mul_accum_r <= 128'd0;
        mul_pending_mask_r <= issue_mul_pending_mask;
        mul_word_r <= issue_is_word;
        mul_high_r <= issue_is_mul_high;
        mul_product_neg_r <= issue_is_mul_high &&
          ((issue_mul_signed_lhs && m_issue_src0_value[63]) ^
           (issue_mul_signed_rhs && m_issue_src1_value[63]));
        mul_product_pipe_r <= mul_partial_product;
        mul_shift_pipe_r <= 2'd0;
        mul_valid_pipe_r <= 1'b1;
        mul_complete_value_r <= {VALUE_WIDTH{1'b0}};
      end
    end
  end

  wire unused_parameters = |{MUL_LATENCY[0], DIV_LATENCY[0]};
endmodule

`endif
