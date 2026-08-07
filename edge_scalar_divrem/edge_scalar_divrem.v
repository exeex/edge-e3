`ifndef EDGE_SCALAR_DIVREM_V
`define EDGE_SCALAR_DIVREM_V

// Radix-4 RV64 divide/remainder domain with a held completion packet.
(* keep_hierarchy = "yes" *)
module edge_scalar_divrem #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter VALUE_WIDTH = 64,
  parameter OP_WIDTH = 4
) (
  input wire forever_cpuclk,
  input wire cpurst_b,
  input wire issue_valid,
  output wire issue_ready,
  input wire [SEQ_ID_WIDTH-1:0] issue_seq_id,
  input wire [EPOCH_WIDTH-1:0] issue_epoch,
  input wire [OP_WIDTH-1:0] issue_op,
  input wire [REG_INDEX_WIDTH-1:0] issue_rd,
  input wire issue_rd_bank,
  input wire issue_rd_valid,
  input wire [VALUE_WIDTH-1:0] issue_src0_value,
  input wire [VALUE_WIDTH-1:0] issue_src1_value,
  input wire [2:0] issue_funct3,
  output wire complete_valid,
  input wire complete_ready,
  output wire [SEQ_ID_WIDTH-1:0] complete_seq_id,
  output wire [EPOCH_WIDTH-1:0] complete_epoch,
  output wire [REG_INDEX_WIDTH-1:0] complete_rd,
  output wire complete_rd_bank,
  output wire complete_rd_valid,
  output wire [VALUE_WIDTH-1:0] complete_value
);
  localparam [OP_WIDTH-1:0] ALU_OP_OP = 4'd1;

  reg busy_r;
  reg [5:0] count_r;
  reg complete_valid_r;
  reg [SEQ_ID_WIDTH-1:0] complete_seq_id_r;
  reg [EPOCH_WIDTH-1:0] complete_epoch_r;
  reg [REG_INDEX_WIDTH-1:0] complete_rd_r;
  reg complete_rd_bank_r;
  reg complete_rd_valid_r;
  reg [VALUE_WIDTH-1:0] complete_value_r;
  reg [65:0] remainder_r;
  reg [63:0] quotient_r;
  reg [63:0] dividend_shift_r;
  reg [65:0] divisor_r;
  reg word_r;
  reg rem_r;
  reg quotient_neg_r;
  reg remainder_neg_r;
  reg special_r;

  wire accept = issue_valid && issue_ready;
  wire word_op = issue_op != ALU_OP_OP;
  wire signed_op = (issue_funct3 == 3'b100) ||
                   (issue_funct3 == 3'b110);
  wire rem_op = issue_funct3[1];
  wire [31:0] src0_word = issue_src0_value[31:0];
  wire [31:0] src1_word = issue_src1_value[31:0];
  wire [VALUE_WIDTH-1:0] signed_min =
    {1'b1, {(VALUE_WIDTH-1){1'b0}}};
  wire [31:0] signed_min_word = {1'b1, 31'd0};
  wire src0_sign = word_op ? src0_word[31] :
                             issue_src0_value[VALUE_WIDTH-1];
  wire src1_sign = word_op ? src1_word[31] :
                             issue_src1_value[VALUE_WIDTH-1];
  wire [VALUE_WIDTH-1:0] src0_abs64 = signed_op && src0_sign ?
    (~issue_src0_value + {{(VALUE_WIDTH-1){1'b0}}, 1'b1}) :
    issue_src0_value;
  wire [VALUE_WIDTH-1:0] src1_abs64 = signed_op && src1_sign ?
    (~issue_src1_value + {{(VALUE_WIDTH-1){1'b0}}, 1'b1}) :
    issue_src1_value;
  wire [31:0] src0_abs32 = signed_op && src0_sign ?
                            (~src0_word + 32'd1) : src0_word;
  wire [31:0] src1_abs32 = signed_op && src1_sign ?
                            (~src1_word + 32'd1) : src1_word;
  wire [63:0] abs_dividend = word_op ? {src0_abs32, 32'd0} :
                                               src0_abs64;
  wire [63:0] abs_divisor = word_op ? {32'd0, src1_abs32} :
                                              src1_abs64;
  wire divide_by_zero = word_op ? src1_word == 32'd0 :
                                  issue_src1_value == {VALUE_WIDTH{1'b0}};
  wire signed_overflow = signed_op &&
    (word_op ? ((src0_word == signed_min_word) &&
                (src1_word == 32'hffff_ffff)) :
               ((issue_src0_value == signed_min) &&
                (issue_src1_value == {VALUE_WIDTH{1'b1}})));
  wire special_case = divide_by_zero || signed_overflow;

  wire [65:0] remainder_shift = {remainder_r[63:0],
                                 dividend_shift_r[63:62]};
  wire [65:0] divisor_x2 = divisor_r << 1;
  wire [65:0] divisor_x3 = divisor_r + divisor_x2;
  wire [1:0] q_digit = remainder_shift >= divisor_x3 ? 2'd3 :
                       remainder_shift >= divisor_x2 ? 2'd2 :
                       remainder_shift >= divisor_r ? 2'd1 : 2'd0;
  wire [65:0] remainder_next = q_digit == 2'd3 ?
    remainder_shift - divisor_x3 : q_digit == 2'd2 ?
    remainder_shift - divisor_x2 : q_digit == 2'd1 ?
    remainder_shift - divisor_r : remainder_shift;
  wire [63:0] quotient_next = {quotient_r[61:0], q_digit};
  wire [63:0] dividend_shift_next = {dividend_shift_r[61:0], 2'b00};
  wire [63:0] quotient_signed = quotient_neg_r ?
                                (~quotient_next + 64'd1) : quotient_next;
  wire [63:0] remainder_signed = remainder_neg_r ?
    (~remainder_next[63:0] + 64'd1) : remainder_next[63:0];
  wire [31:0] quotient_word = quotient_signed[31:0];
  wire [31:0] remainder_word = remainder_signed[31:0];

  reg [VALUE_WIDTH-1:0] special_result;
  reg [VALUE_WIDTH-1:0] final_result;
  always @* begin
    special_result = {VALUE_WIDTH{1'b0}};
    if (divide_by_zero) begin
      special_result = rem_op ?
        (word_op ? {{32{src0_word[31]}}, src0_word} : issue_src0_value) :
        {VALUE_WIDTH{1'b1}};
    end else if (signed_overflow && !rem_op) begin
      special_result = word_op ?
        {{32{signed_min_word[31]}}, signed_min_word} : signed_min;
    end
    if (word_r) begin
      final_result = rem_r ? {{32{remainder_word[31]}}, remainder_word} :
                             {{32{quotient_word[31]}}, quotient_word};
    end else begin
      final_result = rem_r ? remainder_signed : quotient_signed;
    end
  end

  assign issue_ready = !busy_r && (!complete_valid_r || complete_ready);
  assign complete_valid = complete_valid_r;
  assign complete_seq_id = complete_seq_id_r;
  assign complete_epoch = complete_epoch_r;
  assign complete_rd = complete_rd_r;
  assign complete_rd_bank = complete_rd_bank_r;
  assign complete_rd_valid = complete_rd_valid_r;
  assign complete_value = complete_value_r;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      busy_r <= 1'b0;
      count_r <= 6'd0;
      complete_valid_r <= 1'b0;
      complete_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      complete_epoch_r <= {EPOCH_WIDTH{1'b0}};
      complete_rd_r <= {REG_INDEX_WIDTH{1'b0}};
      complete_rd_bank_r <= 1'b0;
      complete_rd_valid_r <= 1'b0;
      complete_value_r <= {VALUE_WIDTH{1'b0}};
      remainder_r <= 66'd0;
      quotient_r <= 64'd0;
      dividend_shift_r <= 64'd0;
      divisor_r <= 66'd0;
      word_r <= 1'b0;
      rem_r <= 1'b0;
      quotient_neg_r <= 1'b0;
      remainder_neg_r <= 1'b0;
      special_r <= 1'b0;
    end else begin
      if (complete_valid_r && complete_ready)
        complete_valid_r <= 1'b0;

      if (busy_r) begin
        remainder_r <= remainder_next;
        quotient_r <= quotient_next;
        dividend_shift_r <= dividend_shift_next;
        if (count_r <= 6'd1) begin
          busy_r <= 1'b0;
          count_r <= 6'd0;
          complete_valid_r <= 1'b1;
          complete_value_r <= special_r ? complete_value_r : final_result;
        end else begin
          count_r <= count_r - 6'd1;
        end
      end

      if (accept) begin
        busy_r <= 1'b1;
        complete_seq_id_r <= issue_seq_id;
        complete_epoch_r <= issue_epoch;
        complete_rd_r <= issue_rd;
        complete_rd_bank_r <= issue_rd_bank;
        complete_rd_valid_r <= issue_rd_valid;
        word_r <= word_op;
        rem_r <= rem_op;
        quotient_neg_r <= signed_op && (src0_sign ^ src1_sign);
        remainder_neg_r <= signed_op && src0_sign;
        special_r <= special_case;
        if (special_case) begin
          count_r <= 6'd1;
          remainder_r <= 66'd0;
          quotient_r <= 64'd0;
          dividend_shift_r <= 64'd0;
          divisor_r <= 66'd0;
          complete_value_r <= special_result;
        end else begin
          count_r <= word_op ? 6'd16 : 6'd32;
          remainder_r <= 66'd0;
          quotient_r <= 64'd0;
          dividend_shift_r <= abs_dividend;
          divisor_r <= {2'b00, abs_divisor};
          complete_value_r <= {VALUE_WIDTH{1'b0}};
        end
      end

    end
  end
endmodule

`endif
