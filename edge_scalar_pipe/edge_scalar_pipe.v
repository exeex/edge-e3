// First-slice scalar pipe with GPR/FPR files, WBTs, and placeholder completion.
module edge_scalar_pipe #(
  parameter PC_WIDTH           = 40,
  parameter SEQ_ID_WIDTH       = 8,
  parameter EPOCH_WIDTH        = 4,
  parameter REG_INDEX_WIDTH    = 5,
  parameter VALUE_WIDTH        = 64,
  parameter PRODUCER_TAG_WIDTH = 16,
  parameter PSEUDO_WIDTH       = 3,
  parameter ENABLE_EARLY_LOAD_RETIRE = 0,
  parameter ENABLE_COMMITTED_STORE_DRAIN = 0
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,
  input  wire                         edge_dtcm_enable,
  input  wire [VALUE_WIDTH-1:0]       edge_dtcm_base,
  input  wire [VALUE_WIDTH-1:0]       edge_dtcm_mask,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_dtcm_store_query_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_dtcm_store_query_epoch,

  input  wire                         issue_valid,
  output wire                         issue_ready,
  input  wire                         issue1_valid,
  output wire                         issue1_ready,
  input  wire                         retire_alloc_ready,
  input  wire                         ordered_retire0_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      ordered_retire0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       ordered_retire0_epoch,
  input  wire                         ordered_retire1_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      ordered_retire1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       ordered_retire1_epoch,
  input  wire [PC_WIDTH-1:0]          issue_pc,
  input  wire [31:0]                  issue_inst,
  input  wire                         issue_len,
  input  wire                         issue_is_pseudo,
  input  wire [PSEUDO_WIDTH-1:0]      issue_pseudo_kind,
  input  wire [SEQ_ID_WIDTH-1:0]      issue_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       issue_epoch,
  input  wire [PC_WIDTH-1:0]          issue1_pc,
  input  wire [31:0]                  issue1_inst,
  input  wire                         issue1_is_pseudo,
  input  wire [PSEUDO_WIDTH-1:0]      issue1_pseudo_kind,
  input  wire [SEQ_ID_WIDTH-1:0]      issue1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       issue1_epoch,

  input  wire                         scalar_def_valid,
  input  wire                         scalar_def_domain,
  input  wire [REG_INDEX_WIDTH-1:0]   scalar_def_dst_reg,
  input  wire                         scalar_def_bank,
  input  wire [SEQ_ID_WIDTH-1:0]      scalar_def_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       scalar_def_epoch,
  input  wire                         scalar1_def_valid,
  input  wire [REG_INDEX_WIDTH-1:0]   scalar1_def_dst_reg,
  input  wire                         scalar1_def_bank,
  input  wire [SEQ_ID_WIDTH-1:0]      scalar1_def_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       scalar1_def_epoch,

  input  wire                         gpr_placeholder_complete_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      gpr_placeholder_complete_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       gpr_placeholder_complete_epoch,
  input  wire [REG_INDEX_WIDTH-1:0]   gpr_placeholder_complete_reg,
  input  wire                         gpr_placeholder_complete_bank,
  input  wire [VALUE_WIDTH-1:0]       gpr_placeholder_complete_value,

  input  wire                         lsu_load_resp_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_load_resp_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_load_resp_epoch,
  input  wire                         lsu_load_resp_error,
  input  wire [VALUE_WIDTH-1:0]       lsu_load_resp_value,
  output wire                         lsu_load_req_valid,
  input  wire                         lsu_load_req_ready,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_load_req_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_load_req_epoch,
  output wire [VALUE_WIDTH-1:0]       lsu_load_req_addr,
  output wire [1:0]                   lsu_load_req_size,
  output wire                         lsu_load_req_signed,
  output wire                         lsu_load_req1_valid,
  input  wire                         lsu_load_req1_ready,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_load_req1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_load_req1_epoch,
  output wire [VALUE_WIDTH-1:0]       lsu_load_req1_addr,
  output wire [1:0]                   lsu_load_req1_size,
  output wire                         lsu_load_req1_signed,
  output wire                         lsu_store_req_valid,
  input  wire                         lsu_store_req_ready,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_store_req_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_store_req_epoch,
  output wire [VALUE_WIDTH-1:0]       lsu_store_req_addr,
  output wire [1:0]                   lsu_store_req_size,
  output wire [VALUE_WIDTH-1:0]       lsu_store_req_data,
  output wire [(VALUE_WIDTH/8)-1:0]   lsu_store_req_wstrb,
  output wire                         lsu_store_req1_valid,
  input  wire                         lsu_store_req1_ready,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_store_req1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_store_req1_epoch,
  output wire [VALUE_WIDTH-1:0]       lsu_store_req1_addr,
  output wire [1:0]                   lsu_store_req1_size,
  output wire [VALUE_WIDTH-1:0]       lsu_store_req1_data,
  output wire [(VALUE_WIDTH/8)-1:0]   lsu_store_req1_wstrb,

  input  wire                         fpr_placeholder_complete_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      fpr_placeholder_complete_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       fpr_placeholder_complete_epoch,
  input  wire [REG_INDEX_WIDTH-1:0]   fpr_placeholder_complete_reg,
  input  wire                         fpr_placeholder_complete_bank,
  input  wire [31:0]                  fpr_placeholder_complete_value,

  input  wire                         redirect_kill_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      redirect_kill_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       redirect_kill_epoch,

  output wire                         producer_valid,
  output wire                         producer_domain,
  output wire [REG_INDEX_WIDTH-1:0]   producer_reg,
  output wire                         producer_bank,
  output wire [PRODUCER_TAG_WIDTH-1:0] producer_tag,
  output wire [VALUE_WIDTH-1:0]       producer_value,
  output wire [EPOCH_WIDTH-1:0]       producer_epoch,

  output wire                         retire_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire_epoch,
  output wire                         retire_is_pseudo,

  output wire                         retire_alloc_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire_alloc_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire_alloc_epoch,
  output wire [1:0]                   retire_alloc_kind,
  output wire                         retire_alloc_serializing,
  output wire                         retire_alloc1_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire_alloc1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire_alloc1_epoch,
  output wire [1:0]                   retire_alloc1_kind,
  output wire                         retire_alloc1_serializing,
  output wire                         retire_complete0_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire_complete0_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire_complete0_epoch,
  output wire                         retire_complete1_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire_complete1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire_complete1_epoch,
  output wire                         retire_complete2_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire_complete2_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire_complete2_epoch,
  output wire                         retire_complete3_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire_complete3_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire_complete3_epoch,
  output wire                         retire_complete4_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire_complete4_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire_complete4_epoch,
  output wire                         retire_complete5_valid,
  output wire [SEQ_ID_WIDTH-1:0]      retire_complete5_seq_id,
  output wire [EPOCH_WIDTH-1:0]       retire_complete5_epoch,

  output wire                         mem_placeholder_valid,
  output wire                         mem_placeholder_is_store,
  output wire [1:0]                   mem_placeholder_size,
  output wire                         mem_placeholder_load_signed,
  output wire [VALUE_WIDTH-1:0]       mem_placeholder_addr,
  output wire [VALUE_WIDTH-1:0]       mem_placeholder_store_data,
  output wire [SEQ_ID_WIDTH-1:0]      mem_placeholder_seq_id,
  output wire [EPOCH_WIDTH-1:0]       mem_placeholder_epoch,
  output wire                         mem_placeholder1_valid,
  output wire                         mem_placeholder1_is_store,
  output wire [1:0]                   mem_placeholder1_size,
  output wire                         mem_placeholder1_load_signed,
  output wire [VALUE_WIDTH-1:0]       mem_placeholder1_addr,
  output wire [VALUE_WIDTH-1:0]       mem_placeholder1_store_data,
  output wire [SEQ_ID_WIDTH-1:0]      mem_placeholder1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       mem_placeholder1_epoch,

  output wire                         system_placeholder_valid,
  output wire [2:0]                   system_placeholder_funct3,
  output wire [11:0]                  system_placeholder_csr,
  output wire [REG_INDEX_WIDTH-1:0]   system_placeholder_rd,
  output wire [REG_INDEX_WIDTH-1:0]   system_placeholder_rs1,
  output wire [VALUE_WIDTH-1:0]       system_placeholder_rs1_value,
  output wire [SEQ_ID_WIDTH-1:0]      system_placeholder_seq_id,
  output wire [EPOCH_WIDTH-1:0]       system_placeholder_epoch,

  output wire                         cache_op_valid,
  input  wire                         cache_op_ready,
  output wire                         cache_op_is_va,
  output wire [1:0]                   cache_op_kind,
  output wire [VALUE_WIDTH-1:0]       cache_op_addr,
  output wire [SEQ_ID_WIDTH-1:0]      cache_op_seq_id,
  output wire [EPOCH_WIDTH-1:0]       cache_op_epoch,
  input  wire                         cache_op_complete_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      cache_op_complete_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       cache_op_complete_epoch,

  output wire                         dma_start_valid,
  input  wire                         dma_start_ready,
  output wire [VALUE_WIDTH-1:0]       dma_start_src,
  output wire [VALUE_WIDTH-1:0]       dma_start_dst,
  output wire [VALUE_WIDTH-1:0]       dma_start_len,
  output wire [SEQ_ID_WIDTH-1:0]      dma_start_seq_id,
  output wire [EPOCH_WIDTH-1:0]       dma_start_epoch,
  output wire                         dma_sync_valid,
  input  wire                         dma_sync_ready,
  output wire [SEQ_ID_WIDTH-1:0]      dma_sync_seq_id,
  output wire [EPOCH_WIDTH-1:0]       dma_sync_epoch,

  output wire                         fence_placeholder_valid,
  output wire                         fence_placeholder_i,
  output wire [SEQ_ID_WIDTH-1:0]      fence_placeholder_seq_id,
  output wire [EPOCH_WIDTH-1:0]       fence_placeholder_epoch,

  output wire                         fatal_report_valid,
  output wire [3:0]                   fatal_report_code,
  output wire [VALUE_WIDTH-1:0]       fatal_report_inst,
  output wire [SEQ_ID_WIDTH-1:0]      fatal_report_seq_id,
  output wire [EPOCH_WIDTH-1:0]       fatal_report_epoch,
  output wire                         ebreak_report_valid,
  output wire [SEQ_ID_WIDTH-1:0]      ebreak_report_seq_id,
  output wire [EPOCH_WIDTH-1:0]       ebreak_report_epoch,

  output wire                         control_placeholder_valid,
  output wire                         control_placeholder_taken,
  output wire [PC_WIDTH-1:0]          control_placeholder_target,
  output wire [SEQ_ID_WIDTH-1:0]      control_placeholder_seq_id,
  output wire [EPOCH_WIDTH-1:0]       control_placeholder_epoch,

  output wire                         tensor_gpr_snapshot_valid,
  output wire [SEQ_ID_WIDTH-1:0]      tensor_gpr_snapshot_seq_id,
  output wire [EPOCH_WIDTH-1:0]       tensor_gpr_snapshot_epoch,
  output wire [2:0]                   tensor_gpr_snapshot_target,
  output wire                         tensor_gpr_snapshot_operand_valid,
  output wire [VALUE_WIDTH-1:0]       tensor_gpr_snapshot_operand_value,

  input  wire                         reverse_snapshot_read_ready,
  input  wire [VALUE_WIDTH-1:0]       reverse_snapshot_read_value,
  output wire                         reverse_snapshot_read_id,
  output wire                         reverse_snapshot_consume_valid,
  output wire                         reverse_snapshot_consume_id,

  output wire                         lsu_dtcm_store_pending,
  output wire [31:0]                  gpr_busy_status
