module edge_accel_pipe(
  forever_cpuclk,
  cpurst_b,
  edge_dtcm_base,
  edge_dtcm_mask,
  edge_dtcm_enable,
  cmd_valid,
  cmd_opcode8,
  cmd_imm8,
  cmd_inst64,
  cmd_seq_id,
  cmd_epoch,
  cmd_capture_valid,
  cmd_capture_value,
  dma_start_ready,
  dma_start_circular_ready,
  dma_sync_done,
  tensor_cmd_ready,
  tensor_start_ready,
  tensor_wld_cmd_ready,
  tensor_sld_cmd_ready,
  tensor_wld_circular_ready,
  tensor_wsld_circular_ready,
  tensor_sld_circular_ready,
  tensor_sync_stall,
  actu_cmd_ready,
  actu_start_ready,
  actu_sync_stall,
  cmpu_cmd_ready,
  cmpu_start_ready,
  cmpu_sync_stall,
  actu_last_sum_bits,
  cmpu_max_value,
  cmpu_argmax_idx,
  cmpu_min_value,
  cmpu_argmin_idx,
  reverse_snapshot_write_ready,
  cmd_ready,
  decode_illegal,
  capture_consume_valid,
  tensor_done_valid,
  tensor_done_seq_id,
  tensor_done_epoch,
  dma_start_req,
  dma_start_circular_req,
  dma_start_src,
  dma_start_dst,
  dma_start_len,
  dma_start_entry_bytes,
  dma_start_circular_tiles,
  dma_start_use_xy,
  dma_start_circular,
  dma_start_x,
  dma_start_y,
  dma_sync_req,
  cmd_setcsr_dtype,
  cmd_setcsr_req,
  cmd_setcsr_wtype,
  cmd_setin_ptr,
  cmd_setin_req,
  cmd_setn_req,
  cmd_setn_value,
  cmd_setout_ptr,
  cmd_setout_req,
  cmd_setpsum_ptr,
  cmd_setpsum_req,
  cmd_start_req,
  cmd_start_tile_req,
  cmd_start_mode,
  cmd_sync_req,
  cmd_wld_ptr,
  cmd_wld_req,
  cmd_wld_circular_req,
  cmd_wld_trans_req,
  cmd_wld_reuse,
  cmd_sld_ptr,
  cmd_sld_req,
  cmd_sld_reuse,
  cmd_sld_stream_ptr,
  cmd_sld_stream_req,
  cmd_wsld_circular_req,
  cmd_wsld_circular_transpose,
  cmd_sld_circular_req,
  actu_cmd_setcsr_dtype,
  actu_cmd_setcsr_mode,
  actu_cmd_setcsr_req,
  actu_cmd_setin_ptr,
  actu_cmd_setin_req,
  actu_cmd_setn_req,
  actu_cmd_setn_value,
  actu_cmd_setout_ptr,
  actu_cmd_setout_req,
  actu_cmd_setscalar_req,
  actu_cmd_setscalar_value,
  actu_cmd_start_req,
  actu_cmd_sync_req,
  cmpu_cmd_setcsr_mode,
  cmpu_cmd_setcsr_req,
  cmpu_cmd_setlhs_ptr,
  cmpu_cmd_setlhs_req,
  cmpu_cmd_setrhs_ptr,
  cmpu_cmd_setrhs_req,
  cmpu_cmd_setmask_ptr,
  cmpu_cmd_setmask_req,
  cmpu_cmd_setout_ptr,
  cmpu_cmd_setout_req,
  cmpu_cmd_setn_req,
  cmpu_cmd_setn_value,
  cmpu_cmd_start_req,
  cmpu_cmd_sync_req,
  reverse_snapshot_write_valid,
  reverse_snapshot_write_id,
  reverse_snapshot_write_value
);

parameter SEQ_ID_WIDTH = 8;
parameter EPOCH_WIDTH  = 4;
parameter VALUE_WIDTH  = 64;
parameter ADDR_WIDTH   = 16;
parameter PA_WIDTH     = 40;
parameter COMPACT_CMD_INPUT = 0;

