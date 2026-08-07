// First-slice Edge predecoder with small scalar capture bookkeeping.
module edge_predecoder #(
  parameter PC_WIDTH           = 40,
  parameter SEQ_ID_WIDTH       = 8,
  parameter EPOCH_WIDTH        = 4,
  parameter CAPTURE_SLOTS      = 8,
  parameter CAPTURE_ID_WIDTH   = 3,
  parameter REG_INDEX_WIDTH    = 5,
  parameter PRODUCER_TAG_WIDTH = 16,
  parameter REF_COUNT_WIDTH    = 4,
  parameter EDGE64_LENGTH_MARKER = 7'b0111111
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,

  input  wire                         scalar_def_valid,
  input  wire                         scalar_def_domain,
  input  wire [REG_INDEX_WIDTH-1:0]   scalar_def_dst_reg,
  input  wire [SEQ_ID_WIDTH-1:0]      scalar_def_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       scalar_def_epoch,

  input  wire                         decoded_valid,
  output wire                         decoded_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      decoded_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       decoded_epoch,
  input  wire                         decoded_is_tensor,
  input  wire [2:0]                   decoded_capture_count,
  input  wire                         decoded_src0_domain,
  input  wire [REG_INDEX_WIDTH-1:0]   decoded_src0_reg,
  input  wire                         decoded_src0_is_n_capture,

  input  wire                         raw_valid,
  output wire                         raw_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      raw_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       raw_epoch,
  input  wire [63:0]                  raw_inst64,
  input  wire                         raw_is_64b,

  input  wire                         window_valid,
  output wire                         window_ready,
  input  wire [63:0]                  window_bits,
  input  wire [7:0]                   window_bytes_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      window_lane0_seq_id,
  input  wire [SEQ_ID_WIDTH-1:0]      window_lane1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       window_epoch,

  input  wire                         token0_valid,
  output wire                         token_ready,
  output wire [1:0]                   token_consume_count,
  input  wire [1:0]                   token0_kind,
  input  wire [3:0]                   token0_len_bytes,
  input  wire [PC_WIDTH-1:0]          token0_pc,
  input  wire [31:0]                  token0_inst32,
  input  wire [63:0]                  token0_inst64,
  input  wire [SEQ_ID_WIDTH-1:0]      token0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       token0_epoch,
  input  wire                         token1_valid,
  input  wire [1:0]                   token1_kind,
  input  wire [3:0]                   token1_len_bytes,
  input  wire [PC_WIDTH-1:0]          token1_pc,
  input  wire [31:0]                  token1_inst32,
  input  wire [63:0]                  token1_inst64,
  input  wire [SEQ_ID_WIDTH-1:0]      token1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       token1_epoch,

  output wire                         window_scalar_valid,
  input  wire                         window_scalar_ready,
  output wire [PC_WIDTH-1:0]          window_scalar_pc,
  output wire [31:0]                  window_scalar_inst,
  output wire [SEQ_ID_WIDTH-1:0]      window_scalar_seq_id,
  output wire [EPOCH_WIDTH-1:0]       window_scalar_epoch,
  output wire                         window_scalar_is_pseudo,
  output wire [2:0]                   window_scalar_pseudo_kind,
  output wire                         window_scalar_def_valid,
  output wire                         window_scalar_def_domain,
  output wire [REG_INDEX_WIDTH-1:0]   window_scalar_def_dst_reg,
  output wire                         window_scalar_def_bank,
  output wire                         window_scalar1_valid,
  input  wire                         window_scalar1_ready,
  output wire [PC_WIDTH-1:0]          window_scalar1_pc,
  output wire [31:0]                  window_scalar1_inst,
  output wire [SEQ_ID_WIDTH-1:0]      window_scalar1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       window_scalar1_epoch,
  output wire                         window_scalar1_is_pseudo,
  output wire [2:0]                   window_scalar1_pseudo_kind,
  output wire                         window_scalar1_def_valid,
  output wire [REG_INDEX_WIDTH-1:0]   window_scalar1_def_dst_reg,
  output wire                         window_scalar1_def_bank,

  input  wire                         consumer_release_valid,
  input  wire                         consumer_release_domain,
  input  wire [CAPTURE_ID_WIDTH-1:0]  consumer_release_capture_id,
  input  wire                         consumer_release_capture_bank,

  input  wire                         redirect_flush_valid,
  input  wire [EPOCH_WIDTH-1:0]       redirect_new_epoch,

  output wire                         loop_predict_valid,
  output wire [PC_WIDTH-1:0]          loop_predict_target,
  output wire [PC_WIDTH-1:0]          loop_predict_fallthrough,
  output wire [SEQ_ID_WIDTH-1:0]      loop_predict_seq_id,
  output wire [EPOCH_WIDTH-1:0]       loop_predict_epoch,

  output wire                         command_valid,
  output wire                         command_is_tensor,
  output wire [SEQ_ID_WIDTH-1:0]      command_seq_id,
  output wire [EPOCH_WIDTH-1:0]       command_epoch,
  output wire [2:0]                   command_capture_count,
  output wire [CAPTURE_ID_WIDTH-1:0]  command_capture_id0,
  output wire                         command_capture_bank0,
  output wire                         command_n_capture_valid,
  output wire [CAPTURE_ID_WIDTH-1:0]  command_n_capture_id,
  output wire                         command_n_capture_bank,
  output wire [PRODUCER_TAG_WIDTH-1:0] command_producer_tag0,

  input  wire                         accel_command_ready,
  input  wire                         reverse_snapshot_alloc_ready,
  input  wire                         reverse_snapshot_alloc_id,
  output wire                         reverse_snapshot_alloc_valid,
  output wire [SEQ_ID_WIDTH-1:0]      reverse_snapshot_alloc_seq_id,
  output wire [EPOCH_WIDTH-1:0]       reverse_snapshot_alloc_epoch,
  output wire                         accel_command_valid,
  output wire                         accel_command_is_tensor,
  output wire [63:0]                  accel_command_inst64,
  output wire [SEQ_ID_WIDTH-1:0]      accel_command_seq_id,
  output wire [EPOCH_WIDTH-1:0]       accel_command_epoch,
  output wire [2:0]                   accel_command_capture_count,
  output wire                         accel_command_n_capture_valid,
  output wire [CAPTURE_ID_WIDTH-1:0]  accel_command_n_capture_id,
  output wire                         accel_command_n_capture_bank,
  output wire [PRODUCER_TAG_WIDTH-1:0] accel_command_n_producer_tag,
  output wire [REG_INDEX_WIDTH-1:0]   accel_command_n_src_gpr,
  output wire                         accel_command_base_capture_valid,
  output wire [CAPTURE_ID_WIDTH-1:0]  accel_command_base_capture_id,
  output wire                         accel_command_base_capture_bank,
  output wire [PRODUCER_TAG_WIDTH-1:0] accel_command_base_producer_tag,
  output wire [REG_INDEX_WIDTH-1:0]   accel_command_base_src_gpr,
  output wire                         accel_decode_is_accel,
  output wire                         accel_decode_needs_base_gpr,

  output wire [CAPTURE_SLOTS-1:0]     debug_slot_owned,
  output wire [2*CAPTURE_SLOTS-1:0]   debug_bank_owned_flat,
  output wire [2*CAPTURE_SLOTS*REF_COUNT_WIDTH-1:0] debug_bank_ref_count_flat,
  output wire [CAPTURE_SLOTS*REF_COUNT_WIDTH-1:0] debug_slot_ref_count_flat,
  output wire [63:0]                  debug_mapping_valid
);

  localparam [1:0] VEC_STATE_IDLE = 2'd0;
  localparam [1:0] VEC_STATE_N    = 2'd1;
  localparam [1:0] VEC_STATE_BASE = 2'd2;
  localparam [1:0] VEC_STATE_EMIT = 2'd3;
  localparam [6:0] OPCODE_LOAD    = 7'b0000011;
  localparam [6:0] OPCODE_STORE   = 7'b0100011;
  localparam [6:0] OPCODE_LUI     = 7'b0110111;
  localparam [6:0] OPCODE_AUIPC   = 7'b0010111;
  localparam [6:0] OPCODE_JAL     = 7'b1101111;
  localparam [6:0] OPCODE_JALR    = 7'b1100111;
  localparam [6:0] OPCODE_BRANCH  = 7'b1100011;
  localparam [6:0] OPCODE_OP_IMM  = 7'b0010011;
  localparam [6:0] OPCODE_OP      = 7'b0110011;
  localparam [6:0] OPCODE_OP_IMM32 = 7'b0011011;
  localparam [6:0] OPCODE_OP32    = 7'b0111011;
  localparam [6:0] OPCODE_SYSTEM  = 7'b1110011;
  localparam [6:0] DMA_START      = 7'h01;
  localparam [6:0] DMA_SYNC       = 7'h02;
  localparam [6:0] DMA_SETN       = 7'h03;
  localparam [6:0] DMA_SETX       = 7'h04;
  localparam [6:0] DMA_SETY       = 7'h05;
  localparam [6:0] DMA_SETSRC     = 7'h06;
  localparam [6:0] DMA_SETTAR     = 7'h07;
  localparam [6:0] DMA_SETENTRY   = 7'h08;
  localparam [6:0] TENSOR_WLD     = 7'h11;
  localparam [6:0] TENSOR_SETCSR  = 7'h10;
  localparam [6:0] TENSOR_SETIN   = 7'h12;
  localparam [6:0] TENSOR_SETOUT  = 7'h13;
  localparam [6:0] TENSOR_SETPSUM = 7'h14;
  localparam [6:0] TENSOR_SETN    = 7'h17;
  localparam [6:0] TENSOR_SYNC    = 7'h16;
  localparam [6:0] TENSOR_WLD_T   = 7'h18;
  localparam [6:0] TENSOR_SLD_STREAM = 7'h1a;
  localparam [6:0] TENSOR_SLD     = 7'h1d;
  localparam [6:0] ACTU_SETCSR    = 7'h20;
  localparam [6:0] ACTU_SETIN     = 7'h21;
  localparam [6:0] ACTU_SETOUT    = 7'h22;
  localparam [6:0] ACTU_SETN      = 7'h23;
  localparam [6:0] ACTU_SETSCALAR = 7'h24;
  localparam [6:0] ACTU_SYNC      = 7'h26;
  localparam [6:0] CMPU_SETCSR    = 7'h27;
  localparam [6:0] CMPU_SETLHS    = 7'h28;
  localparam [6:0] CMPU_SETRHS    = 7'h29;
  localparam [6:0] CMPU_SETMASK   = 7'h2a;
  localparam [6:0] CMPU_SETOUT    = 7'h2b;
  localparam [6:0] CMPU_SETN      = 7'h2c;
  localparam [6:0] CMPU_SYNC      = 7'h2e;
  localparam [6:0] ACCEL_GETCSR   = 7'h2f;
  localparam [1:0] TOKEN_KIND_SCALAR = 2'd0;
  localparam [1:0] TOKEN_KIND_VECTOR = 2'd1;
  localparam [1:0] TOKEN_KIND_TENSOR = 2'd2;
  localparam [2:0] SCALAR_CLASS_OTHER = 3'd0;
  localparam [2:0] SCALAR_CLASS_LOAD  = 3'd1;
  localparam [2:0] SCALAR_CLASS_STORE = 3'd2;
  localparam [2:0] SCALAR_CLASS_ALU   = 3'd3;
  localparam [2:0] SCALAR_CLASS_M     = 3'd4;