`ifdef EDGE_DEBUG
  ,
  input  wire [REG_INDEX_WIDTH-1:0]   debug_gpr_read_reg,
  output wire [VALUE_WIDTH-1:0]       debug_gpr_read_data,
  input  wire [REG_INDEX_WIDTH-1:0]   debug_fpr_read_reg,
  output wire [VALUE_WIDTH-1:0]       debug_fpr_read_data,
  output wire [31:0]                  debug_fpr_busy,
  output wire                         debug_redirect_block,
  output wire                         debug_retire_alloc_ready,
  output wire                         debug_producer_queue_ready,
  output wire [3:0]                   debug_producer_queue_count,
  output wire                         debug_gpr_issue_ready,
  output wire                         debug_fpr_issue_ready,
  output wire                         debug_alu_issue_ready,
  output wire                         debug_lsu_issue_ready,
  output wire                         debug_sys_issue_ready,
  output wire                         debug_issue_gpr_check_candidate,
  output wire                         debug_issue_fpr_dst_candidate,
  output wire                         debug_is_alu_or_branch,
  output wire                         debug_is_lsu_op,
  output wire                         debug_is_sys_or_fence
`endif
);

  localparam [6:0] OPCODE_LOAD    = 7'b0000011;
  localparam [6:0] OPCODE_LOAD_FP = 7'b0000111;
  localparam [6:0] OPCODE_MISC_MEM = 7'b0001111;
  localparam [6:0] OPCODE_OP_IMM  = 7'b0010011;
  localparam [6:0] OPCODE_AUIPC   = 7'b0010111;
  localparam [6:0] OPCODE_OP_IMM32 = 7'b0011011;
  localparam [6:0] OPCODE_STORE   = 7'b0100011;
  localparam [6:0] OPCODE_STORE_FP = 7'b0100111;
  localparam [6:0] OPCODE_OP      = 7'b0110011;
  localparam [6:0] OPCODE_LUI     = 7'b0110111;
  localparam [6:0] OPCODE_OP32    = 7'b0111011;
  localparam [6:0] OPCODE_MADD    = 7'b1000011;
  localparam [6:0] OPCODE_MSUB    = 7'b1000111;
  localparam [6:0] OPCODE_NMSUB   = 7'b1001011;
  localparam [6:0] OPCODE_NMADD   = 7'b1001111;
  localparam [6:0] OPCODE_OP_FP   = 7'b1010011;
  localparam [6:0] OPCODE_BRANCH  = 7'b1100011;
  localparam [6:0] OPCODE_JALR    = 7'b1100111;
  localparam [6:0] OPCODE_JAL     = 7'b1101111;
  localparam [6:0] OPCODE_SYSTEM  = 7'b1110011;
  localparam [6:0] OPCODE_EDGE_CACHE = 7'b0001011;
  localparam [6:0] OPCODE_EDGE_DMA   = 7'b0101011;
  localparam [11:0] CSR_CYCLE     = 12'hc00;
  localparam [3:0] ALU_OP_OP_IMM   = 4'd0;
  localparam [3:0] ALU_OP_OP       = 4'd1;
  localparam [3:0] ALU_OP_OP_IMM32 = 4'd2;
  localparam [3:0] ALU_OP_OP32     = 4'd3;
  localparam [3:0] ALU_OP_LUI      = 4'd4;
  localparam [3:0] ALU_OP_AUIPC    = 4'd5;
  localparam [3:0] ALU_OP_JAL      = 4'd6;
  localparam [3:0] ALU_OP_JALR     = 4'd7;
  localparam [3:0] ALU_OP_BRANCH   = 4'd8;
  localparam [3:0] ALU_OP_ZBA      = 4'd9;
  localparam [3:0] ALU_OP_ZBA_UW   = 4'd10;
  localparam [3:0] FPU_MISC_SGNJ   = 4'd0;
  localparam [3:0] FPU_MISC_MINMAX = 4'd1;
  localparam [3:0] FPU_MISC_CMP    = 4'd2;
  localparam [3:0] FPU_MISC_CLASS  = 4'd3;
  localparam [3:0] FPU_MISC_MV_X_F = 4'd4;
  localparam [3:0] FPU_MISC_MV_F_X = 4'd5;
  localparam [1:0] FPU_CVT_F2F     = 2'd0;
  localparam [1:0] FPU_CVT_F2I     = 2'd1;
  localparam [1:0] FPU_CVT_I2F     = 2'd2;
  localparam [1:0] RETIRE_KIND_SCALAR = 2'd0;
  localparam [PSEUDO_WIDTH-1:0] PSEUDO_TENSOR_JOIN =
    {{(PSEUDO_WIDTH-1){1'b0}}, 1'b1};
  localparam [PSEUDO_WIDTH-1:0] PSEUDO_TENSOR_GPR_HOLDER =
    {{(PSEUDO_WIDTH-2){1'b0}}, 2'b10};
  localparam [PSEUDO_WIDTH-1:0] PSEUDO_ACCEL_GETCSR =
    {{(PSEUDO_WIDTH-2){1'b0}}, 2'b11};
`ifdef EDGE_SCALAR_LSU_QUEUE_DEPTH
  localparam SCALAR_LSU_QUEUE_DEPTH = `EDGE_SCALAR_LSU_QUEUE_DEPTH;
`else
  localparam SCALAR_LSU_QUEUE_DEPTH = 4;
`endif
`ifdef EDGE_SCALAR_LOAD_QUEUE_DEPTH
  localparam SCALAR_LOAD_QUEUE_DEPTH = `EDGE_SCALAR_LOAD_QUEUE_DEPTH;
`else
  localparam SCALAR_LOAD_QUEUE_DEPTH = 2;
`endif
  localparam SCALAR_LOAD_QUEUE_COUNT_WIDTH =
    $clog2(SCALAR_LOAD_QUEUE_DEPTH + 1);
  localparam PRODUCER_QUEUE_DEPTH = 8;
  localparam PRODUCER_QUEUE_INDEX_WIDTH = $clog2(PRODUCER_QUEUE_DEPTH);
  localparam PRODUCER_QUEUE_COUNT_WIDTH = $clog2(PRODUCER_QUEUE_DEPTH + 1);

  function [31:0] fp16_to_fp32;
    input [15:0] value;
    integer shift;
    integer bit_index;
    reg [9:0] frac;
    reg [7:0] exponent;
    reg found;
    begin
      if (value[14:10] == 5'h00) begin
        if (value[9:0] == 10'h000) begin
          fp16_to_fp32 = {value[15], 31'b0};
        end else begin
          frac = value[9:0];
          shift = 0;
          found = 1'b0;
          for (bit_index = 9; bit_index >= 0; bit_index = bit_index - 1) begin
            if (!found && value[bit_index]) begin
              shift = 9 - bit_index;
              found = 1'b1;
            end
          end
          frac = frac << shift;
          exponent = 8'd112 - shift;
          fp16_to_fp32 = {value[15], exponent, frac[8:0], 14'b0};
        end
      end else if (value[14:10] == 5'h1f) begin
        fp16_to_fp32 = value[9:0] == 10'h000 ?
                       {value[15], 8'hff, 23'b0} :
                       32'h7fc0_0000;
      end else begin
        fp16_to_fp32 = {value[15], value[14:10] + 8'd112,
                        value[9:0], 13'b0};
      end
    end
  endfunction

  function [31:0] bf16_to_fp32;
    input [15:0] value;
    begin
      bf16_to_fp32 = (value[14:7] == 8'hff && value[6:0] != 7'b0) ?
                     32'h7fc0_0000 :
                     {value[15:0], 16'b0};
    end
  endfunction

  function redirect_kills_seq;
    input [SEQ_ID_WIDTH-1:0] candidate_seq;
    input [EPOCH_WIDTH-1:0] candidate_epoch;
    reg [SEQ_ID_WIDTH-1:0] distance;
    begin
      distance = candidate_seq - redirect_kill_seq_id;
      redirect_kills_seq = redirect_kill_valid &&
                           (candidate_epoch == redirect_kill_epoch) &&
                           (distance != {SEQ_ID_WIDTH{1'b0}}) &&
                           !distance[SEQ_ID_WIDTH-1];
    end
  endfunction

  function [31:0] fp64_to_fp32_rne;
    input [63:0] value;
    integer unbiased;
    integer rshift;
    reg [52:0] sig;
    reg [24:0] rounded;
    reg [23:0] base;
    reg guard_bit;
    reg sticky_bit;
    reg [7:0] out_exp;
    begin
      sig = {1'b1, value[51:0]};
      if (value[62:52] == 11'h7ff) begin
        fp64_to_fp32_rne = value[51:0] == 52'b0 ?
                           {value[63], 8'hff, 23'b0} :
                           32'h7fc0_0000;
      end else if (value[62:52] == 11'h000) begin
        fp64_to_fp32_rne = {value[63], 31'b0};
      end else begin
        unbiased = value[62:52] - 1023;
        if (unbiased > 127) begin
          fp64_to_fp32_rne = {value[63], 8'hff, 23'b0};
        end else if (unbiased >= -126) begin
          base = sig >> 29;
          guard_bit = value[28];
          sticky_bit = |value[27:0];
          rounded = {1'b0, base} +
                    (guard_bit && (sticky_bit || base[0]));
          if (rounded[24]) begin
            out_exp = unbiased + 128;
            fp64_to_fp32_rne = out_exp == 8'hff ?
              {value[63], 8'hff, 23'b0} :
              {value[63], out_exp, rounded[23:1]};
          end else begin
            out_exp = unbiased + 127;
            fp64_to_fp32_rne = {value[63], out_exp, rounded[22:0]};
          end
        end else if (unbiased >= -150) begin
          rshift = (-126 - unbiased) + 29;
          base = sig >> rshift;
          guard_bit = (sig >> (rshift - 1)) & 1'b1;
          sticky_bit = sig != ((sig >> (rshift - 1)) << (rshift - 1));
          rounded = {1'b0, base} +
                    (guard_bit && (sticky_bit || base[0]));
          fp64_to_fp32_rne = rounded[23] ?
            {value[63], 8'h01, 23'b0} :
            {value[63], 8'h00, rounded[22:0]};
        end else begin
          fp64_to_fp32_rne = {value[63], 31'b0};
        end
      end
    end
  endfunction

  function [15:0] fp32_to_fp16_rne;
    input [31:0] value;
    integer unbiased;
    integer rshift;
    reg [23:0] sig;
    reg [11:0] rounded;
    reg [10:0] base;
    reg guard_bit;
    reg sticky_bit;
    reg [4:0] out_exp;
    begin
      sig = {1'b1, value[22:0]};
      if (value[30:23] == 8'hff) begin
        fp32_to_fp16_rne = value[22:0] == 23'b0 ?
                           {value[31], 5'h1f, 10'b0} :
                           16'h7e00;
      end else if (value[30:23] == 8'h00) begin
        fp32_to_fp16_rne = {value[31], 15'b0};
      end else begin
        unbiased = value[30:23] - 127;
        if (unbiased > 15) begin
          fp32_to_fp16_rne = {value[31], 5'h1f, 10'b0};
        end else if (unbiased >= -14) begin
          base = sig >> 13;
          guard_bit = value[12];
          sticky_bit = |value[11:0];
          rounded = {1'b0, base} +
                    (guard_bit && (sticky_bit || base[0]));
          if (rounded[11]) begin
            out_exp = unbiased + 16;
            fp32_to_fp16_rne = out_exp == 5'h1f ?
              {value[31], 5'h1f, 10'b0} :
              {value[31], out_exp, rounded[10:1]};
          end else begin
            out_exp = unbiased + 15;
            fp32_to_fp16_rne = {value[31], out_exp, rounded[9:0]};
          end
        end else if (unbiased >= -25) begin
          rshift = (-14 - unbiased) + 13;
          base = sig >> rshift;
          guard_bit = (sig >> (rshift - 1)) & 1'b1;
          sticky_bit = sig != ((sig >> (rshift - 1)) << (rshift - 1));
          rounded = {1'b0, base} +
                    (guard_bit && (sticky_bit || base[0]));
          fp32_to_fp16_rne = rounded[10] ?
            {value[31], 5'h01, 10'b0} :
            {value[31], 5'h00, rounded[9:0]};
        end else begin
          fp32_to_fp16_rne = {value[31], 15'b0};
        end
      end
    end
  endfunction

  function [15:0] fp32_to_bf16_rne;
    input [31:0] value;
    reg [16:0] rounded;
    begin
      if (value[30:23] == 8'hff && value[22:0] != 23'b0) begin
        fp32_to_bf16_rne = 16'h7fc0;
      end else begin
        rounded = {1'b0, value[31:16]} +
                  (value[15] && ((|value[14:0]) || value[16]));
        fp32_to_bf16_rne = rounded[16] ?
                           {value[31], 8'hff, 7'b0} :
                           rounded[15:0];
      end
    end
  endfunction

  function [63:0] fp32_to_fp64;
    input [31:0] value;
    integer shift;
    integer bit_index;
    reg [22:0] frac;
    reg [10:0] exponent;
    reg found;
    begin
      if (value[30:23] == 8'h00) begin
        if (value[22:0] == 23'b0) begin
          fp32_to_fp64 = {value[31], 63'b0};
        end else begin
          frac = value[22:0];
          shift = 0;
          found = 1'b0;
          for (bit_index = 22; bit_index >= 0; bit_index = bit_index - 1) begin
            if (!found && value[bit_index]) begin
              shift = 22 - bit_index;
              found = 1'b1;
            end
          end
          frac = frac << shift;
          exponent = 11'd896 - shift;
          fp32_to_fp64 = {value[31], exponent, frac[21:0], 30'b0};
        end
      end else if (value[30:23] == 8'hff) begin
        fp32_to_fp64 = value[22:0] == 23'b0 ?
                       {value[31], 11'h7ff, 52'b0} :
                       64'h7ff8_0000_0000_0000;
      end else begin
        fp32_to_fp64 = {value[31], value[30:23] + 11'd896,
                        value[22:0], 29'b0};
      end
    end
  endfunction

  reg [VALUE_WIDTH-1:0] gpr [0:31];
  reg [31:0] fpr [0:31];
  reg [VALUE_WIDTH-1:0] cycle_counter_q;

  wire [6:0] opcode;
  wire [6:0] opcode1;
  wire [2:0] funct3;
  wire [2:0] funct3_1;
  wire [REG_INDEX_WIDTH-1:0] rd;
  wire [REG_INDEX_WIDTH-1:0] rd1;
  wire [REG_INDEX_WIDTH-1:0] rs1;
  wire [REG_INDEX_WIDTH-1:0] rs1_1;
  wire [REG_INDEX_WIDTH-1:0] rs2;
  wire [REG_INDEX_WIDTH-1:0] rs2_1;
  wire [REG_INDEX_WIDTH-1:0] rs3;
  wire [11:0] imm12;
  wire [11:0] imm12_1;
  wire [11:0] store_imm12;
  wire [11:0] store_imm12_1;
  wire [VALUE_WIDTH-1:0] imm12_sext;
  wire [VALUE_WIDTH-1:0] imm12_1_sext;
  wire [VALUE_WIDTH-1:0] store_imm12_sext;
  wire [VALUE_WIDTH-1:0] store_imm12_1_sext;
  wire [VALUE_WIDTH-1:0] lui_value;
  wire [VALUE_WIDTH-1:0] lui1_value;
  wire [VALUE_WIDTH-1:0] branch_imm_sext;
  wire [VALUE_WIDTH-1:0] jal_imm_sext;
  wire [VALUE_WIDTH-1:0] rs1_value;
  wire [VALUE_WIDTH-1:0] rs1_1_value;
  wire [VALUE_WIDTH-1:0] rs1_1_alu_value;
  wire [VALUE_WIDTH-1:0] rs2_value;
  wire [VALUE_WIDTH-1:0] rs2_1_value;
  wire [VALUE_WIDTH-1:0] rs2_1_alu_value;
  wire [VALUE_WIDTH-1:0] rd_value;
  wire [VALUE_WIDTH-1:0] rd1_value;
  wire [31:0] fpr_rs1_value;
  wire [31:0] fpr_rs2_value;
  wire [31:0] fpr_rs3_value;
  wire gpr_load_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] gpr_load_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] gpr_load_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] gpr_load_complete_reg;
  wire gpr_load_complete_bank;
  wire [VALUE_WIDTH-1:0] gpr_load_complete_value;
  wire gpr_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] gpr_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] gpr_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] gpr_complete_rd;
  wire gpr_complete_rd_bank;
  wire [VALUE_WIDTH-1:0] gpr_complete_value;
  wire fpr_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] fpr_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] fpr_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] fpr_complete_reg;
  wire fpr_complete_bank;
  wire [31:0] fpr_complete_value;
  wire [5:0] shamt;
  wire [4:0] shamt32;
  wire [5:0] shamt1;
  wire [4:0] shamt32_1;

  assign opcode = issue_inst[6:0];
  assign opcode1 = issue1_inst[6:0];
  assign rd = issue_inst[11:7];
  assign rd1 = issue1_inst[11:7];
  assign funct3 = issue_inst[14:12];
  assign funct3_1 = issue1_inst[14:12];
  assign rs1 = issue_inst[19:15];
  assign rs1_1 = issue1_inst[19:15];
  assign rs2 = issue_inst[24:20];
  assign rs2_1 = issue1_inst[24:20];
  assign rs3 = issue_inst[31:27];
  assign imm12 = issue_inst[31:20];
  assign imm12_1 = issue1_inst[31:20];
  assign store_imm12 = {issue_inst[31:25], issue_inst[11:7]};
  assign store_imm12_1 = {issue1_inst[31:25], issue1_inst[11:7]};
  assign imm12_sext = {{(VALUE_WIDTH-12){imm12[11]}}, imm12};
  assign imm12_1_sext = {{(VALUE_WIDTH-12){imm12_1[11]}}, imm12_1};
  assign store_imm12_sext = {{(VALUE_WIDTH-12){store_imm12[11]}}, store_imm12};
  assign store_imm12_1_sext = {{(VALUE_WIDTH-12){store_imm12_1[11]}}, store_imm12_1};
  assign lui_value = {{(VALUE_WIDTH-32){issue_inst[31]}}, issue_inst[31:12], 12'b0};
  assign lui1_value = {{(VALUE_WIDTH-32){issue1_inst[31]}}, issue1_inst[31:12], 12'b0};
  assign branch_imm_sext = {{(VALUE_WIDTH-13){issue_inst[31]}},
                            issue_inst[31],
                            issue_inst[7],
                            issue_inst[30:25],
                            issue_inst[11:8],
                            1'b0};
  assign jal_imm_sext = {{(VALUE_WIDTH-21){issue_inst[31]}},
                         issue_inst[31],
                         issue_inst[19:12],
                         issue_inst[20],
                         issue_inst[30:21],
                         1'b0};
  assign rs1_value = (rs1 == {REG_INDEX_WIDTH{1'b0}}) ? {VALUE_WIDTH{1'b0}} :
                     (alu_m_complete_valid && alu_m_complete_rd_valid &&
                      (alu_m_complete_rd == rs1)) ?
                       alu_m_complete_value :
                     (alu_fast1_complete_valid && alu_fast1_complete_rd_valid &&
                      (alu_fast1_complete_rd == rs1)) ?
                       alu_fast1_complete_value :
                     (gpr_complete_valid &&
                      (gpr_complete_rd == rs1)) ?
                       gpr_complete_value :
                     (gpr_load_complete_valid &&
                      (gpr_load_complete_reg == rs1)) ?
                       gpr_load_complete_value :
                       gpr[rs1];
  assign rs2_value = (rs2 == {REG_INDEX_WIDTH{1'b0}}) ? {VALUE_WIDTH{1'b0}} :
                     (alu_m_complete_valid && alu_m_complete_rd_valid &&
                      (alu_m_complete_rd == rs2)) ?
                       alu_m_complete_value :
                     (alu_fast1_complete_valid && alu_fast1_complete_rd_valid &&
                      (alu_fast1_complete_rd == rs2)) ?
                       alu_fast1_complete_value :
                     (gpr_complete_valid &&
                      (gpr_complete_rd == rs2)) ?
                       gpr_complete_value :
                     (gpr_load_complete_valid &&
                      (gpr_load_complete_reg == rs2)) ?
                       gpr_load_complete_value :
                       gpr[rs2];
  assign rd_value = (rd == {REG_INDEX_WIDTH{1'b0}}) ? {VALUE_WIDTH{1'b0}} :
                    (alu_m_complete_valid && alu_m_complete_rd_valid &&
                     (alu_m_complete_rd == rd)) ?
                      alu_m_complete_value :
                    (alu_fast1_complete_valid && alu_fast1_complete_rd_valid &&
                     (alu_fast1_complete_rd == rd)) ?
                      alu_fast1_complete_value :
                    (gpr_complete_valid &&
                     (gpr_complete_rd == rd)) ?
                      gpr_complete_value :
                    (gpr_load_complete_valid &&
                     (gpr_load_complete_reg == rd)) ?
                      gpr_load_complete_value :
                      gpr[rd];
  assign rd1_value = (rd1 == {REG_INDEX_WIDTH{1'b0}}) ? {VALUE_WIDTH{1'b0}} :
                     (alu_m_complete_valid && alu_m_complete_rd_valid &&
                      (alu_m_complete_rd == rd1)) ?
                       alu_m_complete_value :
                     (alu_fast1_complete_valid && alu_fast1_complete_rd_valid &&
                      (alu_fast1_complete_rd == rd1)) ?
                       alu_fast1_complete_value :
                     (gpr_complete_valid &&
                      (gpr_complete_rd == rd1)) ?
                       gpr_complete_value :
                     (gpr_load_complete_valid &&
                      (gpr_load_complete_reg == rd1)) ?
                       gpr_load_complete_value :
                       gpr[rd1];
  assign fpr_rs1_value = (fpr_complete_valid &&
                          (fpr_complete_reg == rs1)) ?
                           fpr_complete_value : fpr[rs1];
  assign fpr_rs2_value = (fpr_complete_valid &&
                          (fpr_complete_reg == rs2)) ?
                           fpr_complete_value : fpr[rs2];
  assign fpr_rs3_value = (fpr_complete_valid &&
                          (fpr_complete_reg == rs3)) ?
                           fpr_complete_value : fpr[rs3];
  assign rs1_1_value = issue1_src0_forwarded ? alu_issue_fast_result :
                       (rs1_1 == {REG_INDEX_WIDTH{1'b0}}) ? {VALUE_WIDTH{1'b0}} :
                       (alu_m_complete_valid && alu_m_complete_rd_valid &&
                        (alu_m_complete_rd == rs1_1)) ?
                         alu_m_complete_value :
                       (alu_fast1_complete_valid && alu_fast1_complete_rd_valid &&
                        (alu_fast1_complete_rd == rs1_1)) ?
                         alu_fast1_complete_value :
                       (gpr_complete_valid &&
                        (gpr_complete_rd == rs1_1)) ?
                         gpr_complete_value :
                       (gpr_load_complete_valid &&
                        (gpr_load_complete_reg == rs1_1)) ?
                         gpr_load_complete_value :
                         gpr[rs1_1];
  assign rs2_1_value = issue1_src1_forwarded ? alu_issue_fast_result :
                       (rs2_1 == {REG_INDEX_WIDTH{1'b0}}) ? {VALUE_WIDTH{1'b0}} :
                       (alu_m_complete_valid && alu_m_complete_rd_valid &&
                        (alu_m_complete_rd == rs2_1)) ?
                         alu_m_complete_value :
                       (alu_fast1_complete_valid && alu_fast1_complete_rd_valid &&
                        (alu_fast1_complete_rd == rs2_1)) ?
                         alu_fast1_complete_value :
                       (gpr_complete_valid &&
                        (gpr_complete_rd == rs2_1)) ?
                         gpr_complete_value :
                       (gpr_load_complete_valid &&
                        (gpr_load_complete_reg == rs2_1)) ?
                         gpr_load_complete_value :
                         gpr[rs2_1];
  assign rs1_1_alu_value = rs1_1_value;
  assign rs2_1_alu_value = rs2_1_value;
  assign shamt = issue_inst[25:20];
  assign shamt32 = issue_inst[24:20];
  assign shamt1 = issue1_inst[25:20];
  assign shamt32_1 = issue1_inst[24:20];

  wire is_op_imm;
  wire is_op;
  wire is_op_imm32;
  wire is_op32;
  wire is_madd;
  wire is_msub;
  wire is_nmsub;
  wire is_nmadd;
  wire is_op_fp;
  wire is_fpu_fmac;
  wire is_fpu_fmac_madd;
  wire is_fpu_fmac_op;
  wire is_fpu_static_rm;
  wire [2:0] fpu_issue_rm;
  wire legal_fpu_fmac;
  wire is_fpu_div;
  wire is_fpu_sqrt;
  wire legal_fpu_slow;
  wire is_fpu_misc_sgnj;
  wire is_fpu_misc_minmax;
  wire is_fpu_misc_cmp;
  wire is_fpu_misc_class;
  wire is_fpu_misc_mv_x_f;
  wire is_fpu_misc_mv_f_x;
  wire legal_fpu_misc;
  wire is_fpu_misc_gpr_dst;
  wire is_fpu_cvt_f2f;
  wire is_fpu_cvt_f2i;
  wire is_fpu_cvt_i2f;
  wire legal_fpu_cvt;
  wire is_fpu_cvt_gpr_dst;
  wire is_fpu_aux;
  wire is_fpu_aux_gpr_dst;
  wire is_fpu_aux_fpr_dst;
  reg [3:0] fpu_misc_op;
  reg [1:0] fpu_cvt_op;
  reg [19:0] fpu_fmac_func;
  wire is_lui;
  wire is_auipc;
  wire is_jal;
  wire is_jalr;
  wire is_branch;
  wire is_zba_op;
  wire is_zba_uw_op32;
  wire is_slli_uw;
  wire is_system_placeholder;
  wire is_ebreak;
  wire is_fence_placeholder;
  wire is_edge_cache_placeholder;
  wire is_edge_dma_placeholder;
  wire is_edge_dma_start;
  wire is_edge_dma_sync;
  wire legal_edge_cache;
  wire legal_edge_dma;
  wire legal_custom_control;
  wire is_tensor_join_pseudo;
  wire is_tensor_gpr_holder_pseudo;
  wire is_tensor_gpr_pseudo;
  wire is_accel_getcsr_pseudo;
  wire issue1_is_tensor_join_pseudo;
  wire issue1_is_tensor_gpr_holder_pseudo;
  wire issue1_is_tensor_gpr_pseudo;
  wire issue1_is_accel_getcsr_pseudo;
  wire tensor_gpr_src0_valid;
  wire tensor_gpr_src1_valid;
  wire tensor_gpr_src2_valid;
  wire issue1_tensor_gpr_src0_valid;
  wire issue1_tensor_gpr_src1_valid;
  wire issue1_tensor_gpr_src2_valid;
  wire custom_control_ready;
  reg cache_op_pending_q;
  wire [3:0] lsu_debug_stb_count;
  wire [SCALAR_LOAD_QUEUE_COUNT_WIDTH-1:0] lsu_debug_loadq_count;
  wire lsu_debug_stb_dtcm_pending;
  wire [31:0] fpr_busy_status;
  wire lsu_stores_drained;
  wire custom_gpr_src0_valid;
  wire custom_gpr_src1_valid;
  wire custom_gpr_src2_valid;
  wire issue_is_serializing;
  wire issue_requires_lsu_drain;
  wire serializing_lsu_drained;
  wire is_fatal_report_placeholder;
  wire legal_op_imm;
  wire legal_op;
  wire legal_op_imm32;
  wire legal_op32;
  wire legal_branch;
  wire legal_jalr;
  wire legal_system;
  wire is_cycle_csr_read;
  wire cycle_csr_writes_gpr;
  wire cycle_csr_gpr_slot_ready;
  wire legal_fence;
  wire known_placeholder;
  wire is_alu_gpr_placeholder;
  wire is_load_placeholder;
  wire is_store_placeholder;
  wire is_fp_load;
  wire is_fp_store;
  wire is_load1_placeholder;
  wire is_store1_placeholder;
  wire issue1_is_memory;
  wire issue0_is_pairable_alu;
  wire issue1_is_op_imm;
  wire issue1_is_op;
  wire issue1_is_op_imm32;
  wire issue1_is_op32;
  wire issue1_is_lui;
  wire issue1_is_auipc;
  wire issue1_legal_op_imm;
  wire issue1_legal_op;
  wire issue1_legal_op_imm32;
  wire issue1_legal_op32;
  wire issue1_is_zba_op;
  wire issue1_is_zba_uw_op32;
  wire issue1_is_slli_uw;
  wire issue1_is_pairable_alu;
  wire issue1_is_pairable_m;
  wire issue0_is_pairable_m;
  wire issue0_is_pairable_fast;
  wire issue_dual_alu_pair;
  wire issue1_alu_src0_valid;
  wire issue1_alu_src1_valid;
  wire issue1_uses_alu;
  wire issue_pair_same_class;
  reg simulation_disable_fast_fast_pair;
  wire issue1_gpr_dst_candidate;
  wire issue1_gpr_check_candidate;
  wire issue1_gpr_src0_valid;
  wire issue1_gpr_src1_valid;
  wire issue0_fast_lsu_forward_valid;
  wire issue1_src0_forwarded;
  wire issue1_src1_forwarded;
  wire [VALUE_WIDTH-1:0] alu_issue_fast_result;
  wire issue1_tensor_gpr_src_ready;
  wire issue1_pair_allowed;
  wire issue1_fire;
  wire tensor_snapshot0_valid;

  initial begin
    simulation_disable_fast_fast_pair = 1'b0;
`ifndef EDGE_YOSYS_SYNTH
    if ($test$plusargs("disable_scalar_fast_fast_pair"))
      simulation_disable_fast_fast_pair = 1'b1;
`endif
  end
  wire [2:0] tensor_snapshot0_target;
  wire tensor_snapshot0_operand_valid;
  wire [VALUE_WIDTH-1:0] tensor_snapshot0_operand_value;
  wire tensor_snapshot1_valid;
  wire [2:0] tensor_snapshot1_target;
  wire tensor_snapshot1_operand_valid;
  wire [VALUE_WIDTH-1:0] tensor_snapshot1_operand_value;
  wire is_fpr_placeholder;
  assign is_op_imm = !issue_is_pseudo && (opcode == OPCODE_OP_IMM);
  assign is_op = !issue_is_pseudo && (opcode == OPCODE_OP);
  assign is_op_imm32 = !issue_is_pseudo && (opcode == OPCODE_OP_IMM32);
  assign is_op32 = !issue_is_pseudo && (opcode == OPCODE_OP32);
  assign is_madd = !issue_is_pseudo && (opcode == OPCODE_MADD);
  assign is_msub = !issue_is_pseudo && (opcode == OPCODE_MSUB);
  assign is_nmsub = !issue_is_pseudo && (opcode == OPCODE_NMSUB);
  assign is_nmadd = !issue_is_pseudo && (opcode == OPCODE_NMADD);
  assign is_op_fp = !issue_is_pseudo && (opcode == OPCODE_OP_FP);
  assign is_lui = !issue_is_pseudo && (opcode == OPCODE_LUI);
  assign is_auipc = !issue_is_pseudo && (opcode == OPCODE_AUIPC);
  assign is_jal = !issue_is_pseudo && (opcode == OPCODE_JAL);
  assign is_jalr = !issue_is_pseudo && (opcode == OPCODE_JALR);
  assign is_branch = !issue_is_pseudo && (opcode == OPCODE_BRANCH);
  assign is_zba_op = is_op &&
                     (issue_inst[31:25] == 7'b0010000) &&
                     ((funct3 == 3'b010) || (funct3 == 3'b100) ||
                      (funct3 == 3'b110));
  assign is_zba_uw_op32 = is_op32 &&
                          (((issue_inst[31:25] == 7'b0000100) &&
                            (funct3 == 3'b000)) ||
                           ((issue_inst[31:25] == 7'b0010000) &&
                            ((funct3 == 3'b010) || (funct3 == 3'b100) ||
                             (funct3 == 3'b110))));
  assign is_slli_uw = is_op_imm32 &&
                      (funct3 == 3'b001) &&
                      (issue_inst[31:26] == 6'b000010);
  assign is_system_placeholder = !issue_is_pseudo && (opcode == OPCODE_SYSTEM);
  assign is_ebreak = is_system_placeholder &&
                     (funct3 == 3'b000) &&
                     (imm12 == 12'h001) &&
                     (rd == {REG_INDEX_WIDTH{1'b0}}) &&
                     (rs1 == {REG_INDEX_WIDTH{1'b0}});
  assign is_cycle_csr_read = is_system_placeholder &&
                             (funct3 == 3'b010) &&
                             (imm12 == CSR_CYCLE) &&
                             (rs1 == {REG_INDEX_WIDTH{1'b0}});
  assign cycle_csr_writes_gpr = is_cycle_csr_read &&
                                (rd != {REG_INDEX_WIDTH{1'b0}});
  assign is_fence_placeholder = !issue_is_pseudo && (opcode == OPCODE_MISC_MEM);
  assign is_edge_cache_placeholder =
    !issue_is_pseudo &&
    (opcode == OPCODE_EDGE_CACHE) &&
    (issue_inst[31:25] == 7'b0000000) &&
    (rd == {REG_INDEX_WIDTH{1'b0}}) &&
    ((funct3 == 3'b000 &&
      (rs1 == {REG_INDEX_WIDTH{1'b0}}) &&
      ((rs2 == 5'd1) || (rs2 == 5'd2) || (rs2 == 5'd3))) ||
     (funct3 == 3'b001 &&
      ((rs2 == 5'd5) || (rs2 == 5'd6) || (rs2 == 5'd7))));
  assign is_edge_dma_placeholder =
    !issue_is_pseudo &&
    (opcode == OPCODE_EDGE_DMA) &&
    (funct3 == 3'b000) &&
    (((issue_inst[31:25] == 7'b0000000)) ||
     ((issue_inst[31:25] == 7'b0000001) &&
      (rd == {REG_INDEX_WIDTH{1'b0}}) &&
      (rs1 == {REG_INDEX_WIDTH{1'b0}}) &&
      (rs2 == {REG_INDEX_WIDTH{1'b0}})));
  assign is_edge_dma_start = is_edge_dma_placeholder &&
                             (issue_inst[31:25] == 7'b0000000);
  assign is_edge_dma_sync = is_edge_dma_placeholder &&
                            (issue_inst[31:25] == 7'b0000001);
  assign legal_op_imm = is_op_imm &&
                        ((funct3 != 3'b001 && funct3 != 3'b101) ||
                         (funct3 == 3'b001 && issue_inst[31:26] == 6'b000000) ||
                         (funct3 == 3'b101 &&
                          (issue_inst[31:26] == 6'b000000 || issue_inst[31:26] == 6'b010000)));
  assign legal_op = is_op &&
                    (is_zba_op ||
                     (issue_inst[31:25] == 7'b0000000) ||
                     (issue_inst[31:25] == 7'b0000001) ||
                     (issue_inst[31:25] == 7'b0100000 &&
                      (funct3 == 3'b000 || funct3 == 3'b101)));
  assign legal_op_imm32 = is_op_imm32 &&
                          ((funct3 == 3'b000) ||
                           (funct3 == 3'b001 && issue_inst[31:25] == 7'b0000000) ||
                           is_slli_uw ||
                           (funct3 == 3'b101 &&
                            (issue_inst[31:25] == 7'b0000000 || issue_inst[31:25] == 7'b0100000)));
  assign legal_op32 = is_op32 &&
                      (is_zba_uw_op32 ||
                       (funct3 == 3'b000 &&
                        (issue_inst[31:25] == 7'b0000000 ||
                         issue_inst[31:25] == 7'b0000001 ||
                         issue_inst[31:25] == 7'b0100000)) ||
                       (issue_inst[31:25] == 7'b0000001 &&
                        ((funct3 == 3'b100) || (funct3 == 3'b101) ||
                         (funct3 == 3'b110) || (funct3 == 3'b111))) ||
                       (funct3 == 3'b001 && issue_inst[31:25] == 7'b0000000) ||
                       (funct3 == 3'b101 &&
                        (issue_inst[31:25] == 7'b0000000 || issue_inst[31:25] == 7'b0100000)));
  assign legal_branch = is_branch &&
                        ((funct3 == 3'b000) || (funct3 == 3'b001) ||
                         (funct3 == 3'b100) || (funct3 == 3'b101) ||
                         (funct3 == 3'b110) || (funct3 == 3'b111));
  assign legal_jalr = is_jalr && (funct3 == 3'b000);
  assign legal_system = is_system_placeholder && !is_ebreak;
  assign legal_fence = is_fence_placeholder && (funct3 == 3'b000 || funct3 == 3'b001);
  assign legal_edge_cache = is_edge_cache_placeholder;
  assign legal_edge_dma = is_edge_dma_placeholder;
  assign legal_custom_control = legal_edge_cache || legal_edge_dma;
  assign is_tensor_join_pseudo = issue_is_pseudo &&
                                 (issue_pseudo_kind == PSEUDO_TENSOR_JOIN);
  assign is_tensor_gpr_holder_pseudo =
    issue_is_pseudo && (issue_pseudo_kind == PSEUDO_TENSOR_GPR_HOLDER);
  assign is_tensor_gpr_pseudo = is_tensor_join_pseudo ||
                                is_tensor_gpr_holder_pseudo;
  assign is_accel_getcsr_pseudo = issue_is_pseudo &&
                                  (issue_pseudo_kind == PSEUDO_ACCEL_GETCSR);
  assign issue1_is_tensor_join_pseudo = issue1_is_pseudo &&
                                        (issue1_pseudo_kind == PSEUDO_TENSOR_JOIN);
  assign issue1_is_tensor_gpr_holder_pseudo =
    issue1_is_pseudo && (issue1_pseudo_kind == PSEUDO_TENSOR_GPR_HOLDER);
  assign issue1_is_tensor_gpr_pseudo = issue1_is_tensor_join_pseudo ||
                                       issue1_is_tensor_gpr_holder_pseudo;
  assign issue1_is_accel_getcsr_pseudo = issue1_is_pseudo &&
                                         (issue1_pseudo_kind ==
                                          PSEUDO_ACCEL_GETCSR);
  assign tensor_gpr_src0_valid = is_tensor_gpr_pseudo &&
                                 issue_inst[12] &&
                                 (rs1 != {REG_INDEX_WIDTH{1'b0}});
  assign tensor_gpr_src1_valid = is_tensor_gpr_pseudo &&
                                 issue_inst[13] &&
                                 (rs2 != {REG_INDEX_WIDTH{1'b0}});
  assign tensor_gpr_src2_valid = is_tensor_gpr_pseudo &&
                                 issue_inst[14] &&
                                 (rd != {REG_INDEX_WIDTH{1'b0}});
  assign issue1_tensor_gpr_src0_valid = issue1_is_tensor_gpr_pseudo &&
                                        issue1_inst[12] &&
                                        (rs1_1 != {REG_INDEX_WIDTH{1'b0}});
  assign issue1_tensor_gpr_src1_valid = issue1_is_tensor_gpr_pseudo &&
                                        issue1_inst[13] &&
                                        (rs2_1 != {REG_INDEX_WIDTH{1'b0}});
  assign issue1_tensor_gpr_src2_valid = issue1_is_tensor_gpr_pseudo &&
                                        issue1_inst[14] &&
                                        (rd1 != {REG_INDEX_WIDTH{1'b0}});
  assign is_fpu_fmac_madd = is_madd || is_msub || is_nmsub || is_nmadd;
  assign is_fpu_fmac_op =
    is_op_fp &&
    ((issue_inst[31:27] == 5'b00000) ||
     (issue_inst[31:27] == 5'b00001) ||
     (issue_inst[31:27] == 5'b00010));
  assign is_fpu_static_rm = (funct3 <= 3'b100) || (funct3 == 3'b111);
  assign fpu_issue_rm = (funct3 == 3'b111) ? 3'b000 : funct3;
  // Edge keeps one physical FP32 arithmetic format.  Treat every architectural
  // fmt encoding as FP32 instead of carrying format selection into the FPU.
  assign legal_fpu_fmac = (is_fpu_fmac_madd || is_fpu_fmac_op) &&
                          is_fpu_static_rm;
  assign is_fpu_fmac = legal_fpu_fmac;
  assign is_fpu_div = is_op_fp && (issue_inst[31:27] == 5'b00011);
  assign is_fpu_sqrt = is_op_fp && (issue_inst[31:27] == 5'b01011) &&
                       (rs2 == {REG_INDEX_WIDTH{1'b0}});
  assign legal_fpu_slow = (is_fpu_div || is_fpu_sqrt) && is_fpu_static_rm;

  // FPU integration island decode. D/S/H share the physical FP32 FPR; fmt=11
  // remains reserved. Keep these classifications together so the complete
  // FPU island can later be parameterized or removed without scattered decode.
  assign is_fpu_misc_sgnj = is_op_fp &&
                            (issue_inst[31:27] == 5'b00100) &&
                            (funct3 <= 3'b010);
  assign is_fpu_misc_minmax = is_op_fp &&
                              (issue_inst[31:27] == 5'b00101) &&
                              ((funct3 == 3'b000) || (funct3 == 3'b001));
  assign is_fpu_misc_cmp = is_op_fp &&
                           (issue_inst[31:27] == 5'b10100) &&
                           (funct3 <= 3'b010);
  assign is_fpu_misc_class = is_op_fp &&
                             (issue_inst[31:27] == 5'b11100) &&
                             (rs2 == {REG_INDEX_WIDTH{1'b0}}) &&
                             (funct3 == 3'b001);
  assign is_fpu_misc_mv_x_f = is_op_fp &&
                              (issue_inst[31:27] == 5'b11100) &&
                              (rs2 == {REG_INDEX_WIDTH{1'b0}}) &&
                              (funct3 == 3'b000);
  assign is_fpu_misc_mv_f_x = is_op_fp &&
                              (issue_inst[31:27] == 5'b11110) &&
                              (rs2 == {REG_INDEX_WIDTH{1'b0}}) &&
                              (funct3 == 3'b000);
  assign legal_fpu_misc = (issue_inst[26:25] != 2'b11) &&
                          (is_fpu_misc_sgnj || is_fpu_misc_minmax ||
                           is_fpu_misc_cmp || is_fpu_misc_class ||
                           is_fpu_misc_mv_x_f || is_fpu_misc_mv_f_x);
  assign is_fpu_misc_gpr_dst = is_fpu_misc_cmp || is_fpu_misc_class ||
                               is_fpu_misc_mv_x_f;

  assign is_fpu_cvt_f2f = is_op_fp &&
                          (issue_inst[31:27] == 5'b01000) &&
                          (rs2[4:2] == 3'b000) &&
                          (rs2[1:0] != 2'b11);
  assign is_fpu_cvt_f2i = is_op_fp &&
                          (issue_inst[31:27] == 5'b11000) &&
                          (rs2[4:2] == 3'b000);
  assign is_fpu_cvt_i2f = is_op_fp &&
                          (issue_inst[31:27] == 5'b11010) &&
                          (rs2[4:2] == 3'b000);
  assign legal_fpu_cvt = (issue_inst[26:25] != 2'b11) &&
                         is_fpu_static_rm &&
                         (is_fpu_cvt_f2f || is_fpu_cvt_f2i ||
                          is_fpu_cvt_i2f);
  assign is_fpu_cvt_gpr_dst = is_fpu_cvt_f2i;
  assign is_fpu_aux = legal_fpu_misc || legal_fpu_cvt;
  assign is_fpu_aux_gpr_dst = (legal_fpu_misc && is_fpu_misc_gpr_dst) ||
                              (legal_fpu_cvt && is_fpu_cvt_gpr_dst);
  assign is_fpu_aux_fpr_dst = is_fpu_aux && !is_fpu_aux_gpr_dst;

  always @* begin
    fpu_misc_op = FPU_MISC_SGNJ;
    if (is_fpu_misc_minmax) fpu_misc_op = FPU_MISC_MINMAX;
    else if (is_fpu_misc_cmp) fpu_misc_op = FPU_MISC_CMP;
    else if (is_fpu_misc_class) fpu_misc_op = FPU_MISC_CLASS;
    else if (is_fpu_misc_mv_x_f) fpu_misc_op = FPU_MISC_MV_X_F;
    else if (is_fpu_misc_mv_f_x) fpu_misc_op = FPU_MISC_MV_F_X;

    fpu_cvt_op = FPU_CVT_F2F;
    if (is_fpu_cvt_f2i) fpu_cvt_op = FPU_CVT_F2I;
    else if (is_fpu_cvt_i2f) fpu_cvt_op = FPU_CVT_I2F;
  end

  always @* begin
    fpu_fmac_func = 20'b0;
    if (is_fpu_fmac_madd) begin
      fpu_fmac_func[6:4] = 3'b010;
      fpu_fmac_func[2:0] = is_madd  ? 3'b001 :
                           is_msub  ? 3'b011 :
                           is_nmadd ? 3'b101 : 3'b111;
    end else if (is_fpu_fmac_op) begin
      if (issue_inst[31:27] == 5'b00000) begin
        fpu_fmac_func[15:12] = 4'b0010;
        fpu_fmac_func[7] = 1'b1;
        fpu_fmac_func[4] = 1'b1;
      end else if (issue_inst[31:27] == 5'b00001) begin
        fpu_fmac_func[15:12] = 4'b0010;
        fpu_fmac_func[7] = 1'b1;
        fpu_fmac_func[3] = 1'b1;
      end else begin
        fpu_fmac_func[6:4] = 3'b010;
      end
    end
  end

  assign custom_control_ready =
    is_edge_cache_placeholder ?
      (cache_op_ready && !cache_op_pending_q) :
    is_edge_dma_start ? (dma_start_ready && !cache_op_pending_q) :
    is_edge_dma_sync ? (dma_sync_ready && !cache_op_pending_q) :
    1'b1;
  assign issue_is_serializing = is_ebreak || legal_system || legal_fence ||
                                legal_custom_control;
  assign issue_requires_lsu_drain = is_ebreak ||
                                    (legal_system && !is_cycle_csr_read) ||
                                    legal_fence || legal_custom_control;
  assign serializing_lsu_drained = lsu_stores_drained &&
                                   (lsu_debug_loadq_count == 4'd0);
  assign custom_gpr_src0_valid =
    ((is_edge_cache_placeholder && (funct3 == 3'b001)) ||
     is_edge_dma_start) &&
    (rs1 != {REG_INDEX_WIDTH{1'b0}});
  assign custom_gpr_src1_valid = is_edge_dma_start &&
                                 (rs2 != {REG_INDEX_WIDTH{1'b0}});
  assign custom_gpr_src2_valid = is_edge_dma_start &&
                                 (rd != {REG_INDEX_WIDTH{1'b0}});
  assign known_placeholder = legal_op_imm || legal_op || legal_op_imm32 || legal_op32 ||
                             is_lui || is_auipc || is_jal || legal_jalr ||
                             legal_branch || is_load_placeholder || is_store_placeholder ||
                             is_fp_load || is_fp_store || legal_fpu_fmac ||
                             legal_fpu_slow ||
                             legal_fpu_misc || legal_fpu_cvt ||
                             legal_system || is_ebreak || legal_fence ||
                             legal_custom_control ||
                             issue_is_pseudo;
  assign is_fatal_report_placeholder = !issue_is_pseudo && !known_placeholder;
  assign is_alu_gpr_placeholder = is_op_imm || is_op || is_op_imm32 || is_op32 ||
                                  is_lui || is_auipc || is_jal || is_jalr;
  assign is_load_placeholder = !issue_is_pseudo && (opcode == OPCODE_LOAD) &&
                               (funct3 != 3'b111);
  assign is_store_placeholder = !issue_is_pseudo && (opcode == OPCODE_STORE) &&
                                ((funct3 == 3'b000) || (funct3 == 3'b001) ||
                                 (funct3 == 3'b010) || (funct3 == 3'b011));
  assign is_fp_load = !issue_is_pseudo && (opcode == OPCODE_LOAD_FP) &&
                      ((funct3 == 3'b001) || (funct3 == 3'b010) ||
                       (funct3 == 3'b011) || (funct3 == 3'b101));
  assign is_fp_store = !issue_is_pseudo && (opcode == OPCODE_STORE_FP) &&
                       ((funct3 == 3'b001) || (funct3 == 3'b010) ||
                        (funct3 == 3'b011) || (funct3 == 3'b101));
  assign is_fpr_placeholder = is_fp_load;
  assign is_load1_placeholder = !issue1_is_pseudo &&
                                (opcode1 == OPCODE_LOAD) &&
                                (funct3_1 != 3'b111);
  assign is_store1_placeholder = !issue1_is_pseudo &&
                                 (opcode1 == OPCODE_STORE) &&
                                 ((funct3_1 == 3'b000) || (funct3_1 == 3'b001) ||
                                  (funct3_1 == 3'b010) || (funct3_1 == 3'b011));
  assign issue1_is_memory = !issue1_is_pseudo &&
                            (is_load1_placeholder || is_store1_placeholder);
  assign issue1_is_op_imm = !issue1_is_pseudo && (opcode1 == OPCODE_OP_IMM);
  assign issue1_is_op = !issue1_is_pseudo && (opcode1 == OPCODE_OP);
  assign issue1_is_op_imm32 = !issue1_is_pseudo && (opcode1 == OPCODE_OP_IMM32);
  assign issue1_is_op32 = !issue1_is_pseudo && (opcode1 == OPCODE_OP32);
  assign issue1_is_lui = !issue1_is_pseudo && (opcode1 == OPCODE_LUI);
  assign issue1_is_auipc = !issue1_is_pseudo && (opcode1 == OPCODE_AUIPC);
  assign issue1_is_zba_op = issue1_is_op &&
                            (issue1_inst[31:25] == 7'b0010000) &&
                            ((funct3_1 == 3'b010) || (funct3_1 == 3'b100) ||
                             (funct3_1 == 3'b110));
  assign issue1_is_zba_uw_op32 = issue1_is_op32 &&
                                 (((issue1_inst[31:25] == 7'b0000100) &&
                                   (funct3_1 == 3'b000)) ||
                                  ((issue1_inst[31:25] == 7'b0010000) &&
                                   ((funct3_1 == 3'b010) ||
                                    (funct3_1 == 3'b100) ||
                                    (funct3_1 == 3'b110))));
  assign issue1_is_slli_uw = issue1_is_op_imm32 &&
                             (funct3_1 == 3'b001) &&
                             (issue1_inst[31:26] == 6'b000010);
  assign issue1_legal_op_imm = issue1_is_op_imm &&
    ((funct3_1 != 3'b001 && funct3_1 != 3'b101) ||
     (funct3_1 == 3'b001 && issue1_inst[31:26] == 6'b000000) ||
     (funct3_1 == 3'b101 &&
      (issue1_inst[31:26] == 6'b000000 || issue1_inst[31:26] == 6'b010000)));
  assign issue1_legal_op = issue1_is_op &&
    (issue1_is_zba_op ||
     (issue1_inst[31:25] == 7'b0000000) ||
     (issue1_inst[31:25] == 7'b0100000 &&
      (funct3_1 == 3'b000 || funct3_1 == 3'b101)));
  assign issue1_legal_op_imm32 = issue1_is_op_imm32 &&
    ((funct3_1 == 3'b000) ||
     (funct3_1 == 3'b001 && issue1_inst[31:25] == 7'b0000000) ||
     issue1_is_slli_uw ||
     (funct3_1 == 3'b101 &&
      (issue1_inst[31:25] == 7'b0000000 || issue1_inst[31:25] == 7'b0100000)));
  assign issue1_legal_op32 = issue1_is_op32 &&
    (issue1_is_zba_uw_op32 ||
     (funct3_1 == 3'b000 &&
      (issue1_inst[31:25] == 7'b0000000 || issue1_inst[31:25] == 7'b0100000)) ||
     (funct3_1 == 3'b001 && issue1_inst[31:25] == 7'b0000000) ||
     (funct3_1 == 3'b101 &&
      (issue1_inst[31:25] == 7'b0000000 || issue1_inst[31:25] == 7'b0100000)));
  assign issue1_is_pairable_alu = issue1_legal_op_imm || issue1_legal_op ||
                                  issue1_legal_op_imm32 || issue1_legal_op32 ||
                                  issue1_is_lui || issue1_is_auipc;
  assign issue1_is_pairable_m = (issue1_is_op || issue1_is_op32) &&
                                (issue1_inst[31:25] == 7'b0000001) &&
                                (issue1_is_op || (funct3_1 == 3'b000) ||
                                 (funct3_1 >= 3'b100));
  assign issue1_alu_src0_valid = (issue1_is_pairable_alu || issue1_is_pairable_m) &&
                                !issue1_is_lui && !issue1_is_auipc &&
                                (rs1_1 != {REG_INDEX_WIDTH{1'b0}});
  assign issue1_alu_src1_valid = (issue1_legal_op || issue1_legal_op32 ||
                                  issue1_is_pairable_m) &&
                                (rs2_1 != {REG_INDEX_WIDTH{1'b0}});
  assign issue1_uses_alu = issue1_fire &&
                           (issue1_is_pairable_alu || issue1_is_pairable_m) &&
                           !((issue0_is_pairable_m && issue1_is_pairable_alu) ||
                             (issue0_is_pairable_fast && issue1_is_pairable_m) ||
                             (issue0_is_pairable_fast && issue1_is_pairable_alu &&
                              !issue1_is_pairable_m));
  assign issue0_is_pairable_alu = !issue_is_pseudo &&
                                  (legal_op_imm || legal_op ||
                                   legal_op_imm32 || legal_op32 ||
                                   is_lui || is_auipc);
  assign issue0_is_pairable_m = !issue_is_pseudo &&
                                (is_op || is_op32) &&
                                (issue_inst[31:25] == 7'b0000001) &&
                                (is_op || (funct3 == 3'b000) ||
                                 (funct3 >= 3'b100));
  assign issue0_is_pairable_fast = issue0_is_pairable_alu &&
                                   !issue0_is_pairable_m;
  assign issue_dual_alu_pair = issue_fire && issue1_fire &&
    ((issue0_is_pairable_m && issue1_is_pairable_alu) ||
     (issue0_is_pairable_fast && issue1_is_pairable_m) ||
     (issue0_is_pairable_fast && issue1_is_pairable_alu &&
      !issue1_is_pairable_m));
  assign issue0_fast_lsu_forward_valid = issue_fire &&
                                         issue0_is_pairable_alu &&
                                         !((is_op || is_op32) &&
                                           (issue_inst[31:25] == 7'b0000001)) &&
                                         scalar_def_valid &&
                                         !scalar_def_domain &&
                                         (scalar_def_dst_reg != {REG_INDEX_WIDTH{1'b0}});
  assign issue1_src0_forwarded = issue0_fast_lsu_forward_valid &&
                                 issue1_gpr_src0_valid &&
                                 (rs1_1 == scalar_def_dst_reg);
  assign issue1_src1_forwarded = issue0_fast_lsu_forward_valid &&
                                 issue1_gpr_src1_valid &&
                                 (rs2_1 == scalar_def_dst_reg);
  assign issue_pair_same_class =
    (is_load_placeholder && is_load1_placeholder) ||
    (is_store_placeholder && is_store1_placeholder) ||
    (issue0_is_pairable_alu && issue1_is_memory) ||
    ((is_load_placeholder || is_store_placeholder) &&
     issue1_is_pairable_alu) ||
    (issue0_is_pairable_m && issue1_is_pairable_alu) ||
    (issue0_is_pairable_fast && issue1_is_pairable_m) ||
    (!simulation_disable_fast_fast_pair &&
     issue0_is_pairable_fast && issue1_is_pairable_alu &&
     !issue1_is_pairable_m);
  assign issue1_gpr_dst_candidate = (is_load1_placeholder ||
                                     issue1_is_pairable_alu ||
                                     issue1_is_pairable_m ||
                                     issue1_is_accel_getcsr_pseudo) &&
                                    scalar1_def_valid &&
                                    (scalar1_def_dst_reg != {REG_INDEX_WIDTH{1'b0}});
  assign issue1_gpr_check_candidate = issue1_gpr_dst_candidate ||
                                      is_load1_placeholder ||
                                      is_store1_placeholder ||
                                      issue1_is_pairable_alu ||
                                      issue1_is_pairable_m ||
                                      issue1_is_tensor_gpr_pseudo;
  assign issue1_gpr_src0_valid = (issue1_is_memory || issue1_alu_src0_valid) &&
                                 (rs1_1 != {REG_INDEX_WIDTH{1'b0}});
  assign issue1_gpr_src1_valid = (is_store1_placeholder ||
                                  issue1_alu_src1_valid) &&
                                 (rs2_1 != {REG_INDEX_WIDTH{1'b0}});
  assign issue1_tensor_gpr_src_ready =
    (!issue1_tensor_gpr_src0_valid ||
     !gpr_busy_status[rs1_1] ||
     (gpr_complete_valid && (gpr_complete_rd == rs1_1)) ||
     (gpr_load_complete_valid && (gpr_load_complete_reg == rs1_1))) &&
    (!issue1_tensor_gpr_src1_valid ||
     !gpr_busy_status[rs2_1] ||
     (gpr_complete_valid && (gpr_complete_rd == rs2_1)) ||
     (gpr_load_complete_valid && (gpr_load_complete_reg == rs2_1))) &&
    (!issue1_tensor_gpr_src2_valid ||
     !gpr_busy_status[rd1] ||
     (gpr_complete_valid && (gpr_complete_rd == rd1)) ||
     (gpr_load_complete_valid && (gpr_load_complete_reg == rd1)));

  wire gpr_issue_valid;
  wire gpr_issue1_valid;
  wire fpr_issue_valid;
  wire gpr_issue_ready;
  wire gpr_issue1_ready;
  wire fpr_issue_ready;
  wire fpu_issue_valid;
  wire fpu_issue_ready;
  wire fpu_fmac_stall;
  wire fpu_fmac_wb_vld;
  wire [31:0] fpu_fmac_wb_data;
  wire [4:0] fpu_fmac_wb_fflags;
  wire [REG_INDEX_WIDTH-1:0] fpu_fmac_wb_reg;
  wire fpu_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] fpu_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] fpu_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] fpu_complete_reg;
  wire fpu_complete_bank;
  wire [VALUE_WIDTH-1:0] fpu_complete_value;
  reg fpu_pending_valid_r;
  reg fpu_pending_valid_s0_r;
  reg fpu_pending_valid_s1_r;
  reg fpu_pending_valid_s2_r;
  reg [SEQ_ID_WIDTH-1:0] fpu_pending_seq_id_r;
  reg [SEQ_ID_WIDTH-1:0] fpu_pending_seq_id_s0_r;
  reg [SEQ_ID_WIDTH-1:0] fpu_pending_seq_id_s1_r;
  reg [SEQ_ID_WIDTH-1:0] fpu_pending_seq_id_s2_r;
  reg [EPOCH_WIDTH-1:0] fpu_pending_epoch_r;
  reg [EPOCH_WIDTH-1:0] fpu_pending_epoch_s0_r;
  reg [EPOCH_WIDTH-1:0] fpu_pending_epoch_s1_r;
  reg [EPOCH_WIDTH-1:0] fpu_pending_epoch_s2_r;
  reg fpu_pending_bank_r;
  reg fpu_pending_bank_s0_r;
  reg fpu_pending_bank_s1_r;
  reg fpu_pending_bank_s2_r;

  // -----------------------------------------------------------------------
  // FPU integration island: all optional misc/cvt attachment wires and the
  // shared serialization bit live here. External pipe logic consumes only
  // fpu_aux_{gpr,fpr}_complete_* below.
  // -----------------------------------------------------------------------
  wire fpu_misc_issue_valid;
  wire fpu_misc_issue_ready;
  wire fpu_misc_complete_valid_raw;
  wire [SEQ_ID_WIDTH-1:0] fpu_misc_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] fpu_misc_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] fpu_misc_complete_reg;
  wire fpu_misc_complete_bank;
  wire fpu_misc_complete_domain;
  wire [VALUE_WIDTH-1:0] fpu_misc_complete_value;
  wire [4:0] fpu_misc_complete_fflags;
  wire fpu_cvt_issue_valid;
  wire fpu_cvt_issue_ready;
  wire fpu_cvt_complete_valid_raw;
  wire [SEQ_ID_WIDTH-1:0] fpu_cvt_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] fpu_cvt_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] fpu_cvt_complete_reg;
  wire fpu_cvt_complete_bank;
  wire fpu_cvt_complete_domain;
  wire [VALUE_WIDTH-1:0] fpu_cvt_complete_value;
  wire [4:0] fpu_cvt_complete_fflags;
  wire fpu_aux_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] fpu_aux_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] fpu_aux_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] fpu_aux_complete_reg;
  wire fpu_aux_complete_bank;
  wire fpu_aux_complete_domain;
  wire [VALUE_WIDTH-1:0] fpu_aux_complete_value;
  wire [4:0] fpu_aux_complete_fflags;
  wire fpu_aux_gpr_complete_valid;
  wire fpu_aux_fpr_complete_valid;
  wire fpu_fpr_complete_valid;
  wire fpu_mul_slot_ready;
  wire fpu_complete_queue_ingress_ready;
  wire fpu_complete_queue_valid;
  wire fpu_complete_queue_ready;
  wire [SEQ_ID_WIDTH-1:0] fpu_complete_queue_seq_id;
  wire [EPOCH_WIDTH-1:0] fpu_complete_queue_epoch;
  wire fpu_complete_queue_domain;
  wire [REG_INDEX_WIDTH-1:0] fpu_complete_queue_reg;
  wire fpu_complete_queue_bank;
  wire [VALUE_WIDTH-1:0] fpu_complete_queue_value;
  wire [4:0] fpu_complete_queue_fflags;
  wire fpu_slow_issue_valid;
  wire fpu_slow_issue_ready;
  wire fpu_slow_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] fpu_slow_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] fpu_slow_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] fpu_slow_complete_reg;
  wire fpu_slow_complete_bank;
  wire [31:0] fpu_slow_complete_value;
  wire [4:0] fpu_slow_complete_fflags;

  wire alu_issue_valid;
  wire alu_issue_ready;
  wire alu_mul_issue_ready;
  wire alu_div_issue_ready;
  wire alu_issue0_ready_for_class;
  wire alu_issue1_ready_for_class;
  reg [3:0] alu_issue_op;
  reg [3:0] alu_issue1_op;
  wire alu_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] alu_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] alu_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] alu_complete_rd;
  wire alu_complete_rd_bank;
  wire alu_complete_rd_valid;
  wire [VALUE_WIDTH-1:0] alu_complete_value;
  wire alu_complete_control_valid;
  wire alu_complete_control_taken;
  wire [PC_WIDTH-1:0] alu_complete_control_target;
  wire alu_issue_control_valid;
  wire alu_issue_control_taken;
  wire [PC_WIDTH-1:0] alu_issue_control_target;
  wire alu_complete_nowb_valid;
  wire alu_fast_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] alu_fast_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] alu_fast_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] alu_fast_complete_rd;
  wire alu_fast_complete_rd_bank;
  wire alu_fast_complete_rd_valid;
  wire [VALUE_WIDTH-1:0] alu_fast_complete_value;
  wire alu_fast1_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] alu_fast1_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] alu_fast1_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] alu_fast1_complete_rd;
  wire alu_fast1_complete_rd_bank;
  wire alu_fast1_complete_rd_valid;
  wire [VALUE_WIDTH-1:0] alu_fast1_complete_value;
  wire alu_m_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] alu_m_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] alu_m_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] alu_m_complete_rd;
  wire alu_m_complete_rd_bank;
  wire alu_m_complete_rd_valid;
  wire [VALUE_WIDTH-1:0] alu_m_complete_value;
  wire lsu_issue_valid;
  wire lsu_issue_ready;
  wire lsu_issue1_valid;
  wire lsu_issue1_ready;
  wire lsu_issue0_ready_for_class;
  wire lsu_issue1_ready_for_class;
  wire lsu_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] lsu_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] lsu_complete_epoch;
  wire lsu_complete_is_store;
  wire [1:0] lsu_complete_size;
  wire lsu_complete_load_signed;
  wire [VALUE_WIDTH-1:0] lsu_complete_addr;
  wire [VALUE_WIDTH-1:0] lsu_complete_store_data;
  wire lsu_misaligned_valid;
  wire lsu_misaligned_lane1;
  wire [SEQ_ID_WIDTH-1:0] lsu_misaligned_seq_id;
  wire [EPOCH_WIDTH-1:0] lsu_misaligned_epoch;
  wire lsu_misaligned_is_store;
  wire [1:0] lsu_misaligned_size;
  wire [VALUE_WIDTH-1:0] lsu_misaligned_addr;
  wire lsu_complete1_valid;
  wire [SEQ_ID_WIDTH-1:0] lsu_complete1_seq_id;
  wire [EPOCH_WIDTH-1:0] lsu_complete1_epoch;
  wire lsu_complete1_is_store;
  wire [1:0] lsu_complete1_size;
  wire lsu_complete1_load_signed;
  wire [VALUE_WIDTH-1:0] lsu_complete1_addr;
  wire [VALUE_WIDTH-1:0] lsu_complete1_store_data;
  wire lsu_load_accept_valid;
  wire [SEQ_ID_WIDTH-1:0] lsu_load_accept_seq_id;
  wire [EPOCH_WIDTH-1:0] lsu_load_accept_epoch;
  wire lsu_load_accept_domain;
  wire lsu_load_accept1_valid;
  wire [SEQ_ID_WIDTH-1:0] lsu_load_accept1_seq_id;
  wire [EPOCH_WIDTH-1:0] lsu_load_accept1_epoch;
  wire lsu_load_accept1_domain;
  wire early_gpr_load_retire_valid;
  wire early_gpr_load_retire1_valid;
  wire lsu_load_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] lsu_load_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] lsu_load_complete_epoch;
  wire [REG_INDEX_WIDTH-1:0] lsu_load_complete_reg;
  wire lsu_load_complete_bank;
  wire lsu_load_complete_domain;
  wire [1:0] lsu_load_complete_size;
  wire lsu_load_complete_error;
  wire [VALUE_WIDTH-1:0] lsu_load_complete_value;
  wire [31:0] lsu_fpr_load_complete_value;
  reg [(1 << SEQ_ID_WIDTH)-1:0] fpr_load_bf16_by_seq;
  wire lsu_fpr_load_complete_is_bf16;
  wire sys_issue_valid;
  wire sys_issue_ready;
  wire sys_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] sys_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] sys_complete_epoch;
  wire sys_system_placeholder_valid;
  wire [2:0] sys_system_placeholder_funct3;
  wire [11:0] sys_system_placeholder_csr;
  wire [REG_INDEX_WIDTH-1:0] sys_system_placeholder_rd;
  wire [REG_INDEX_WIDTH-1:0] sys_system_placeholder_rs1;
  wire sys_fence_placeholder_valid;
  wire sys_fence_placeholder_i;
  wire issue_fire;
  wire retire_complete_nowb_valid;
  wire retire_complete1_nowb_valid;
  wire csr_cycle_complete_valid;
  wire csr_cycle_accept;
  wire issue_gpr_dst_candidate;
  wire issue_fpr_dst_candidate;
  wire issue_fpr_check_candidate;
  wire issue_fpr_src0_valid;
  wire issue_fpr_src1_valid;
  wire issue_fpr_src2_valid;
  wire issue_gpr_check_candidate;
  wire producer_queue_issue_ready;
  reg csr_cycle_complete_valid_r;
  reg [SEQ_ID_WIDTH-1:0] csr_cycle_complete_seq_id_r;
  reg [EPOCH_WIDTH-1:0] csr_cycle_complete_epoch_r;
  reg [REG_INDEX_WIDTH-1:0] csr_cycle_complete_rd_r;
  reg csr_cycle_complete_rd_bank_r;
  reg [VALUE_WIDTH-1:0] csr_cycle_complete_value_r;
  reg [1:0] reverse_snapshot_pending_valid_r;
  reg [SEQ_ID_WIDTH-1:0] reverse_snapshot_pending_seq_id_r [0:1];
  reg [EPOCH_WIDTH-1:0] reverse_snapshot_pending_epoch_r [0:1];
  reg [REG_INDEX_WIDTH-1:0] reverse_snapshot_pending_rd_r [0:1];
  reg reverse_snapshot_pending_rd_bank_r [0:1];
  wire reverse_snapshot_pending_select_id;
  wire reverse_snapshot_pending_any;
  wire reverse_snapshot_complete_accept;
  wire reverse_snapshot_issue_accept;

  assign cycle_csr_gpr_slot_ready = !csr_cycle_complete_valid_r;

  assign gpr_load_complete_valid = (lsu_load_complete_valid &&
                                    !lsu_load_complete_domain) ||
                                   gpr_placeholder_complete_valid;
  assign gpr_load_complete_seq_id = (lsu_load_complete_valid &&
                                     !lsu_load_complete_domain) ?
                                    lsu_load_complete_seq_id :
                                    gpr_placeholder_complete_seq_id;
  assign gpr_load_complete_epoch = (lsu_load_complete_valid &&
                                    !lsu_load_complete_domain) ?
                                   lsu_load_complete_epoch :
                                   gpr_placeholder_complete_epoch;
  assign gpr_load_complete_reg = (lsu_load_complete_valid &&
                                  !lsu_load_complete_domain) ?
                                 lsu_load_complete_reg :
                                 gpr_placeholder_complete_reg;
  assign gpr_load_complete_bank = (lsu_load_complete_valid &&
                                   !lsu_load_complete_domain) ?
                                  lsu_load_complete_bank :
                                  gpr_placeholder_complete_bank;
  assign gpr_load_complete_value = (lsu_load_complete_valid &&
                                    !lsu_load_complete_domain) ?
                                   lsu_load_complete_value :
                                   gpr_placeholder_complete_value;

  assign lsu_fpr_load_complete_value =
    lsu_load_complete_size == 2'b01 ?
      (lsu_fpr_load_complete_is_bf16 ?
       bf16_to_fp32(lsu_load_complete_value[15:0]) :
       fp16_to_fp32(lsu_load_complete_value[15:0])) :
    lsu_load_complete_size == 2'b11 ? fp64_to_fp32_rne(lsu_load_complete_value) :
    lsu_load_complete_value[31:0];
  assign lsu_fpr_load_complete_is_bf16 =
    fpr_load_bf16_by_seq[lsu_load_complete_seq_id];

  assign fpu_complete_valid = fpu_fmac_wb_vld && fpu_pending_valid_r;
  assign fpu_complete_seq_id = fpu_pending_seq_id_r;
  assign fpu_complete_epoch = fpu_pending_epoch_r;
  assign fpu_complete_reg = fpu_fmac_wb_reg;
  assign fpu_complete_bank = fpu_pending_bank_r;
  assign fpu_complete_value = {32'b0, fpu_fmac_wb_data};
  assign fpu_aux_complete_valid = !redirect_kill_valid &&
                                  (fpu_misc_complete_valid_raw ||
                                   fpu_cvt_complete_valid_raw);
  assign fpu_aux_complete_seq_id = fpu_cvt_complete_valid_raw ?
                                   fpu_cvt_complete_seq_id :
                                   fpu_misc_complete_seq_id;
  assign fpu_aux_complete_epoch = fpu_cvt_complete_valid_raw ?
                                  fpu_cvt_complete_epoch :
                                  fpu_misc_complete_epoch;
  assign fpu_aux_complete_reg = fpu_cvt_complete_valid_raw ?
                                fpu_cvt_complete_reg :
                                fpu_misc_complete_reg;
  assign fpu_aux_complete_bank = fpu_cvt_complete_valid_raw ?
                                 fpu_cvt_complete_bank :
                                 fpu_misc_complete_bank;
  assign fpu_aux_complete_domain = fpu_cvt_complete_valid_raw ?
                                   fpu_cvt_complete_domain :
                                   fpu_misc_complete_domain;
  assign fpu_aux_complete_value = fpu_cvt_complete_valid_raw ?
                                  fpu_cvt_complete_value :
                                  fpu_misc_complete_value;
  assign fpu_aux_complete_fflags = fpu_cvt_complete_valid_raw ?
                                   fpu_cvt_complete_fflags :
                                   fpu_misc_complete_fflags;
  assign fpu_aux_gpr_complete_valid = fpu_complete_queue_valid &&
                                      fpu_complete_queue_ready &&
                                      !fpu_complete_queue_domain;
  assign fpu_aux_fpr_complete_valid = fpu_complete_queue_valid &&
                                      fpu_complete_queue_ready &&
                                      fpu_complete_queue_domain;
  assign fpu_fpr_complete_valid = fpu_aux_fpr_complete_valid;
  assign fpr_complete_valid = fpu_aux_fpr_complete_valid;
  assign fpr_complete_seq_id = fpu_complete_queue_seq_id;
  assign fpr_complete_epoch = fpu_complete_queue_epoch;
  assign fpr_complete_reg = fpu_complete_queue_reg;
  assign fpr_complete_bank = fpu_complete_queue_bank;
  assign fpr_complete_value = fpu_complete_queue_value[31:0];

  assign gpr_issue_valid = issue_fire && scalar_def_valid && !scalar_def_domain &&
                           issue_gpr_dst_candidate && known_placeholder;
  assign gpr_issue1_valid = issue1_fire && issue1_gpr_check_candidate;
  assign fpr_issue_valid = issue_fire && scalar_def_valid && scalar_def_domain &&
                           issue_fpr_dst_candidate && known_placeholder;
  assign fpu_issue_valid = issue_fire && legal_fpu_fmac;
  assign fpu_misc_issue_valid = issue_fire && legal_fpu_misc;
  assign fpu_cvt_issue_valid = issue_fire && legal_fpu_cvt;
  assign fpu_slow_issue_valid = issue_fire && legal_fpu_slow;
  assign fpu_mul_slot_ready = fpu_complete_queue_ingress_ready &&
                              !fpu_fmac_stall;
  assign fpu_issue_ready = legal_fpu_fmac ? fpu_mul_slot_ready :
                           legal_fpu_slow ?
                             (fpu_slow_issue_ready &&
                              fpu_complete_queue_ingress_ready) :
                           (fpu_complete_queue_ingress_ready &&
                            (!legal_fpu_misc || fpu_misc_issue_ready) &&
                            (!legal_fpu_cvt || fpu_cvt_issue_ready));
  assign issue_gpr_dst_candidate =
                                   (rd != {REG_INDEX_WIDTH{1'b0}}) &&
                                   ((!issue_is_pseudo &&
                                     (is_alu_gpr_placeholder ||
                                    is_load_placeholder ||
                                    is_cycle_csr_read ||
                                     is_fpu_aux_gpr_dst)) ||
                                    is_accel_getcsr_pseudo);
  assign issue_gpr_check_candidate = issue_gpr_dst_candidate ||
                                     is_store_placeholder ||
                                     is_load_placeholder ||
                                     is_fp_load ||
                                     is_fp_store ||
                                     is_branch ||
                                     is_jalr ||
                                     custom_gpr_src0_valid ||
                                     custom_gpr_src1_valid ||
                                     custom_gpr_src2_valid ||
                                     is_fpu_aux ||
                                     is_tensor_gpr_pseudo ||
                                     is_accel_getcsr_pseudo;
  assign issue_fpr_dst_candidate = !issue_is_pseudo &&
                                   (is_fp_load || is_fpu_fmac || legal_fpu_slow ||
                                    is_fpu_aux_fpr_dst);
  assign issue_fpr_check_candidate = issue_fpr_dst_candidate ||
                                     is_fpu_fmac || legal_fpu_slow || is_fpu_aux ||
                                     is_fp_store;
  assign issue_fpr_src0_valid = (is_fpu_fmac || legal_fpu_slow ||
                                 (legal_fpu_misc &&
                                  !is_fpu_misc_mv_f_x) ||
                                 is_fpu_cvt_f2f || is_fpu_cvt_f2i);
  assign issue_fpr_src1_valid = (is_fpu_fmac ||
                                 (legal_fpu_slow && is_fpu_div) || is_fp_store ||
                                 is_fpu_misc_sgnj ||
                                 is_fpu_misc_minmax ||
                                 is_fpu_misc_cmp);
  assign issue_fpr_src2_valid = is_fpu_fmac_madd;
  assign lsu_issue0_ready_for_class =
    (is_load_placeholder || is_fp_load) ?
      (lsu_issue_ready && lsu_stores_drained) :
    ((is_store_placeholder || is_fp_store) ? lsu_issue_ready : 1'b1);
  assign lsu_issue1_ready_for_class =
    is_load1_placeholder ? (lsu_issue1_ready && lsu_stores_drained) :
    (is_store1_placeholder ? lsu_issue1_ready : 1'b1);
  assign alu_issue0_ready_for_class = !issue0_is_pairable_m ? 1'b1 :
                                      (funct3[2] ? alu_div_issue_ready :
                                                   alu_mul_issue_ready);
  assign alu_issue1_ready_for_class = !issue1_is_pairable_m ? 1'b1 :
                                      (funct3_1[2] ? alu_div_issue_ready :
                                                     alu_mul_issue_ready);
  assign issue_ready = !redirect_kill_valid &&
                       (!cache_op_pending_q || cache_op_complete_valid) &&
                       (retire_alloc_ready || is_tensor_gpr_holder_pseudo) &&
                       producer_queue_issue_ready &&
                       (!is_accel_getcsr_pseudo ||
                        !reverse_snapshot_pending_valid_r[issue_inst[25]]) &&
                       (is_fatal_report_placeholder ||
                        ((!issue_gpr_check_candidate || gpr_issue_ready) &&
                         (!issue_fpr_check_candidate || fpr_issue_ready) &&
                         (!(is_fpu_fmac || is_fpu_aux || legal_fpu_slow) ||
                           fpu_issue_ready) &&
                         (!(is_alu_gpr_placeholder || is_branch) ||
                           alu_issue0_ready_for_class) &&
                         (!(is_load_placeholder || is_store_placeholder ||
                            is_fp_load || is_fp_store) ||
                          lsu_issue0_ready_for_class) &&
                         (!(legal_system || is_ebreak || legal_fence ||
                            legal_custom_control) ||
                          (sys_issue_ready && custom_control_ready &&
                           (!issue_requires_lsu_drain ||
                            serializing_lsu_drained) &&
                           (!cycle_csr_writes_gpr || cycle_csr_gpr_slot_ready)))));
  assign issue_fire = issue_valid && issue_ready;
`ifdef EDGE_DISABLE_SCALAR_ISSUE1
  assign issue1_pair_allowed = 1'b0;
`else
  assign issue1_pair_allowed =
    issue1_is_tensor_gpr_pseudo || issue1_is_accel_getcsr_pseudo ||
    (issue_valid && issue_ready &&
     (issue1_is_memory || issue1_is_pairable_alu || issue1_is_pairable_m) &&
     issue_pair_same_class);
`endif
  assign issue1_ready = !redirect_kill_valid &&
                        (retire_alloc_ready || issue1_is_tensor_gpr_holder_pseudo) &&
                        issue1_pair_allowed &&
                        !(alu_fast1_complete_valid &&
                          (issue1_is_tensor_join_pseudo ||
                           (!issue1_is_pseudo &&
                            (is_store1_placeholder ||
                             (ENABLE_EARLY_LOAD_RETIRE &&
                              is_load1_placeholder))))) &&
                        (issue1_is_accel_getcsr_pseudo ?
                         (!is_accel_getcsr_pseudo &&
                          !reverse_snapshot_pending_valid_r[issue1_inst[25]] &&
                          gpr_issue1_ready) :
                         (issue1_is_tensor_gpr_pseudo ?
                         issue1_tensor_gpr_src_ready :
                         (!issue1_gpr_check_candidate || gpr_issue1_ready))) &&
                        (issue1_is_tensor_gpr_pseudo ||
                         issue1_is_accel_getcsr_pseudo ||
                         (issue1_is_memory ? lsu_issue1_ready_for_class :
                          ((issue1_is_pairable_alu || issue1_is_pairable_m) &&
                           alu_issue1_ready_for_class)));
  assign issue1_fire = issue1_valid && issue1_ready;
  assign retire_complete_nowb_valid = issue_fire && known_placeholder &&
                                       !is_edge_cache_placeholder &&
                                       !is_tensor_join_pseudo &&
                                       !is_accel_getcsr_pseudo &&
                                       !(is_fpu_fmac || is_fpu_aux ||
                                         legal_fpu_slow) &&
                                       (!scalar_def_valid || issue_is_pseudo ||
                                       is_store_placeholder || is_fp_store ||
                                       (is_system_placeholder && !cycle_csr_writes_gpr) ||
                                       is_fence_placeholder ||
                                       (legal_custom_control &&
                                        !is_edge_cache_placeholder));
  assign retire_complete1_nowb_valid =
    issue1_fire && !issue1_is_pseudo && is_store1_placeholder;
  assign retire_alloc_valid = issue_fire && known_placeholder &&
                              !is_tensor_gpr_holder_pseudo;
  assign retire_alloc_seq_id = issue_seq_id;
  assign retire_alloc_epoch = issue_epoch;
  assign retire_alloc_kind = RETIRE_KIND_SCALAR;
  assign retire_alloc_serializing = issue_is_serializing;
  assign retire_alloc1_valid = issue1_fire &&
                               !issue1_is_tensor_gpr_holder_pseudo;
  assign retire_alloc1_seq_id = issue1_seq_id;
  assign retire_alloc1_epoch = issue1_epoch;
  assign retire_alloc1_kind = RETIRE_KIND_SCALAR;
  assign retire_alloc1_serializing = 1'b0;
  assign retire_complete0_valid = gpr_complete_valid ||
                                  alu_complete_nowb_valid;
  assign retire_complete0_seq_id = gpr_complete_valid ?
                                   gpr_complete_seq_id :
                                   alu_fast_complete_seq_id;
  assign retire_complete0_epoch = gpr_complete_valid ?
                                  gpr_complete_epoch :
                                  alu_fast_complete_epoch;
  assign early_gpr_load_retire_valid = ENABLE_EARLY_LOAD_RETIRE &&
                                       lsu_load_accept_valid &&
                                       !lsu_load_accept_domain;
  assign early_gpr_load_retire1_valid = ENABLE_EARLY_LOAD_RETIRE &&
                                        lsu_load_accept1_valid &&
                                        !lsu_load_accept1_domain;
  assign retire_complete1_valid = early_gpr_load_retire_valid ||
                                  (ENABLE_EARLY_LOAD_RETIRE ?
                                   gpr_placeholder_complete_valid :
                                   gpr_load_complete_valid);
  assign retire_complete1_seq_id = early_gpr_load_retire_valid ?
                                   lsu_load_accept_seq_id :
                                   gpr_load_complete_seq_id;
  assign retire_complete1_epoch = early_gpr_load_retire_valid ?
                                  lsu_load_accept_epoch :
                                  gpr_load_complete_epoch;
  assign retire_complete2_valid = fpr_complete_valid;
  assign retire_complete2_seq_id = fpr_complete_seq_id;
  assign retire_complete2_epoch = fpr_complete_epoch;
  assign retire_complete3_valid = retire_complete_nowb_valid ||
                                  cache_op_complete_valid;
  assign retire_complete3_seq_id = cache_op_complete_valid ?
                                   cache_op_complete_seq_id : issue_seq_id;
  assign retire_complete3_epoch = cache_op_complete_valid ?
                                  cache_op_complete_epoch : issue_epoch;
  assign retire_complete4_valid = retire_complete1_nowb_valid ||
                                  early_gpr_load_retire1_valid ||
                                  alu_fast1_complete_valid;
  assign retire_complete4_seq_id = alu_fast1_complete_valid ?
                                   alu_fast1_complete_seq_id :
                                   (early_gpr_load_retire1_valid ?
                                    lsu_load_accept1_seq_id : issue1_seq_id);
  assign retire_complete4_epoch = alu_fast1_complete_valid ?
                                  alu_fast1_complete_epoch :
                                  (early_gpr_load_retire1_valid ?
                                   lsu_load_accept1_epoch : issue1_epoch);
  assign retire_complete5_valid = alu_m_complete_valid;
  assign retire_complete5_seq_id = alu_m_complete_seq_id;
  assign retire_complete5_epoch = alu_m_complete_epoch;
  assign lsu_stores_drained = lsu_debug_stb_count == 4'd0;
  assign lsu_dtcm_store_pending = lsu_debug_stb_dtcm_pending;

  wire gpr_src0_valid;
  wire gpr_src1_valid;
  assign gpr_src0_valid = ((is_op_imm && !is_lui && !is_auipc && !is_jal) ||
                           is_op ||
                           is_op_imm32 ||
                           is_op32 ||
                           is_load_placeholder ||
                           is_store_placeholder ||
                           is_fp_load ||
                           is_fp_store ||
                           is_branch ||
                           is_jalr ||
                           custom_gpr_src0_valid ||
                           is_fpu_misc_mv_f_x || is_fpu_cvt_i2f ||
                           tensor_gpr_src0_valid) &&
                          (rs1 != {REG_INDEX_WIDTH{1'b0}});
  assign gpr_src1_valid =
    (is_op || is_op32 || is_store_placeholder || is_branch ||
     custom_gpr_src1_valid || tensor_gpr_src1_valid) &&
    (rs2 != {REG_INDEX_WIDTH{1'b0}});

  wire [VALUE_WIDTH-1:0] gpr_result;
  assign csr_cycle_accept = issue_fire && cycle_csr_writes_gpr;
  assign reverse_snapshot_issue_accept =
    (issue_fire && is_accel_getcsr_pseudo) ||
    (issue1_fire && issue1_is_accel_getcsr_pseudo);
  assign reverse_snapshot_pending_select_id =
    !reverse_snapshot_pending_valid_r[0] &&
    reverse_snapshot_pending_valid_r[1];
  assign reverse_snapshot_pending_any =
    |reverse_snapshot_pending_valid_r;
  assign reverse_snapshot_complete_accept =
    !redirect_kill_valid && reverse_snapshot_pending_any &&
    reverse_snapshot_read_ready &&
    cycle_csr_gpr_slot_ready;
  assign csr_cycle_complete_valid = csr_cycle_complete_valid_r &&
                                    !redirect_kills_seq(
                                      csr_cycle_complete_seq_id_r,
                                      csr_cycle_complete_epoch_r) &&
                                    !fpu_aux_gpr_complete_valid &&
                                    !(alu_fast_complete_valid &&
                                      alu_fast_complete_rd_valid);
  assign alu_issue_valid = (issue_fire && known_placeholder &&
                            (is_alu_gpr_placeholder || is_branch)) ||
                           issue1_uses_alu;
  assign alu_complete_nowb_valid = alu_fast_complete_valid &&
                                   !alu_fast_complete_rd_valid &&
                                   !alu_complete_control_valid;
  assign gpr_complete_valid = fpu_aux_gpr_complete_valid ||
                              (alu_fast_complete_valid && alu_fast_complete_rd_valid) ||
                              csr_cycle_complete_valid;
  assign gpr_complete_seq_id = fpu_aux_gpr_complete_valid ?
                               fpu_complete_queue_seq_id :
                               (alu_fast_complete_valid && alu_fast_complete_rd_valid) ?
                               alu_fast_complete_seq_id : csr_cycle_complete_seq_id_r;
  assign gpr_complete_epoch = fpu_aux_gpr_complete_valid ?
                              fpu_complete_queue_epoch :
                              (alu_fast_complete_valid && alu_fast_complete_rd_valid) ?
                              alu_fast_complete_epoch : csr_cycle_complete_epoch_r;
  assign gpr_complete_rd = fpu_aux_gpr_complete_valid ?
                           fpu_complete_queue_reg :
                           (alu_fast_complete_valid && alu_fast_complete_rd_valid) ?
                           alu_fast_complete_rd : csr_cycle_complete_rd_r;
  assign gpr_complete_rd_bank = fpu_aux_gpr_complete_valid ?
                                fpu_complete_queue_bank :
                                (alu_fast_complete_valid && alu_fast_complete_rd_valid) ?
                                alu_fast_complete_rd_bank :
                                csr_cycle_complete_rd_bank_r;
  assign gpr_complete_value = fpu_aux_gpr_complete_valid ?
                              fpu_complete_queue_value :
                              (alu_fast_complete_valid && alu_fast_complete_rd_valid) ?
                              alu_fast_complete_value : csr_cycle_complete_value_r;
  assign gpr_result = gpr_complete_value;

  always @* begin
    if (issue1_uses_alu && issue1_is_zba_op) begin
      alu_issue_op = ALU_OP_ZBA;
    end else if (issue1_uses_alu &&
                 (issue1_is_zba_uw_op32 || issue1_is_slli_uw)) begin
      alu_issue_op = ALU_OP_ZBA_UW;
    end else if (issue1_uses_alu && issue1_is_op_imm) begin
      alu_issue_op = ALU_OP_OP_IMM;
    end else if (issue1_uses_alu && issue1_is_op) begin
      alu_issue_op = ALU_OP_OP;
    end else if (issue1_uses_alu && issue1_is_op_imm32) begin
      alu_issue_op = ALU_OP_OP_IMM32;
    end else if (issue1_uses_alu && issue1_is_op32) begin
      alu_issue_op = ALU_OP_OP32;
    end else if (issue1_uses_alu && issue1_is_lui) begin
      alu_issue_op = ALU_OP_LUI;
    end else if (issue1_uses_alu && issue1_is_auipc) begin
      alu_issue_op = ALU_OP_AUIPC;
    end else if (is_zba_op) begin
      alu_issue_op = ALU_OP_ZBA;
    end else if (is_zba_uw_op32 || is_slli_uw) begin
      alu_issue_op = ALU_OP_ZBA_UW;
    end else if (is_op_imm) begin
      alu_issue_op = ALU_OP_OP_IMM;
    end else if (is_op) begin
      alu_issue_op = ALU_OP_OP;
    end else if (is_op_imm32) begin
      alu_issue_op = ALU_OP_OP_IMM32;
    end else if (is_op32) begin
      alu_issue_op = ALU_OP_OP32;
    end else if (is_lui) begin
      alu_issue_op = ALU_OP_LUI;
    end else if (is_auipc) begin
      alu_issue_op = ALU_OP_AUIPC;
    end else if (is_jal) begin
      alu_issue_op = ALU_OP_JAL;
    end else if (is_jalr) begin
      alu_issue_op = ALU_OP_JALR;
    end else begin
      alu_issue_op = ALU_OP_BRANCH;
    end
  end

  always @* begin
    if (issue1_is_zba_op) begin
      alu_issue1_op = ALU_OP_ZBA;
    end else if (issue1_is_zba_uw_op32 || issue1_is_slli_uw) begin
      alu_issue1_op = ALU_OP_ZBA_UW;
    end else if (issue1_is_op_imm) begin
      alu_issue1_op = ALU_OP_OP_IMM;
    end else if (issue1_is_op) begin
      alu_issue1_op = ALU_OP_OP;
    end else if (issue1_is_op_imm32) begin
      alu_issue1_op = ALU_OP_OP_IMM32;
    end else if (issue1_is_op32) begin
      alu_issue1_op = ALU_OP_OP32;
    end else if (issue1_is_lui) begin
      alu_issue1_op = ALU_OP_LUI;
    end else begin
      alu_issue1_op = ALU_OP_AUIPC;
    end
  end

  edge_scalar_alu #(
    .PC_WIDTH(PC_WIDTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .OP_WIDTH(4)
  ) scalar_alu (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .alu_issue_valid(alu_issue_valid),
    .alu_issue_ready(alu_issue_ready),
    .alu_issue_seq_id(issue1_uses_alu ?
                      (scalar1_def_valid ? scalar1_def_seq_id : issue1_seq_id) :
                      (scalar_def_valid ? scalar_def_seq_id : issue_seq_id)),
    .alu_issue_epoch(issue1_uses_alu ?
                     (scalar1_def_valid ? scalar1_def_epoch : issue1_epoch) :
                     (scalar_def_valid ? scalar_def_epoch : issue_epoch)),
    .alu_issue_op(alu_issue_op),
    .alu_issue_pc(issue1_uses_alu ? issue1_pc : issue_pc),
    .alu_issue_rd(issue1_uses_alu ?
                  (scalar1_def_valid ? scalar1_def_dst_reg : rd1) :
                  (scalar_def_valid ? scalar_def_dst_reg : rd)),
    .alu_issue_rd_bank(issue1_uses_alu ? scalar1_def_bank : scalar_def_bank),
    .alu_issue_rd_valid(issue1_uses_alu ?
                        (scalar1_def_valid &&
                         (scalar1_def_dst_reg != {REG_INDEX_WIDTH{1'b0}})) :
                        (scalar_def_valid && !scalar_def_domain &&
                         (scalar_def_dst_reg != {REG_INDEX_WIDTH{1'b0}}))),
    .alu_issue_src0_value(issue1_uses_alu ? rs1_1_alu_value : rs1_value),
    .alu_issue_src1_value(issue1_uses_alu ? rs2_1_alu_value : rs2_value),
    .alu_issue_imm(issue1_uses_alu ?
                   ((issue1_is_lui || issue1_is_auipc) ?
                    lui1_value : imm12_1_sext) :
                   ((is_lui || is_auipc) ? lui_value : imm12_sext)),
    .alu_issue_branch_imm(branch_imm_sext),
    .alu_issue_jal_imm(jal_imm_sext),
    .alu_issue_funct3(issue1_uses_alu ? funct3_1 : funct3),
    .alu_issue_funct7_bit5(issue1_uses_alu ? issue1_inst[30] : issue_inst[30]),
    .alu_issue_funct7_is_m(issue1_uses_alu ? 1'b0 :
                           (issue_inst[31:25] == 7'b0000001)),
    .alu_issue_shamt(issue1_uses_alu ? shamt1 : shamt),
    .alu_issue_shamt32(issue1_uses_alu ? shamt32_1 : shamt32),
    .alu_issue1_valid(issue_dual_alu_pair),
    .alu_issue1_ready(),
    .alu_issue1_seq_id(scalar1_def_valid ? scalar1_def_seq_id : issue1_seq_id),
    .alu_issue1_epoch(scalar1_def_valid ? scalar1_def_epoch : issue1_epoch),
    .alu_issue1_op(alu_issue1_op),
    .alu_issue1_pc(issue1_pc),
    .alu_issue1_rd(scalar1_def_valid ? scalar1_def_dst_reg : rd1),
    .alu_issue1_rd_bank(scalar1_def_bank),
    .alu_issue1_rd_valid(scalar1_def_valid &&
                         (scalar1_def_dst_reg != {REG_INDEX_WIDTH{1'b0}})),
    .alu_issue1_src0_value(rs1_1_alu_value),
    .alu_issue1_src1_value(rs2_1_alu_value),
    .alu_issue1_imm((issue1_is_lui || issue1_is_auipc) ?
                    lui1_value : imm12_1_sext),
    .alu_issue1_funct3(funct3_1),
    .alu_issue1_funct7_bit5(issue1_inst[30]),
    .alu_issue1_funct7_is_m(issue1_is_pairable_m),
    .alu_issue1_shamt(shamt1),
    .alu_issue1_shamt32(shamt32_1),
    .alu_issue_fast_result(alu_issue_fast_result),
    .alu_issue_control_valid(alu_issue_control_valid),
    .alu_issue_control_taken(alu_issue_control_taken),
    .alu_issue_control_target(alu_issue_control_target),
    .alu_complete_valid(alu_complete_valid),
    .alu_complete_seq_id(alu_complete_seq_id),
    .alu_complete_epoch(alu_complete_epoch),
    .alu_complete_rd(alu_complete_rd),
    .alu_complete_rd_bank(alu_complete_rd_bank),
    .alu_complete_rd_valid(alu_complete_rd_valid),
    .alu_complete_value(alu_complete_value),
    .alu_complete_control_valid(alu_complete_control_valid),
    .alu_complete_control_taken(alu_complete_control_taken),
    .alu_complete_control_target(alu_complete_control_target),
    .fast_complete_valid(alu_fast_complete_valid),
    .fast_complete_seq_id(alu_fast_complete_seq_id),
    .fast_complete_epoch(alu_fast_complete_epoch),
    .fast_complete_rd(alu_fast_complete_rd),
    .fast_complete_rd_bank(alu_fast_complete_rd_bank),
    .fast_complete_rd_valid(alu_fast_complete_rd_valid),
    .fast_complete_value(alu_fast_complete_value),
    .fast1_complete_valid(alu_fast1_complete_valid),
    .fast1_complete_seq_id(alu_fast1_complete_seq_id),
    .fast1_complete_epoch(alu_fast1_complete_epoch),
    .fast1_complete_rd(alu_fast1_complete_rd),
    .fast1_complete_rd_bank(alu_fast1_complete_rd_bank),
    .fast1_complete_rd_valid(alu_fast1_complete_rd_valid),
    .fast1_complete_value(alu_fast1_complete_value),
    .m_complete_valid_o(alu_m_complete_valid),
    .m_complete_seq_id_o(alu_m_complete_seq_id),
    .m_complete_epoch_o(alu_m_complete_epoch),
    .m_complete_rd_o(alu_m_complete_rd),
    .m_complete_rd_bank_o(alu_m_complete_rd_bank),
    .m_complete_rd_valid_o(alu_m_complete_rd_valid),
    .m_complete_value_o(alu_m_complete_value),
    .m_issue_ready_o(),
    .mul_issue_ready_o(alu_mul_issue_ready),
    .div_issue_ready_o(alu_div_issue_ready)
  );

  assign fpu_complete_queue_ready = fpu_complete_queue_domain ? 1'b1 :
                                    !(alu_fast_complete_valid && alu_fast_complete_rd_valid) &&
                                    !(alu_m_complete_valid && alu_m_complete_rd_valid) &&
                                    !csr_cycle_complete_valid;

  edge_fpu_complete_queue #(
    .DEPTH(4), .MAX_PUSH(4),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH), .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH), .VALUE_WIDTH(VALUE_WIDTH)
  ) scalar_fpu_complete_queue (
    .forever_cpuclk(forever_cpuclk), .cpurst_b(cpurst_b),
    .flush(redirect_kill_valid),
    .flush_seq_id(redirect_kill_seq_id),
    .flush_epoch(redirect_kill_epoch),
    .in0_valid(fpu_aux_complete_valid),
    .in0_seq_id(fpu_aux_complete_seq_id), .in0_epoch(fpu_aux_complete_epoch),
    .in0_domain(fpu_aux_complete_domain), .in0_reg(fpu_aux_complete_reg),
    .in0_bank(fpu_aux_complete_bank), .in0_value(fpu_aux_complete_value),
    .in0_fflags(fpu_aux_complete_fflags),
    .in1_valid(1'b0),
    .in1_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .in1_epoch({EPOCH_WIDTH{1'b0}}), .in1_domain(1'b1),
    .in1_reg({REG_INDEX_WIDTH{1'b0}}), .in1_bank(1'b0),
    .in1_value({VALUE_WIDTH{1'b0}}), .in1_fflags(5'b0),
    .in2_valid(fpu_complete_valid),
    .in2_seq_id(fpu_complete_seq_id), .in2_epoch(fpu_complete_epoch),
    .in2_domain(1'b1), .in2_reg(fpu_complete_reg),
    .in2_bank(fpu_complete_bank), .in2_value(fpu_complete_value),
    .in2_fflags(fpu_fmac_wb_fflags),
    .in3_valid((lsu_load_complete_valid && lsu_load_complete_domain) ||
               fpr_placeholder_complete_valid),
    .in3_seq_id((lsu_load_complete_valid && lsu_load_complete_domain) ?
                lsu_load_complete_seq_id : fpr_placeholder_complete_seq_id),
    .in3_epoch((lsu_load_complete_valid && lsu_load_complete_domain) ?
               lsu_load_complete_epoch : fpr_placeholder_complete_epoch),
    .in3_domain(1'b1),
    .in3_reg((lsu_load_complete_valid && lsu_load_complete_domain) ?
             lsu_load_complete_reg : fpr_placeholder_complete_reg),
    .in3_bank((lsu_load_complete_valid && lsu_load_complete_domain) ?
              lsu_load_complete_bank : fpr_placeholder_complete_bank),
    .in3_value((lsu_load_complete_valid && lsu_load_complete_domain) ?
               {32'b0, lsu_fpr_load_complete_value} :
               {32'b0, fpr_placeholder_complete_value}), .in3_fflags(5'b0),
    .in4_valid(fpu_slow_complete_valid),
    .in4_seq_id(fpu_slow_complete_seq_id),
    .in4_epoch(fpu_slow_complete_epoch), .in4_domain(1'b1),
    .in4_reg(fpu_slow_complete_reg), .in4_bank(fpu_slow_complete_bank),
    .in4_value({32'b0,fpu_slow_complete_value}),
    .in4_fflags(fpu_slow_complete_fflags),
    .ingress_ready(fpu_complete_queue_ingress_ready),
    .out_valid(fpu_complete_queue_valid), .out_ready(fpu_complete_queue_ready),
    .out_seq_id(fpu_complete_queue_seq_id),
    .out_epoch(fpu_complete_queue_epoch),
    .out_domain(fpu_complete_queue_domain), .out_reg(fpu_complete_queue_reg),
    .out_bank(fpu_complete_queue_bank), .out_value(fpu_complete_queue_value),
    .out_fflags(fpu_complete_queue_fflags)
  );

  edge_fpu_slow #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH), .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH)
  ) scalar_fpu_slow (
    .forever_cpuclk(forever_cpuclk), .cpurst_b(cpurst_b),
    .slow_cancel(redirect_kills_seq(fpu_slow_complete_seq_id,
                                    fpu_slow_complete_epoch)),
    .slow_issue_valid(fpu_slow_issue_valid),
    .slow_issue_ready(fpu_slow_issue_ready),
    .slow_issue_seq_id(issue_seq_id), .slow_issue_epoch(issue_epoch),
    .slow_issue_sqrt(is_fpu_sqrt), .slow_issue_rm(fpu_issue_rm),
    .slow_issue_rd(rd), .slow_issue_rd_bank(scalar_def_bank),
    .slow_issue_src0(fpr_rs1_value), .slow_issue_src1(fpr_rs2_value),
    .slow_complete_valid(fpu_slow_complete_valid),
    .slow_complete_seq_id(fpu_slow_complete_seq_id),
    .slow_complete_epoch(fpu_slow_complete_epoch),
    .slow_complete_rd(fpu_slow_complete_reg),
    .slow_complete_rd_bank(fpu_slow_complete_bank),
    .slow_complete_value(fpu_slow_complete_value),
    .slow_complete_fflags(fpu_slow_complete_fflags)
  );

  edge_fpu_fmac scalar_fpu_fmac (
    .cpurst_b(cpurst_b),
    .forever_cpuclk(forever_cpuclk),
    .fmac_cancel(1'b0),
    .fmac_inst_vld(fpu_issue_valid),
    .fmac_func(fpu_fmac_func),
    .fmac_rm(fpu_issue_rm),
    .fmac_src0(fpr_rs1_value),
    .fmac_src1(fpr_rs2_value),
    .fmac_src2(fpr_rs3_value),
    .fmac_dst_reg(scalar_def_valid ? scalar_def_dst_reg : rd),
    .fmac_dst_vld(scalar_def_valid && scalar_def_domain),
    .fmac_stall(fpu_fmac_stall),
    .fmac_wb_data(fpu_fmac_wb_data),
    .fmac_wb_fflags(fpu_fmac_wb_fflags),
    .fmac_wb_reg(fpu_fmac_wb_reg),
    .fmac_wb_vld(fpu_fmac_wb_vld)
  );

  edge_fpu_misc #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH)
  ) scalar_fpu_misc (
    .forever_cpuclk(forever_cpuclk), .cpurst_b(cpurst_b),
    .misc_issue_valid(fpu_misc_issue_valid),
    .misc_issue_ready(fpu_misc_issue_ready),
    .misc_issue_seq_id(issue_seq_id), .misc_issue_epoch(issue_epoch),
    .misc_issue_op(fpu_misc_op), .misc_issue_fmt(issue_inst[26:25]),
    .misc_issue_rm(fpu_issue_rm), .misc_issue_funct3(funct3),
    .misc_issue_rd(rd), .misc_issue_rd_bank(scalar_def_bank),
    .misc_issue_fsrc0(fpr_rs1_value),
    .misc_issue_fsrc1(fpr_rs2_value), .misc_issue_gsrc0(rs1_value),
    .misc_complete_valid(fpu_misc_complete_valid_raw),
    .misc_complete_seq_id(fpu_misc_complete_seq_id),
    .misc_complete_epoch(fpu_misc_complete_epoch),
    .misc_complete_rd(fpu_misc_complete_reg),
    .misc_complete_rd_bank(fpu_misc_complete_bank),
    .misc_complete_domain(fpu_misc_complete_domain),
    .misc_complete_value(fpu_misc_complete_value),
    .misc_complete_fflags(fpu_misc_complete_fflags)
  );

  edge_fpu_cvt #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH)
  ) scalar_fpu_cvt (
    .forever_cpuclk(forever_cpuclk), .cpurst_b(cpurst_b),
    .cvt_issue_valid(fpu_cvt_issue_valid),
    .cvt_issue_ready(fpu_cvt_issue_ready),
    .cvt_issue_seq_id(issue_seq_id), .cvt_issue_epoch(issue_epoch),
    .cvt_issue_op(fpu_cvt_op), .cvt_issue_int_type(rs2[1:0]),
    .cvt_issue_rm(fpu_issue_rm), .cvt_issue_rd(rd),
    .cvt_issue_rd_bank(scalar_def_bank),
    .cvt_issue_fsrc(fpr_rs1_value), .cvt_issue_gsrc(rs1_value),
    .cvt_complete_valid(fpu_cvt_complete_valid_raw),
    .cvt_complete_seq_id(fpu_cvt_complete_seq_id),
    .cvt_complete_epoch(fpu_cvt_complete_epoch),
    .cvt_complete_rd(fpu_cvt_complete_reg),
    .cvt_complete_rd_bank(fpu_cvt_complete_bank),
    .cvt_complete_domain(fpu_cvt_complete_domain),
    .cvt_complete_value(fpu_cvt_complete_value),
    .cvt_complete_fflags(fpu_cvt_complete_fflags)
  );

  assign lsu_issue_valid = issue_fire && known_placeholder &&
                           (is_load_placeholder || is_store_placeholder ||
                            is_fp_load || is_fp_store);
  assign lsu_issue1_valid = issue1_fire && issue1_is_memory;

  edge_lsu_top #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .STB_DEPTH(SCALAR_LSU_QUEUE_DEPTH),
    .LOADQ_DEPTH(SCALAR_LOAD_QUEUE_DEPTH),
    .LOADQ_COUNT_WIDTH(SCALAR_LOAD_QUEUE_COUNT_WIDTH),
    .ENABLE_COMMITTED_STORE_DRAIN(ENABLE_COMMITTED_STORE_DRAIN)
  ) scalar_lsu (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .edge_dtcm_enable(edge_dtcm_enable),
    .edge_dtcm_base(edge_dtcm_base),
    .edge_dtcm_mask(edge_dtcm_mask),
    .lsu_dtcm_store_query_seq_id(lsu_dtcm_store_query_seq_id),
    .lsu_dtcm_store_query_epoch(lsu_dtcm_store_query_epoch),
    .lsu_issue_valid(lsu_issue_valid),
    .lsu_issue_ready(lsu_issue_ready),
    .lsu_issue_seq_id(issue_seq_id),
    .lsu_issue_epoch(issue_epoch),
    .lsu_issue_is_store(is_store_placeholder || is_fp_store),
    .lsu_issue_funct3(funct3),
    .lsu_issue_rd(scalar_def_valid ? scalar_def_dst_reg : rd),
    .lsu_issue_bank(scalar_def_bank),
    .lsu_issue_domain(is_fp_load),
    .lsu_issue_base_value(rs1_value),
    .lsu_issue_offset((is_store_placeholder || is_fp_store) ?
                      store_imm12_sext : imm12_sext),
    .lsu_issue_store_data(is_fp_store ?
      (funct3 == 3'b001 ? {{(VALUE_WIDTH-16){1'b0}},
                           fp32_to_fp16_rne(fpr_rs2_value)} :
       funct3 == 3'b101 ? {{(VALUE_WIDTH-16){1'b0}},
                           fp32_to_bf16_rne(fpr_rs2_value)} :
       funct3 == 3'b011 ? fp32_to_fp64(fpr_rs2_value) :
                          {{(VALUE_WIDTH-32){1'b0}}, fpr_rs2_value}) :
      rs2_value),
    .lsu_issue1_valid(lsu_issue1_valid),
    .lsu_issue1_ready(lsu_issue1_ready),
    .lsu_issue1_seq_id(issue1_seq_id),
    .lsu_issue1_epoch(issue1_epoch),
    .lsu_issue1_is_store(is_store1_placeholder),
    .lsu_issue1_funct3(funct3_1),
    .lsu_issue1_rd(scalar1_def_valid ? scalar1_def_dst_reg : rd1),
    .lsu_issue1_bank(scalar1_def_bank),
    .lsu_issue1_domain(1'b0),
    .lsu_issue1_base_value(rs1_1_value),
    .lsu_issue1_offset(is_store1_placeholder ? store_imm12_1_sext : imm12_1_sext),
    .lsu_issue1_store_data(rs2_1_value),
    .lsu_store_commit0_valid(ordered_retire0_valid),
    .lsu_store_commit0_seq_id(ordered_retire0_seq_id),
    .lsu_store_commit0_epoch(ordered_retire0_epoch),
    .lsu_store_commit1_valid(ordered_retire1_valid),
    .lsu_store_commit1_seq_id(ordered_retire1_seq_id),
    .lsu_store_commit1_epoch(ordered_retire1_epoch),
    .lsu_complete_valid(lsu_complete_valid),
    .lsu_complete_seq_id(lsu_complete_seq_id),
    .lsu_complete_epoch(lsu_complete_epoch),
    .lsu_complete_is_store(lsu_complete_is_store),
    .lsu_complete_size(lsu_complete_size),
    .lsu_complete_load_signed(lsu_complete_load_signed),
    .lsu_complete_addr(lsu_complete_addr),
    .lsu_complete_store_data(lsu_complete_store_data),
    .lsu_misaligned_valid(lsu_misaligned_valid),
    .lsu_misaligned_lane1(lsu_misaligned_lane1),
    .lsu_misaligned_seq_id(lsu_misaligned_seq_id),
    .lsu_misaligned_epoch(lsu_misaligned_epoch),
    .lsu_misaligned_is_store(lsu_misaligned_is_store),
    .lsu_misaligned_size(lsu_misaligned_size),
    .lsu_misaligned_addr(lsu_misaligned_addr),
    .lsu_complete1_valid(lsu_complete1_valid),
    .lsu_complete1_seq_id(lsu_complete1_seq_id),
    .lsu_complete1_epoch(lsu_complete1_epoch),
    .lsu_complete1_is_store(lsu_complete1_is_store),
    .lsu_complete1_size(lsu_complete1_size),
    .lsu_complete1_load_signed(lsu_complete1_load_signed),
    .lsu_complete1_addr(lsu_complete1_addr),
    .lsu_complete1_store_data(lsu_complete1_store_data),
    .lsu_load_accept_valid(lsu_load_accept_valid),
    .lsu_load_accept_seq_id(lsu_load_accept_seq_id),
    .lsu_load_accept_epoch(lsu_load_accept_epoch),
    .lsu_load_accept_domain(lsu_load_accept_domain),
    .lsu_load_accept1_valid(lsu_load_accept1_valid),
    .lsu_load_accept1_seq_id(lsu_load_accept1_seq_id),
    .lsu_load_accept1_epoch(lsu_load_accept1_epoch),
    .lsu_load_accept1_domain(lsu_load_accept1_domain),
    .lsu_load_resp_valid(lsu_load_resp_valid),
    .lsu_load_resp_seq_id(lsu_load_resp_seq_id),
    .lsu_load_resp_epoch(lsu_load_resp_epoch),
    .lsu_load_resp_error(lsu_load_resp_error),
    .lsu_load_resp_value(lsu_load_resp_value),
    .lsu_load_req_valid(lsu_load_req_valid),
    .lsu_load_req_ready(lsu_load_req_ready),
    .lsu_load_req_seq_id(lsu_load_req_seq_id),
    .lsu_load_req_epoch(lsu_load_req_epoch),
    .lsu_load_req_addr(lsu_load_req_addr),
    .lsu_load_req_size(lsu_load_req_size),
    .lsu_load_req_signed(lsu_load_req_signed),
    .lsu_load_req1_valid(lsu_load_req1_valid),
    .lsu_load_req1_ready(lsu_load_req1_ready),
    .lsu_load_req1_seq_id(lsu_load_req1_seq_id),
    .lsu_load_req1_epoch(lsu_load_req1_epoch),
    .lsu_load_req1_addr(lsu_load_req1_addr),
    .lsu_load_req1_size(lsu_load_req1_size),
    .lsu_load_req1_signed(lsu_load_req1_signed),
    .lsu_store_req_valid(lsu_store_req_valid),
    .lsu_store_req_ready(lsu_store_req_ready),
    .lsu_store_req_seq_id(lsu_store_req_seq_id),
    .lsu_store_req_epoch(lsu_store_req_epoch),
    .lsu_store_req_addr(lsu_store_req_addr),
    .lsu_store_req_size(lsu_store_req_size),
    .lsu_store_req_data(lsu_store_req_data),
    .lsu_store_req_wstrb(lsu_store_req_wstrb),
    .lsu_store_req1_valid(lsu_store_req1_valid),
    .lsu_store_req1_ready(lsu_store_req1_ready),
    .lsu_store_req1_seq_id(lsu_store_req1_seq_id),
    .lsu_store_req1_epoch(lsu_store_req1_epoch),
    .lsu_store_req1_addr(lsu_store_req1_addr),
    .lsu_store_req1_size(lsu_store_req1_size),
    .lsu_store_req1_data(lsu_store_req1_data),
    .lsu_store_req1_wstrb(lsu_store_req1_wstrb),
    .lsu_load_complete_valid(lsu_load_complete_valid),
    .lsu_load_complete_seq_id(lsu_load_complete_seq_id),
    .lsu_load_complete_epoch(lsu_load_complete_epoch),
    .lsu_load_complete_reg(lsu_load_complete_reg),
    .lsu_load_complete_bank(lsu_load_complete_bank),
    .lsu_load_complete_domain(lsu_load_complete_domain),
    .lsu_load_complete_size(lsu_load_complete_size),
    .lsu_load_complete_error(lsu_load_complete_error),
    .lsu_load_complete_value(lsu_load_complete_value),
    .lsu_flush_valid(redirect_kill_valid),
    .lsu_flush_seq_id(redirect_kill_seq_id),
    .lsu_flush_epoch(redirect_kill_epoch),
	    .lsu_debug_stb_count(lsu_debug_stb_count),
	    .lsu_debug_stb_drain_valid(),
	    .lsu_debug_stb_drain_data(),
	    .lsu_debug_stb_drain_wstrb(),
	    .lsu_debug_stb_dtcm_pending(lsu_debug_stb_dtcm_pending),
	    .lsu_debug_loadq_count(lsu_debug_loadq_count),
	    .lsu_debug_load_req_valid(),
	    .lsu_debug_load_req_addr()
	  );

  assign sys_issue_valid = issue_fire &&
                           ((legal_system && !is_cycle_csr_read) ||
                            legal_fence ||
                            legal_custom_control);

  edge_scalar_csr_sys #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH)
  ) scalar_csr_sys (
    .sys_issue_valid(sys_issue_valid),
    .sys_issue_ready(sys_issue_ready),
    .sys_issue_seq_id(issue_seq_id),
    .sys_issue_epoch(issue_epoch),
    .sys_issue_is_fence(legal_fence),
    .sys_issue_fence_i(funct3 == 3'b001),
    .sys_issue_funct3(funct3),
    .sys_issue_csr(issue_inst[31:20]),
    .sys_issue_rd(rd),
    .sys_issue_rs1(rs1),
    .sys_complete_valid(sys_complete_valid),
    .sys_complete_seq_id(sys_complete_seq_id),
    .sys_complete_epoch(sys_complete_epoch),
    .system_placeholder_valid(sys_system_placeholder_valid),
    .system_placeholder_funct3(sys_system_placeholder_funct3),
    .system_placeholder_csr(sys_system_placeholder_csr),
    .system_placeholder_rd(sys_system_placeholder_rd),
    .system_placeholder_rs1(sys_system_placeholder_rs1),
    .fence_placeholder_valid(sys_fence_placeholder_valid),
    .fence_placeholder_i(sys_fence_placeholder_i)
  );

  edge_wbt #(
    .REG_COUNT(32),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH)
  ) gpr_wbt (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .issue_valid(gpr_issue_valid),
    .issue_seq_id(issue_seq_id),
    .issue_epoch(issue_epoch),
    .issue_src0(rs1),
    .issue_src0_valid(issue_gpr_check_candidate && gpr_src0_valid),
    .issue_src1(rs2),
    .issue_src1_valid(issue_gpr_check_candidate && gpr_src1_valid),
    .issue_src2(rd),
    .issue_src2_valid(issue_gpr_check_candidate &&
                      (custom_gpr_src2_valid ||
                       tensor_gpr_src2_valid)),
    .issue_dst(rd),
    .issue_dst_valid(issue_gpr_dst_candidate),
    .issue_ready(gpr_issue_ready),
    .issue1_valid(gpr_issue1_valid),
    .issue1_seq_id(scalar1_def_valid ? scalar1_def_seq_id : issue1_seq_id),
    .issue1_epoch(scalar1_def_valid ? scalar1_def_epoch : issue1_epoch),
    .issue1_src0(rs1_1),
    .issue1_src0_valid(issue1_gpr_check_candidate &&
                       (issue1_gpr_src0_valid ||
                        issue1_tensor_gpr_src0_valid) &&
                       !issue1_src0_forwarded),
    .issue1_src1(rs2_1),
    .issue1_src1_valid(issue1_gpr_check_candidate &&
                       (issue1_gpr_src1_valid ||
                        issue1_tensor_gpr_src1_valid) &&
                       !issue1_src1_forwarded),
    .issue1_src2(rd1),
    .issue1_src2_valid(issue1_gpr_check_candidate &&
                       issue1_tensor_gpr_src2_valid),
    .issue1_dst(scalar1_def_valid ? scalar1_def_dst_reg : rd1),
    .issue1_dst_valid(issue1_gpr_dst_candidate),
    .issue1_ready(gpr_issue1_ready),
    .src_ready(),
    .dst_reserve_ready(),
    .dependency_stall(),
    .complete_valid(gpr_complete_valid),
    .complete_seq_id(gpr_complete_seq_id),
    .complete_epoch(gpr_complete_epoch),
    .complete_dst(gpr_complete_rd),
    .complete2_valid(gpr_load_complete_valid),
    .complete2_seq_id(gpr_load_complete_seq_id),
    .complete2_epoch(gpr_load_complete_epoch),
    .complete2_dst(gpr_load_complete_reg),
    .complete3_valid(alu_m_complete_valid && alu_m_complete_rd_valid),
    .complete3_seq_id(alu_m_complete_seq_id),
    .complete3_epoch(alu_m_complete_epoch),
    .complete3_dst(alu_m_complete_rd),
    .complete4_valid(alu_fast1_complete_valid && alu_fast1_complete_rd_valid),
    .complete4_seq_id(alu_fast1_complete_seq_id),
    .complete4_epoch(alu_fast1_complete_epoch),
    .complete4_dst(alu_fast1_complete_rd),
    .redirect_kill_valid(redirect_kill_valid),
    .redirect_kill_seq_id(redirect_kill_seq_id),
    .redirect_kill_epoch(redirect_kill_epoch),
    .debug_busy(gpr_busy_status)
  );

  edge_wbt #(
    .REG_COUNT(32),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .ISSUE1_ENABLE(0)
  ) fpr_wbt (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .issue_valid(fpr_issue_valid),
    .issue_seq_id(issue_seq_id),
    .issue_epoch(issue_epoch),
    .issue_src0(rs1),
    .issue_src0_valid(issue_fpr_src0_valid),
    .issue_src1(rs2),
    .issue_src1_valid(issue_fpr_src1_valid),
    .issue_src2(rs3),
    .issue_src2_valid(issue_fpr_src2_valid),
    .issue_dst(rd),
    .issue_dst_valid(issue_fpr_dst_candidate),
    .issue_ready(fpr_issue_ready),
    .issue1_valid(1'b0),
    .issue1_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .issue1_epoch({EPOCH_WIDTH{1'b0}}),
    .issue1_src0({REG_INDEX_WIDTH{1'b0}}),
    .issue1_src0_valid(1'b0),
    .issue1_src1({REG_INDEX_WIDTH{1'b0}}),
    .issue1_src1_valid(1'b0),
    .issue1_src2({REG_INDEX_WIDTH{1'b0}}),
    .issue1_src2_valid(1'b0),
    .issue1_dst({REG_INDEX_WIDTH{1'b0}}),
    .issue1_dst_valid(1'b0),
    .issue1_ready(),
    .src_ready(),
    .dst_reserve_ready(),
    .dependency_stall(),
    .complete_valid(fpr_complete_valid),
    .complete_seq_id(fpr_complete_seq_id),
    .complete_epoch(fpr_complete_epoch),
    .complete_dst(fpr_complete_reg),
    .complete2_valid(1'b0),
    .complete2_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .complete2_epoch({EPOCH_WIDTH{1'b0}}),
    .complete2_dst({REG_INDEX_WIDTH{1'b0}}),
    .complete3_valid(1'b0),
    .complete3_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .complete3_epoch({EPOCH_WIDTH{1'b0}}),
    .complete3_dst({REG_INDEX_WIDTH{1'b0}}),
    .complete4_valid(1'b0),
    .complete4_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .complete4_epoch({EPOCH_WIDTH{1'b0}}),
    .complete4_dst({REG_INDEX_WIDTH{1'b0}}),
    .redirect_kill_valid(redirect_kill_valid),
    .redirect_kill_seq_id(redirect_kill_seq_id),
    .redirect_kill_epoch(redirect_kill_epoch),
    .debug_busy(fpr_busy_status)
  );

  reg producer_valid_r;
  reg producer_domain_r;
  reg [REG_INDEX_WIDTH-1:0] producer_reg_r;
  reg producer_bank_r;
  reg [PRODUCER_TAG_WIDTH-1:0] producer_tag_r;
  reg [VALUE_WIDTH-1:0] producer_value_r;
  reg [EPOCH_WIDTH-1:0] producer_epoch_r;
  reg [PRODUCER_QUEUE_INDEX_WIDTH-1:0] producer_queue_head_r;
  reg [PRODUCER_QUEUE_INDEX_WIDTH-1:0] producer_queue_tail_r;
  reg [PRODUCER_QUEUE_COUNT_WIDTH-1:0] producer_queue_count_r;
  reg producer_queue_domain [0:PRODUCER_QUEUE_DEPTH-1];
  reg [REG_INDEX_WIDTH-1:0] producer_queue_reg [0:PRODUCER_QUEUE_DEPTH-1];
  reg producer_queue_bank [0:PRODUCER_QUEUE_DEPTH-1];
  reg [PRODUCER_TAG_WIDTH-1:0] producer_queue_tag [0:PRODUCER_QUEUE_DEPTH-1];
  reg [VALUE_WIDTH-1:0] producer_queue_value [0:PRODUCER_QUEUE_DEPTH-1];
  reg [EPOCH_WIDTH-1:0] producer_queue_epoch [0:PRODUCER_QUEUE_DEPTH-1];
  reg retire_valid_r;
  reg [SEQ_ID_WIDTH-1:0] retire_seq_id_r;
  reg [EPOCH_WIDTH-1:0] retire_epoch_r;
  reg retire_is_pseudo_r;
  reg mem_placeholder_valid_r;
  reg mem_placeholder_is_store_r;
  reg [1:0] mem_placeholder_size_r;
  reg [VALUE_WIDTH-1:0] mem_placeholder_addr_r;
  reg [VALUE_WIDTH-1:0] mem_placeholder_store_data_r;
  reg [SEQ_ID_WIDTH-1:0] mem_placeholder_seq_id_r;
  reg [EPOCH_WIDTH-1:0] mem_placeholder_epoch_r;
  reg mem_placeholder_load_signed_r;
  reg mem_placeholder1_valid_r;
  reg mem_placeholder1_is_store_r;
  reg [1:0] mem_placeholder1_size_r;
  reg [VALUE_WIDTH-1:0] mem_placeholder1_addr_r;
  reg [VALUE_WIDTH-1:0] mem_placeholder1_store_data_r;
  reg [SEQ_ID_WIDTH-1:0] mem_placeholder1_seq_id_r;
  reg [EPOCH_WIDTH-1:0] mem_placeholder1_epoch_r;
  reg mem_placeholder1_load_signed_r;
  reg system_placeholder_valid_r;
  reg [2:0] system_placeholder_funct3_r;
  reg [11:0] system_placeholder_csr_r;
  reg [REG_INDEX_WIDTH-1:0] system_placeholder_rd_r;
  reg [REG_INDEX_WIDTH-1:0] system_placeholder_rs1_r;
  reg [VALUE_WIDTH-1:0] system_placeholder_rs1_value_r;
  reg [SEQ_ID_WIDTH-1:0] system_placeholder_seq_id_r;
  reg [EPOCH_WIDTH-1:0] system_placeholder_epoch_r;
  reg fence_placeholder_valid_r;
  reg fence_placeholder_i_r;
  reg [SEQ_ID_WIDTH-1:0] fence_placeholder_seq_id_r;
  reg [EPOCH_WIDTH-1:0] fence_placeholder_epoch_r;
  reg fatal_report_valid_r;
  reg [3:0] fatal_report_code_r;
  reg [VALUE_WIDTH-1:0] fatal_report_inst_r;
  reg [SEQ_ID_WIDTH-1:0] fatal_report_seq_id_r;
  reg [EPOCH_WIDTH-1:0] fatal_report_epoch_r;
  reg ebreak_report_valid_r;
  reg [SEQ_ID_WIDTH-1:0] ebreak_report_seq_id_r;
  reg [EPOCH_WIDTH-1:0] ebreak_report_epoch_r;
  reg ebreak_report_pending_r;
  reg [SEQ_ID_WIDTH-1:0] ebreak_report_pending_seq_id_r;
  reg [EPOCH_WIDTH-1:0] ebreak_report_pending_epoch_r;
  wire ebreak_ordered_retire;
  wire [SEQ_ID_WIDTH-1:0] ebreak_redirect_distance;
  wire ebreak_killed_by_redirect;

  assign ebreak_ordered_retire = ebreak_report_pending_r &&
    ((ordered_retire0_valid &&
      (ordered_retire0_seq_id == ebreak_report_pending_seq_id_r) &&
      (ordered_retire0_epoch == ebreak_report_pending_epoch_r)) ||
     (ordered_retire1_valid &&
      (ordered_retire1_seq_id == ebreak_report_pending_seq_id_r) &&
      (ordered_retire1_epoch == ebreak_report_pending_epoch_r)));
  assign ebreak_redirect_distance = ebreak_report_pending_seq_id_r -
                                    redirect_kill_seq_id;
  assign ebreak_killed_by_redirect = redirect_kill_valid &&
    ebreak_report_pending_r &&
    (ebreak_report_pending_epoch_r == redirect_kill_epoch) &&
    (ebreak_redirect_distance != {SEQ_ID_WIDTH{1'b0}}) &&
    !ebreak_redirect_distance[SEQ_ID_WIDTH-1];

  assign producer_valid = producer_valid_r;
  assign producer_domain = producer_domain_r;
  assign producer_reg = producer_reg_r;
  assign producer_bank = producer_bank_r;
  assign producer_tag = producer_tag_r;
  assign producer_value = producer_value_r;
  assign producer_epoch = producer_epoch_r;
  assign retire_valid = retire_valid_r;
  assign retire_seq_id = retire_seq_id_r;
  assign retire_epoch = retire_epoch_r;
  assign retire_is_pseudo = retire_is_pseudo_r;
  assign mem_placeholder_valid = mem_placeholder_valid_r;
  assign mem_placeholder_is_store = mem_placeholder_is_store_r;
  assign mem_placeholder_size = mem_placeholder_size_r;
  assign mem_placeholder_load_signed = mem_placeholder_load_signed_r;
  assign mem_placeholder_addr = mem_placeholder_addr_r;
  assign mem_placeholder_store_data = mem_placeholder_store_data_r;
  assign mem_placeholder_seq_id = mem_placeholder_seq_id_r;
  assign mem_placeholder_epoch = mem_placeholder_epoch_r;
  assign mem_placeholder1_valid = mem_placeholder1_valid_r;
  assign mem_placeholder1_is_store = mem_placeholder1_is_store_r;
  assign mem_placeholder1_size = mem_placeholder1_size_r;
  assign mem_placeholder1_load_signed = mem_placeholder1_load_signed_r;
  assign mem_placeholder1_addr = mem_placeholder1_addr_r;
  assign mem_placeholder1_store_data = mem_placeholder1_store_data_r;
  assign mem_placeholder1_seq_id = mem_placeholder1_seq_id_r;
  assign mem_placeholder1_epoch = mem_placeholder1_epoch_r;
  assign system_placeholder_valid = system_placeholder_valid_r;
  assign system_placeholder_funct3 = system_placeholder_funct3_r;
  assign system_placeholder_csr = system_placeholder_csr_r;
  assign system_placeholder_rd = system_placeholder_rd_r;
  assign system_placeholder_rs1 = system_placeholder_rs1_r;
  assign system_placeholder_rs1_value = system_placeholder_rs1_value_r;
  assign system_placeholder_seq_id = system_placeholder_seq_id_r;
  assign system_placeholder_epoch = system_placeholder_epoch_r;
  assign cache_op_valid = issue_fire && is_edge_cache_placeholder;
  assign cache_op_is_va = funct3 == 3'b001;
  assign cache_op_kind = rs2[1:0];
  assign cache_op_addr = rs1_value;
  assign cache_op_seq_id = issue_seq_id;
  assign cache_op_epoch = issue_epoch;
  assign dma_start_valid = issue_fire && is_edge_dma_start;
  assign dma_start_src = rs1_value;
  assign dma_start_dst = rs2_value;
  assign dma_start_len = rd_value;
  assign dma_start_seq_id = issue_seq_id;
  assign dma_start_epoch = issue_epoch;
  assign dma_sync_valid = issue_fire && is_edge_dma_sync;
  assign dma_sync_seq_id = issue_seq_id;
  assign dma_sync_epoch = issue_epoch;
  assign fence_placeholder_valid = fence_placeholder_valid_r;
  assign fence_placeholder_i = fence_placeholder_i_r;
  assign fence_placeholder_seq_id = fence_placeholder_seq_id_r;
  assign fence_placeholder_epoch = fence_placeholder_epoch_r;
  assign fatal_report_valid = fatal_report_valid_r;
  assign fatal_report_code = fatal_report_code_r;
  assign fatal_report_inst = fatal_report_inst_r;
  assign fatal_report_seq_id = fatal_report_seq_id_r;
  assign fatal_report_epoch = fatal_report_epoch_r;
  assign ebreak_report_valid = ebreak_report_valid_r;
  assign ebreak_report_seq_id = ebreak_report_seq_id_r;
  assign ebreak_report_epoch = ebreak_report_epoch_r;
  assign control_placeholder_valid = alu_issue_control_valid;
  assign control_placeholder_taken = alu_issue_control_taken;
  assign control_placeholder_target = alu_issue_control_target;
  assign control_placeholder_seq_id = issue_seq_id;
  assign control_placeholder_epoch = issue_epoch;
  edge_scalar_snapshot #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .SNAPSHOT_TARGET_WIDTH(3)
  ) tensor_snapshot_lane0 (
    .issue_valid(issue_fire && is_tensor_gpr_pseudo),
    .issue_ready(),
    .issue_inst(issue_inst),
    .issue_seq_id(issue_seq_id),
    .issue_epoch(issue_epoch),
    .rs1_ready(1'b1),
    .rs1_value(rs1_value),
    .rs2_ready(1'b1),
    .rs2_value(rs2_value),
    .rd_ready(1'b1),
    .rd_value(rd_value),
    .snapshot_ready(1'b1),
    .redirect_kill_valid(1'b0),
    .snapshot_valid(tensor_snapshot0_valid),
    .snapshot_target_o(tensor_snapshot0_target),
    .snapshot_operand_valid(tensor_snapshot0_operand_valid),
    .snapshot_operand_reg(),
    .snapshot_operand_value(tensor_snapshot0_operand_value),
    .retire_valid(),
    .retire_seq_id(),
    .retire_epoch()
  );

  edge_scalar_snapshot #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .SNAPSHOT_TARGET_WIDTH(3)
  ) tensor_snapshot_lane1 (
    .issue_valid(issue1_fire && issue1_is_tensor_gpr_pseudo),
    .issue_ready(),
    .issue_inst(issue1_inst),
    .issue_seq_id(issue1_seq_id),
    .issue_epoch(issue1_epoch),
    .rs1_ready(1'b1),
    .rs1_value(rs1_1_value),
    .rs2_ready(1'b1),
    .rs2_value(rs2_1_value),
    .rd_ready(1'b1),
    .rd_value(rd1_value),
    .snapshot_ready(1'b1),
    .redirect_kill_valid(1'b0),
    .snapshot_valid(tensor_snapshot1_valid),
    .snapshot_target_o(tensor_snapshot1_target),
    .snapshot_operand_valid(tensor_snapshot1_operand_valid),
    .snapshot_operand_reg(),
    .snapshot_operand_value(tensor_snapshot1_operand_value),
    .retire_valid(),
    .retire_seq_id(),
    .retire_epoch()
  );

  assign tensor_gpr_snapshot_valid = tensor_snapshot0_valid || tensor_snapshot1_valid;
  assign tensor_gpr_snapshot_seq_id =
    tensor_snapshot1_valid ? issue1_seq_id : issue_seq_id;
  assign tensor_gpr_snapshot_epoch =
    tensor_snapshot1_valid ? issue1_epoch : issue_epoch;
  assign tensor_gpr_snapshot_target =
    tensor_snapshot1_valid ? tensor_snapshot1_target : tensor_snapshot0_target;
  assign tensor_gpr_snapshot_operand_valid = tensor_snapshot1_valid ?
                                             tensor_snapshot1_operand_valid :
                                             tensor_snapshot0_operand_valid;
  assign tensor_gpr_snapshot_operand_value = tensor_snapshot1_valid ?
                                             tensor_snapshot1_operand_value :
                                             tensor_snapshot0_operand_value;
  assign reverse_snapshot_read_id = reverse_snapshot_pending_select_id;
  assign reverse_snapshot_consume_valid = reverse_snapshot_complete_accept;
  assign reverse_snapshot_consume_id = reverse_snapshot_read_id;
`ifdef EDGE_DEBUG
  assign debug_gpr_read_data = (debug_gpr_read_reg == {REG_INDEX_WIDTH{1'b0}}) ?
                               {VALUE_WIDTH{1'b0}} : gpr[debug_gpr_read_reg];
  assign debug_fpr_read_data = {{(VALUE_WIDTH-32){1'b0}},
                                fpr[debug_fpr_read_reg]};
  assign debug_fpr_busy = fpr_busy_status;
  assign debug_redirect_block = redirect_kill_valid;
  assign debug_retire_alloc_ready = retire_alloc_ready;
  assign debug_producer_queue_ready = producer_queue_issue_ready;
  assign debug_producer_queue_count = producer_queue_count_r;
  assign debug_gpr_issue_ready = gpr_issue_ready;
  assign debug_fpr_issue_ready = fpr_issue_ready;
  assign debug_alu_issue_ready = alu_issue_ready;
  assign debug_lsu_issue_ready = lsu_issue_ready;
  assign debug_sys_issue_ready = sys_issue_ready;
  assign debug_issue_gpr_check_candidate = issue_gpr_check_candidate;
  assign debug_issue_fpr_dst_candidate = issue_fpr_dst_candidate;
  assign debug_is_alu_or_branch = is_alu_gpr_placeholder || is_branch;
  assign debug_is_lsu_op = is_load_placeholder || is_store_placeholder;
  assign debug_is_sys_or_fence = legal_system || legal_fence || legal_custom_control;
`endif

  assign producer_queue_issue_ready =
    (producer_queue_count_r <= (PRODUCER_QUEUE_DEPTH - 5));

  function [PRODUCER_TAG_WIDTH-1:0] make_producer_tag;
    input domain;
    input [REG_INDEX_WIDTH-1:0] reg_id;
    input [SEQ_ID_WIDTH-1:0] seq_id;
    begin
      make_producer_tag = {
        seq_id,
        domain,
        reg_id,
        2'b00
      };
    end
	  endfunction

  wire producer_in0_valid;
  wire producer_in0_domain;
  wire [REG_INDEX_WIDTH-1:0] producer_in0_reg;
  wire producer_in0_bank;
  wire [PRODUCER_TAG_WIDTH-1:0] producer_in0_tag;
  wire [VALUE_WIDTH-1:0] producer_in0_value;
  wire [EPOCH_WIDTH-1:0] producer_in0_epoch;
  wire producer_in1_valid;
  wire producer_in1_domain;
  wire [REG_INDEX_WIDTH-1:0] producer_in1_reg;
  wire producer_in1_bank;
  wire [PRODUCER_TAG_WIDTH-1:0] producer_in1_tag;
  wire [VALUE_WIDTH-1:0] producer_in1_value;
  wire [EPOCH_WIDTH-1:0] producer_in1_epoch;
  wire producer_in2_valid;
  wire producer_in2_domain;
  wire [REG_INDEX_WIDTH-1:0] producer_in2_reg;
  wire producer_in2_bank;
  wire [PRODUCER_TAG_WIDTH-1:0] producer_in2_tag;
  wire [VALUE_WIDTH-1:0] producer_in2_value;
  wire [EPOCH_WIDTH-1:0] producer_in2_epoch;
  wire producer_in3_valid;
  wire producer_in3_domain;
  wire [REG_INDEX_WIDTH-1:0] producer_in3_reg;
  wire producer_in3_bank;
  wire [PRODUCER_TAG_WIDTH-1:0] producer_in3_tag;
  wire [VALUE_WIDTH-1:0] producer_in3_value;
  wire [EPOCH_WIDTH-1:0] producer_in3_epoch;
  wire producer_in4_valid;
  wire producer_in4_domain;
  wire [REG_INDEX_WIDTH-1:0] producer_in4_reg;
  wire producer_in4_bank;
  wire [PRODUCER_TAG_WIDTH-1:0] producer_in4_tag;
  wire [VALUE_WIDTH-1:0] producer_in4_value;
  wire [EPOCH_WIDTH-1:0] producer_in4_epoch;
  wire producer_direct_in0;
  wire producer_direct_in1;
  wire producer_direct_in2;
  wire producer_direct_in3;
  wire producer_direct_in4;

  assign producer_in0_valid = gpr_load_complete_valid;
  assign producer_in0_domain = 1'b0;
  assign producer_in0_reg = gpr_load_complete_reg;
  assign producer_in0_bank = gpr_load_complete_bank;
  assign producer_in0_tag = make_producer_tag(
    1'b0,
    gpr_load_complete_reg,
    gpr_load_complete_seq_id
  );
  assign producer_in0_value = gpr_load_complete_value;
  assign producer_in0_epoch = gpr_load_complete_epoch;

  assign producer_in1_valid = gpr_complete_valid;
  assign producer_in1_domain = 1'b0;
  assign producer_in1_reg = gpr_complete_rd;
  assign producer_in1_bank = gpr_complete_rd_bank;
  assign producer_in1_tag = make_producer_tag(1'b0, gpr_complete_rd, gpr_complete_seq_id);
  assign producer_in1_value = gpr_result;
  assign producer_in1_epoch = gpr_complete_epoch;

  assign producer_in2_valid = fpr_complete_valid;
  assign producer_in2_domain = 1'b1;
  assign producer_in2_reg = fpr_complete_reg;
  assign producer_in2_bank = fpr_complete_bank;
  assign producer_in2_tag = make_producer_tag(
    1'b1,
    fpr_complete_reg,
    fpr_complete_seq_id
  );
  assign producer_in2_value = {{(VALUE_WIDTH-32){1'b0}}, fpr_complete_value};
  assign producer_in2_epoch = fpr_complete_epoch;

  assign producer_in3_valid = alu_m_complete_valid && alu_m_complete_rd_valid;
  assign producer_in3_domain = 1'b0;
  assign producer_in3_reg = alu_m_complete_rd;
  assign producer_in3_bank = alu_m_complete_rd_bank;
  assign producer_in3_tag = make_producer_tag(
    1'b0, alu_m_complete_rd, alu_m_complete_seq_id
  );
  assign producer_in3_value = alu_m_complete_value;
  assign producer_in3_epoch = alu_m_complete_epoch;

  assign producer_in4_valid = alu_fast1_complete_valid &&
                              alu_fast1_complete_rd_valid;
  assign producer_in4_domain = 1'b0;
  assign producer_in4_reg = alu_fast1_complete_rd;
  assign producer_in4_bank = alu_fast1_complete_rd_bank;
  assign producer_in4_tag = make_producer_tag(
    1'b0, alu_fast1_complete_rd, alu_fast1_complete_seq_id
  );
  assign producer_in4_value = alu_fast1_complete_value;
  assign producer_in4_epoch = alu_fast1_complete_epoch;

  assign producer_direct_in0 = (producer_queue_count_r == {PRODUCER_QUEUE_COUNT_WIDTH{1'b0}}) &&
                               producer_in0_valid;
  assign producer_direct_in1 = (producer_queue_count_r == {PRODUCER_QUEUE_COUNT_WIDTH{1'b0}}) &&
                               !producer_in0_valid &&
                               producer_in1_valid;
  assign producer_direct_in2 = (producer_queue_count_r == {PRODUCER_QUEUE_COUNT_WIDTH{1'b0}}) &&
                               !producer_in0_valid &&
                               !producer_in1_valid &&
                               producer_in2_valid;
  assign producer_direct_in3 = (producer_queue_count_r == {PRODUCER_QUEUE_COUNT_WIDTH{1'b0}}) &&
                               !producer_in0_valid && !producer_in1_valid &&
                               !producer_in2_valid && producer_in3_valid;
  assign producer_direct_in4 = (producer_queue_count_r == {PRODUCER_QUEUE_COUNT_WIDTH{1'b0}}) &&
                               !producer_in0_valid && !producer_in1_valid &&
                               !producer_in2_valid && !producer_in3_valid &&
                               producer_in4_valid;

  integer i;
  reg [PRODUCER_QUEUE_INDEX_WIDTH-1:0] producer_tail_next;
  reg [PRODUCER_QUEUE_COUNT_WIDTH-1:0] producer_count_next;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      producer_valid_r <= 1'b0;
      producer_domain_r <= 1'b0;
      producer_reg_r <= {REG_INDEX_WIDTH{1'b0}};
      producer_bank_r <= 1'b0;
	      producer_tag_r <= {PRODUCER_TAG_WIDTH{1'b0}};
	      producer_value_r <= {VALUE_WIDTH{1'b0}};
	      producer_epoch_r <= {EPOCH_WIDTH{1'b0}};
	      producer_queue_head_r <= {PRODUCER_QUEUE_INDEX_WIDTH{1'b0}};
	      producer_queue_tail_r <= {PRODUCER_QUEUE_INDEX_WIDTH{1'b0}};
	      producer_queue_count_r <= {PRODUCER_QUEUE_COUNT_WIDTH{1'b0}};
      cache_op_pending_q <= 1'b0;
      cycle_counter_q <= {VALUE_WIDTH{1'b0}};
      csr_cycle_complete_valid_r <= 1'b0;
      csr_cycle_complete_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      csr_cycle_complete_epoch_r <= {EPOCH_WIDTH{1'b0}};
      csr_cycle_complete_rd_r <= {REG_INDEX_WIDTH{1'b0}};
      csr_cycle_complete_rd_bank_r <= 1'b0;
      csr_cycle_complete_value_r <= {VALUE_WIDTH{1'b0}};
      reverse_snapshot_pending_valid_r <= 2'b00;
      reverse_snapshot_pending_seq_id_r[0] <= {SEQ_ID_WIDTH{1'b0}};
      reverse_snapshot_pending_seq_id_r[1] <= {SEQ_ID_WIDTH{1'b0}};
      reverse_snapshot_pending_epoch_r[0] <= {EPOCH_WIDTH{1'b0}};
      reverse_snapshot_pending_epoch_r[1] <= {EPOCH_WIDTH{1'b0}};
      reverse_snapshot_pending_rd_r[0] <= {REG_INDEX_WIDTH{1'b0}};
      reverse_snapshot_pending_rd_r[1] <= {REG_INDEX_WIDTH{1'b0}};
      reverse_snapshot_pending_rd_bank_r[0] <= 1'b0;
      reverse_snapshot_pending_rd_bank_r[1] <= 1'b0;
      fpu_pending_valid_r <= 1'b0;
      fpu_pending_valid_s0_r <= 1'b0;
      fpu_pending_valid_s1_r <= 1'b0;
      fpu_pending_valid_s2_r <= 1'b0;
      fpu_pending_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      fpu_pending_seq_id_s0_r <= {SEQ_ID_WIDTH{1'b0}};
      fpu_pending_seq_id_s1_r <= {SEQ_ID_WIDTH{1'b0}};
      fpu_pending_seq_id_s2_r <= {SEQ_ID_WIDTH{1'b0}};
      fpu_pending_epoch_r <= {EPOCH_WIDTH{1'b0}};
      fpu_pending_epoch_s0_r <= {EPOCH_WIDTH{1'b0}};
      fpu_pending_epoch_s1_r <= {EPOCH_WIDTH{1'b0}};
      fpu_pending_epoch_s2_r <= {EPOCH_WIDTH{1'b0}};
      fpu_pending_bank_r <= 1'b0;
      fpu_pending_bank_s0_r <= 1'b0;
      fpu_pending_bank_s1_r <= 1'b0;
      fpu_pending_bank_s2_r <= 1'b0;
      fpr_load_bf16_by_seq <= {(1 << SEQ_ID_WIDTH){1'b0}};
	      retire_valid_r <= 1'b0;
      retire_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      retire_epoch_r <= {EPOCH_WIDTH{1'b0}};
      retire_is_pseudo_r <= 1'b0;
      mem_placeholder_valid_r <= 1'b0;
      mem_placeholder_is_store_r <= 1'b0;
      mem_placeholder_size_r <= 2'b00;
      mem_placeholder_addr_r <= {VALUE_WIDTH{1'b0}};
      mem_placeholder_store_data_r <= {VALUE_WIDTH{1'b0}};
      mem_placeholder_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      mem_placeholder_epoch_r <= {EPOCH_WIDTH{1'b0}};
      mem_placeholder_load_signed_r <= 1'b0;
      mem_placeholder1_valid_r <= 1'b0;
      mem_placeholder1_is_store_r <= 1'b0;
      mem_placeholder1_size_r <= 2'b00;
      mem_placeholder1_addr_r <= {VALUE_WIDTH{1'b0}};
      mem_placeholder1_store_data_r <= {VALUE_WIDTH{1'b0}};
      mem_placeholder1_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      mem_placeholder1_epoch_r <= {EPOCH_WIDTH{1'b0}};
      mem_placeholder1_load_signed_r <= 1'b0;
      system_placeholder_valid_r <= 1'b0;
      system_placeholder_funct3_r <= 3'b000;
      system_placeholder_csr_r <= 12'd0;
      system_placeholder_rd_r <= {REG_INDEX_WIDTH{1'b0}};
      system_placeholder_rs1_r <= {REG_INDEX_WIDTH{1'b0}};
      system_placeholder_rs1_value_r <= {VALUE_WIDTH{1'b0}};
      system_placeholder_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      system_placeholder_epoch_r <= {EPOCH_WIDTH{1'b0}};
      fence_placeholder_valid_r <= 1'b0;
      fence_placeholder_i_r <= 1'b0;
      fence_placeholder_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      fence_placeholder_epoch_r <= {EPOCH_WIDTH{1'b0}};
      fatal_report_valid_r <= 1'b0;
      fatal_report_code_r <= 4'd0;
      fatal_report_inst_r <= {VALUE_WIDTH{1'b0}};
      fatal_report_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      fatal_report_epoch_r <= {EPOCH_WIDTH{1'b0}};
      ebreak_report_valid_r <= 1'b0;
      ebreak_report_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      ebreak_report_epoch_r <= {EPOCH_WIDTH{1'b0}};
      ebreak_report_pending_r <= 1'b0;
      ebreak_report_pending_seq_id_r <= {SEQ_ID_WIDTH{1'b0}};
      ebreak_report_pending_epoch_r <= {EPOCH_WIDTH{1'b0}};
	      for (i = 0; i < 32; i = i + 1) begin
	        gpr[i] <= {VALUE_WIDTH{1'b0}};
	        fpr[i] <= 32'b0;
	      end
	      for (i = 0; i < PRODUCER_QUEUE_DEPTH; i = i + 1) begin
	        producer_queue_domain[i] <= 1'b0;
	        producer_queue_reg[i] <= {REG_INDEX_WIDTH{1'b0}};
	        producer_queue_bank[i] <= 1'b0;
	        producer_queue_tag[i] <= {PRODUCER_TAG_WIDTH{1'b0}};
	        producer_queue_value[i] <= {VALUE_WIDTH{1'b0}};
	        producer_queue_epoch[i] <= {EPOCH_WIDTH{1'b0}};
	      end
	    end else begin
      cycle_counter_q <= cycle_counter_q + {{(VALUE_WIDTH-1){1'b0}}, 1'b1};
	      producer_valid_r <= 1'b0;
	      retire_valid_r <= 1'b0;
      if (csr_cycle_complete_valid)
        csr_cycle_complete_valid_r <= 1'b0;
      if (csr_cycle_complete_valid_r &&
          redirect_kills_seq(csr_cycle_complete_seq_id_r,
                             csr_cycle_complete_epoch_r))
        csr_cycle_complete_valid_r <= 1'b0;
	      mem_placeholder_valid_r <= 1'b0;
	      mem_placeholder1_valid_r <= 1'b0;
      system_placeholder_valid_r <= 1'b0;
      fence_placeholder_valid_r <= 1'b0;
	      fatal_report_valid_r <= 1'b0;
      ebreak_report_valid_r <= ebreak_ordered_retire;
      if (ebreak_ordered_retire) begin
        ebreak_report_seq_id_r <= ebreak_report_pending_seq_id_r;
        ebreak_report_epoch_r <= ebreak_report_pending_epoch_r;
        ebreak_report_pending_r <= 1'b0;
      end
      if (ebreak_killed_by_redirect)
        ebreak_report_pending_r <= 1'b0;
	      producer_tail_next = producer_queue_tail_r;
	      producer_count_next = producer_queue_count_r;
      if (cache_op_complete_valid)
        cache_op_pending_q <= 1'b0;
      if (cache_op_valid && cache_op_ready)
        cache_op_pending_q <= 1'b1;

      if (issue_fire && is_fp_load)
        fpr_load_bf16_by_seq[issue_seq_id] <= (funct3 == 3'b101);
      if (lsu_load_complete_valid && lsu_load_complete_domain)
        fpr_load_bf16_by_seq[lsu_load_complete_seq_id] <= 1'b0;

      // Fixed-latency metadata pipelines mirror edge_scalar_alu's registered
      // fast completion path. Redirect only kills younger entries in the old
      // epoch; older in-flight FMAC results still need to release WBT/retire.
      fpu_pending_valid_r <= fpu_pending_valid_s2_r &&
                             !redirect_kills_seq(fpu_pending_seq_id_s2_r,
                                                 fpu_pending_epoch_s2_r);
        fpu_pending_seq_id_r <= fpu_pending_seq_id_s2_r;
        fpu_pending_epoch_r <= fpu_pending_epoch_s2_r;
        fpu_pending_bank_r <= fpu_pending_bank_s2_r;
      fpu_pending_valid_s2_r <= fpu_pending_valid_s1_r &&
                                !redirect_kills_seq(fpu_pending_seq_id_s1_r,
                                                    fpu_pending_epoch_s1_r);
        fpu_pending_seq_id_s2_r <= fpu_pending_seq_id_s1_r;
        fpu_pending_epoch_s2_r <= fpu_pending_epoch_s1_r;
        fpu_pending_bank_s2_r <= fpu_pending_bank_s1_r;
      fpu_pending_valid_s1_r <= fpu_pending_valid_s0_r &&
                                !redirect_kills_seq(fpu_pending_seq_id_s0_r,
                                                    fpu_pending_epoch_s0_r);
        fpu_pending_seq_id_s1_r <= fpu_pending_seq_id_s0_r;
        fpu_pending_epoch_s1_r <= fpu_pending_epoch_s0_r;
        fpu_pending_bank_s1_r <= fpu_pending_bank_s0_r;
      fpu_pending_valid_s0_r <= !redirect_kill_valid &&
                                fpu_issue_valid && fpu_issue_ready;
        if (fpu_issue_valid && fpu_issue_ready) begin
          fpu_pending_seq_id_s0_r <= scalar_def_valid ? scalar_def_seq_id : issue_seq_id;
          fpu_pending_epoch_s0_r <= scalar_def_valid ? scalar_def_epoch : issue_epoch;
          fpu_pending_bank_s0_r <= scalar_def_bank;
        end

      if (csr_cycle_accept) begin
        csr_cycle_complete_valid_r <= 1'b1;
        csr_cycle_complete_seq_id_r <= issue_seq_id;
        csr_cycle_complete_epoch_r <= issue_epoch;
        csr_cycle_complete_rd_r <= rd;
        csr_cycle_complete_rd_bank_r <= scalar_def_bank;
        csr_cycle_complete_value_r <= cycle_counter_q;
      end

      if (reverse_snapshot_complete_accept) begin
        csr_cycle_complete_valid_r <= 1'b1;
        csr_cycle_complete_seq_id_r <=
          reverse_snapshot_pending_seq_id_r[reverse_snapshot_pending_select_id];
        csr_cycle_complete_epoch_r <=
          reverse_snapshot_pending_epoch_r[reverse_snapshot_pending_select_id];
        csr_cycle_complete_rd_r <=
          reverse_snapshot_pending_rd_r[reverse_snapshot_pending_select_id];
        csr_cycle_complete_rd_bank_r <=
          reverse_snapshot_pending_rd_bank_r[reverse_snapshot_pending_select_id];
        csr_cycle_complete_value_r <= reverse_snapshot_read_value;
        reverse_snapshot_pending_valid_r[reverse_snapshot_pending_select_id] <= 1'b0;
      end

      if (redirect_kill_valid) begin
        if (reverse_snapshot_pending_valid_r[0] &&
            (reverse_snapshot_pending_epoch_r[0] == redirect_kill_epoch) &&
            redirect_kills_seq(reverse_snapshot_pending_seq_id_r[0],
                               reverse_snapshot_pending_epoch_r[0]))
          reverse_snapshot_pending_valid_r[0] <= 1'b0;
        if (reverse_snapshot_pending_valid_r[1] &&
            (reverse_snapshot_pending_epoch_r[1] == redirect_kill_epoch) &&
            redirect_kills_seq(reverse_snapshot_pending_seq_id_r[1],
                               reverse_snapshot_pending_epoch_r[1]))
          reverse_snapshot_pending_valid_r[1] <= 1'b0;
      end

      if (reverse_snapshot_issue_accept) begin
        reverse_snapshot_pending_valid_r[
          issue1_is_accel_getcsr_pseudo ? issue1_inst[25] : issue_inst[25]
        ] <= 1'b1;
        reverse_snapshot_pending_seq_id_r[
          issue1_is_accel_getcsr_pseudo ? issue1_inst[25] : issue_inst[25]
        ] <= issue1_is_accel_getcsr_pseudo ? issue1_seq_id : issue_seq_id;
        reverse_snapshot_pending_epoch_r[
          issue1_is_accel_getcsr_pseudo ? issue1_inst[25] : issue_inst[25]
        ] <= issue1_is_accel_getcsr_pseudo ? issue1_epoch : issue_epoch;
        reverse_snapshot_pending_rd_r[
          issue1_is_accel_getcsr_pseudo ? issue1_inst[25] : issue_inst[25]
        ] <= issue1_is_accel_getcsr_pseudo ? rd1 : rd;
        reverse_snapshot_pending_rd_bank_r[
          issue1_is_accel_getcsr_pseudo ? issue1_inst[25] : issue_inst[25]
        ] <= issue1_is_accel_getcsr_pseudo ? scalar1_def_bank : scalar_def_bank;
      end

      if (issue_fire && is_ebreak) begin
        ebreak_report_pending_r <= 1'b1;
        ebreak_report_pending_seq_id_r <= issue_seq_id;
        ebreak_report_pending_epoch_r <= issue_epoch;
      end

      if (lsu_load_complete_valid && lsu_load_complete_error) begin
        fatal_report_valid_r <= 1'b1;
        fatal_report_code_r <= 4'd4;
        fatal_report_inst_r <= {VALUE_WIDTH{1'b0}};
        fatal_report_seq_id_r <= lsu_load_complete_seq_id;
        fatal_report_epoch_r <= lsu_load_complete_epoch;
`ifdef IVERILOG_SIM
        $display(
          "EDGE_SCALAR_PIPE_FATAL_LOAD_RESPONSE code=%0d seq=%0d epoch=%0d",
          4'd4,
          lsu_load_complete_seq_id,
          lsu_load_complete_epoch
        );
        $fatal(1);
`endif
      end else if (issue_fire && is_fatal_report_placeholder && !is_ebreak) begin
          fatal_report_valid_r <= 1'b1;
          fatal_report_code_r <= 4'd2;
          fatal_report_inst_r <= {{(VALUE_WIDTH-32){1'b0}}, issue_inst};
          fatal_report_seq_id_r <= issue_seq_id;
          fatal_report_epoch_r <= issue_epoch;
`ifdef IVERILOG_SIM
        $display(
          "EDGE_SCALAR_PIPE_FATAL_UNREACHABLE code=%0d seq=%0d epoch=%0d pc=0x%0h inst=0x%08h",
          4'd2,
          issue_seq_id,
          issue_epoch,
          issue_pc,
          issue_inst
        );
`ifndef EDGE_SCALAR_PIPE_EBREAK_REPORT_ONLY
        $fatal(1);
`else
        $fatal(1);
`endif
`endif
	      end else if (lsu_misaligned_valid) begin
        fatal_report_valid_r <= 1'b1;
        fatal_report_code_r <= 4'd3;
        fatal_report_inst_r <= {{(VALUE_WIDTH-32){1'b0}},
                                lsu_misaligned_lane1 ? issue1_inst : issue_inst};
        fatal_report_seq_id_r <= lsu_misaligned_seq_id;
        fatal_report_epoch_r <= lsu_misaligned_epoch;
`ifdef IVERILOG_SIM
        $display(
          "EDGE_SCALAR_PIPE_FATAL_MISALIGNED code=%0d seq=%0d epoch=%0d lane1=%0b store=%0b size=%0d addr=0x%0h inst=0x%08h",
          4'd3,
          lsu_misaligned_seq_id,
          lsu_misaligned_epoch,
          lsu_misaligned_lane1,
          lsu_misaligned_is_store,
          lsu_misaligned_size,
          lsu_misaligned_addr,
          lsu_misaligned_lane1 ? issue1_inst : issue_inst
        );
        $fatal(1);
`endif
	      end else begin
	        if (producer_queue_count_r != {PRODUCER_QUEUE_COUNT_WIDTH{1'b0}}) begin
	          producer_valid_r <= 1'b1;
	          producer_domain_r <= producer_queue_domain[producer_queue_head_r];
	          producer_reg_r <= producer_queue_reg[producer_queue_head_r];
	          producer_bank_r <= producer_queue_bank[producer_queue_head_r];
	          producer_tag_r <= producer_queue_tag[producer_queue_head_r];
	          producer_value_r <= producer_queue_value[producer_queue_head_r];
	          producer_epoch_r <= producer_queue_epoch[producer_queue_head_r];
	          producer_queue_head_r <= producer_queue_head_r +
	                                   {{(PRODUCER_QUEUE_INDEX_WIDTH-1){1'b0}}, 1'b1};
	          producer_count_next = producer_count_next -
	                                {{(PRODUCER_QUEUE_COUNT_WIDTH-1){1'b0}}, 1'b1};
	        end else if (producer_direct_in0) begin
	          producer_valid_r <= 1'b1;
	          producer_domain_r <= producer_in0_domain;
	          producer_reg_r <= producer_in0_reg;
	          producer_bank_r <= producer_in0_bank;
	          producer_tag_r <= producer_in0_tag;
	          producer_value_r <= producer_in0_value;
	          producer_epoch_r <= producer_in0_epoch;
	        end else if (producer_direct_in1) begin
	          producer_valid_r <= 1'b1;
	          producer_domain_r <= producer_in1_domain;
	          producer_reg_r <= producer_in1_reg;
	          producer_bank_r <= producer_in1_bank;
	          producer_tag_r <= producer_in1_tag;
	          producer_value_r <= producer_in1_value;
	          producer_epoch_r <= producer_in1_epoch;
	        end else if (producer_direct_in2) begin
	          producer_valid_r <= 1'b1;
	          producer_domain_r <= producer_in2_domain;
	          producer_reg_r <= producer_in2_reg;
	          producer_bank_r <= producer_in2_bank;
	          producer_tag_r <= producer_in2_tag;
	          producer_value_r <= producer_in2_value;
	          producer_epoch_r <= producer_in2_epoch;
	        end else if (producer_direct_in3) begin
	          producer_valid_r <= 1'b1;
	          producer_domain_r <= producer_in3_domain;
	          producer_reg_r <= producer_in3_reg;
	          producer_bank_r <= producer_in3_bank;
	          producer_tag_r <= producer_in3_tag;
	          producer_value_r <= producer_in3_value;
	          producer_epoch_r <= producer_in3_epoch;
	        end else if (producer_direct_in4) begin
	          producer_valid_r <= 1'b1;
	          producer_domain_r <= producer_in4_domain;
	          producer_reg_r <= producer_in4_reg;
	          producer_bank_r <= producer_in4_bank;
	          producer_tag_r <= producer_in4_tag;
	          producer_value_r <= producer_in4_value;
	          producer_epoch_r <= producer_in4_epoch;
	        end

	        if (producer_in0_valid && !producer_direct_in0) begin
	          if (producer_count_next >= PRODUCER_QUEUE_DEPTH) begin
	`ifdef IVERILOG_SIM
	            $fatal(1, "edge_scalar_pipe producer queue overflow");
	`endif
	          end else begin
	            producer_queue_domain[producer_tail_next] <= producer_in0_domain;
	            producer_queue_reg[producer_tail_next] <= producer_in0_reg;
	            producer_queue_bank[producer_tail_next] <= producer_in0_bank;
	            producer_queue_tag[producer_tail_next] <= producer_in0_tag;
	            producer_queue_value[producer_tail_next] <= producer_in0_value;
	            producer_queue_epoch[producer_tail_next] <= producer_in0_epoch;
	            producer_tail_next = producer_tail_next +
	                                 {{(PRODUCER_QUEUE_INDEX_WIDTH-1){1'b0}}, 1'b1};
	            producer_count_next = producer_count_next +
	                                  {{(PRODUCER_QUEUE_COUNT_WIDTH-1){1'b0}}, 1'b1};
	          end
	        end
	        if (producer_in1_valid && !producer_direct_in1) begin
	          if (producer_count_next >= PRODUCER_QUEUE_DEPTH) begin
	`ifdef IVERILOG_SIM
	            $fatal(1, "edge_scalar_pipe producer queue overflow");
	`endif
	          end else begin
	            producer_queue_domain[producer_tail_next] <= producer_in1_domain;
	            producer_queue_reg[producer_tail_next] <= producer_in1_reg;
	            producer_queue_bank[producer_tail_next] <= producer_in1_bank;
	            producer_queue_tag[producer_tail_next] <= producer_in1_tag;
	            producer_queue_value[producer_tail_next] <= producer_in1_value;
	            producer_queue_epoch[producer_tail_next] <= producer_in1_epoch;
	            producer_tail_next = producer_tail_next +
	                                 {{(PRODUCER_QUEUE_INDEX_WIDTH-1){1'b0}}, 1'b1};
	            producer_count_next = producer_count_next +
	                                  {{(PRODUCER_QUEUE_COUNT_WIDTH-1){1'b0}}, 1'b1};
	          end
	        end
	        if (producer_in2_valid && !producer_direct_in2) begin
	          if (producer_count_next >= PRODUCER_QUEUE_DEPTH) begin
	`ifdef IVERILOG_SIM
	            $fatal(1, "edge_scalar_pipe producer queue overflow");
	`endif
	          end else begin
	            producer_queue_domain[producer_tail_next] <= producer_in2_domain;
	            producer_queue_reg[producer_tail_next] <= producer_in2_reg;
	            producer_queue_bank[producer_tail_next] <= producer_in2_bank;
	            producer_queue_tag[producer_tail_next] <= producer_in2_tag;
	            producer_queue_value[producer_tail_next] <= producer_in2_value;
	            producer_queue_epoch[producer_tail_next] <= producer_in2_epoch;
	            producer_tail_next = producer_tail_next +
	                                 {{(PRODUCER_QUEUE_INDEX_WIDTH-1){1'b0}}, 1'b1};
	            producer_count_next = producer_count_next +
	                                  {{(PRODUCER_QUEUE_COUNT_WIDTH-1){1'b0}}, 1'b1};
	          end
	        end
	        if (producer_in3_valid && !producer_direct_in3) begin
	          if (producer_count_next >= PRODUCER_QUEUE_DEPTH) begin
	`ifdef IVERILOG_SIM
	            $fatal(1, "edge_scalar_pipe producer queue overflow");
	`endif
	          end else begin
	            producer_queue_domain[producer_tail_next] <= producer_in3_domain;
	            producer_queue_reg[producer_tail_next] <= producer_in3_reg;
	            producer_queue_bank[producer_tail_next] <= producer_in3_bank;
	            producer_queue_tag[producer_tail_next] <= producer_in3_tag;
	            producer_queue_value[producer_tail_next] <= producer_in3_value;
	            producer_queue_epoch[producer_tail_next] <= producer_in3_epoch;
	            producer_tail_next = producer_tail_next +
	                                 {{(PRODUCER_QUEUE_INDEX_WIDTH-1){1'b0}}, 1'b1};
	            producer_count_next = producer_count_next +
	                                  {{(PRODUCER_QUEUE_COUNT_WIDTH-1){1'b0}}, 1'b1};
	          end
	        end
	        if (producer_in4_valid && !producer_direct_in4) begin
	          if (producer_count_next >= PRODUCER_QUEUE_DEPTH) begin
`ifdef IVERILOG_SIM
	            $fatal(1, "edge_scalar_pipe producer queue overflow");
`endif
	          end else begin
	            producer_queue_domain[producer_tail_next] <= producer_in4_domain;
	            producer_queue_reg[producer_tail_next] <= producer_in4_reg;
	            producer_queue_bank[producer_tail_next] <= producer_in4_bank;
	            producer_queue_tag[producer_tail_next] <= producer_in4_tag;
	            producer_queue_value[producer_tail_next] <= producer_in4_value;
	            producer_queue_epoch[producer_tail_next] <= producer_in4_epoch;
	            producer_tail_next = producer_tail_next +
	                                 {{(PRODUCER_QUEUE_INDEX_WIDTH-1){1'b0}}, 1'b1};
	            producer_count_next = producer_count_next +
	                                  {{(PRODUCER_QUEUE_COUNT_WIDTH-1){1'b0}}, 1'b1};
	          end
	        end
	        producer_queue_tail_r <= producer_tail_next;
	        producer_queue_count_r <= producer_count_next;

        if (gpr_load_complete_valid &&
            (gpr_load_complete_reg != {REG_INDEX_WIDTH{1'b0}})) begin
          gpr[gpr_load_complete_reg] <= gpr_load_complete_value;
        end
	        if (gpr_complete_valid && (gpr_complete_rd != {REG_INDEX_WIDTH{1'b0}})) begin
	          gpr[gpr_complete_rd] <= gpr_result;
	        end
        if (alu_fast1_complete_valid && alu_fast1_complete_rd_valid &&
            (alu_fast1_complete_rd != {REG_INDEX_WIDTH{1'b0}})) begin
          gpr[alu_fast1_complete_rd] <= alu_fast1_complete_value;
        end
        if (alu_m_complete_valid && alu_m_complete_rd_valid &&
            (alu_m_complete_rd != {REG_INDEX_WIDTH{1'b0}})) begin
          gpr[alu_m_complete_rd] <= alu_m_complete_value;
        end
        if (fpr_complete_valid) begin
          fpr[fpr_complete_reg] <= fpr_complete_value;
        end

	        if (early_gpr_load_retire_valid) begin
	          retire_valid_r <= 1'b1;
	          retire_seq_id_r <= lsu_load_accept_seq_id;
	          retire_epoch_r <= lsu_load_accept_epoch;
	          retire_is_pseudo_r <= 1'b0;
	        end else if (gpr_load_complete_valid &&
	                     (!ENABLE_EARLY_LOAD_RETIRE ||
	                      gpr_placeholder_complete_valid)) begin
	          retire_valid_r <= 1'b1;
	          retire_seq_id_r <= gpr_load_complete_seq_id;
	          retire_epoch_r <= gpr_load_complete_epoch;
	          retire_is_pseudo_r <= 1'b0;
	        end else if (gpr_complete_valid || alu_complete_nowb_valid ||
                       alu_m_complete_valid) begin
	          retire_valid_r <= 1'b1;
	          retire_seq_id_r <= alu_m_complete_valid ? alu_m_complete_seq_id :
                                   (gpr_complete_valid ? gpr_complete_seq_id :
                                                         alu_fast_complete_seq_id);
	          retire_epoch_r <= alu_m_complete_valid ? alu_m_complete_epoch :
                                  (gpr_complete_valid ? gpr_complete_epoch :
                                                        alu_fast_complete_epoch);
	          retire_is_pseudo_r <= 1'b0;
        end else if (fpr_complete_valid) begin
	          retire_valid_r <= 1'b1;
	          retire_seq_id_r <= fpr_complete_seq_id;
          retire_epoch_r <= fpr_complete_epoch;
          retire_is_pseudo_r <= 1'b0;
        end else if (cache_op_complete_valid) begin
          retire_valid_r <= 1'b1;
          retire_seq_id_r <= cache_op_complete_seq_id;
          retire_epoch_r <= cache_op_complete_epoch;
          retire_is_pseudo_r <= 1'b0;
        end else if (retire_complete_nowb_valid) begin
          retire_valid_r <= 1'b1;
          retire_seq_id_r <= issue_seq_id;
          retire_epoch_r <= issue_epoch;
          retire_is_pseudo_r <= issue_is_pseudo;
        end
      end

      if (lsu_complete_valid) begin
        mem_placeholder_valid_r <= 1'b1;
        mem_placeholder_is_store_r <= lsu_complete_is_store;
        mem_placeholder_size_r <= lsu_complete_size;
        mem_placeholder_load_signed_r <= lsu_complete_load_signed;
        mem_placeholder_addr_r <= lsu_complete_addr;
        mem_placeholder_store_data_r <= lsu_complete_store_data;
        mem_placeholder_seq_id_r <= lsu_complete_seq_id;
        mem_placeholder_epoch_r <= lsu_complete_epoch;
      end

      if (lsu_complete1_valid) begin
        mem_placeholder1_valid_r <= 1'b1;
        mem_placeholder1_is_store_r <= lsu_complete1_is_store;
        mem_placeholder1_size_r <= lsu_complete1_size;
        mem_placeholder1_load_signed_r <= lsu_complete1_load_signed;
        mem_placeholder1_addr_r <= lsu_complete1_addr;
        mem_placeholder1_store_data_r <= lsu_complete1_store_data;
        mem_placeholder1_seq_id_r <= lsu_complete1_seq_id;
        mem_placeholder1_epoch_r <= lsu_complete1_epoch;
      end

      if (sys_complete_valid && sys_system_placeholder_valid) begin
        system_placeholder_valid_r <= 1'b1;
        system_placeholder_funct3_r <= sys_system_placeholder_funct3;
        system_placeholder_csr_r <= sys_system_placeholder_csr;
        system_placeholder_rd_r <= sys_system_placeholder_rd;
        system_placeholder_rs1_r <= sys_system_placeholder_rs1;
        system_placeholder_rs1_value_r <= rs1_value;
        system_placeholder_seq_id_r <= sys_complete_seq_id;
        system_placeholder_epoch_r <= sys_complete_epoch;
      end

      if (sys_complete_valid && sys_fence_placeholder_valid) begin
        fence_placeholder_valid_r <= 1'b1;
        fence_placeholder_i_r <= sys_fence_placeholder_i;
        fence_placeholder_seq_id_r <= sys_complete_seq_id;
        fence_placeholder_epoch_r <= sys_complete_epoch;
      end
    end
  end

  wire unused_issue_len = issue_len;

endmodule