input                       forever_cpuclk;
input                       cpurst_b;
input  [PA_WIDTH-1:0]        edge_dtcm_base;
input  [PA_WIDTH-1:0]        edge_dtcm_mask;
input                       edge_dtcm_enable;
input                       cmd_valid;
input  [7:0]                cmd_opcode8;
input  [7:0]                cmd_imm8;
input  [63:0]               cmd_inst64;
input  [SEQ_ID_WIDTH-1:0]   cmd_seq_id;
input  [EPOCH_WIDTH-1:0]    cmd_epoch;
input                       cmd_capture_valid;
input  [VALUE_WIDTH-1:0]    cmd_capture_value;
input                       dma_start_ready;
input                       dma_start_circular_ready;
input                       dma_sync_done;
input                       tensor_cmd_ready;
input                       tensor_start_ready;
input                       tensor_wld_cmd_ready;
input                       tensor_sld_cmd_ready;
input                       tensor_wld_circular_ready;
input                       tensor_wsld_circular_ready;
input                       tensor_sld_circular_ready;
input                       tensor_sync_stall;
input                       actu_cmd_ready;
input                       actu_start_ready;
input                       actu_sync_stall;
input                       cmpu_cmd_ready;
input                       cmpu_start_ready;
input                       cmpu_sync_stall;
input  [31:0]               actu_last_sum_bits;
input  [15:0]               cmpu_max_value;
input  [15:0]               cmpu_argmax_idx;
input  [15:0]               cmpu_min_value;
input  [15:0]               cmpu_argmin_idx;
input                       reverse_snapshot_write_ready;

output                      cmd_ready;
output                      decode_illegal;
output                      capture_consume_valid;
output                      tensor_done_valid;
output [SEQ_ID_WIDTH-1:0]   tensor_done_seq_id;
output [EPOCH_WIDTH-1:0]    tensor_done_epoch;
output                      dma_start_req;
output                      dma_start_circular_req;
output [VALUE_WIDTH-1:0]    dma_start_src;
output [VALUE_WIDTH-1:0]    dma_start_dst;
output [31:0]               dma_start_len;
output [31:0]               dma_start_entry_bytes;
output [15:0]               dma_start_circular_tiles;
output                      dma_start_use_xy;
output                      dma_start_circular;
output [63:0]               dma_start_x;
output [63:0]               dma_start_y;
output                      dma_sync_req;
output [3:0]                cmd_setcsr_dtype;
output                      cmd_setcsr_req;
output [3:0]                cmd_setcsr_wtype;
output [ADDR_WIDTH-1:0]     cmd_setin_ptr;
output                      cmd_setin_req;
output                      cmd_setn_req;
output [15:0]               cmd_setn_value;
output [ADDR_WIDTH-1:0]     cmd_setout_ptr;
output                      cmd_setout_req;
output [ADDR_WIDTH-1:0]     cmd_setpsum_ptr;
output                      cmd_setpsum_req;
output                      cmd_start_req;
output                      cmd_start_tile_req;
output [7:0]                cmd_start_mode;
output                      cmd_sync_req;
output [ADDR_WIDTH-1:0]     cmd_wld_ptr;
output                      cmd_wld_req;
output                      cmd_wld_circular_req;
output                      cmd_wld_trans_req;
output                      cmd_wld_reuse;
output [ADDR_WIDTH-1:0]     cmd_sld_ptr;
output                      cmd_sld_req;
output                      cmd_sld_reuse;
output [ADDR_WIDTH-1:0]     cmd_sld_stream_ptr;
output                      cmd_sld_stream_req;
output                      cmd_wsld_circular_req;
output                      cmd_wsld_circular_transpose;
output                      cmd_sld_circular_req;
output [3:0]                actu_cmd_setcsr_dtype;
output [3:0]                actu_cmd_setcsr_mode;
output                      actu_cmd_setcsr_req;
output [ADDR_WIDTH-1:0]     actu_cmd_setin_ptr;
output                      actu_cmd_setin_req;
output                      actu_cmd_setn_req;
output [15:0]               actu_cmd_setn_value;
output [ADDR_WIDTH-1:0]     actu_cmd_setout_ptr;
output                      actu_cmd_setout_req;
output                      actu_cmd_setscalar_req;
output [VALUE_WIDTH-1:0]    actu_cmd_setscalar_value;
output                      actu_cmd_start_req;
output                      actu_cmd_sync_req;
output [3:0]                cmpu_cmd_setcsr_mode;
output                      cmpu_cmd_setcsr_req;
output [ADDR_WIDTH-1:0]     cmpu_cmd_setlhs_ptr;
output                      cmpu_cmd_setlhs_req;
output [ADDR_WIDTH-1:0]     cmpu_cmd_setrhs_ptr;
output                      cmpu_cmd_setrhs_req;
output [ADDR_WIDTH-1:0]     cmpu_cmd_setmask_ptr;
output                      cmpu_cmd_setmask_req;
output [ADDR_WIDTH-1:0]     cmpu_cmd_setout_ptr;
output                      cmpu_cmd_setout_req;
output                      cmpu_cmd_setn_req;
output [15:0]               cmpu_cmd_setn_value;
output                      cmpu_cmd_start_req;
output                      cmpu_cmd_sync_req;
output                      reverse_snapshot_write_valid;
output                      reverse_snapshot_write_id;
output [VALUE_WIDTH-1:0]    reverse_snapshot_write_value;