`ifdef EDGE_DISABLE_SCALAR_M_FAST_PAIR
  localparam SCALAR_M_FAST_PAIR_ENABLE = 1'b0;
`else
  localparam SCALAR_M_FAST_PAIR_ENABLE = 1'b1;
`endif
  localparam [2:0] PSEUDO_TENSOR_JOIN = 3'd1;
  localparam [2:0] PSEUDO_TENSOR_GPR_HOLDER = 3'd2;
  localparam [2:0] PSEUDO_ACCEL_GETCSR = 3'd3;

  reg [PRODUCER_TAG_WIDTH-1:0] current_producer_tag [0:63];
  reg [63:0] mapping_valid;
  reg [CAPTURE_ID_WIDTH-1:0] mapping_capture_id [0:63];
  reg [PRODUCER_TAG_WIDTH-1:0] mapping_producer_tag [0:63];
  reg capture_owned [0:CAPTURE_SLOTS-1];
  reg [REF_COUNT_WIDTH-1:0] capture_ref_count [0:CAPTURE_SLOTS-1];
  reg [1:0] vec_state;
  reg [63:0] vec_inst64_q;
  reg vec_is_tensor_q;
  reg [SEQ_ID_WIDTH-1:0] vec_seq_id_q;
  reg [EPOCH_WIDTH-1:0] vec_epoch_q;
  reg vec_needs_base_q;
  reg [CAPTURE_ID_WIDTH-1:0] vec_n_capture_id_q;
  reg vec_n_capture_bank_q;
  reg [CAPTURE_ID_WIDTH-1:0] vec_base_capture_id_q;
  reg vec_base_capture_bank_q;
  reg [PRODUCER_TAG_WIDTH-1:0] vec_n_producer_tag_q;
  reg [PRODUCER_TAG_WIDTH-1:0] vec_base_producer_tag_q;
  reg scalar_hold_valid_q;
  reg [PC_WIDTH-1:0] scalar_hold_pc_q;
  reg [31:0] scalar_hold_inst_q;
  reg [SEQ_ID_WIDTH-1:0] scalar_hold_seq_id_q;
  reg [EPOCH_WIDTH-1:0] scalar_hold_epoch_q;
  wire vec_busy;

  function [CAPTURE_ID_WIDTH:0] first_free_capture;
    input [CAPTURE_SLOTS-1:0] owned;
    integer fi;
    begin
      first_free_capture = {1'b0, {CAPTURE_ID_WIDTH{1'b0}}};
      for (fi = 0; fi < CAPTURE_SLOTS; fi = fi + 1) begin
        if (!owned[fi] && !first_free_capture[CAPTURE_ID_WIDTH]) begin
          first_free_capture = {1'b1, fi[CAPTURE_ID_WIDTH-1:0]};
        end
      end
    end
  endfunction

  function [PRODUCER_TAG_WIDTH-1:0] make_producer_tag;
    input scalar_domain;
    input [REG_INDEX_WIDTH-1:0] scalar_reg;
    input [SEQ_ID_WIDTH-1:0] scalar_seq;
    begin
      make_producer_tag = {
        scalar_seq,
        scalar_domain,
        scalar_reg,
        2'b00
      };
    end
  endfunction

  function [31:0] make_tensor_snapshot_pseudo_inst;
    input [31:0] inst;
    input [2:0] source_mask;
    input [2:0] snapshot_target;
    begin
      make_tensor_snapshot_pseudo_inst = inst;
      make_tensor_snapshot_pseudo_inst[14:12] = source_mask;
      make_tensor_snapshot_pseudo_inst[31:25] = {4'd0, snapshot_target};
    end
  endfunction

  function [63:0] set_reverse_snapshot_id;
    input [63:0] inst;
    input snapshot_id;
    begin
      set_reverse_snapshot_id = inst;
      set_reverse_snapshot_id[52] = snapshot_id;
    end
  endfunction

  function rv64i_writes_gpr;
    input [31:0] inst;
    reg [6:0] opcode;
    begin
      opcode = inst[6:0];
      case (opcode)
        OPCODE_LUI,
        OPCODE_AUIPC,
        OPCODE_JAL,
        OPCODE_JALR,
        OPCODE_LOAD,
        OPCODE_OP_IMM,
        OPCODE_OP,
        OPCODE_OP_IMM32,
        OPCODE_OP32: rv64i_writes_gpr = (inst[11:7] != 5'd0);
        OPCODE_SYSTEM: rv64i_writes_gpr = (inst[14:12] != 3'b000) &&
                                          (inst[11:7] != 5'd0);
        default: rv64i_writes_gpr = 1'b0;
      endcase
    end
  endfunction

  function [PC_WIDTH-1:0] branch_target;
    input [PC_WIDTH-1:0] pc;
    input [31:0] inst;
    reg [12:0] imm13;
    reg signed [PC_WIDTH-1:0] signed_imm;
    begin
      imm13 = {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
      signed_imm = {{(PC_WIDTH-13){imm13[12]}}, imm13};
      branch_target = pc + signed_imm;
    end
  endfunction

  function [PC_WIDTH-1:0] jal_target;
    input [PC_WIDTH-1:0] pc;
    input [31:0] inst;
    reg [20:0] imm21;
    reg signed [PC_WIDTH-1:0] signed_imm;
    begin
      imm21 = {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
      signed_imm = {{(PC_WIDTH-21){imm21[20]}}, imm21};
      jal_target = pc + signed_imm;
    end
  endfunction

  function [2:0] scalar_class;
    input [31:0] inst;
    begin
      case (inst[6:0])
        OPCODE_LOAD: scalar_class = SCALAR_CLASS_LOAD;
        OPCODE_STORE: scalar_class = SCALAR_CLASS_STORE;
        OPCODE_LUI,
        OPCODE_AUIPC,
        OPCODE_OP_IMM,
        OPCODE_OP_IMM32: scalar_class = SCALAR_CLASS_ALU;
        OPCODE_OP,
        OPCODE_OP32: scalar_class = (inst[31:25] == 7'b0000001) ?
                                    SCALAR_CLASS_M : SCALAR_CLASS_ALU;
        default: scalar_class = SCALAR_CLASS_OTHER;
      endcase
    end
  endfunction

  wire [CAPTURE_SLOTS-1:0] capture_owned_bits;
  genvar capture_owned_gi;
  generate
    for (capture_owned_gi = 0; capture_owned_gi < CAPTURE_SLOTS; capture_owned_gi = capture_owned_gi + 1) begin : gen_capture_owned_bits
      assign capture_owned_bits[capture_owned_gi] = capture_owned[capture_owned_gi];
    end
  endgenerate

  wire [CAPTURE_ID_WIDTH:0] free_capture;
  wire free_capture_found;
  wire [CAPTURE_ID_WIDTH-1:0] free_capture_id;
  assign free_capture = first_free_capture(capture_owned_bits);
  assign free_capture_found = free_capture[CAPTURE_ID_WIDTH];
  assign free_capture_id = free_capture[CAPTURE_ID_WIDTH-1:0];

  wire [5:0] src0_key;
  assign src0_key = {decoded_src0_domain, decoded_src0_reg};

  wire src0_has_mapping;
  wire [CAPTURE_ID_WIDTH-1:0] src0_selected_capture_id;
  assign src0_has_mapping = mapping_valid[src0_key] &&
                            (mapping_producer_tag[src0_key] == current_producer_tag[src0_key]);
  assign src0_selected_capture_id = src0_has_mapping ? mapping_capture_id[src0_key] :
                                                       free_capture_id;

  wire raw_low_is_vector;
  wire raw_vector_valid;
  wire [6:0] raw_vector_scalar_opcode;
  wire raw_vector_needs_base;
  assign raw_low_is_vector = raw_is_64b &&
                             (raw_inst64[6:0] == EDGE64_LENGTH_MARKER) &&
                             !raw_inst64[39];
  assign raw_vector_valid = raw_valid && raw_low_is_vector;
  assign raw_vector_scalar_opcode = raw_inst64[38:32];
  assign raw_vector_needs_base = (raw_vector_scalar_opcode == OPCODE_LOAD) ||
                                 (raw_vector_scalar_opcode == OPCODE_STORE);

  wire token0_is_scalar;
  wire token0_is_vector;
  wire token0_is_tensor;
  wire token0_is_64b;
  wire token1_is_scalar;
  wire token1_is_vector;
  wire token1_is_tensor;
  wire token1_is_64b;
  assign token0_is_scalar = token0_valid && (token0_kind == TOKEN_KIND_SCALAR);
  assign token0_is_vector = token0_valid && (token0_kind == TOKEN_KIND_VECTOR);
  assign token0_is_tensor = token0_valid && (token0_kind == TOKEN_KIND_TENSOR);
  assign token0_is_64b = token0_valid && (token0_len_bytes == 4'd8);
  assign token1_is_scalar = token1_valid && (token1_kind == TOKEN_KIND_SCALAR);
  assign token1_is_vector = token1_valid && (token1_kind == TOKEN_KIND_VECTOR);
  assign token1_is_tensor = token1_valid && (token1_kind == TOKEN_KIND_TENSOR);
  assign token1_is_64b = token1_valid && (token1_len_bytes == 4'd8);

  wire token_path_valid;
  wire token_pair_scalar_scalar;
  wire token0_scalar_token1_accel;
  wire token0_accel_token1_scalar;
  wire token_scalar_only_path;
  wire token_direct_path_valid;
  wire token_stream_supported;
  assign token_path_valid = token0_valid && !window_valid;
  assign token_pair_scalar_scalar = token0_is_scalar && token1_is_scalar;
  assign token0_scalar_token1_accel =
    token0_is_scalar && token1_valid && (token1_is_vector || token1_is_tensor);
  assign token0_accel_token1_scalar =
    (token0_is_vector || token0_is_tensor) && token1_is_scalar;
  assign token_scalar_only_path = token_path_valid && token0_is_scalar &&
                                  (!token1_valid || token1_is_scalar ||
                                   token0_scalar_token1_accel);
  assign token_direct_path_valid = token_path_valid && !token_scalar_only_path;
  wire token_pack_packet_valid;
  wire [1:0] token_pack_slot_valid;
  wire [31:0] token_pack_slot0_inst32;
  wire [31:0] token_pack_slot1_inst32;
  wire [PC_WIDTH-1:0] token_pack_slot0_pc;
  wire [PC_WIDTH-1:0] token_pack_slot1_pc;
  wire [SEQ_ID_WIDTH-1:0] token_pack_slot0_seq_id;
  wire [SEQ_ID_WIDTH-1:0] token_pack_slot1_seq_id;
  wire token_pack_scalar0_valid;
  wire [31:0] token_pack_scalar0_inst32;
  wire [PC_WIDTH-1:0] token_pack_scalar0_pc;
  wire [SEQ_ID_WIDTH-1:0] token_pack_scalar0_seq_id;
  wire [EPOCH_WIDTH-1:0] token_pack_scalar0_epoch;
  wire token_pack_accel0_valid;
  wire token_pack_accel0_is_tensor;
  wire [63:0] token_pack_accel0_inst64;
  wire [PC_WIDTH-1:0] token_pack_accel0_pc;
  wire [SEQ_ID_WIDTH-1:0] token_pack_accel0_seq_id;
  wire [EPOCH_WIDTH-1:0] token_pack_accel0_epoch;
  wire [1:0] token_direct_consume_count;

  assign token_pack_packet_valid = token_direct_path_valid;
  assign token_pack_slot0_inst32 = token0_inst32;
  assign token_pack_slot0_pc = token0_pc;
  assign token_pack_slot0_seq_id = token0_seq_id;
  assign token_pack_slot1_inst32 = token0_is_64b ? token0_inst64[63:32] :
                                   token1_inst32;
  assign token_pack_slot1_pc = token0_is_64b ?
                               (token0_pc + {{(PC_WIDTH-3){1'b0}}, 3'd4}) :
                               token1_pc;
  assign token_pack_slot1_seq_id = token0_is_64b ? token0_seq_id :
                                                    token1_seq_id;
  assign token_pack_slot_valid[0] = token0_valid;
  assign token_pack_slot_valid[1] = token0_is_64b || token1_valid;

  edge_predecode_token_packer #(
    .PC_WIDTH(PC_WIDTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .EDGE64_LENGTH_MARKER(EDGE64_LENGTH_MARKER)
  ) token_path_packer (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .flush_valid(redirect_flush_valid),
    .packet_valid(token_pack_packet_valid),
    .packet_ready(),
    .packet_slot_valid(token_pack_slot_valid),
    .packet_slot0_inst32(token_pack_slot0_inst32),
    .packet_slot1_inst32(token_pack_slot1_inst32),
    .packet_slot0_pc(token_pack_slot0_pc),
    .packet_slot1_pc(token_pack_slot1_pc),
    .packet_slot0_seq_id(token_pack_slot0_seq_id),
    .packet_slot1_seq_id(token_pack_slot1_seq_id),
    .packet_epoch(token0_epoch),
    .scalar_ready(1'b1),
    .accel_ready(1'b1),
    .scalar0_valid(token_pack_scalar0_valid),
    .scalar0_inst32(token_pack_scalar0_inst32),
    .scalar0_pc(token_pack_scalar0_pc),
    .scalar0_seq_id(token_pack_scalar0_seq_id),
    .scalar0_epoch(token_pack_scalar0_epoch),
    .scalar1_valid(),
    .scalar1_inst32(),
    .scalar1_pc(),
    .scalar1_seq_id(),
    .scalar1_epoch(),
    .accel0_valid(token_pack_accel0_valid),
    .accel0_is_tensor(token_pack_accel0_is_tensor),
    .accel0_inst64(token_pack_accel0_inst64),
    .accel0_pc(token_pack_accel0_pc),
    .accel0_seq_id(token_pack_accel0_seq_id),
    .accel0_epoch(token_pack_accel0_epoch),
    .debug_pending64_valid(),
    .debug_pending64_low32(),
    .debug_pending64_pc(),
    .debug_pending64_seq_id(),
    .debug_pending64_epoch(),
    .debug_pending64_is_tensor()
  );

  assign token_stream_supported = token_direct_path_valid &&
                                  token_pack_accel0_valid;
  // A 64-bit issue window can dispatch only the accelerator at token0.
  // Keep token1, whether scalar or accelerator, at the tokenizer head for
  // next-cycle refill instead of consuming a shape the packer did not emit.
  assign token_direct_consume_count = 2'd1;

  wire scalar_iw_enqueue0_valid;
  wire scalar_iw_enqueue1_valid;
  wire scalar_iw_enqueue0_from_token1;
  wire scalar_iw_buffer_token1;
  wire scalar_iw_enqueue_pair;
  wire scalar_iw_enqueue_ready;
  wire scalar_iw_head0_valid;
  wire [1:0] scalar_iw_head0_kind;
  wire [2:0] scalar_iw_head0_class;
  wire [PC_WIDTH-1:0] scalar_iw_head0_pc;
  wire [63:0] scalar_iw_head0_inst;
  wire [SEQ_ID_WIDTH-1:0] scalar_iw_head0_seq_id;
  wire [EPOCH_WIDTH-1:0] scalar_iw_head0_epoch;
  wire scalar_iw_head1_valid;
  wire [1:0] scalar_iw_head1_kind;
  wire [2:0] scalar_iw_head1_class;
  wire [PC_WIDTH-1:0] scalar_iw_head1_pc;
  wire [63:0] scalar_iw_head1_inst;
  wire [SEQ_ID_WIDTH-1:0] scalar_iw_head1_seq_id;
  wire [EPOCH_WIDTH-1:0] scalar_iw_head1_epoch;
  wire [1:0] scalar_iw_pop_count;
  wire [3:0] scalar_iw_debug_count;
  wire scalar_iw_empty;
  wire scalar_token_base_ready;
  wire scalar_token_fire;
  wire scalar_token_bypass0_fire;
  wire scalar_token_bypass1_fire;
  wire scalar_iw_head0_fire;
  wire scalar_iw_head1_fire;
  wire scalar_iw_pair_ready;
  wire scalar_iw_m_fast_pair;
  wire scalar_token_m_fast_pair;
  wire scalar_token_pairable;

  assign scalar_iw_empty = !scalar_iw_head0_valid;
  assign scalar_token_base_ready = token_scalar_only_path && !vec_busy &&
                                   !decoded_valid && !raw_valid &&
                                   !scalar_hold_valid_q;
  assign scalar_token_bypass0_fire = scalar_token_fire && scalar_iw_empty &&
                                     window_scalar_ready;
  assign scalar_token_bypass1_fire = scalar_token_bypass0_fire &&
                                     scalar_token_pairable && window_scalar1_ready;
  assign scalar_iw_buffer_token1 =
    scalar_token_base_ready && scalar_iw_empty && window_scalar_ready &&
    token1_is_scalar &&
    !(scalar_token_pairable && window_scalar1_ready) &&
    (scalar_iw_debug_count <= 4'd4);
  assign scalar_iw_enqueue_pair =
    scalar_token_base_ready && scalar_iw_head0_valid && token1_is_scalar &&
    (scalar_iw_debug_count <= 4'd4);
  assign scalar_iw_enqueue0_from_token1 = scalar_iw_buffer_token1;
  assign scalar_iw_enqueue0_valid =
    scalar_token_base_ready &&
    ((token0_valid && (scalar_iw_head0_valid || !window_scalar_ready)) ||
     scalar_iw_enqueue0_from_token1);
  assign scalar_iw_enqueue1_valid = scalar_iw_enqueue_pair;
  assign scalar_iw_m_fast_pair = SCALAR_M_FAST_PAIR_ENABLE &&
    (((scalar_iw_head0_class == SCALAR_CLASS_M) &&
      (scalar_iw_head1_class == SCALAR_CLASS_ALU)) ||
     ((scalar_iw_head0_class == SCALAR_CLASS_ALU) &&
      (scalar_iw_head1_class == SCALAR_CLASS_M)));
  assign scalar_token_m_fast_pair = SCALAR_M_FAST_PAIR_ENABLE &&
    (((scalar_class(token0_inst32) == SCALAR_CLASS_M) &&
      (scalar_class(token1_inst32) == SCALAR_CLASS_ALU)) ||
     ((scalar_class(token0_inst32) == SCALAR_CLASS_ALU) &&
      (scalar_class(token1_inst32) == SCALAR_CLASS_M)));
  assign scalar_token_pairable = token1_is_scalar &&
    ((((scalar_class(token0_inst32) == SCALAR_CLASS_LOAD) &&
       (scalar_class(token1_inst32) == SCALAR_CLASS_LOAD)) ||
      ((scalar_class(token0_inst32) == SCALAR_CLASS_STORE) &&
       (scalar_class(token1_inst32) == SCALAR_CLASS_STORE)) ||
      ((scalar_class(token0_inst32) == SCALAR_CLASS_ALU) &&
       (scalar_class(token1_inst32) == SCALAR_CLASS_ALU)) ||
      ((scalar_class(token0_inst32) == SCALAR_CLASS_ALU) &&
       ((scalar_class(token1_inst32) == SCALAR_CLASS_LOAD) ||
        (scalar_class(token1_inst32) == SCALAR_CLASS_STORE))) ||
      (((scalar_class(token0_inst32) == SCALAR_CLASS_LOAD) ||
        (scalar_class(token0_inst32) == SCALAR_CLASS_STORE)) &&
       (scalar_class(token1_inst32) == SCALAR_CLASS_ALU)) ||
      scalar_token_m_fast_pair));
  assign scalar_iw_pair_ready = scalar_iw_head0_valid && scalar_iw_head1_valid &&
                                (((scalar_iw_head0_class == SCALAR_CLASS_LOAD) &&
                                  (scalar_iw_head1_class == SCALAR_CLASS_LOAD)) ||
                                 ((scalar_iw_head0_class == SCALAR_CLASS_STORE) &&
                                  (scalar_iw_head1_class == SCALAR_CLASS_STORE)) ||
                                 ((scalar_iw_head0_class == SCALAR_CLASS_ALU) &&
                                  (scalar_iw_head1_class == SCALAR_CLASS_ALU)) ||
                                 ((scalar_iw_head0_class == SCALAR_CLASS_ALU) &&
                                  ((scalar_iw_head1_class == SCALAR_CLASS_LOAD) ||
                                   (scalar_iw_head1_class == SCALAR_CLASS_STORE))) ||
                                 (((scalar_iw_head0_class == SCALAR_CLASS_LOAD) ||
                                   (scalar_iw_head0_class == SCALAR_CLASS_STORE)) &&
                                  (scalar_iw_head1_class == SCALAR_CLASS_ALU)) ||
                                 scalar_iw_m_fast_pair);
  assign scalar_iw_head0_fire = scalar_iw_head0_valid && window_scalar_ready;
  assign scalar_iw_head1_fire = scalar_iw_head0_fire && scalar_iw_pair_ready &&
                                window_scalar1_ready;
  assign scalar_iw_pop_count = scalar_iw_head1_fire ? 2'd2 :
                               (scalar_iw_head0_fire ? 2'd1 : 2'd0);
  assign scalar_token_fire = scalar_token_base_ready && scalar_iw_enqueue_ready;

  edge_predecode_issue_window #(
    .DEPTH(8),
    .PTR_WIDTH(3),
    .COUNT_WIDTH(4),
    .PC_WIDTH(PC_WIDTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .INST_WIDTH(64),
    .KIND_WIDTH(2),
    .CLASS_WIDTH(3)
  ) scalar_issue_window (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .flush_valid(redirect_flush_valid),
    .enqueue0_valid(scalar_iw_enqueue0_valid),
    .enqueue0_kind(TOKEN_KIND_SCALAR),
    .enqueue0_class(scalar_iw_enqueue0_from_token1 ? scalar_class(token1_inst32) :
                                                     scalar_class(token0_inst32)),
    .enqueue0_pc(scalar_iw_enqueue0_from_token1 ? token1_pc : token0_pc),
    .enqueue0_inst(scalar_iw_enqueue0_from_token1 ? {32'd0, token1_inst32} :
                                                    {32'd0, token0_inst32}),
    .enqueue0_seq_id(scalar_iw_enqueue0_from_token1 ? token1_seq_id : token0_seq_id),
    .enqueue0_epoch(scalar_iw_enqueue0_from_token1 ? token1_epoch : token0_epoch),
    .enqueue1_valid(scalar_iw_enqueue1_valid),
    .enqueue1_kind(TOKEN_KIND_SCALAR),
    .enqueue1_class(scalar_class(token1_inst32)),
    .enqueue1_pc(token1_pc),
    .enqueue1_inst({32'd0, token1_inst32}),
    .enqueue1_seq_id(token1_seq_id),
    .enqueue1_epoch(token1_epoch),
    .enqueue2_valid(1'b0),
    .enqueue2_kind(TOKEN_KIND_SCALAR),
    .enqueue2_class(SCALAR_CLASS_OTHER),
    .enqueue2_pc({PC_WIDTH{1'b0}}),
    .enqueue2_inst(64'd0),
    .enqueue2_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .enqueue2_epoch({EPOCH_WIDTH{1'b0}}),
    .enqueue3_valid(1'b0),
    .enqueue3_kind(TOKEN_KIND_SCALAR),
    .enqueue3_class(SCALAR_CLASS_OTHER),
    .enqueue3_pc({PC_WIDTH{1'b0}}),
    .enqueue3_inst(64'd0),
    .enqueue3_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .enqueue3_epoch({EPOCH_WIDTH{1'b0}}),
    .enqueue_ready(scalar_iw_enqueue_ready),
    .pop_count(scalar_iw_pop_count),
    .head0_valid(scalar_iw_head0_valid),
    .head0_kind(scalar_iw_head0_kind),
    .head0_class(scalar_iw_head0_class),
    .head0_pc(scalar_iw_head0_pc),
    .head0_inst(scalar_iw_head0_inst),
    .head0_seq_id(scalar_iw_head0_seq_id),
    .head0_epoch(scalar_iw_head0_epoch),
    .head1_valid(scalar_iw_head1_valid),
    .head1_kind(scalar_iw_head1_kind),
    .head1_class(scalar_iw_head1_class),
    .head1_pc(scalar_iw_head1_pc),
    .head1_inst(scalar_iw_head1_inst),
    .head1_seq_id(scalar_iw_head1_seq_id),
    .head1_epoch(scalar_iw_head1_epoch),
    .debug_count(scalar_iw_debug_count)
  );

  wire [31:0] window_lane0;
  wire [31:0] window_lane1;
  wire [SEQ_ID_WIDTH-1:0] frontend_lane0_seq_id;
  wire [SEQ_ID_WIDTH-1:0] frontend_lane1_seq_id;
  wire [PC_WIDTH-1:0] frontend_lane0_pc;
  wire [PC_WIDTH-1:0] frontend_lane1_pc;
  wire [EPOCH_WIDTH-1:0] frontend_epoch;
  assign window_lane0 = window_valid ? window_bits[31:0] : token0_inst32;
  assign window_lane1 = window_valid ? window_bits[63:32] :
                        (token0_is_64b ? token0_inst64[63:32] : token1_inst32);
  assign frontend_lane0_seq_id = window_valid ? window_lane0_seq_id : token0_seq_id;
  assign frontend_lane1_seq_id = window_valid ? window_lane1_seq_id :
                                 (token0_is_64b ? token0_seq_id : token1_seq_id);
  assign frontend_lane0_pc = window_valid ? {PC_WIDTH{1'b0}} : token0_pc;
  assign frontend_lane1_pc = window_valid ? {PC_WIDTH{1'b0}} :
                             (token0_is_64b ? (token0_pc + {{(PC_WIDTH-3){1'b0}}, 3'd4}) :
                                              token1_pc);
  assign frontend_epoch = window_valid ? window_epoch : token0_epoch;

  wire window_lane0_full;
  wire window_lane1_full;
  assign window_lane0_full = window_valid ? (&window_bytes_valid[3:0]) : token0_valid;
  assign window_lane1_full = window_valid ? (&window_bytes_valid[7:4]) :
                             (token0_is_64b ? token0_valid : token1_valid);

  wire window_lane0_is_vector;
  assign window_lane0_is_vector = window_lane0_full && window_lane1_full &&
                                  (window_lane0[6:0] == EDGE64_LENGTH_MARKER) &&
                                  !window_lane1[7];

  wire window_pattern_64;
  wire window_pattern_32_32;
  wire window_pattern_32_only;
  assign window_pattern_64 = window_lane0_is_vector;
  assign window_pattern_32_32 = !window_lane0_is_vector && window_lane0_full &&
                                window_lane1_full;
  assign window_pattern_32_only = !window_lane0_is_vector && window_lane0_full &&
                                  !window_lane1_full;

  wire window_has_vector;
  wire window_has_scalar;
  wire [31:0] window_selected_scalar_inst;
  wire [PC_WIDTH-1:0] window_selected_scalar_pc;
  wire [63:0] window_selected_vector_inst64;
  wire [SEQ_ID_WIDTH-1:0] window_selected_scalar_seq_id;
  wire [SEQ_ID_WIDTH-1:0] window_selected_vector_seq_id;
  wire window_scalar_before_vector;
  assign window_has_vector = window_valid ?
                             window_pattern_64 :
                             (token_direct_path_valid && token_pack_accel0_valid);
  assign window_has_scalar = window_valid ?
                             (window_pattern_32_32 || window_pattern_32_only) :
                             (token_direct_path_valid && token_pack_scalar0_valid &&
                              !token0_accel_token1_scalar);
  assign window_selected_scalar_inst = window_valid ?
                                       window_lane0 :
                                       token_pack_scalar0_inst32;
  assign window_selected_scalar_pc = window_valid ?
                                     frontend_lane0_pc :
                                     token_pack_scalar0_pc;
  assign window_selected_vector_inst64 = window_valid ?
                                         {window_lane1, window_lane0} :
                                         token_pack_accel0_inst64;
  assign window_selected_scalar_seq_id = window_valid ?
                                         frontend_lane0_seq_id :
                                         token_pack_scalar0_seq_id;
  assign window_selected_vector_seq_id = window_valid ?
                                         frontend_lane0_seq_id :
                                         token_pack_accel0_seq_id;
  assign window_scalar_before_vector = window_valid ? 1'b0 :
                                       (token_direct_path_valid &&
                                        token_pack_scalar0_valid &&
                                        token_pack_accel0_valid &&
                                        (token_pack_scalar0_seq_id <
                                         token_pack_accel0_seq_id));

  wire window_scalar_writes_gpr;
  wire window_scalar_frontend_writes_gpr;
  wire window_scalar_is_branch;
  wire window_scalar_is_jal;
  wire [PC_WIDTH-1:0] window_scalar_branch_target;
  wire [PC_WIDTH-1:0] window_scalar_jal_target;
  wire [PC_WIDTH-1:0] window_scalar_predict_target;
  wire [PC_WIDTH-1:0] window_scalar_fallthrough;
  wire window_scalar_predict_taken;
  wire [REG_INDEX_WIDTH-1:0] window_scalar_rd;
  wire [5:0] window_scalar_key;
  wire [PRODUCER_TAG_WIDTH-1:0] window_scalar_producer_tag;
  assign window_scalar_writes_gpr = window_has_scalar &&
                                    rv64i_writes_gpr(window_selected_scalar_inst);
  assign window_scalar_is_branch = window_has_scalar &&
                                   (window_selected_scalar_inst[6:0] == OPCODE_BRANCH);
  assign window_scalar_is_jal = window_has_scalar &&
                                (window_selected_scalar_inst[6:0] == OPCODE_JAL);
  assign window_scalar_branch_target = branch_target(
    window_selected_scalar_pc,
    window_selected_scalar_inst
  );
  assign window_scalar_jal_target = jal_target(
    window_selected_scalar_pc,
    window_selected_scalar_inst
  );
  assign window_scalar_predict_target = window_scalar_is_jal ? window_scalar_jal_target :
                                                               window_scalar_branch_target;
  assign window_scalar_fallthrough =
    window_selected_scalar_pc + {{(PC_WIDTH-3){1'b0}}, 3'd4};
  assign window_scalar_predict_taken =
    window_scalar_is_jal ||
    (window_scalar_is_branch &&
     (window_scalar_branch_target < window_selected_scalar_pc));
  assign window_scalar_rd = window_tensor_pseudo_lane0 ?
                            window_selected_vector_inst64[11:7] :
                            window_selected_scalar_inst[11:7];
  assign window_scalar_key = {1'b0, window_scalar_rd};
  assign window_scalar_producer_tag = make_producer_tag(
    1'b0,
    window_scalar_rd,
    window_tensor_pseudo_lane0 ? window_selected_vector_seq_id :
                                 window_selected_scalar_seq_id
  );

  wire window_selected_vector_is_tensor;
  wire [REG_INDEX_WIDTH-1:0] window_vector_n_src_gpr;
  wire [REG_INDEX_WIDTH-1:0] window_tensor_src_gpr;
  wire [REG_INDEX_WIDTH-1:0] window_accel_capture_src_gpr;
  wire [REG_INDEX_WIDTH-1:0] window_vector_base_src_gpr;
  wire [6:0] window_vector_scalar_opcode;
  wire window_accel_is_dma_start;
  wire window_accel_is_getcsr;
  wire window_tensor_sync_join;
  wire window_tensor_gpr_holder_only;
  wire window_tensor_pseudo_lane0;
  wire window_tensor_pseudo_lane1;
  wire [2:0] window_tensor_pseudo_kind;
  wire [2:0] window_tensor_snapshot_source_mask;
  wire window_tensor_needs_capture;
  wire window_vector_needs_base;
  wire window_accel_needs_capture;
  wire [5:0] window_vector_n_key;
  wire [5:0] window_vector_base_key;
  wire window_vector_n_uses_same_prior_scalar;
  wire window_vector_base_uses_same_prior_scalar;
  wire window_vector_uses_same_prior_scalar;
  wire window_vector_base_has_mapping;
  wire window_accel_uses_capture;
  wire [2:0] window_accel_capture_count;
  wire [CAPTURE_ID_WIDTH-1:0] window_base_selected_capture_id;
  assign window_selected_vector_is_tensor = window_valid ?
                                            (window_selected_vector_inst64[39]) :
                                            token_pack_accel0_is_tensor;
  assign window_vector_n_src_gpr = window_selected_vector_inst64[47:43];
  assign window_tensor_src_gpr = window_accel_is_dma_start ?
                                 window_selected_vector_inst64[11:7] :
                                 window_selected_vector_inst64[19:15];
  assign window_vector_scalar_opcode = window_selected_vector_inst64[38:32];
  assign window_accel_is_dma_start = window_selected_vector_is_tensor &&
                                     (window_vector_scalar_opcode == DMA_START);
  assign window_accel_is_getcsr = window_selected_vector_is_tensor &&
                                  (window_vector_scalar_opcode == ACCEL_GETCSR);
  assign window_tensor_sync_join = window_has_vector &&
                                   window_selected_vector_is_tensor &&
                                   ((window_vector_scalar_opcode == TENSOR_SYNC) ||
                                    (window_vector_scalar_opcode == DMA_SYNC) ||
                                    (window_vector_scalar_opcode == ACTU_SYNC) ||
                                    (window_vector_scalar_opcode == CMPU_SYNC));
  assign window_tensor_needs_capture =
    (window_vector_scalar_opcode == TENSOR_WLD) ||
    (window_vector_scalar_opcode == TENSOR_WLD_T) ||
    (window_vector_scalar_opcode == TENSOR_SLD_STREAM) ||
    (window_vector_scalar_opcode == TENSOR_SLD) ||
    (window_vector_scalar_opcode == TENSOR_SETIN) ||
    (window_vector_scalar_opcode == TENSOR_SETOUT) ||
    (window_vector_scalar_opcode == TENSOR_SETPSUM) ||
    (window_vector_scalar_opcode == ACTU_SETIN) ||
    (window_vector_scalar_opcode == ACTU_SETOUT) ||
    (window_vector_scalar_opcode == ACTU_SETSCALAR) ||
    (window_vector_scalar_opcode == CMPU_SETLHS) ||
    (window_vector_scalar_opcode == CMPU_SETRHS) ||
    (window_vector_scalar_opcode == CMPU_SETMASK) ||
    (window_vector_scalar_opcode == CMPU_SETOUT) ||
    (window_vector_scalar_opcode == CMPU_SETN) ||
    (window_vector_scalar_opcode == TENSOR_SETN) ||
    (window_vector_scalar_opcode == ACTU_SETN) ||
    (window_vector_scalar_opcode == DMA_SETN) ||
    (window_vector_scalar_opcode == DMA_SETENTRY) ||
    (window_vector_scalar_opcode == DMA_SETX) ||
    (window_vector_scalar_opcode == DMA_SETY) ||
    (window_vector_scalar_opcode == DMA_SETSRC) ||
    (window_vector_scalar_opcode == DMA_SETTAR) ||
    window_accel_is_dma_start;
  assign window_tensor_gpr_holder_only =
    window_has_vector &&
    window_selected_vector_is_tensor &&
    window_tensor_needs_capture &&
    !window_tensor_sync_join;
  assign window_tensor_pseudo_kind = window_accel_is_getcsr ?
                                     PSEUDO_ACCEL_GETCSR :
                                     (window_tensor_sync_join ?
                                      PSEUDO_TENSOR_JOIN :
                                      PSEUDO_TENSOR_GPR_HOLDER);
  assign window_tensor_pseudo_lane0 =
    (window_tensor_sync_join || window_tensor_gpr_holder_only ||
     window_accel_is_getcsr) && !window_has_scalar;
  assign window_tensor_pseudo_lane1 =
    (window_tensor_sync_join || window_tensor_gpr_holder_only ||
     window_accel_is_getcsr) && window_has_scalar;
  assign window_scalar_frontend_writes_gpr = window_scalar_writes_gpr ||
    (window_tensor_pseudo_lane0 && window_accel_is_getcsr &&
     (window_selected_vector_inst64[11:7] != {REG_INDEX_WIDTH{1'b0}}));
  assign window_tensor_snapshot_source_mask =
    (window_tensor_sync_join || window_accel_is_getcsr) ? 3'b000 :
    (window_accel_is_dma_start ? 3'b100 :
    (((window_vector_scalar_opcode == TENSOR_SETCSR) ||
      (window_vector_scalar_opcode == ACTU_SETCSR) ||
      (window_vector_scalar_opcode == CMPU_SETCSR)) ? 3'b000 :
     3'b001));
  assign window_accel_capture_src_gpr = window_selected_vector_is_tensor ?
                                        window_tensor_src_gpr :
                                        window_vector_n_src_gpr;
  assign window_vector_base_src_gpr = window_selected_vector_inst64[19:15];
  assign window_vector_needs_base = !window_selected_vector_is_tensor &&
                                    ((window_vector_scalar_opcode == OPCODE_LOAD) ||
                                     (window_vector_scalar_opcode == OPCODE_STORE));
  assign window_accel_needs_capture = !window_selected_vector_is_tensor ||
                                      window_tensor_needs_capture;
  assign window_accel_uses_capture =
    !window_selected_vector_is_tensor && window_accel_needs_capture;
  assign window_accel_capture_count = window_accel_needs_capture ? 3'd1 : 3'd0;
  assign window_vector_n_key = {1'b0, window_accel_capture_src_gpr};
  assign window_vector_base_key = {1'b0, window_vector_base_src_gpr};
  assign window_vector_n_uses_same_prior_scalar =
    window_has_vector && window_scalar_before_vector && window_scalar_writes_gpr &&
    (window_scalar_rd == window_accel_capture_src_gpr);
  assign window_vector_base_uses_same_prior_scalar =
    window_has_vector && window_vector_needs_base && window_scalar_before_vector &&
    window_scalar_writes_gpr && (window_scalar_rd == window_vector_base_src_gpr);
  assign window_vector_uses_same_prior_scalar =
    window_vector_n_uses_same_prior_scalar || window_vector_base_uses_same_prior_scalar;

  wire window_n_has_mapping;
  wire window_n_new_capture_found;
  wire [CAPTURE_ID_WIDTH-1:0] window_n_selected_capture_id;
  wire [PRODUCER_TAG_WIDTH-1:0] window_n_selected_producer_tag;
  assign window_n_has_mapping = !window_vector_n_uses_same_prior_scalar &&
                                mapping_valid[window_vector_n_key] &&
                                (mapping_producer_tag[window_vector_n_key] ==
                                 current_producer_tag[window_vector_n_key]);
  assign window_n_new_capture_found = free_capture_found;
  assign window_n_selected_capture_id = window_n_has_mapping ? mapping_capture_id[window_vector_n_key] :
                                      free_capture_id;
  assign window_n_selected_producer_tag = window_vector_n_uses_same_prior_scalar ?
                                          window_scalar_producer_tag :
                                          current_producer_tag[window_vector_n_key];
  assign window_vector_base_has_mapping = !window_vector_base_uses_same_prior_scalar &&
                                          mapping_valid[window_vector_base_key] &&
                                          (mapping_producer_tag[window_vector_base_key] ==
                                           current_producer_tag[window_vector_base_key]);
  assign window_base_selected_capture_id =
    window_vector_base_has_mapping ? mapping_capture_id[window_vector_base_key] :
                                     free_capture_id;

  wire window_capture_ready;
  wire window_reverse_snapshot_ready;
  assign window_capture_ready = !window_has_vector ||
                                !window_accel_needs_capture ||
                                !window_accel_uses_capture ||
                                window_vector_uses_same_prior_scalar ||
                                window_n_has_mapping ||
                                window_n_new_capture_found;
  assign window_reverse_snapshot_ready = !window_has_vector ||
                                         !window_accel_is_getcsr ||
                                         reverse_snapshot_alloc_ready;

  wire window_supported;
  wire frontend_present;
  wire frontend_supported;
  wire frontend_control_ready;
  assign frontend_present = window_valid || token_direct_path_valid;
  assign window_supported = window_pattern_64 || window_pattern_32_32 ||
                            window_pattern_32_only;
  assign frontend_supported = window_supported &&
                              (!token_direct_path_valid || token_stream_supported);

  wire window_fire;
  wire token_fire;
  wire frontend_fire;
  wire frontend_ready;
  wire frontend_scalar_ready;
  assign frontend_scalar_ready =
    (!(window_has_scalar || window_tensor_pseudo_lane0) || window_scalar_ready) &&
    (!(window_tensor_pseudo_lane1 || (window_valid && window_pattern_32_32)) ||
     window_scalar1_ready);
  // Keep the scalar valid side of a bundled tensor command independent of
  // that scalar lane's ready.  In particular, GPR-holder pseudos feed a
  // scalar ready path that may itself depend on valid; gating their valid
  // with frontend_fire creates a valid/ready combinational loop.
  assign frontend_control_ready =
    !redirect_flush_valid && !scalar_hold_valid_q && !scalar_iw_head0_valid &&
    !vec_busy && !decoded_valid && !raw_valid &&
    frontend_supported && window_capture_ready &&
    window_reverse_snapshot_ready &&
    (!window_has_vector ||
     window_vector_uses_same_prior_scalar ||
     window_vector_needs_base ||
     accel_command_ready);
  assign frontend_ready = frontend_control_ready && frontend_scalar_ready;
  assign window_ready = window_valid && !token_path_valid && frontend_ready;
  assign window_fire = window_valid && window_ready;
  assign token_consume_count =
    token_scalar_only_path ? (scalar_token_bypass1_fire ? 2'd2 :
                              (scalar_iw_enqueue_pair && scalar_token_fire ? 2'd2 :
                              (scalar_iw_buffer_token1 && scalar_token_fire ? 2'd2 :
                               (scalar_token_fire ? 2'd1 : 2'd0)))) :
    ((token_direct_path_valid && !window_valid && frontend_ready) ?
     token_direct_consume_count : 2'd0);
  assign token_ready = token_consume_count != 2'd0;
  assign token_fire = token_direct_path_valid && token_ready;
  assign frontend_fire = window_fire || token_fire;

  wire hold_scalar_writes_gpr;
  wire hold_scalar_is_branch;
  wire hold_scalar_is_jal;
  wire [PC_WIDTH-1:0] hold_scalar_branch_target;
  wire [PC_WIDTH-1:0] hold_scalar_jal_target;
  wire [PC_WIDTH-1:0] hold_scalar_predict_target;
  wire [PC_WIDTH-1:0] hold_scalar_fallthrough;
  wire hold_scalar_predict_taken;
  wire hold_scalar_fire;
  wire scalar_iw_head0_is_branch;
  wire scalar_iw_head0_is_jal;
  wire [PC_WIDTH-1:0] scalar_iw_head0_branch_target;
  wire [PC_WIDTH-1:0] scalar_iw_head0_jal_target;
  wire [PC_WIDTH-1:0] scalar_iw_head0_predict_target;
  wire [PC_WIDTH-1:0] scalar_iw_head0_fallthrough;
  wire scalar_iw_head0_predict_taken;
  wire token0_is_branch;
  wire token0_is_jal;
  wire [PC_WIDTH-1:0] token0_branch_target;
  wire [PC_WIDTH-1:0] token0_jal_target;
  wire [PC_WIDTH-1:0] token0_predict_target;
  wire [PC_WIDTH-1:0] token0_fallthrough;
  wire token0_predict_taken;
  wire window_scalar1_fire;
  wire [REG_INDEX_WIDTH-1:0] hold_scalar_rd;
  wire [5:0] hold_scalar_key;
  wire [PRODUCER_TAG_WIDTH-1:0] hold_scalar_producer_tag;
  wire [REG_INDEX_WIDTH-1:0] window_scalar1_rd;
  wire [5:0] window_scalar1_key;
  wire [PRODUCER_TAG_WIDTH-1:0] window_scalar1_producer_tag;
  wire window_scalar1_writes_gpr;
  assign hold_scalar_writes_gpr = scalar_hold_valid_q &&
                                  rv64i_writes_gpr(scalar_hold_inst_q);
  assign hold_scalar_is_branch = scalar_hold_valid_q &&
                                 (scalar_hold_inst_q[6:0] == OPCODE_BRANCH);
  assign hold_scalar_is_jal = scalar_hold_valid_q &&
                              (scalar_hold_inst_q[6:0] == OPCODE_JAL);
  assign hold_scalar_branch_target = branch_target(
    scalar_hold_pc_q,
    scalar_hold_inst_q
  );
  assign hold_scalar_jal_target = jal_target(
    scalar_hold_pc_q,
    scalar_hold_inst_q
  );
  assign hold_scalar_predict_target = hold_scalar_is_jal ? hold_scalar_jal_target :
                                                           hold_scalar_branch_target;
  assign hold_scalar_fallthrough =
    scalar_hold_pc_q + {{(PC_WIDTH-3){1'b0}}, 3'd4};
  assign hold_scalar_predict_taken =
    hold_scalar_is_jal ||
    (hold_scalar_is_branch &&
     (hold_scalar_branch_target < scalar_hold_pc_q));
  assign hold_scalar_fire = scalar_hold_valid_q && window_scalar_ready;
  assign scalar_iw_head0_is_branch = scalar_iw_head0_valid &&
                                     (scalar_iw_head0_inst[6:0] == OPCODE_BRANCH);
  assign scalar_iw_head0_is_jal = scalar_iw_head0_valid &&
                                  (scalar_iw_head0_inst[6:0] == OPCODE_JAL);
  assign scalar_iw_head0_branch_target = branch_target(
    scalar_iw_head0_pc,
    scalar_iw_head0_inst[31:0]
  );
  assign scalar_iw_head0_jal_target = jal_target(
    scalar_iw_head0_pc,
    scalar_iw_head0_inst[31:0]
  );
  assign scalar_iw_head0_predict_target =
    scalar_iw_head0_is_jal ? scalar_iw_head0_jal_target :
                             scalar_iw_head0_branch_target;
  assign scalar_iw_head0_fallthrough =
    scalar_iw_head0_pc + {{(PC_WIDTH-3){1'b0}}, 3'd4};
  assign scalar_iw_head0_predict_taken =
    scalar_iw_head0_is_jal ||
    (scalar_iw_head0_is_branch &&
     (scalar_iw_head0_branch_target < scalar_iw_head0_pc));
  assign token0_is_branch = scalar_token_bypass0_fire &&
                            (token0_inst32[6:0] == OPCODE_BRANCH);
  assign token0_is_jal = scalar_token_bypass0_fire &&
                         (token0_inst32[6:0] == OPCODE_JAL);
  assign token0_branch_target = branch_target(token0_pc, token0_inst32);
  assign token0_jal_target = jal_target(token0_pc, token0_inst32);
  assign token0_predict_target = token0_is_jal ? token0_jal_target :
                                                 token0_branch_target;
  assign token0_fallthrough = token0_pc + {{(PC_WIDTH-3){1'b0}}, 3'd4};
  assign token0_predict_taken = token0_is_jal ||
                                (token0_is_branch &&
                                 (token0_branch_target < token0_pc));
  assign hold_scalar_rd = scalar_hold_inst_q[11:7];
  assign hold_scalar_key = {1'b0, hold_scalar_rd};
  assign hold_scalar_producer_tag = make_producer_tag(
    1'b0,
    hold_scalar_rd,
    scalar_hold_seq_id_q
  );
  assign window_scalar1_valid =
    (scalar_iw_head0_valid && scalar_iw_head1_valid && scalar_iw_pair_ready) ||
    (scalar_token_bypass0_fire && scalar_token_pairable) ||
    (frontend_present && frontend_control_ready &&
     window_valid && window_pattern_32_32) ||
    (frontend_present && frontend_control_ready && window_tensor_pseudo_lane1);
  assign window_scalar1_fire =
    scalar_iw_head1_fire || scalar_token_bypass1_fire ||
    (frontend_fire && window_valid && window_pattern_32_32) ||
    (frontend_fire && window_tensor_pseudo_lane1);
  assign window_scalar1_pc = window_tensor_pseudo_lane1 ? {PC_WIDTH{1'b0}} :
                             (scalar_iw_head1_valid ? scalar_iw_head1_pc :
                              ((window_valid && window_pattern_32_32) ?
                               frontend_lane1_pc : token1_pc));
  assign window_scalar1_inst = scalar_iw_head1_valid ? scalar_iw_head1_inst[31:0] :
                               (window_tensor_pseudo_lane1 ?
                                 make_tensor_snapshot_pseudo_inst(
                                  window_selected_vector_inst64[31:0],
                                  window_tensor_snapshot_source_mask,
                                  window_accel_is_getcsr ?
                                    {2'b0, reverse_snapshot_alloc_id} :
                                    window_selected_vector_seq_id[2:0]
                                ) : ((window_valid && window_pattern_32_32) ?
                                     window_lane1 : token1_inst32));
  assign window_scalar1_seq_id = scalar_iw_head1_valid ? scalar_iw_head1_seq_id :
                                 (window_tensor_pseudo_lane1 ?
                                  window_selected_vector_seq_id :
                                  ((window_valid && window_pattern_32_32) ?
                                   frontend_lane1_seq_id : token1_seq_id));
  assign window_scalar1_epoch = scalar_iw_head1_valid ? scalar_iw_head1_epoch :
                                (window_tensor_pseudo_lane1 ? frontend_epoch :
                                 ((window_valid && window_pattern_32_32) ?
                                  frontend_epoch : token1_epoch));
  assign window_scalar1_is_pseudo = window_tensor_pseudo_lane1;
  assign window_scalar1_pseudo_kind = window_scalar1_is_pseudo ?
                                      window_tensor_pseudo_kind : 3'd0;
  assign window_scalar1_rd = window_scalar1_inst[11:7];
  assign window_scalar1_key = {1'b0, window_scalar1_rd};
  assign window_scalar1_writes_gpr = window_scalar1_valid &&
    ((!window_scalar1_is_pseudo && rv64i_writes_gpr(window_scalar1_inst)) ||
     (window_scalar1_is_pseudo &&
      (window_scalar1_pseudo_kind == PSEUDO_ACCEL_GETCSR) &&
      (window_scalar1_rd != {REG_INDEX_WIDTH{1'b0}})));
  assign window_scalar1_def_valid = window_scalar1_writes_gpr;
  assign window_scalar1_def_dst_reg = window_scalar1_rd;
  assign window_scalar1_def_bank = 1'b0;
  assign window_scalar1_producer_tag = make_producer_tag(
    1'b0,
    window_scalar1_rd,
    window_scalar1_seq_id
  );

  assign window_scalar_valid = scalar_hold_valid_q || scalar_iw_head0_valid ||
                               scalar_token_bypass0_fire ||
                               (frontend_present && frontend_control_ready &&
                                (window_has_scalar || window_tensor_pseudo_lane0));
  assign window_scalar_pc = scalar_hold_valid_q ? scalar_hold_pc_q :
                            (scalar_iw_head0_valid ? scalar_iw_head0_pc :
                             (scalar_token_bypass0_fire ? token0_pc :
                              (window_tensor_pseudo_lane0 ?
                               {PC_WIDTH{1'b0}} : window_selected_scalar_pc)));
  assign window_scalar_inst = scalar_hold_valid_q ? scalar_hold_inst_q :
                              (scalar_iw_head0_valid ? scalar_iw_head0_inst[31:0] :
                               (scalar_token_bypass0_fire ? token0_inst32 :
                                (window_tensor_pseudo_lane0 ?
                                 make_tensor_snapshot_pseudo_inst(
                                   window_selected_vector_inst64[31:0],
                                   window_tensor_snapshot_source_mask,
                                   window_accel_is_getcsr ?
                                     {2'b0, reverse_snapshot_alloc_id} :
                                     window_selected_vector_seq_id[2:0]
                                 ) :
                                 window_selected_scalar_inst)));
  assign window_scalar_seq_id = scalar_hold_valid_q ? scalar_hold_seq_id_q :
                                (scalar_iw_head0_valid ? scalar_iw_head0_seq_id :
                                 (scalar_token_bypass0_fire ? token0_seq_id :
                                  (window_tensor_pseudo_lane0 ?
                                   window_selected_vector_seq_id :
                                   window_selected_scalar_seq_id)));
  assign window_scalar_epoch = scalar_hold_valid_q ? scalar_hold_epoch_q :
                               (scalar_iw_head0_valid ? scalar_iw_head0_epoch :
                                (scalar_token_bypass0_fire ? token0_epoch :
                                 frontend_epoch));
  assign window_scalar_is_pseudo =
    window_scalar_valid && !scalar_hold_valid_q && !scalar_iw_head0_valid &&
    !scalar_token_bypass0_fire && window_tensor_pseudo_lane0;
  assign window_scalar_pseudo_kind = window_scalar_is_pseudo ?
                                     window_tensor_pseudo_kind : 3'd0;
  assign window_scalar_def_valid = scalar_hold_valid_q ? hold_scalar_writes_gpr :
                                   (scalar_iw_head0_valid ?
                                    rv64i_writes_gpr(scalar_iw_head0_inst[31:0]) :
                                    (scalar_token_bypass0_fire ?
                                     rv64i_writes_gpr(token0_inst32) :
                                     (window_scalar_valid &&
                                      ((!window_scalar_is_pseudo &&
                                        window_scalar_writes_gpr) ||
                                       (window_scalar_is_pseudo &&
                                        (window_tensor_pseudo_kind ==
                                         PSEUDO_ACCEL_GETCSR) &&
                                        (window_selected_vector_inst64[11:7] !=
                                         {REG_INDEX_WIDTH{1'b0}}))))));
  assign window_scalar_def_domain = 1'b0;
  assign window_scalar_def_dst_reg = scalar_hold_valid_q ? hold_scalar_rd :
                                     (scalar_iw_head0_valid ?
                                      scalar_iw_head0_inst[11:7] :
                                      (scalar_token_bypass0_fire ? token0_inst32[11:7] :
                                       (window_scalar_is_pseudo ?
                                        window_selected_vector_inst64[11:7] :
                                        window_scalar_rd)));
  assign window_scalar_def_bank = 1'b0;

  assign accel_decode_is_accel = raw_low_is_vector ||
                                   (frontend_present && window_has_vector);
  assign accel_decode_needs_base_gpr = (raw_low_is_vector && raw_vector_needs_base) ||
                                        (frontend_present && window_has_vector &&
                                         window_vector_needs_base);

  wire vec_action_is_base;
  wire [REG_INDEX_WIDTH-1:0] vec_action_src_reg;
  wire [5:0] vec_action_key;
  wire vec_action_has_mapping;
  wire vec_action_new_capture_found;
  wire [CAPTURE_ID_WIDTH-1:0] vec_action_selected_capture_id;
  assign vec_action_is_base = (vec_state == VEC_STATE_BASE);
  assign vec_action_src_reg = vec_action_is_base ? accel_command_base_src_gpr :
                                                   accel_command_n_src_gpr;
  assign vec_action_key = {1'b0, vec_action_src_reg};
  assign vec_action_has_mapping = mapping_valid[vec_action_key] &&
                                  (mapping_producer_tag[vec_action_key] ==
                                   current_producer_tag[vec_action_key]);
  assign vec_action_new_capture_found = free_capture_found;
  assign vec_action_selected_capture_id = vec_action_has_mapping ? mapping_capture_id[vec_action_key] :
                                           free_capture_id;

  wire unsupported_multi_capture;
  assign unsupported_multi_capture = decoded_capture_count > 3'd1;

  wire needs_capture;
  assign needs_capture = decoded_capture_count == 3'd1;

  wire [CAPTURE_ID_WIDTH-1:0] selected_capture_id;
  assign selected_capture_id = src0_selected_capture_id;

  wire can_allocate;
  assign can_allocate = !src0_has_mapping && free_capture_found;

  wire can_reuse;
  assign can_reuse = src0_has_mapping;

  wire capture_path_ready;
  assign capture_path_ready = !needs_capture ||
                              (!unsupported_multi_capture &&
                               ((src0_has_mapping && can_reuse) ||
                                (!src0_has_mapping && can_allocate)));

  assign vec_busy = (vec_state != VEC_STATE_IDLE);

  assign decoded_ready = !scalar_hold_valid_q && !scalar_iw_head0_valid &&
                         !vec_busy && !raw_vector_valid && !frontend_present &&
                         capture_path_ready && !unsupported_multi_capture;

  wire decoded_fire;
  assign decoded_fire = decoded_valid && decoded_ready;

  wire raw_fire;
  assign raw_ready = !scalar_hold_valid_q && !scalar_iw_head0_valid &&
                     !vec_busy && !decoded_valid &&
                     !frontend_present && raw_low_is_vector;
  assign raw_fire = raw_valid && raw_ready;

  wire vec_action_valid;
  wire vec_can_allocate;
  wire vec_can_reuse;
  wire vec_action_fire;
  assign vec_action_valid = (vec_state == VEC_STATE_N) || (vec_state == VEC_STATE_BASE);
  assign vec_can_allocate = !vec_action_has_mapping && vec_action_new_capture_found;
  assign vec_can_reuse = vec_action_has_mapping;
  assign vec_action_fire = vec_action_valid &&
                           ((vec_action_has_mapping && vec_can_reuse) ||
                            (!vec_action_has_mapping && vec_can_allocate));

  assign command_valid = decoded_fire;
  assign command_is_tensor = decoded_is_tensor;
  assign command_seq_id = decoded_seq_id;
  assign command_epoch = decoded_epoch;
  assign command_capture_count = needs_capture ? 3'd1 : 3'd0;
  assign command_capture_id0 = selected_capture_id;
  assign command_capture_bank0 = 1'b0;
  assign command_n_capture_valid = needs_capture && decoded_src0_is_n_capture;
  assign command_n_capture_id = selected_capture_id;
  assign command_n_capture_bank = 1'b0;
  assign command_producer_tag0 = needs_capture ? current_producer_tag[src0_key] :
                                                {PRODUCER_TAG_WIDTH{1'b0}};

  assign accel_command_valid = ((vec_state == VEC_STATE_EMIT) &&
                                 accel_command_ready) ||
                                (frontend_fire && window_has_vector &&
                                 !window_vector_needs_base &&
                                 accel_command_ready);
  assign accel_command_is_tensor = (frontend_fire && window_has_vector) ?
                                    window_selected_vector_is_tensor :
                                    vec_is_tensor_q;
  assign accel_command_inst64 = (frontend_fire && window_has_vector) ?
                                 (window_accel_is_getcsr ?
                                  set_reverse_snapshot_id(
                                    window_selected_vector_inst64,
                                    reverse_snapshot_alloc_id) :
                                  window_selected_vector_inst64) : vec_inst64_q;
  assign accel_command_seq_id = (frontend_fire && window_has_vector) ?
                                 window_selected_vector_seq_id : vec_seq_id_q;
  assign accel_command_epoch = (frontend_fire && window_has_vector) ?
                                frontend_epoch : vec_epoch_q;
  assign accel_command_capture_count = (frontend_fire && window_has_vector) ?
                                        window_accel_capture_count :
                                        (vec_needs_base_q ? 3'd2 : 3'd1);
  assign accel_command_n_capture_valid =
    accel_command_valid &&
    (!(frontend_fire && window_has_vector) || window_accel_needs_capture);
  assign accel_command_n_capture_id = (frontend_fire && window_has_vector) ?
                                       window_n_selected_capture_id : vec_n_capture_id_q;
  assign accel_command_n_capture_bank = 1'b0;
  assign accel_command_n_producer_tag = (frontend_fire && window_has_vector) ?
                                         window_n_selected_producer_tag :
                                         vec_n_producer_tag_q;
  assign accel_command_n_src_gpr = (frontend_fire && window_has_vector) ?
                                    window_accel_capture_src_gpr :
                                    (vec_is_tensor_q ? vec_inst64_q[19:15] :
                                                       vec_inst64_q[47:43]);
  assign accel_command_base_capture_valid = (frontend_fire && window_has_vector) ?
                                             1'b0 :
                                             (accel_command_valid && vec_needs_base_q);
  assign accel_command_base_capture_id = (frontend_fire && window_has_vector) ?
                                          window_base_selected_capture_id :
                                          vec_base_capture_id_q;
  assign accel_command_base_capture_bank = (frontend_fire && window_has_vector) ?
                                            1'b0 : vec_base_capture_bank_q;
  assign accel_command_base_producer_tag = (frontend_fire && window_has_vector) ?
                                            current_producer_tag[window_vector_base_key] :
                                            vec_base_producer_tag_q;
  assign accel_command_base_src_gpr = (frontend_fire && window_has_vector) ?
                                       window_vector_base_src_gpr :
                                       ((vec_is_tensor_q &&
                                        (vec_inst64_q[38:32] == DMA_START)) ?
                                        vec_inst64_q[24:20] : vec_inst64_q[19:15]);

  assign reverse_snapshot_alloc_valid = frontend_fire && window_has_vector &&
                                        window_accel_is_getcsr;
  assign reverse_snapshot_alloc_seq_id = window_selected_vector_seq_id;
  assign reverse_snapshot_alloc_epoch = frontend_epoch;

  assign loop_predict_valid = (frontend_fire && window_scalar_predict_taken) ||
                              (hold_scalar_fire && hold_scalar_predict_taken) ||
                              (scalar_iw_head0_fire && scalar_iw_head0_predict_taken) ||
                              (scalar_token_bypass0_fire && token0_predict_taken);
  assign loop_predict_target = hold_scalar_fire ? hold_scalar_predict_target :
                               (scalar_iw_head0_fire ? scalar_iw_head0_predict_target :
                                (scalar_token_bypass0_fire ? token0_predict_target :
                                 window_scalar_predict_target));
  assign loop_predict_fallthrough = hold_scalar_fire ? hold_scalar_fallthrough :
                                    (scalar_iw_head0_fire ? scalar_iw_head0_fallthrough :
                                     (scalar_token_bypass0_fire ? token0_fallthrough :
                                      window_scalar_fallthrough));
  assign loop_predict_seq_id = hold_scalar_fire ? scalar_hold_seq_id_q :
                               (scalar_iw_head0_fire ? scalar_iw_head0_seq_id :
                                (scalar_token_bypass0_fire ? token0_seq_id :
                                 window_selected_scalar_seq_id));
  assign loop_predict_epoch = hold_scalar_fire ? scalar_hold_epoch_q :
                              (scalar_iw_head0_fire ? scalar_iw_head0_epoch :
                               (scalar_token_bypass0_fire ? token0_epoch :
                                frontend_epoch));

  genvar gi;
  generate
    for (gi = 0; gi < CAPTURE_SLOTS; gi = gi + 1) begin : gen_debug_ref
      assign debug_slot_owned[gi] = capture_owned[gi];
      assign debug_bank_owned_flat[(2*gi)] = capture_owned[gi];
      assign debug_bank_owned_flat[(2*gi)+1] = 1'b0;
      assign debug_bank_ref_count_flat[((2*gi)+1)*REF_COUNT_WIDTH-1:(2*gi)*REF_COUNT_WIDTH] =
        capture_ref_count[gi];
      assign debug_bank_ref_count_flat[((2*gi)+2)*REF_COUNT_WIDTH-1:((2*gi)+1)*REF_COUNT_WIDTH] =
        {REF_COUNT_WIDTH{1'b0}};
      assign debug_slot_ref_count_flat[(gi+1)*REF_COUNT_WIDTH-1:gi*REF_COUNT_WIDTH] =
        capture_ref_count[gi];
    end
  endgenerate

  assign debug_mapping_valid = mapping_valid;

  integer i;
  wire [5:0] scalar_def_key;
  wire [CAPTURE_ID_WIDTH-1:0] consumer_release_id;
  assign scalar_def_key = {scalar_def_domain, scalar_def_dst_reg};
  assign consumer_release_id = consumer_release_capture_id;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      mapping_valid <= 64'd0;
      vec_state <= VEC_STATE_IDLE;
      vec_inst64_q <= 64'd0;
      vec_is_tensor_q <= 1'b0;
      vec_seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
      vec_epoch_q <= {EPOCH_WIDTH{1'b0}};
      vec_needs_base_q <= 1'b0;
      vec_n_capture_id_q <= {CAPTURE_ID_WIDTH{1'b0}};
      vec_n_capture_bank_q <= 1'b0;
      vec_base_capture_id_q <= {CAPTURE_ID_WIDTH{1'b0}};
      vec_base_capture_bank_q <= 1'b0;
      vec_n_producer_tag_q <= {PRODUCER_TAG_WIDTH{1'b0}};
      vec_base_producer_tag_q <= {PRODUCER_TAG_WIDTH{1'b0}};
      scalar_hold_valid_q <= 1'b0;
      scalar_hold_pc_q <= {PC_WIDTH{1'b0}};
      scalar_hold_inst_q <= 32'd0;
      scalar_hold_seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
      scalar_hold_epoch_q <= {EPOCH_WIDTH{1'b0}};
      for (i = 0; i < 64; i = i + 1) begin
        current_producer_tag[i] <= {PRODUCER_TAG_WIDTH{1'b0}};
        mapping_capture_id[i] <= {CAPTURE_ID_WIDTH{1'b0}};
        mapping_producer_tag[i] <= {PRODUCER_TAG_WIDTH{1'b0}};
      end
      for (i = 0; i < CAPTURE_SLOTS; i = i + 1) begin
        capture_owned[i] <= 1'b0;
        capture_ref_count[i] <= {REF_COUNT_WIDTH{1'b0}};
      end
    end else if (redirect_flush_valid) begin
      mapping_valid <= 64'd0;
      vec_state <= VEC_STATE_IDLE;
      vec_is_tensor_q <= 1'b0;
      scalar_hold_valid_q <= 1'b0;
      for (i = 0; i < 64; i = i + 1) begin
        current_producer_tag[i] <= {
          {(PRODUCER_TAG_WIDTH-EPOCH_WIDTH){1'b0}},
          redirect_new_epoch
        };
        mapping_capture_id[i] <= {CAPTURE_ID_WIDTH{1'b0}};
        mapping_producer_tag[i] <= {PRODUCER_TAG_WIDTH{1'b0}};
      end
      for (i = 0; i < CAPTURE_SLOTS; i = i + 1) begin
        capture_owned[i] <= 1'b0;
        capture_ref_count[i] <= {REF_COUNT_WIDTH{1'b0}};
      end
    end else begin
      if (scalar_hold_valid_q && window_scalar_ready) begin
        current_producer_tag[hold_scalar_key] <= hold_scalar_producer_tag;
        mapping_valid[hold_scalar_key] <= 1'b0;
        scalar_hold_valid_q <= 1'b0;
      end

      if (consumer_release_valid && capture_owned[consumer_release_id]) begin
        if (capture_ref_count[consumer_release_id] <=
            {{(REF_COUNT_WIDTH-1){1'b0}}, 1'b1}) begin
          capture_owned[consumer_release_id] <= 1'b0;
          capture_ref_count[consumer_release_id] <= {REF_COUNT_WIDTH{1'b0}};
          for (i = 0; i < 64; i = i + 1) begin
            if (mapping_valid[i] && (mapping_capture_id[i] == consumer_release_id)) begin
              mapping_valid[i] <= 1'b0;
            end
          end
        end else begin
          capture_ref_count[consumer_release_id] <=
            capture_ref_count[consumer_release_id] -
            {{(REF_COUNT_WIDTH-1){1'b0}}, 1'b1};
        end
      end

      if (scalar_def_valid) begin
        current_producer_tag[scalar_def_key] <= make_producer_tag(
          scalar_def_domain,
          scalar_def_dst_reg,
          scalar_def_seq_id
        );
        mapping_valid[scalar_def_key] <= 1'b0;
      end

      if (frontend_fire && window_has_vector) begin
        if (window_accel_uses_capture) begin
          if (window_n_has_mapping) begin
            capture_ref_count[window_n_selected_capture_id] <=
              capture_ref_count[window_n_selected_capture_id] +
              {{(REF_COUNT_WIDTH-1){1'b0}}, 1'b1};
          end else begin
            capture_owned[window_n_selected_capture_id] <= 1'b1;
            capture_ref_count[window_n_selected_capture_id] <=
              {{(REF_COUNT_WIDTH-1){1'b0}}, 1'b1};
            mapping_valid[window_vector_n_key] <= 1'b1;
            mapping_capture_id[window_vector_n_key] <= window_n_selected_capture_id;
            mapping_producer_tag[window_vector_n_key] <= window_n_selected_producer_tag;
          end
        end

        if (window_vector_needs_base) begin
          vec_state <= VEC_STATE_BASE;
          vec_inst64_q <= window_selected_vector_inst64;
          vec_is_tensor_q <= window_selected_vector_is_tensor;
          vec_seq_id_q <= window_selected_vector_seq_id;
          vec_epoch_q <= frontend_epoch;
          vec_needs_base_q <= 1'b1;
          vec_n_capture_id_q <= window_n_selected_capture_id;
          vec_n_capture_bank_q <= 1'b0;
          vec_base_capture_id_q <= {CAPTURE_ID_WIDTH{1'b0}};
          vec_base_capture_bank_q <= 1'b0;
          vec_n_producer_tag_q <= window_n_selected_producer_tag;
          vec_base_producer_tag_q <= {PRODUCER_TAG_WIDTH{1'b0}};
        end
      end

      if (frontend_fire && window_scalar_frontend_writes_gpr) begin
        current_producer_tag[window_scalar_key] <= window_scalar_producer_tag;
        if (!window_vector_uses_same_prior_scalar) begin
          mapping_valid[window_scalar_key] <= 1'b0;
        end
      end

      if (scalar_iw_head0_fire && rv64i_writes_gpr(scalar_iw_head0_inst[31:0])) begin
        current_producer_tag[{1'b0, scalar_iw_head0_inst[11:7]}] <=
          make_producer_tag(1'b0, scalar_iw_head0_inst[11:7], scalar_iw_head0_seq_id);
        mapping_valid[{1'b0, scalar_iw_head0_inst[11:7]}] <= 1'b0;
      end

      if (scalar_token_bypass0_fire && rv64i_writes_gpr(token0_inst32)) begin
        current_producer_tag[{1'b0, token0_inst32[11:7]}] <=
          make_producer_tag(1'b0, token0_inst32[11:7], token0_seq_id);
        mapping_valid[{1'b0, token0_inst32[11:7]}] <= 1'b0;
      end

      if (window_scalar1_fire && window_scalar1_writes_gpr) begin
        current_producer_tag[window_scalar1_key] <= window_scalar1_producer_tag;
        mapping_valid[window_scalar1_key] <= 1'b0;
      end

      if (token_fire && token_pair_scalar_scalar && !window_scalar1_fire) begin
        scalar_hold_valid_q <= 1'b1;
        scalar_hold_pc_q <= token1_pc;
        scalar_hold_inst_q <= token1_inst32;
        scalar_hold_seq_id_q <= token1_seq_id;
        scalar_hold_epoch_q <= token1_epoch;
      end

      if (decoded_fire && needs_capture) begin
        if (src0_has_mapping) begin
          capture_ref_count[selected_capture_id] <=
            capture_ref_count[selected_capture_id] +
            {{(REF_COUNT_WIDTH-1){1'b0}}, 1'b1};
        end else begin
          capture_owned[selected_capture_id] <= 1'b1;
          capture_ref_count[selected_capture_id] <= {{(REF_COUNT_WIDTH-1){1'b0}}, 1'b1};
          mapping_valid[src0_key] <= 1'b1;
          mapping_capture_id[src0_key] <= selected_capture_id;
          mapping_producer_tag[src0_key] <= current_producer_tag[src0_key];
        end
      end

      if (raw_fire) begin
        vec_state <= VEC_STATE_N;
        vec_inst64_q <= raw_inst64;
        vec_is_tensor_q <= 1'b0;
        vec_seq_id_q <= raw_seq_id;
        vec_epoch_q <= raw_epoch;
        vec_needs_base_q <= raw_vector_needs_base;
        vec_n_capture_id_q <= {CAPTURE_ID_WIDTH{1'b0}};
        vec_n_capture_bank_q <= 1'b0;
        vec_base_capture_id_q <= {CAPTURE_ID_WIDTH{1'b0}};
        vec_base_capture_bank_q <= 1'b0;
        vec_n_producer_tag_q <= {PRODUCER_TAG_WIDTH{1'b0}};
        vec_base_producer_tag_q <= {PRODUCER_TAG_WIDTH{1'b0}};
      end else if (vec_action_fire) begin
        if (vec_action_has_mapping) begin
          capture_ref_count[vec_action_selected_capture_id] <=
            capture_ref_count[vec_action_selected_capture_id] +
            {{(REF_COUNT_WIDTH-1){1'b0}}, 1'b1};
        end else begin
          capture_owned[vec_action_selected_capture_id] <= 1'b1;
          capture_ref_count[vec_action_selected_capture_id] <= {{(REF_COUNT_WIDTH-1){1'b0}}, 1'b1};
          mapping_valid[vec_action_key] <= 1'b1;
          mapping_capture_id[vec_action_key] <= vec_action_selected_capture_id;
          mapping_producer_tag[vec_action_key] <= current_producer_tag[vec_action_key];
        end

        if (vec_action_is_base) begin
          vec_base_capture_id_q <= vec_action_selected_capture_id;
          vec_base_capture_bank_q <= 1'b0;
          vec_base_producer_tag_q <= current_producer_tag[vec_action_key];
          vec_state <= VEC_STATE_EMIT;
        end else begin
          vec_n_capture_id_q <= vec_action_selected_capture_id;
          vec_n_capture_bank_q <= 1'b0;
          vec_n_producer_tag_q <= current_producer_tag[vec_action_key];
          vec_state <= vec_needs_base_q ? VEC_STATE_BASE : VEC_STATE_EMIT;
        end
      end else if (vec_state == VEC_STATE_EMIT && accel_command_ready) begin
        vec_state <= VEC_STATE_IDLE;
      end
    end
  end

endmodule
