module edge_fpu_misc #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter VALUE_WIDTH = 64,
  parameter OP_WIDTH = 4
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,
  input  wire                       misc_issue_valid,
  output wire                       misc_issue_ready,
  input  wire [SEQ_ID_WIDTH-1:0]    misc_issue_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     misc_issue_epoch,
  input  wire [OP_WIDTH-1:0]        misc_issue_op,
  input  wire [1:0]                 misc_issue_fmt,
  input  wire [2:0]                 misc_issue_rm,
  input  wire [2:0]                 misc_issue_funct3,
  input  wire [REG_INDEX_WIDTH-1:0] misc_issue_rd,
  input  wire                       misc_issue_rd_bank,
  input  wire [31:0]                misc_issue_fsrc0,
  input  wire [31:0]                misc_issue_fsrc1,
  input  wire [VALUE_WIDTH-1:0]     misc_issue_gsrc0,
  output reg                        misc_complete_valid,
  output reg  [SEQ_ID_WIDTH-1:0]    misc_complete_seq_id,
  output reg  [EPOCH_WIDTH-1:0]     misc_complete_epoch,
  output reg  [REG_INDEX_WIDTH-1:0] misc_complete_rd,
  output reg                        misc_complete_rd_bank,
  output reg                        misc_complete_domain,
  output reg  [VALUE_WIDTH-1:0]     misc_complete_value,
  output reg  [4:0]                 misc_complete_fflags
);

  localparam [OP_WIDTH-1:0] OP_SGNJ  = 4'd0;
  localparam [OP_WIDTH-1:0] OP_MINMAX = 4'd1;
  localparam [OP_WIDTH-1:0] OP_CMP   = 4'd2;
  localparam [OP_WIDTH-1:0] OP_CLASS = 4'd3;
  localparam [OP_WIDTH-1:0] OP_MV_X_F = 4'd4;
  localparam [OP_WIDTH-1:0] OP_MV_F_X = 4'd5;

  localparam [1:0] FMT_S = 2'b00;
  localparam [1:0] FMT_H = 2'b10;

  reg [VALUE_WIDTH-1:0] result_d;
  reg result_domain_d;
  reg [4:0] fflags_d;
  reg [15:0] half_payload;
  reg [31:0] fpr_result;
  reg less_than;
  reg equal;
  wire src0_nan = (&misc_issue_fsrc0[30:23]) && (|misc_issue_fsrc0[22:0]);
  wire src1_nan = (&misc_issue_fsrc1[30:23]) && (|misc_issue_fsrc1[22:0]);
  wire src0_snan = src0_nan && !misc_issue_fsrc0[22];
  wire src1_snan = src1_nan && !misc_issue_fsrc1[22];
  wire src0_zero = (misc_issue_fsrc0[30:0] == 31'b0);
  wire src1_zero = (misc_issue_fsrc1[30:0] == 31'b0);

  assign misc_issue_ready = 1'b1;

  function [15:0] fp32_to_fp16;
    input [31:0] value;
    input [2:0] rm;
    reg sign;
    reg [7:0] exp;
    reg [22:0] frac;
    reg [23:0] sig;
    reg [10:0] kept;
    reg [24:0] rounded;
    reg [22:0] discarded_mask;
    reg guard;
    reg sticky;
    reg increment;
    reg [5:0] half_exp;
    reg overflow_to_inf;
    integer unbiased;
    integer shift;
    begin
      sign = value[31]; exp = value[30:23]; frac = value[22:0];
      if (exp == 8'hff) begin
        fp32_to_fp16 = (frac == 0) ? {sign, 5'h1f, 10'b0} : 16'h7e00;
      end else if (exp == 0 && frac == 0) begin
        fp32_to_fp16 = {sign, 15'b0};
      end else begin
        unbiased = (exp == 0) ? -126 : exp - 127;
        sig = (exp == 0) ? {1'b0, frac} : {1'b1, frac};
        shift = (unbiased < -14) ? (-14 - unbiased + 13) : 13;
        if (shift >= 25) begin
          kept = 0; guard = 0; sticky = |sig;
        end else begin
          kept = sig >> shift;
          guard = (shift > 0) ? sig[shift-1] : 1'b0;
          discarded_mask = (shift > 1) ? ((23'h1 << (shift-1)) - 1'b1) : 23'b0;
          sticky = |(sig[22:0] & discarded_mask);
        end
        case (rm)
          3'd0: increment = guard && (sticky || kept[0]);
          3'd1: increment = 1'b0;
          3'd2: increment = sign && (guard || sticky);
          3'd3: increment = !sign && (guard || sticky);
          3'd4: increment = guard;
          default: increment = guard && (sticky || kept[0]);
        endcase
        rounded = {14'b0, kept} + increment;
        overflow_to_inf = (rm == 3'd0) || (rm == 3'd4) ||
                          ((rm == 3'd2) && sign) ||
                          ((rm == 3'd3) && !sign);
        if (unbiased > 15 || (unbiased == 15 && rounded[11]))
          fp32_to_fp16 = overflow_to_inf ? {sign, 5'h1f, 10'b0}
                                         : {sign, 5'h1e, 10'h3ff};
        else if (unbiased >= -14) begin
          half_exp = unbiased + 15 + rounded[11];
          fp32_to_fp16 = {sign, half_exp[4:0],
                          rounded[11] ? 10'b0 : rounded[9:0]};
        end
        else if (rounded[10])
          fp32_to_fp16 = {sign, 5'h01, 10'b0};
        else
          fp32_to_fp16 = {sign, 5'b0, rounded[9:0]};
      end
    end
  endfunction

  function [31:0] fp16_to_fp32;
    input [15:0] value;
    integer i;
    integer lead;
    reg [9:0] frac;
    reg [7:0] out_exp;
    reg found;
    begin
      frac = value[9:0];
      if (value[14:10] == 5'h1f)
        fp16_to_fp32 = (frac == 0) ? {value[15], 8'hff, 23'b0} : 32'h7fc00000;
      else if (value[14:10] != 0)
        fp16_to_fp32 = {value[15], value[14:10] + 8'd112, frac, 13'b0};
      else if (frac == 0)
        fp16_to_fp32 = {value[15], 31'b0};
      else begin
        lead = 0; found = 0;
        for (i = 9; i >= 0; i = i - 1)
          if (!found && frac[i]) begin lead = 9-i; found = 1; end
        out_exp = 8'd112 - lead;
        fp16_to_fp32 = {value[15], out_exp, (frac << (lead+1)), 13'b0};
      end
    end
  endfunction

  function fp32_lt;
    input [31:0] a;
    input [31:0] b;
    begin
      if (a[30:0] == 0 && b[30:0] == 0) fp32_lt = 1'b0;
      else if (a[31] != b[31]) fp32_lt = a[31];
      else if (a[31]) fp32_lt = a[30:0] > b[30:0];
      else fp32_lt = a[30:0] < b[30:0];
    end
  endfunction

  always @* begin
    result_d = {VALUE_WIDTH{1'b0}};
    result_domain_d = 1'b0;
    fflags_d = 5'b0;
    fpr_result = 32'b0;
    half_payload = fp32_to_fp16(misc_issue_fsrc0, misc_issue_rm);
    equal = (misc_issue_fsrc0 == misc_issue_fsrc1) || (src0_zero && src1_zero);
    less_than = fp32_lt(misc_issue_fsrc0, misc_issue_fsrc1);
    case (misc_issue_op)
      OP_SGNJ: begin
        result_domain_d = 1'b1;
        case (misc_issue_funct3)
          3'b000: fpr_result = {misc_issue_fsrc1[31], misc_issue_fsrc0[30:0]};
          3'b001: fpr_result = {!misc_issue_fsrc1[31], misc_issue_fsrc0[30:0]};
          default: fpr_result = {misc_issue_fsrc0[31] ^ misc_issue_fsrc1[31], misc_issue_fsrc0[30:0]};
        endcase
        result_d = {{(VALUE_WIDTH-32){1'b0}}, fpr_result};
      end
      OP_MINMAX: begin
        result_domain_d = 1'b1;
        fflags_d[4] = src0_snan || src1_snan;
        if (src0_nan && src1_nan) fpr_result = 32'h7fc00000;
        else if (src0_nan) fpr_result = misc_issue_fsrc1;
        else if (src1_nan) fpr_result = misc_issue_fsrc0;
        else if (equal && src0_zero) begin
          if (misc_issue_funct3[0]) fpr_result = {misc_issue_fsrc0[31] & misc_issue_fsrc1[31], 31'b0};
          else fpr_result = {misc_issue_fsrc0[31] | misc_issue_fsrc1[31], 31'b0};
        end else if (misc_issue_funct3[0])
          fpr_result = less_than ? misc_issue_fsrc1 : misc_issue_fsrc0;
        else
          fpr_result = less_than ? misc_issue_fsrc0 : misc_issue_fsrc1;
        result_d = {{(VALUE_WIDTH-32){1'b0}}, fpr_result};
      end
      OP_CMP: begin
        fflags_d[4] = (misc_issue_funct3 == 3'b010) ? (src0_snan || src1_snan) : (src0_nan || src1_nan);
        if (src0_nan || src1_nan) result_d = 0;
        else case (misc_issue_funct3)
          3'b010: result_d = equal;
          3'b001: result_d = less_than;
          default: result_d = less_than || equal;
        endcase
      end
      OP_CLASS: begin
        if (misc_issue_fsrc0[30:23] == 8'hff)
          result_d = (misc_issue_fsrc0[22:0] == 0) ? (misc_issue_fsrc0[31] ? 10'b0000000001 : 10'b0010000000)
                                                   : (misc_issue_fsrc0[22] ? 10'b1000000000 : 10'b0100000000);
        else if (misc_issue_fsrc0[30:23] == 0)
          result_d = (misc_issue_fsrc0[22:0] == 0) ? (misc_issue_fsrc0[31] ? 10'b0000001000 : 10'b0000010000)
                                                   : (misc_issue_fsrc0[31] ? 10'b0000000100 : 10'b0000100000);
        else result_d = misc_issue_fsrc0[31] ? 10'b0000000010 : 10'b0001000000;
      end
      OP_MV_X_F: begin
        if (misc_issue_fmt == FMT_H)
          result_d = {{(VALUE_WIDTH-16){half_payload[15]}}, half_payload};
        else
          result_d = {{(VALUE_WIDTH-32){misc_issue_fsrc0[31]}}, misc_issue_fsrc0};
      end
      OP_MV_F_X: begin
        result_domain_d = 1'b1;
        fpr_result = (misc_issue_fmt == FMT_H) ? fp16_to_fp32(misc_issue_gsrc0[15:0])
                                               : misc_issue_gsrc0[31:0];
        result_d = {{(VALUE_WIDTH-32){1'b0}}, fpr_result};
      end
      default: begin end
    endcase
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      misc_complete_valid <= 1'b0;
      misc_complete_seq_id <= 0;
      misc_complete_epoch <= 0;
      misc_complete_rd <= 0;
      misc_complete_rd_bank <= 1'b0;
      misc_complete_domain <= 1'b0;
      misc_complete_value <= 0;
      misc_complete_fflags <= 0;
    end else begin
      misc_complete_valid <= misc_issue_valid && misc_issue_ready;
      if (misc_issue_valid && misc_issue_ready) begin
        misc_complete_seq_id <= misc_issue_seq_id;
        misc_complete_epoch <= misc_issue_epoch;
        misc_complete_rd <= misc_issue_rd;
        misc_complete_rd_bank <= misc_issue_rd_bank;
        misc_complete_domain <= result_domain_d;
        misc_complete_value <= result_d;
        misc_complete_fflags <= fflags_d;
      end
    end
  end
endmodule