localparam [6:0] EDGE64_LENGTH_OPCODE = 7'h3f;

localparam [6:0] DMA_START    = 7'h01;
localparam [6:0] DMA_SYNC     = 7'h02;
localparam [6:0] DMA_SETN     = 7'h03;
localparam [6:0] DMA_SETX     = 7'h04;
localparam [6:0] DMA_SETY     = 7'h05;
localparam [6:0] DMA_SETSRC   = 7'h06;
localparam [6:0] DMA_SETTAR   = 7'h07;
localparam [6:0] DMA_SETENTRY = 7'h08;

localparam [6:0] TENSOR_SETCSR = 7'h10;
localparam [6:0] TENSOR_WLD    = 7'h11;
localparam [6:0] TENSOR_SETIN  = 7'h12;
localparam [6:0] TENSOR_SETOUT = 7'h13;
localparam [6:0] TENSOR_SETPSUM= 7'h14;
localparam [6:0] TENSOR_START  = 7'h15;
localparam [6:0] TENSOR_SYNC   = 7'h16;
localparam [6:0] TENSOR_SETN   = 7'h17;
localparam [6:0] TENSOR_WLD_T  = 7'h18;
localparam [6:0] TENSOR_START_TILE = 7'h19;
localparam [6:0] TENSOR_SLD_STREAM = 7'h1a;
localparam [6:0] TENSOR_WLD_CIRCULAR = 7'h1b;
localparam [6:0] TENSOR_WLD_T_CIRCULAR = 7'h1c;
localparam [6:0] TENSOR_SLD    = 7'h1d;
localparam [6:0] TENSOR_WSLD_CIRCULAR = 7'h1e;
localparam [6:0] TENSOR_SLD_CIRCULAR = 7'h1f;

localparam [6:0] ACTU_SETCSR    = 7'h20;
localparam [6:0] ACTU_SETIN     = 7'h21;
localparam [6:0] ACTU_SETOUT    = 7'h22;
localparam [6:0] ACTU_SETN      = 7'h23;
localparam [6:0] ACTU_SETSCALAR = 7'h24;
localparam [6:0] ACTU_START     = 7'h25;
localparam [6:0] ACTU_SYNC      = 7'h26;
localparam [6:0] CMPU_SETCSR    = 7'h27;
localparam [6:0] CMPU_SETLHS    = 7'h28;
localparam [6:0] CMPU_SETRHS    = 7'h29;
localparam [6:0] CMPU_SETMASK   = 7'h2a;
localparam [6:0] CMPU_SETOUT    = 7'h2b;
localparam [6:0] CMPU_SETN      = 7'h2c;
localparam [6:0] CMPU_START     = 7'h2d;
localparam [6:0] CMPU_SYNC      = 7'h2e;
localparam [6:0] ACCEL_GETCSR   = 7'h2f;

localparam [3:0] CSR_CMPU_MAX_VALUE  = 4'd0;
localparam [3:0] CSR_CMPU_ARGMAX_IDX = 4'd1;
localparam [3:0] CSR_CMPU_MIN_VALUE  = 4'd2;
localparam [3:0] CSR_CMPU_ARGMIN_IDX = 4'd3;
localparam [3:0] CSR_ACTU_EXP_SUM     = 4'd4;

wire [6:0] subop;
wire [7:0] control_opcode8;
wire [7:0] control_imm8;
wire       opcode_is_edge64;
wire       subop_is_stream;
wire       needs_capture;
wire       is_sync;
wire       is_dma_start;
wire       is_dma_start_circular;
wire       is_dma_set;
wire       is_dma_sync;
wire       is_start;
wire       is_wld;
wire       is_wld_reuse;
wire       is_wld_circular;
wire       is_sld;
wire       is_sld_reuse;
wire       is_sld_stream;
wire       is_wsld_circular;
wire       is_sld_circular;
wire       is_actu_setup;
wire       is_actu_start;
wire       is_actu_sync;
wire       is_cmpu_setup;
wire       is_cmpu_start;
wire       is_cmpu_sync;
wire       is_accel_getcsr;
wire       getcsr_csr_valid;
wire       tensor_ready_for_target;
wire       actu_ready_for_target;
wire       cmpu_ready_for_target;
wire       getcsr_owner_idle;
wire       getcsr_ready_for_target;
wire       ready_for_target;
wire       cmd_fire;
wire [ADDR_WIDTH-1:0] capture_addr;
wire [PA_WIDTH-1:0] capture_dtcm_byte_offset;
wire       capture_is_dtcm_ptr;
wire [ADDR_WIDTH-1:0] capture_dtcm_word_addr;
reg  [31:0] dma_n_q;
reg  [31:0] dma_entry_q;
reg  [63:0] dma_x_q;
reg  [63:0] dma_y_q;
reg  [63:0] dma_src_q;
reg  [63:0] dma_tar_q;

function [7:0] compact_legacy_imm8;
  input [63:0] inst64;
  begin
    case (inst64[38:32])
      7'h01: compact_legacy_imm8 = {6'b0, inst64[57:56]};
      7'h10,
      7'h20: compact_legacy_imm8 = {inst64[55:52], inst64[50:47]};
      7'h27: compact_legacy_imm8 = {4'b0, inst64[50:47]};
      7'h2f: compact_legacy_imm8 = {3'b0, inst64[52], inst64[50:47]};
      7'h11,
      7'h18,
      7'h1d: compact_legacy_imm8 = {6'b0, inst64[57], 1'b0};
      7'h15: compact_legacy_imm8 = inst64[63:56];
      7'h1e: compact_legacy_imm8 = {7'b0, inst64[56]};
      default: compact_legacy_imm8 = 8'b0;
    endcase
  end
endfunction

assign control_opcode8 = COMPACT_CMD_INPUT ? cmd_opcode8 : cmd_inst64[39:32];
assign control_imm8 = COMPACT_CMD_INPUT ? cmd_imm8 : compact_legacy_imm8(cmd_inst64);
assign subop            = control_opcode8[6:0];
assign opcode_is_edge64 = COMPACT_CMD_INPUT ? control_opcode8[7] :
                          (cmd_inst64[6:0] == EDGE64_LENGTH_OPCODE);
assign subop_is_stream  = control_opcode8[7] &&
                          ((subop == DMA_START)     ||
                           (subop == DMA_SYNC)      ||
                           (subop == DMA_SETN)      ||
                           (subop == DMA_SETENTRY)  ||
                           (subop == DMA_SETX)      ||
                           (subop == DMA_SETY)      ||
                           (subop == DMA_SETSRC)    ||
                           (subop == DMA_SETTAR)    ||
                           (subop == TENSOR_SETCSR) ||
                           (subop == TENSOR_WLD)    ||
                           (subop == TENSOR_SETIN)  ||
                           (subop == TENSOR_SETOUT) ||
                           (subop == TENSOR_SETPSUM)||
                           (subop == TENSOR_START)  ||
                           (subop == TENSOR_SYNC)   ||
                           (subop == TENSOR_SETN)   ||
                           (subop == TENSOR_WLD_T)  ||
                           (subop == TENSOR_START_TILE) ||
                           (subop == TENSOR_SLD_STREAM) ||
                           (subop == TENSOR_WLD_CIRCULAR) ||
                           (subop == TENSOR_WLD_T_CIRCULAR) ||
                           (subop == TENSOR_SLD) ||
                           (subop == TENSOR_WSLD_CIRCULAR) ||
                           (subop == TENSOR_SLD_CIRCULAR) ||
                           (subop == ACTU_SETCSR) ||
                           (subop == ACTU_SETIN) ||
                           (subop == ACTU_SETOUT) ||
                           (subop == ACTU_SETN) ||
                           (subop == ACTU_SETSCALAR) ||
                           (subop == ACTU_START) ||
                           (subop == ACTU_SYNC) ||
                           (subop == CMPU_SETCSR) ||
                           (subop == CMPU_SETLHS) ||
                           (subop == CMPU_SETRHS) ||
                           (subop == CMPU_SETMASK) ||
                           (subop == CMPU_SETOUT) ||
                           (subop == CMPU_SETN) ||
                           (subop == CMPU_START) ||
                           (subop == CMPU_SYNC) ||
                           (subop == ACCEL_GETCSR));
assign needs_capture    = (is_wld && !is_wld_reuse) ||
                          (is_sld && !is_sld_reuse) ||
                          is_sld_stream ||
                          (subop == TENSOR_SETIN)  ||
                          (subop == TENSOR_SETOUT) ||
                          (subop == TENSOR_SETPSUM)||
                          (subop == ACTU_SETIN)    ||
                          (subop == ACTU_SETOUT)   ||
                          (subop == ACTU_SETSCALAR)||
                          (subop == TENSOR_SETN)   ||
                          (subop == ACTU_SETN)     ||
                          (subop == CMPU_SETLHS)   ||
                          (subop == CMPU_SETRHS)   ||
                          (subop == CMPU_SETMASK)  ||
                          (subop == CMPU_SETOUT)   ||
                          (subop == CMPU_SETN)     ||
                          (subop == DMA_SETN)      ||
                          (subop == DMA_SETENTRY)  ||
                          (subop == DMA_SETX)      ||
                          (subop == DMA_SETY)      ||
                          (subop == DMA_SETSRC)    ||
                          (subop == DMA_SETTAR)    ||
                          (subop == DMA_START);
assign is_dma_start     = (subop == DMA_START);
assign is_dma_start_circular = is_dma_start && control_imm8[1];
assign is_dma_set       = (subop == DMA_SETN) ||
                          (subop == DMA_SETENTRY) ||
                          (subop == DMA_SETX) ||
                          (subop == DMA_SETY) ||
                          (subop == DMA_SETSRC) ||
                          (subop == DMA_SETTAR);
assign is_dma_sync      = (subop == DMA_SYNC);
assign is_start         = (subop == TENSOR_START) || (subop == TENSOR_START_TILE);
assign is_wld           = (subop == TENSOR_WLD) || (subop == TENSOR_WLD_T);
assign is_wld_reuse     = is_wld && control_imm8[1];
assign is_wld_circular  = (subop == TENSOR_WLD_CIRCULAR) ||
                          (subop == TENSOR_WLD_T_CIRCULAR);
assign is_sld           = (subop == TENSOR_SLD);
assign is_sld_reuse     = is_sld && control_imm8[1];
assign is_sld_stream    = (subop == TENSOR_SLD_STREAM);
assign is_wsld_circular = (subop == TENSOR_WSLD_CIRCULAR);
assign is_sld_circular = (subop == TENSOR_SLD_CIRCULAR);
assign is_actu_setup    = (subop == ACTU_SETCSR) ||
                          (subop == ACTU_SETIN) ||
                          (subop == ACTU_SETOUT) ||
                          (subop == ACTU_SETN) ||
                          (subop == ACTU_SETSCALAR);
assign is_actu_start    = (subop == ACTU_START);
assign is_actu_sync     = (subop == ACTU_SYNC);
assign is_cmpu_setup    = (subop == CMPU_SETCSR) ||
                          (subop == CMPU_SETLHS) ||
                          (subop == CMPU_SETRHS) ||
                          (subop == CMPU_SETMASK) ||
                          (subop == CMPU_SETOUT) ||
                          (subop == CMPU_SETN);
assign is_cmpu_start    = (subop == CMPU_START);
assign is_cmpu_sync     = (subop == CMPU_SYNC);
assign is_accel_getcsr  = (subop == ACCEL_GETCSR);
assign getcsr_csr_valid = control_imm8[3:0] <= CSR_ACTU_EXP_SUM;
assign is_sync          = (subop == TENSOR_SYNC) || is_dma_sync ||
                          is_actu_sync || is_cmpu_sync;

assign decode_illegal   = cmd_valid &&
                          (!opcode_is_edge64 || !subop_is_stream ||
                           (is_accel_getcsr && !getcsr_csr_valid));
assign tensor_ready_for_target =
    is_sync ? !tensor_sync_stall :
    (is_start ? tensor_start_ready :
     (is_sld ? tensor_sld_cmd_ready :
      (is_sld_circular ? tensor_sld_circular_ready :
       (is_wsld_circular ? tensor_wsld_circular_ready :
       (is_wld_circular ? tensor_wld_circular_ready :
        (is_wld ? tensor_wld_cmd_ready : tensor_cmd_ready))))));
assign actu_ready_for_target =
    is_actu_sync ? !actu_sync_stall :
    (is_actu_start ? actu_start_ready : actu_cmd_ready);
assign cmpu_ready_for_target =
    is_cmpu_sync ? !cmpu_sync_stall :
    (is_cmpu_start ? cmpu_start_ready : cmpu_cmd_ready);
assign getcsr_owner_idle = (control_imm8[3:0] <= CSR_CMPU_ARGMIN_IDX) ?
                           !cmpu_sync_stall :
                           ((control_imm8[3:0] == CSR_ACTU_EXP_SUM) ?
                            !actu_sync_stall : 1'b1);
assign getcsr_ready_for_target = reverse_snapshot_write_ready &&
                                 getcsr_owner_idle;
assign ready_for_target = is_dma_start ?
                          (is_dma_start_circular ? dma_start_circular_ready
                                                 : dma_start_ready) :
                          (is_dma_sync ? dma_sync_done :
                           (is_accel_getcsr ? getcsr_ready_for_target :
                           ((is_cmpu_setup || is_cmpu_start || is_cmpu_sync)
                            ? cmpu_ready_for_target :
                           ((is_actu_setup || is_actu_start || is_actu_sync)
                            ? actu_ready_for_target
                            : tensor_ready_for_target))));
assign cmd_ready        = decode_illegal ||
                          (subop_is_stream &&
                           (!needs_capture || cmd_capture_valid) &&
                           ready_for_target);
assign cmd_fire         = cmd_valid && cmd_ready && !decode_illegal &&
                          subop_is_stream && opcode_is_edge64;
assign capture_is_dtcm_ptr = edge_dtcm_enable &&
       ((cmd_capture_value[PA_WIDTH-1:0] & edge_dtcm_mask[PA_WIDTH-1:0]) ==
        edge_dtcm_base[PA_WIDTH-1:0]);
assign capture_dtcm_byte_offset[PA_WIDTH-1:0] =
       cmd_capture_value[PA_WIDTH-1:0] - edge_dtcm_base[PA_WIDTH-1:0];
assign capture_dtcm_word_addr[ADDR_WIDTH-1:0] =
       capture_dtcm_byte_offset[ADDR_WIDTH+2:3];
assign capture_addr[ADDR_WIDTH-1:0] =
       capture_is_dtcm_ptr ? capture_dtcm_word_addr[ADDR_WIDTH-1:0]
                           : cmd_capture_value[ADDR_WIDTH-1:0];

assign capture_consume_valid = cmd_fire && needs_capture;
// A start may be accepted into the tensor unit's pending state before an
// engine slot opens.  Its completion is reported by the tensor unit at the
// actual launch point, so later WLD commands are not held behind it here.
assign tensor_done_valid     = cmd_fire && !is_start;
assign tensor_done_seq_id    = cmd_seq_id;
assign tensor_done_epoch     = cmd_epoch;

assign dma_start_req     = cmd_fire && is_dma_start;
assign dma_start_circular_req = dma_start_req && dma_start_circular;
assign dma_start_src     = dma_src_q;
assign dma_start_dst     = dma_tar_q;
assign dma_start_use_xy  = control_imm8[0];
assign dma_start_circular = control_imm8[1];
assign dma_start_len     = dma_start_use_xy ? dma_n_q[31:0]
                                                : cmd_capture_value[31:0];
assign dma_start_entry_bytes = dma_entry_q[31:0];
assign dma_start_x       = dma_x_q[63:0];
assign dma_start_y       = dma_y_q[63:0];
// The rd operand is the circular ring depth in DMA entries.  Entry size comes
// from setn in XY mode (64B for legacy WLD, 272B for grouped WSLD).  The
// descriptor transfer count is x_max*y_max from packed setx/sety.
assign dma_start_circular_tiles = cmd_capture_value[15:0];
assign dma_sync_req      = cmd_fire && is_dma_sync;

always @(posedge forever_cpuclk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    dma_n_q[31:0] <= 32'b0;
    dma_entry_q[31:0] <= 32'b0;
    dma_x_q[63:0] <= 64'b0;
    dma_y_q[63:0] <= 64'b0;
    dma_src_q[63:0] <= 64'b0;
    dma_tar_q[63:0] <= 64'b0;
  end else if (cmd_fire && is_dma_set) begin
    if (subop == DMA_SETN)
      dma_n_q[31:0] <= cmd_capture_value[31:0];
    if (subop == DMA_SETENTRY)
      dma_entry_q[31:0] <= cmd_capture_value[31:0];
    else if (subop == DMA_SETX)
      dma_x_q[63:0] <= cmd_capture_value[63:0];
    else if (subop == DMA_SETY)
      dma_y_q[63:0] <= cmd_capture_value[63:0];
    else if (subop == DMA_SETSRC)
      dma_src_q[63:0] <= cmd_capture_value[63:0];
    else
      dma_tar_q[63:0] <= cmd_capture_value[63:0];
  end
end

assign cmd_setcsr_req   = cmd_fire && (subop == TENSOR_SETCSR);
assign cmd_setcsr_dtype = control_imm8[3:0];
assign cmd_setcsr_wtype = control_imm8[7:4];

assign cmd_wld_req      = cmd_fire && (subop == TENSOR_WLD);
assign cmd_wld_circular_req = cmd_fire && is_wld_circular;
assign cmd_wld_trans_req= cmd_fire && ((subop == TENSOR_WLD_T) ||
                                       (subop == TENSOR_WLD_T_CIRCULAR));
assign cmd_wld_reuse    = control_imm8[1] && is_wld;
assign cmd_wld_ptr      = capture_addr;

assign cmd_setin_req    = cmd_fire && (subop == TENSOR_SETIN);
assign cmd_setin_ptr    = capture_addr;

assign cmd_setout_req   = cmd_fire && (subop == TENSOR_SETOUT);
assign cmd_setout_ptr   = capture_addr;

assign cmd_setpsum_req  = cmd_fire && (subop == TENSOR_SETPSUM);
assign cmd_setpsum_ptr  = capture_addr;

assign cmd_setn_req     = cmd_fire && (subop == TENSOR_SETN);
assign cmd_setn_value   = cmd_capture_value[15:0];

assign cmd_start_req    = cmd_fire && (subop == TENSOR_START);
assign cmd_start_tile_req = cmd_fire && (subop == TENSOR_START_TILE);
assign cmd_start_mode[7:0] = control_imm8;
assign cmd_sync_req     = cmd_fire && (subop == TENSOR_SYNC);

assign cmd_sld_req      = cmd_fire && is_sld;
assign cmd_sld_reuse    = control_imm8[1] && is_sld;
assign cmd_sld_ptr      = capture_addr;
assign cmd_sld_stream_ptr = capture_addr;
assign cmd_sld_stream_req = cmd_fire && is_sld_stream;
assign cmd_wsld_circular_req = cmd_fire && is_wsld_circular;
assign cmd_wsld_circular_transpose = control_imm8[0];
assign cmd_sld_circular_req = cmd_fire && is_sld_circular;

assign actu_cmd_setcsr_req = cmd_fire && (subop == ACTU_SETCSR);
assign actu_cmd_setcsr_dtype = control_imm8[3:0];
assign actu_cmd_setcsr_mode = control_imm8[7:4];
assign actu_cmd_setin_req = cmd_fire && (subop == ACTU_SETIN);
assign actu_cmd_setin_ptr = capture_addr;
assign actu_cmd_setout_req = cmd_fire && (subop == ACTU_SETOUT);
assign actu_cmd_setout_ptr = capture_addr;
assign actu_cmd_setn_req = cmd_fire && (subop == ACTU_SETN);
assign actu_cmd_setn_value = cmd_capture_value[15:0];
assign actu_cmd_setscalar_req = cmd_fire && (subop == ACTU_SETSCALAR);
assign actu_cmd_setscalar_value = cmd_capture_value[VALUE_WIDTH-1:0];
assign actu_cmd_start_req = cmd_fire && is_actu_start;
assign actu_cmd_sync_req = cmd_fire && is_actu_sync;

assign cmpu_cmd_setcsr_req = cmd_fire && (subop == CMPU_SETCSR);
assign cmpu_cmd_setcsr_mode = control_imm8[3:0];
assign cmpu_cmd_setlhs_req = cmd_fire && (subop == CMPU_SETLHS);
assign cmpu_cmd_setlhs_ptr = capture_addr;
assign cmpu_cmd_setrhs_req = cmd_fire && (subop == CMPU_SETRHS);
assign cmpu_cmd_setrhs_ptr = capture_addr;
assign cmpu_cmd_setmask_req = cmd_fire && (subop == CMPU_SETMASK);
assign cmpu_cmd_setmask_ptr = capture_addr;
assign cmpu_cmd_setout_req = cmd_fire && (subop == CMPU_SETOUT);
assign cmpu_cmd_setout_ptr = capture_addr;
assign cmpu_cmd_setn_req = cmd_fire && (subop == CMPU_SETN);
assign cmpu_cmd_setn_value = cmd_capture_value[15:0];
assign cmpu_cmd_start_req = cmd_fire && is_cmpu_start;
assign cmpu_cmd_sync_req = cmd_fire && is_cmpu_sync;

assign reverse_snapshot_write_valid = cmd_fire && is_accel_getcsr;
assign reverse_snapshot_write_id = control_imm8[4];
assign reverse_snapshot_write_value =
  (control_imm8[3:0] == CSR_CMPU_MAX_VALUE) ?
    {{(VALUE_WIDTH-16){1'b0}}, cmpu_max_value} :
  (control_imm8[3:0] == CSR_CMPU_ARGMAX_IDX) ?
    {{(VALUE_WIDTH-16){1'b0}}, cmpu_argmax_idx} :
  (control_imm8[3:0] == CSR_CMPU_MIN_VALUE) ?
    {{(VALUE_WIDTH-16){1'b0}}, cmpu_min_value} :
  (control_imm8[3:0] == CSR_CMPU_ARGMIN_IDX) ?
    {{(VALUE_WIDTH-16){1'b0}}, cmpu_argmin_idx} :
  (control_imm8[3:0] == CSR_ACTU_EXP_SUM) ?
    {{(VALUE_WIDTH-32){1'b0}}, actu_last_sum_bits} :
    {VALUE_WIDTH{1'b0}};

endmodule
