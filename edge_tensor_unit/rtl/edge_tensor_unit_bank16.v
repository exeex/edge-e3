module edge_tensor_unit_bank16 #(
  parameter ADDR_WIDTH = 16,
  parameter BANK_NUM = 16,
  parameter BANK_INDEX_WIDTH = 4,
  parameter SRAM_ADDR_WIDTH = 10,
  parameter DATA_WIDTH = 64,
  parameter VECTOR_COUNT_WIDTH = 16,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter READ_LATENCY = 1,
  parameter LOWER_SIX = 0,
  parameter PACKED_WEIGHT = 0
) (
  input  wire                         clk,
  input  wire                         cpurst_b,

  input  wire [3:0]                   cmd_setcsr_dtype,
  input  wire                         cmd_setcsr_req,
  input  wire [3:0]                   cmd_setcsr_wtype,
  input  wire [ADDR_WIDTH-1:0]        cmd_setin_ptr,
  input  wire                         cmd_setin_req,
  input  wire                         cmd_setn_req,
  input  wire [15:0]                  cmd_setn_value,
  input  wire [ADDR_WIDTH-1:0]        cmd_setout_ptr,
  input  wire                         cmd_setout_req,
  input  wire [ADDR_WIDTH-1:0]        cmd_setpsum_ptr,
  input  wire                         cmd_setpsum_req,
  input  wire                         cmd_start_req,
  input  wire                         cmd_start_tile_req,
  input  wire [7:0]                   cmd_start_mode,
  input  wire [SEQ_ID_WIDTH-1:0]      cmd_start_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       cmd_start_epoch,
  input  wire [ADDR_WIDTH-1:0]        cmd_wld_ptr,
  input  wire                         cmd_wld_req,
  input  wire                         cmd_wld_trans_req,
  input  wire                         cmd_wld_reuse,
  input  wire [ADDR_WIDTH-1:0]        cmd_sld_ptr,
  input  wire                         cmd_sld_req,
  input  wire                         cmd_sld_reuse,
  input  wire                         cmd_sld_stream,
  input  wire [ADDR_WIDTH-1:0]        cmd_sld_stream_setup_ptr,
  input  wire                         cmd_sld_stream_setup_req,

  output wire                         tensor_busy,
  output wire                         tensor_cmd_ready,
  output wire                         tensor_start_ready,
  output wire                         tensor_wld_cmd_ready,
  output wire                         tensor_sld_cmd_ready,
  output wire                         tensor_sld_fill_done,
  output wire [ADDR_WIDTH-1:0]        tensor_sld_addr,
  output wire                         tensor_sld_req,
  input  wire                         tensor_sld_ready,
  input  wire [127:0]                 tensor_sld_rdata,
  input  wire                         tensor_sld_rvalid,
  output wire [ADDR_WIDTH-1:0]        tensor_wld_addr,
  output wire                         tensor_wld_req,
  input  wire                         tensor_wld_ready,
  input  wire [127:0]                 tensor_wld_rdata,
  input  wire                         tensor_wld_rvalid,
  output wire                         tensor_wld_fill_done,
  output wire [4:0]                   tensor_wld_tile_words,
  output wire                         tensor_sync_stall,
  output wire                         tensor_start_retire_valid,
  output wire [SEQ_ID_WIDTH-1:0]      tensor_start_retire_seq_id,
  output wire [EPOCH_WIDTH-1:0]       tensor_start_retire_epoch,

  output wire [7:0]                   tensor_io_lease_channel_mask,
  output wire [8:0]                   tensor_io_lease_cycles,
  output wire [3:0]                   tensor_io_lease_delay,
  output wire [7:0]                   tensor_io_lease1_channel_mask,
  output wire [8:0]                   tensor_io_lease1_cycles,
  output wire [3:0]                   tensor_io_lease1_delay,
  output wire                         tensor_io_lease1_valid,
  output wire [7:0]                   tensor_io_lease2_channel_mask,
  output wire [8:0]                   tensor_io_lease2_cycles,
  output wire [3:0]                   tensor_io_lease2_delay,
  output wire                         tensor_io_lease2_valid,
  output wire                         tensor_io_lease_valid,
  output wire [7:0]                   tensor_wld_lease_channel_mask,
  output wire [8:0]                   tensor_wld_lease_cycles,
  output wire [3:0]                   tensor_wld_lease_delay,
  output wire                         tensor_wld_lease_valid,

  output wire [BANK_NUM-1:0]          tensor_bank_req,
  output wire [BANK_NUM-1:0]          tensor_bank_we,
  output wire [BANK_NUM*SRAM_ADDR_WIDTH-1:0] tensor_bank_addr,
  output wire [BANK_NUM*DATA_WIDTH-1:0] tensor_bank_wdata,
  output wire [BANK_NUM*(DATA_WIDTH/8)-1:0] tensor_bank_wstrb,
  input  wire [BANK_NUM*DATA_WIDTH-1:0] tensor_bank_rdata,
  output wire [BANK_NUM-1:0]          tensor_active_mask,
  input  wire [BANK_INDEX_WIDTH-1:0]  tensor_phase
);

localparam BYTE_WIDTH = DATA_WIDTH / 8;
localparam BYTE_INDEX_WIDTH = $clog2(BYTE_WIDTH);
localparam PAIR_WIDTH = DATA_WIDTH * 2;

reg  [3:0]                    cfg_dtype_q [0:1];
reg  [3:0]                    cfg_wtype_q [0:1];
reg  [ADDR_WIDTH-1:0]         cfg_in_ptr_q [0:1];
reg  [ADDR_WIDTH-1:0]         cfg_out_ptr_q [0:1];
reg  [ADDR_WIDTH-1:0]         cfg_psum_ptr_q [0:1];
reg  [VECTOR_COUNT_WIDTH-1:0] cfg_run_count_q [0:1];
reg                           cfg_write_sel_q;
reg                           weight_loaded_q;
reg                           weight_reuse_token_q;
reg                           queued_start_valid_q;
reg                           queued_start_preactivated_q;
reg  [7:0]                    queued_start_mode_q;
reg                           queued_start_reuse_weight_q;
reg                           queued_start_scale_sel_q;
reg  [SEQ_ID_WIDTH-1:0]       queued_start_seq_id_q;
reg  [EPOCH_WIDTH-1:0]        queued_start_epoch_q;
reg  [VECTOR_COUNT_WIDTH-1:0] queued_count_q;
reg  [ADDR_WIDTH-1:0]         queued_in_q;
reg  [ADDR_WIDTH-1:0]         queued_out_q;
reg  [ADDR_WIDTH-1:0]         queued_psum_q;
reg                           start_pending_q;
reg  [VECTOR_COUNT_WIDTH-1:0] start_pending_count_q;
reg  [ADDR_WIDTH-1:0]         start_pending_in_q;
reg  [ADDR_WIDTH-1:0]         start_pending_out_q;
reg  [ADDR_WIDTH-1:0]         start_pending_psum_q;
reg                           start_pending_wld_pending_q;
reg  [7:0]                    start_pending_mode_q;
reg                           start_pending_reuse_weight_q;
reg                           start_pending_scale_sel_q;
reg  [SEQ_ID_WIDTH-1:0]       start_pending_seq_id_q;
reg  [EPOCH_WIDTH-1:0]        start_pending_epoch_q;
reg                           wld_cmd_pending_q;
reg                           wld_cmd_pending_transpose_q;
reg                           wld_cmd_pending_bf16_q;
reg  [ADDR_WIDTH-1:0]         wld_cmd_pending_ptr_q;
reg                           wld_cmd_pending_next_q;
reg                           wld_cmd_pending_next_transpose_q;
reg                           wld_cmd_pending_next_bf16_q;
reg  [ADDR_WIDTH-1:0]         wld_cmd_pending_next_ptr_q;
reg                           wld_active_q;
reg                           wld_active_bf16_q;
reg  [ADDR_WIDTH-1:0]         wld_base_q;
reg  [2:0]                    wld_issue_idx_q;
reg  [3:0]                    wld_read_count_q;
wire [2:0] wld_rsp_idx_q;
reg [2:0] wld_tag_pipe [0:READ_LATENCY-1];
integer wld_stage;
wire [BANK_INDEX_WIDTH-1:0] engine_host_rsp_bank;
reg  [127:0]                  scale_buf_q [0:1];
reg                           scale_active_sel_q;
reg                           scale_active_valid_q;
reg                           scale_pending_sel_q;
reg                           scale_pending_valid_q;
reg                           sld_pending_q;
reg                           sld_wait_q;
reg  [ADDR_WIDTH-1:0]         sld_ptr_q;
reg                           sld_load_sel_q;
reg                           sld_stream_q;
reg  [127:0]                 scale_stream_fifo_q [0:7];
reg  [2:0]                   scale_stream_head_q;
reg  [2:0]                   scale_stream_tail_q;
reg  [3:0]                   scale_stream_count_q;
reg                          direct_sld_setup_valid_q;
reg                          direct_sld_active_q;
reg  [ADDR_WIDTH-1:0]        direct_sld_next_ptr_q;
reg  [VECTOR_COUNT_WIDTH-1:0] direct_sld_target_q;
reg  [VECTOR_COUNT_WIDTH-1:0] direct_sld_issued_q;
reg  [VECTOR_COUNT_WIDTH-1:0] direct_sld_received_q;
reg                           copy_active_q;
reg                           copy_write_q;
reg  [ADDR_WIDTH-1:0]         copy_in_q;
reg  [ADDR_WIDTH-1:0]         copy_out_q;
reg  [VECTOR_COUNT_WIDTH-1:0] copy_bytes_q;
reg  [VECTOR_COUNT_WIDTH-1:0] copy_offset_q;
reg  [DATA_WIDTH-1:0]         copy_data_q;

wire                          engine_busy;
wire                          engine_done;
wire                          engine_handoff_ready;
wire                          engine_weight_idle;
wire                          engine_start;
wire                          engine_weight_preactivate;
wire                          queued_weight_preactivate;
wire                          wld_replace_preactivate;
wire                          engine_start_use_active;
wire                          tensor_weight_active_valid;
wire                          start_weight_available;
wire                          start_pending_weight_available;
wire                          start_uses_pending_weight;
wire                          start_uses_reuse_weight;
wire                          start_accept;
wire                          start_direct_accept;
wire                          start_queue_accept;
wire                          start_wait_accept;
wire                          start_pending_direct_launch;
wire                          start_pending_queue_launch;
wire                          start_consume_weight;
wire [15:0]                   start_data_run_count;
wire [ADDR_WIDTH-1:0]         start_data_in;
wire [ADDR_WIDTH-1:0]         start_data_out;
wire [ADDR_WIDTH-1:0]         start_data_psum;
wire [ADDR_WIDTH-1:0]         engine_start_in;
wire [ADDR_WIDTH-1:0]         engine_start_out;
wire [ADDR_WIDTH-1:0]         engine_start_psum;
wire [VECTOR_COUNT_WIDTH-1:0] engine_start_count;
wire                          start_data_scale_sel;
wire [7:0]                    engine_start_mode;
wire                          engine_start_scale_sel;
wire [127:0]                  engine_start_scale;
wire                          wld_cmd_accept;
wire                          wld_reuse_accept;
wire                          sld_reuse_accept;
wire                          wld_cmd_can_launch;
wire                          wld_cmd_immediate_launch;
wire                          wld_cmd_pending_launch;
wire                          wld_cmd_launch;
wire [ADDR_WIDTH-1:0]         wld_cmd_launch_ptr;
wire                          wld_cmd_launch_transpose;
wire                          wld_cmd_launch_bf16;
wire                          wld_fill_start_ready;
wire                          wld_fill_done;
wire                          wld_read_fire;
wire                          wld_bank_conflict;
wire                          cfg_cmd_ready;
wire [ADDR_WIDTH-1:0]         wld_req_addr;
wire [BANK_NUM-1:0]           wld_req_mask;
wire [PAIR_WIDTH-1:0]         wld_load_data;
wire                          tensor_weight_fill_start;
wire                          tensor_weight_fill_bf16_mode;
wire                          tensor_weight_fill_start_ready;
wire                          tensor_weight_fill_valid;
wire                          tensor_weight_fill_ready;
wire [1:0]                    tensor_weight_fill_pair_idx;
wire [PAIR_WIDTH-1:0]         tensor_weight_fill_data;
wire                          tensor_weight_fill_last;
wire                          tensor_weight_pending_valid;
wire                          packed_weight_start_ready;
wire                          packed_weight_busy;
wire                          packed_weight_done;
wire                          packed_weight_load_ready;
wire [BANK_NUM-1:0]           engine_bank_req;
wire [BANK_NUM-1:0]           engine_bank_we;
wire [BANK_NUM*SRAM_ADDR_WIDTH-1:0] engine_bank_addr;
wire [BANK_NUM*DATA_WIDTH-1:0] engine_bank_wdata;
wire [BANK_NUM*BYTE_WIDTH-1:0] engine_bank_wstrb;
wire                          engine_host_bank_req;
wire                          engine_host_bank_we;
wire [BANK_INDEX_WIDTH-1:0]   engine_host_bank;
wire [SRAM_ADDR_WIDTH-1:0]    engine_host_bank_addr;
wire [DATA_WIDTH-1:0]         engine_host_bank_wdata;
wire [BYTE_WIDTH-1:0]         engine_host_bank_wstrb;
wire [DATA_WIDTH-1:0]         engine_host_bank_rdata;
wire                          engine_host_ready;
wire [DATA_WIDTH-1:0]         engine_host_rdata;
wire                          engine_host_rvalid;
wire                          engine_i_pair_req;
wire [BANK_INDEX_WIDTH-1:0]   engine_i_pair_bank0;
wire [BANK_INDEX_WIDTH-1:0]   engine_i_pair_bank1;
wire [SRAM_ADDR_WIDTH-1:0]    engine_i_pair_addr;
wire [BANK_INDEX_WIDTH-1:0]   engine_i_pair_rsp_bank0;
wire [BANK_INDEX_WIDTH-1:0]   engine_i_pair_rsp_bank1;
wire [PAIR_WIDTH-1:0]         engine_i_pair_rdata;
wire                          engine_psum_pair_req;
wire [BANK_INDEX_WIDTH-1:0]   engine_psum_pair_bank0;
wire [BANK_INDEX_WIDTH-1:0]   engine_psum_pair_bank1;
wire [SRAM_ADDR_WIDTH-1:0]    engine_psum_pair_addr;
wire [BANK_INDEX_WIDTH-1:0]   engine_psum_pair_rsp_bank0;
wire [BANK_INDEX_WIDTH-1:0]   engine_psum_pair_rsp_bank1;
wire [PAIR_WIDTH-1:0]         engine_psum_pair_rdata;
wire                          engine_o_pair_req;
wire [BANK_INDEX_WIDTH-1:0]   engine_o_pair_bank0;
wire [BANK_INDEX_WIDTH-1:0]   engine_o_pair_bank1;
wire [SRAM_ADDR_WIDTH-1:0]    engine_o_pair_addr;
wire [PAIR_WIDTH-1:0]         engine_o_pair_wdata;
wire                          stream_out_push;
wire                          stream_i_prefetch_accept;
wire                          stream_psum_prefetch_accept;
wire                          start_queue_launch;
wire                          unused_cmd_bits;
wire                          engine_scale_stream_ready;
wire                          scale_stream_push;
wire                          direct_sld_launch;
wire [BANK_NUM-1:0]           lower_owned_mask;
wire                          wld_req_owned;
wire                          copy_mode_req;
wire                          copy_start_accept;
wire                          copy_host_req;
wire                          copy_host_we;
wire [ADDR_WIDTH-1:0]         copy_host_addr;
wire [BYTE_WIDTH-1:0]         copy_host_wstrb;
genvar                        bank_gen_i;

function [BANK_NUM-1:0] pair_mask;
  input [ADDR_WIDTH-1:0] addr;
  integer i;
  reg [ADDR_WIDTH-1:0] addr_next;
begin
  addr_next = addr + {{ADDR_WIDTH-1{1'b0}}, 1'b1};
  pair_mask[BANK_NUM-1:0] = {BANK_NUM{1'b0}};
  for (i = 0; i < BANK_NUM; i = i + 1) begin
    if (addr[BANK_INDEX_WIDTH-1:0] == i[BANK_INDEX_WIDTH-1:0])
      pair_mask[i] = 1'b1;
    if (addr_next[BANK_INDEX_WIDTH-1:0] == i[BANK_INDEX_WIDTH-1:0])
      pair_mask[i] = 1'b1;
  end
end
endfunction

function [DATA_WIDTH-1:0] bank_data;
  input [BANK_NUM*DATA_WIDTH-1:0] data;
  input [BANK_INDEX_WIDTH-1:0] bank;
begin
  bank_data[DATA_WIDTH-1:0] = data[bank*DATA_WIDTH +: DATA_WIDTH];
end
endfunction

function [BANK_INDEX_WIDTH-1:0] next_bank;
  input [ADDR_WIDTH-1:0] addr;
begin
  next_bank[BANK_INDEX_WIDTH-1:0] =
      addr[BANK_INDEX_WIDTH-1:0] + {{BANK_INDEX_WIDTH-1{1'b0}}, 1'b1};
end
endfunction

assign tensor_busy = engine_busy
                  || copy_active_q
                  || queued_start_valid_q
                  || start_pending_q
                  || wld_cmd_pending_q
                  || wld_cmd_pending_next_q
                  || wld_active_q
                  || sld_pending_q
                  || sld_wait_q
                  || direct_sld_active_q
                  || (scale_stream_count_q != 0);
assign cfg_cmd_ready = !queued_start_valid_q && !start_pending_q;
assign tensor_cmd_ready = cfg_cmd_ready;
assign tensor_start_ready = !queued_start_valid_q
                         && !start_pending_q
                         && (!cmd_start_mode[0]
                             || cmd_start_mode[3]
                             || cmd_start_mode[4]
                             || scale_pending_valid_q)
                         && (cmd_start_mode[5]
                             ? (!engine_busy && !copy_active_q)
                             : start_weight_available);
assign tensor_wld_cmd_ready = cmd_wld_reuse
                            ? (tensor_weight_active_valid
                               && !tensor_weight_pending_valid
                               && !weight_loaded_q
                               && !weight_reuse_token_q
                               && !wld_active_q
                               && !wld_cmd_pending_q
                               && !wld_cmd_pending_next_q
                               && !queued_start_valid_q
                               && !start_pending_q)
                            : (!wld_cmd_pending_next_q
                               && !weight_reuse_token_q
                               && !queued_start_valid_q
                               && !start_pending_q);
assign tensor_sld_cmd_ready = cmd_sld_reuse
                            ? (scale_active_valid_q
                               && !sld_pending_q
                               && !sld_wait_q
                               && !scale_pending_valid_q
                               && !queued_start_valid_q
                               && !start_pending_q)
                            : (!sld_pending_q
                               && !sld_wait_q
                               && !scale_pending_valid_q
                               && (scale_stream_count_q != 4'd8)
                               && !queued_start_valid_q
                               && !start_pending_q);
assign tensor_sld_addr[ADDR_WIDTH-1:0] = sld_ptr_q[ADDR_WIDTH-1:0];
assign tensor_sld_req = sld_pending_q && !sld_wait_q;
assign tensor_sld_fill_done = tensor_sld_rvalid && sld_wait_q;
assign scale_stream_push = tensor_sld_rvalid && sld_wait_q && sld_stream_q;
assign tensor_wld_fill_done = wld_fill_done;
assign tensor_wld_tile_words[4:0] =
    (cfg_wtype_q[cfg_write_sel_q][3:0] == 4'd1) ? 5'd16 : 5'd8;
always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    for (wld_stage=0; wld_stage<READ_LATENCY; wld_stage=wld_stage+1)
      wld_tag_pipe[wld_stage] <= 0;
  end else begin
    wld_tag_pipe[0] <= wld_issue_idx_q;
    for (wld_stage=1; wld_stage<READ_LATENCY; wld_stage=wld_stage+1)
      wld_tag_pipe[wld_stage] <= wld_tag_pipe[wld_stage-1];
  end
end
assign wld_rsp_idx_q = wld_tag_pipe[READ_LATENCY-1];

assign tensor_sync_stall = engine_busy
                         || copy_active_q
                         || queued_start_valid_q
                         || start_pending_q
                         || wld_cmd_pending_q
                         || wld_cmd_pending_next_q
                         || wld_active_q
                         || sld_pending_q
                         || sld_wait_q
                         || direct_sld_active_q
                         || (scale_stream_count_q != 0);
assign direct_sld_launch = direct_sld_active_q
                        && (direct_sld_issued_q < direct_sld_target_q)
                        && !sld_pending_q && !sld_wait_q
                        && (scale_stream_count_q != 4'd8);

assign tensor_io_lease_channel_mask[7:0] = 8'b0;
assign tensor_io_lease_cycles[8:0] = 9'b0;
assign tensor_io_lease_delay[3:0] = 4'b0;
assign tensor_io_lease1_channel_mask[7:0] = 8'b0;
assign tensor_io_lease1_cycles[8:0] = 9'b0;
assign tensor_io_lease1_delay[3:0] = 4'b0;
assign tensor_io_lease1_valid = 1'b0;
assign tensor_io_lease2_channel_mask[7:0] = 8'b0;
assign tensor_io_lease2_cycles[8:0] = 9'b0;
assign tensor_io_lease2_delay[3:0] = 4'b0;
assign tensor_io_lease2_valid = 1'b0;
assign tensor_io_lease_valid = 1'b0;
assign tensor_wld_lease_channel_mask[7:0] = 8'b0;
assign tensor_wld_lease_cycles[8:0] = 9'b0;
assign tensor_wld_lease_delay[3:0] = 4'b0;
assign tensor_wld_lease_valid = 1'b0;
assign tensor_active_mask[BANK_NUM-1:0] = tensor_bank_req[BANK_NUM-1:0];
assign start_accept = (cmd_start_req || cmd_start_tile_req)
                   && tensor_start_ready;
assign copy_mode_req = cmd_start_req && cmd_start_mode[5];
assign copy_start_accept = start_accept && copy_mode_req;
assign start_weight_available =
    weight_reuse_token_q
    || weight_loaded_q
    || wld_active_q
    || wld_cmd_pending_q
    || wld_cmd_pending_next_q;
assign start_pending_weight_available =
    start_pending_reuse_weight_q ? tensor_weight_active_valid
                                 : weight_loaded_q;
assign start_uses_pending_weight =
    (start_direct_accept && weight_loaded_q)
    || (start_queue_accept && weight_loaded_q)
    || (start_pending_direct_launch && weight_loaded_q)
    || (start_pending_queue_launch && weight_loaded_q);
assign start_uses_reuse_weight =
    (start_direct_accept && weight_reuse_token_q)
    || (start_queue_accept && weight_reuse_token_q)
    || (start_pending_direct_launch && start_pending_reuse_weight_q)
    || (start_pending_queue_launch && start_pending_reuse_weight_q);
assign start_direct_accept =
    start_accept && !copy_mode_req
    && (weight_reuse_token_q || weight_loaded_q)
    && !queued_start_valid_q && !engine_busy;
assign start_queue_accept =
    start_accept && !copy_mode_req
    && (weight_reuse_token_q || weight_loaded_q)
    && !queued_start_valid_q && engine_busy;
assign start_wait_accept = start_accept
                        && !copy_mode_req
                        && !((weight_reuse_token_q || weight_loaded_q)
                             && !queued_start_valid_q);
assign start_pending_direct_launch =
    start_pending_q && start_pending_weight_available
    && !queued_start_valid_q && !engine_busy;
assign start_pending_queue_launch =
    start_pending_q && start_pending_weight_available
    && !queued_start_valid_q && engine_busy;
assign start_consume_weight =
    start_uses_pending_weight;
assign start_data_run_count[15:0] =
    cmd_start_tile_req ? 16'd1 :
                         cfg_run_count_q[cfg_write_sel_q][15:0];
assign start_data_scale_sel = scale_pending_valid_q
                            ? scale_pending_sel_q : 1'b0;
assign start_queue_launch = queued_start_valid_q &&
                            (engine_handoff_ready ||
                             (!engine_busy && (queued_start_preactivated_q ||
                                              (queued_start_reuse_weight_q &&
                                               !tensor_weight_pending_valid))));
assign queued_weight_preactivate = queued_start_valid_q
                                  && !queued_start_preactivated_q
                                  && engine_weight_idle
                                  && tensor_weight_pending_valid;
// A younger WLD before any start supersedes the previously loaded tile.  The
// dot8x8 fill boundary cannot overwrite a pending buffer directly, so rotate
// that unused tile active while the engine is idle; the next cycle can fill
// the other physical buffer.  Never rotate a tile already owned by a pending
// or queued start.
assign wld_replace_preactivate = wld_cmd_pending_q
                               && weight_loaded_q
                               && !wld_active_q
                               && !engine_busy
                               && !queued_start_valid_q
                               && !start_pending_q
                               && tensor_weight_pending_valid;
assign engine_weight_preactivate = queued_weight_preactivate
                                 || wld_replace_preactivate;
assign engine_start_use_active =
    (start_queue_launch && (queued_start_preactivated_q ||
                            (queued_start_reuse_weight_q &&
                             !tensor_weight_pending_valid)))
    || (start_direct_accept && weight_reuse_token_q)
    || (start_pending_direct_launch && start_pending_reuse_weight_q);
assign engine_start = start_direct_accept
                   || start_pending_direct_launch
                   || start_queue_launch;
assign tensor_start_retire_valid = engine_start || copy_start_accept;
assign tensor_start_retire_seq_id = copy_start_accept ? cmd_start_seq_id :
                                    start_direct_accept ? cmd_start_seq_id :
                                    (start_pending_direct_launch ?
                                     start_pending_seq_id_q : queued_start_seq_id_q);
assign tensor_start_retire_epoch = copy_start_accept ? cmd_start_epoch :
                                   start_direct_accept ? cmd_start_epoch :
                                   (start_pending_direct_launch ?
                                    start_pending_epoch_q : queued_start_epoch_q);
assign start_data_in[ADDR_WIDTH-1:0] =
    cfg_in_ptr_q[cfg_write_sel_q][ADDR_WIDTH-1:0];
assign start_data_out[ADDR_WIDTH-1:0] =
    cfg_out_ptr_q[cfg_write_sel_q][ADDR_WIDTH-1:0];
assign start_data_psum[ADDR_WIDTH-1:0] =
    cfg_psum_ptr_q[cfg_write_sel_q][ADDR_WIDTH-1:0];
assign engine_start_in[ADDR_WIDTH-1:0] =
    start_queue_launch ? queued_in_q[ADDR_WIDTH-1:0]
  : start_pending_direct_launch ? start_pending_in_q[ADDR_WIDTH-1:0]
                       : start_data_in[ADDR_WIDTH-1:0];
assign engine_start_out[ADDR_WIDTH-1:0] =
    start_queue_launch ? queued_out_q[ADDR_WIDTH-1:0]
  : start_pending_direct_launch ? start_pending_out_q[ADDR_WIDTH-1:0]
                       : start_data_out[ADDR_WIDTH-1:0];
assign engine_start_psum[ADDR_WIDTH-1:0] =
    start_queue_launch ? queued_psum_q[ADDR_WIDTH-1:0]
  : start_pending_direct_launch ? start_pending_psum_q[ADDR_WIDTH-1:0]
                       : start_data_psum[ADDR_WIDTH-1:0];
assign engine_start_count[VECTOR_COUNT_WIDTH-1:0] =
    start_queue_launch ? queued_count_q[VECTOR_COUNT_WIDTH-1:0]
  : start_pending_direct_launch ? start_pending_count_q[VECTOR_COUNT_WIDTH-1:0]
                       : start_data_run_count[VECTOR_COUNT_WIDTH-1:0];
assign engine_start_mode[7:0] =
    start_queue_launch ? queued_start_mode_q[7:0]
  : start_pending_direct_launch ? start_pending_mode_q[7:0]
                                : cmd_start_mode[7:0];
assign engine_start_scale_sel =
    start_queue_launch ? queued_start_scale_sel_q
  : start_pending_direct_launch ? start_pending_scale_sel_q
                                : start_data_scale_sel;
assign engine_start_scale[127:0] = scale_buf_q[engine_start_scale_sel][127:0];
assign wld_reuse_accept = (cmd_wld_req || cmd_wld_trans_req)
                       && cmd_wld_reuse
                       && tensor_wld_cmd_ready;
assign wld_cmd_accept = (cmd_wld_req || cmd_wld_trans_req)
                     && !cmd_wld_reuse
                     && tensor_wld_cmd_ready;
assign sld_reuse_accept = cmd_sld_req
                       && cmd_sld_reuse
                       && tensor_sld_cmd_ready;
assign wld_cmd_can_launch = !wld_active_q && !weight_loaded_q &&
                            wld_fill_start_ready;
assign wld_cmd_immediate_launch = wld_cmd_accept
                                && !wld_cmd_pending_q
                                && wld_cmd_can_launch;
assign wld_cmd_pending_launch = wld_cmd_pending_q && wld_cmd_can_launch;
assign wld_cmd_launch = wld_cmd_immediate_launch || wld_cmd_pending_launch;
assign wld_cmd_launch_ptr[ADDR_WIDTH-1:0] =
    wld_cmd_pending_launch ? wld_cmd_pending_ptr_q[ADDR_WIDTH-1:0]
                           : cmd_wld_ptr[ADDR_WIDTH-1:0];
assign wld_cmd_launch_transpose =
    wld_cmd_pending_launch ? wld_cmd_pending_transpose_q
                           : cmd_wld_trans_req;
assign wld_cmd_launch_bf16 =
    wld_cmd_pending_launch ? wld_cmd_pending_bf16_q
                           : (cfg_wtype_q[cfg_write_sel_q][3:0] == 4'd1);
assign wld_req_addr[ADDR_WIDTH-1:0] =
    wld_base_q[ADDR_WIDTH-1:0] + {{ADDR_WIDTH-4{1'b0}},
                                  wld_issue_idx_q[2:0], 1'b0};
assign tensor_wld_addr[ADDR_WIDTH-1:0] = wld_req_addr[ADDR_WIDTH-1:0];
assign tensor_wld_req = wld_active_q
                     && (wld_read_count_q[3:0]
                         < (wld_active_bf16_q ? 4'd8 : 4'd4));
assign wld_read_fire = tensor_wld_req && tensor_wld_ready;
assign wld_load_data[PAIR_WIDTH-1:0] = tensor_wld_rdata[PAIR_WIDTH-1:0];
assign engine_host_bank_rdata[DATA_WIDTH-1:0] =
    bank_data(tensor_bank_rdata[BANK_NUM*DATA_WIDTH-1:0], engine_host_rsp_bank);
assign copy_host_req = copy_active_q && engine_host_ready
                     && (LOWER_SIX ? (3'(copy_host_addr[3:1]-tensor_phase[3:1]) < 3'd5)
                                       : (copy_host_addr[1] == tensor_phase[1]))
                     && (copy_write_q || !engine_host_rvalid);
assign copy_host_we = copy_write_q;
assign copy_host_addr[ADDR_WIDTH-1:0] =
    (copy_write_q ? copy_out_q : copy_in_q)
    + (copy_offset_q[ADDR_WIDTH-1:0] >> BYTE_INDEX_WIDTH);
assign copy_host_wstrb[BYTE_WIDTH-1:0] =
    (copy_bytes_q - copy_offset_q >= BYTE_WIDTH)
    ? {BYTE_WIDTH{1'b1}}
    : ({BYTE_WIDTH{1'b1}} >> (BYTE_WIDTH - (copy_bytes_q - copy_offset_q)));
assign engine_i_pair_rdata[PAIR_WIDTH-1:0] =
    {bank_data(tensor_bank_rdata[BANK_NUM*DATA_WIDTH-1:0], engine_i_pair_rsp_bank1),
     bank_data(tensor_bank_rdata[BANK_NUM*DATA_WIDTH-1:0], engine_i_pair_rsp_bank0)};
assign engine_psum_pair_rdata[PAIR_WIDTH-1:0] =
    {bank_data(tensor_bank_rdata[BANK_NUM*DATA_WIDTH-1:0], engine_psum_pair_rsp_bank1),
     bank_data(tensor_bank_rdata[BANK_NUM*DATA_WIDTH-1:0], engine_psum_pair_rsp_bank0)};
assign unused_cmd_bits = cmd_setcsr_req || (|cmd_setcsr_dtype[3:0])
                      || (|cmd_setcsr_wtype[3:0])
                      || cmd_wld_trans_req
                      || (|cmd_start_mode[7:5])
                      || engine_done;

edge_tensor_engine #(
  .LOWER_SIX(LOWER_SIX),
  .READ_LATENCY(READ_LATENCY),
  .ADDR_WIDTH(ADDR_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .BANK_NUM(BANK_NUM),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .VECTOR_COUNT_WIDTH(VECTOR_COUNT_WIDTH),
  .PACKED_WEIGHT(PACKED_WEIGHT)
) x_tensor_engine (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .start(engine_start),
  .in_base_addr(engine_start_in[ADDR_WIDTH-1:0]),
  .psum_base_addr(engine_start_psum[ADDR_WIDTH-1:0]),
  .out_base_addr(engine_start_out[ADDR_WIDTH-1:0]),
  .vector_count(engine_start_count[VECTOR_COUNT_WIDTH-1:0]),
  .start_mode(engine_start_mode[7:0]),
  .scale_bf16(engine_start_scale[127:0]),
  .scale_stream_valid(scale_stream_count_q != 0),
  .scale_stream_data(scale_stream_fifo_q[scale_stream_head_q]),
  .scale_stream_ready(engine_scale_stream_ready),
  .weight_fill_bf16_mode(tensor_weight_fill_bf16_mode),
  .weight_fill_start(tensor_weight_fill_start),
  .weight_fill_start_ready(tensor_weight_fill_start_ready),
  .weight_fill_valid(tensor_weight_fill_valid),
  .weight_fill_ready(tensor_weight_fill_ready),
  .weight_fill_pair_idx(tensor_weight_fill_pair_idx[1:0]),
  .weight_fill_data(tensor_weight_fill_data[PAIR_WIDTH-1:0]),
  .weight_fill_last(tensor_weight_fill_last),
  .weight_pending_valid(tensor_weight_pending_valid),
  .weight_active_valid(tensor_weight_active_valid),
  .weight_preactivate(engine_weight_preactivate),
  .start_use_active(engine_start_use_active),
  .weight_idle(engine_weight_idle),
  .packed_weight_start(PACKED_WEIGHT ? wld_cmd_launch : 1'b0),
  .packed_weight_start_ready(packed_weight_start_ready),
  .packed_weight_bf16_mode(wld_cmd_launch_bf16),
  .packed_weight_transpose(wld_cmd_launch_transpose),
  .packed_weight_busy(packed_weight_busy),
  .packed_weight_done(packed_weight_done),
  .packed_weight_load_valid(PACKED_WEIGHT ? tensor_wld_rvalid : 1'b0),
  .packed_weight_load_ready(packed_weight_load_ready),
  .packed_weight_load_idx(wld_rsp_idx_q[2:0]),
  .packed_weight_load_data(wld_load_data[PAIR_WIDTH-1:0]),
  .next_input_prefetch_valid(queued_start_valid_q),
  .next_input_prefetch_base_addr(queued_in_q[ADDR_WIDTH-1:0]),
  .next_input_prefetch_psum_base_addr(queued_psum_q[ADDR_WIDTH-1:0]),
  .next_input_prefetch_mode(queued_start_mode_q[7:0]),
  .next_input_prefetch_vector_count(
      queued_count_q[VECTOR_COUNT_WIDTH-1:0]),
  .handoff_ready(engine_handoff_ready),
  .busy(engine_busy),
  .done(engine_done),
  .host_req(copy_host_req),
  .host_we(copy_host_we),
  .host_addr(copy_host_addr),
  .host_wdata(copy_data_q),
  .host_wstrb(copy_host_wstrb),
  .host_ready(engine_host_ready),
  .host_rdata(engine_host_rdata),
  .host_rvalid(engine_host_rvalid),
  .host_rsp_bank(engine_host_rsp_bank),
  .fabric_phase(tensor_phase[BANK_INDEX_WIDTH-1:0]),
  .host_bank_req(engine_host_bank_req),
  .host_bank_we(engine_host_bank_we),
  .host_bank(engine_host_bank[BANK_INDEX_WIDTH-1:0]),
  .host_bank_addr(engine_host_bank_addr[SRAM_ADDR_WIDTH-1:0]),
  .host_bank_wdata(engine_host_bank_wdata[DATA_WIDTH-1:0]),
  .host_bank_wstrb(engine_host_bank_wstrb[BYTE_WIDTH-1:0]),
  .host_bank_rdata(engine_host_bank_rdata[DATA_WIDTH-1:0]),
  .i_pair_req(engine_i_pair_req),
  .i_pair_bank0(engine_i_pair_bank0[BANK_INDEX_WIDTH-1:0]),
  .i_pair_bank1(engine_i_pair_bank1[BANK_INDEX_WIDTH-1:0]),
  .i_pair_addr(engine_i_pair_addr[SRAM_ADDR_WIDTH-1:0]),
  .i_pair_rsp_bank0(engine_i_pair_rsp_bank0[BANK_INDEX_WIDTH-1:0]),
  .i_pair_rsp_bank1(engine_i_pair_rsp_bank1[BANK_INDEX_WIDTH-1:0]),
  .i_pair_rdata(engine_i_pair_rdata[PAIR_WIDTH-1:0]),
  .psum_pair_req(engine_psum_pair_req),
  .psum_pair_bank0(engine_psum_pair_bank0[BANK_INDEX_WIDTH-1:0]),
  .psum_pair_bank1(engine_psum_pair_bank1[BANK_INDEX_WIDTH-1:0]),
  .psum_pair_addr(engine_psum_pair_addr[SRAM_ADDR_WIDTH-1:0]),
  .psum_pair_rsp_bank0(engine_psum_pair_rsp_bank0[BANK_INDEX_WIDTH-1:0]),
  .psum_pair_rsp_bank1(engine_psum_pair_rsp_bank1[BANK_INDEX_WIDTH-1:0]),
  .psum_pair_rdata(engine_psum_pair_rdata[PAIR_WIDTH-1:0]),
  .o_pair_req(engine_o_pair_req),
  .o_pair_bank0(engine_o_pair_bank0[BANK_INDEX_WIDTH-1:0]),
  .o_pair_bank1(engine_o_pair_bank1[BANK_INDEX_WIDTH-1:0]),
  .o_pair_addr(engine_o_pair_addr[SRAM_ADDR_WIDTH-1:0]),
  .o_pair_wdata(engine_o_pair_wdata[PAIR_WIDTH-1:0]),
  .stream_out_push(stream_out_push),
  .stream_i_prefetch_accept(stream_i_prefetch_accept),
  .stream_psum_prefetch_accept(stream_psum_prefetch_accept)
);

generate
  if (PACKED_WEIGHT) begin : GEN_PACKED_WLD
    assign wld_fill_start_ready = packed_weight_start_ready;
    assign wld_fill_done = packed_weight_done;
    assign tensor_weight_fill_start = 1'b0;
    assign tensor_weight_fill_bf16_mode = 1'b0;
    assign tensor_weight_fill_valid = 1'b0;
    assign tensor_weight_fill_pair_idx = 2'b0;
    assign tensor_weight_fill_data = {PAIR_WIDTH{1'b0}};
    assign tensor_weight_fill_last = 1'b0;
  end else begin : GEN_LEGACY_WLD
    edge_tensor_wld8x8_fill #(
      .DATA_WIDTH(DATA_WIDTH), .PAIR_WIDTH(PAIR_WIDTH)
    ) x_edge_tensor_wld8x8_fill (
      .clk(clk), .rst_b(cpurst_b), .start(wld_cmd_launch),
      .start_ready(wld_fill_start_ready),
      .start_bf16_mode(wld_cmd_launch_bf16),
      .start_transpose(wld_cmd_launch_transpose), .busy(),
      .done(wld_fill_done), .load_valid(tensor_wld_rvalid),
      .load_idx(wld_rsp_idx_q[2:0]),
      .load_data(wld_load_data[PAIR_WIDTH-1:0]), .load_done(),
      .weight_fill_start(tensor_weight_fill_start),
      .weight_fill_bf16_mode(tensor_weight_fill_bf16_mode),
      .weight_fill_start_ready(tensor_weight_fill_start_ready),
      .weight_fill_valid(tensor_weight_fill_valid),
      .weight_fill_ready(tensor_weight_fill_ready),
      .weight_fill_pair_idx(tensor_weight_fill_pair_idx[1:0]),
      .weight_fill_data(tensor_weight_fill_data[PAIR_WIDTH-1:0]),
      .weight_fill_last(tensor_weight_fill_last)
    );
  end
endgenerate

wire unused_packed_weight_status = packed_weight_busy
                                 || packed_weight_load_ready;

generate
  for (bank_gen_i = 0; bank_gen_i < BANK_NUM; bank_gen_i = bank_gen_i + 1) begin: MERGE_BANK
    assign engine_bank_req[bank_gen_i] =
        engine_host_bank_req
        && (engine_host_bank[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])
      || engine_i_pair_req
        && ((engine_i_pair_bank0[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])
            || (engine_i_pair_bank1[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0]))
      || engine_psum_pair_req
        && ((engine_psum_pair_bank0[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])
            || (engine_psum_pair_bank1[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0]))
      || engine_o_pair_req
        && ((engine_o_pair_bank0[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])
            || (engine_o_pair_bank1[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0]));
    assign engine_bank_we[bank_gen_i] =
        (engine_host_bank_req
         && (engine_host_bank[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0]))
        ? engine_host_bank_we
      : (engine_o_pair_req
         && ((engine_o_pair_bank0[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])
             || (engine_o_pair_bank1[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])));
    assign engine_bank_addr[bank_gen_i*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] =
        (engine_host_bank_req
         && (engine_host_bank[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0]))
        ? engine_host_bank_addr[SRAM_ADDR_WIDTH-1:0]
      : (engine_o_pair_req
         && ((engine_o_pair_bank0[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])
             || (engine_o_pair_bank1[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])))
        ? engine_o_pair_addr[SRAM_ADDR_WIDTH-1:0]
      : engine_psum_pair_req
        && ((engine_psum_pair_bank0[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])
            || (engine_psum_pair_bank1[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0]))
        ? engine_psum_pair_addr[SRAM_ADDR_WIDTH-1:0]
      : engine_i_pair_addr[SRAM_ADDR_WIDTH-1:0];
    assign engine_bank_wdata[bank_gen_i*DATA_WIDTH +: DATA_WIDTH] =
        (engine_host_bank_req
         && (engine_host_bank[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0]))
        ? engine_host_bank_wdata[DATA_WIDTH-1:0]
      : (engine_o_pair_bank0[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])
        ? engine_o_pair_wdata[DATA_WIDTH-1:0]
      : engine_o_pair_wdata[PAIR_WIDTH-1:DATA_WIDTH];
    assign engine_bank_wstrb[bank_gen_i*BYTE_WIDTH +: BYTE_WIDTH] =
        (engine_host_bank_req
         && (engine_host_bank[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0]))
        ? engine_host_bank_wstrb[BYTE_WIDTH-1:0]
      : (engine_o_pair_req
         && ((engine_o_pair_bank0[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])
             || (engine_o_pair_bank1[BANK_INDEX_WIDTH-1:0] == bank_gen_i[BANK_INDEX_WIDTH-1:0])))
        ? {BYTE_WIDTH{1'b1}}
      : {BYTE_WIDTH{1'b0}};

    assign tensor_bank_req[bank_gen_i] = engine_bank_req[bank_gen_i];
    assign tensor_bank_we[bank_gen_i] = engine_bank_we[bank_gen_i];
    assign tensor_bank_addr[bank_gen_i*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH] =
        engine_bank_addr[bank_gen_i*SRAM_ADDR_WIDTH +: SRAM_ADDR_WIDTH];
    assign tensor_bank_wdata[bank_gen_i*DATA_WIDTH +: DATA_WIDTH] =
        engine_bank_wdata[bank_gen_i*DATA_WIDTH +: DATA_WIDTH];
    assign tensor_bank_wstrb[bank_gen_i*BYTE_WIDTH +: BYTE_WIDTH] =
        engine_bank_wstrb[bank_gen_i*BYTE_WIDTH +: BYTE_WIDTH];
  end
endgenerate

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    cfg_dtype_q[0] <= 4'b0;
    cfg_dtype_q[1] <= 4'b0;
    cfg_wtype_q[0] <= 4'b0;
    cfg_wtype_q[1] <= 4'b0;
    cfg_in_ptr_q[0] <= {ADDR_WIDTH{1'b0}};
    cfg_in_ptr_q[1] <= {ADDR_WIDTH{1'b0}};
    cfg_out_ptr_q[0] <= {ADDR_WIDTH{1'b0}};
    cfg_out_ptr_q[1] <= {ADDR_WIDTH{1'b0}};
    cfg_psum_ptr_q[0] <= {ADDR_WIDTH{1'b0}};
    cfg_psum_ptr_q[1] <= {ADDR_WIDTH{1'b0}};
    cfg_run_count_q[0] <= {{VECTOR_COUNT_WIDTH-1{1'b0}}, 1'b1};
    cfg_run_count_q[1] <= {{VECTOR_COUNT_WIDTH-1{1'b0}}, 1'b1};
    cfg_write_sel_q <= 1'b0;
    weight_loaded_q <= 1'b0;
    weight_reuse_token_q <= 1'b0;
    queued_start_valid_q <= 1'b0;
    queued_start_preactivated_q <= 1'b0;
    queued_start_mode_q <= 8'b0;
    queued_start_reuse_weight_q <= 1'b0;
    queued_start_scale_sel_q <= 1'b0;
    queued_start_seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
    queued_start_epoch_q <= {EPOCH_WIDTH{1'b0}};
    queued_count_q <= {{VECTOR_COUNT_WIDTH-1{1'b0}}, 1'b1};
    queued_in_q <= {ADDR_WIDTH{1'b0}};
    queued_out_q <= {ADDR_WIDTH{1'b0}};
    queued_psum_q <= {ADDR_WIDTH{1'b0}};
    start_pending_q <= 1'b0;
    start_pending_count_q <= {VECTOR_COUNT_WIDTH{1'b0}};
    start_pending_in_q <= {ADDR_WIDTH{1'b0}};
    start_pending_out_q <= {ADDR_WIDTH{1'b0}};
    start_pending_psum_q <= {ADDR_WIDTH{1'b0}};
    start_pending_wld_pending_q <= 1'b0;
    start_pending_mode_q <= 8'b0;
    start_pending_reuse_weight_q <= 1'b0;
    start_pending_scale_sel_q <= 1'b0;
    start_pending_seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
    start_pending_epoch_q <= {EPOCH_WIDTH{1'b0}};
    wld_cmd_pending_q <= 1'b0;
    wld_cmd_pending_transpose_q <= 1'b0;
    wld_cmd_pending_bf16_q <= 1'b0;
    wld_cmd_pending_ptr_q <= {ADDR_WIDTH{1'b0}};
    wld_cmd_pending_next_q <= 1'b0;
    wld_cmd_pending_next_transpose_q <= 1'b0;
    wld_cmd_pending_next_bf16_q <= 1'b0;
    wld_cmd_pending_next_ptr_q <= {ADDR_WIDTH{1'b0}};
    wld_active_q <= 1'b0;
    wld_active_bf16_q <= 1'b0;
    wld_base_q <= {ADDR_WIDTH{1'b0}};
    wld_issue_idx_q <= 3'b0;
    wld_read_count_q <= 4'b0;
    scale_buf_q[0] <= 128'b0;
    scale_buf_q[1] <= 128'b0;
    scale_active_sel_q <= 1'b0;
    scale_active_valid_q <= 1'b0;
    scale_pending_sel_q <= 1'b0;
    scale_pending_valid_q <= 1'b0;
    sld_pending_q <= 1'b0;
    sld_wait_q <= 1'b0;
    sld_ptr_q <= {ADDR_WIDTH{1'b0}};
    sld_load_sel_q <= 1'b0;
    sld_stream_q <= 1'b0;
    scale_stream_head_q <= 3'b0;
    scale_stream_tail_q <= 3'b0;
    scale_stream_count_q <= 4'b0;
    direct_sld_setup_valid_q <= 1'b0;
    direct_sld_active_q <= 1'b0;
    direct_sld_next_ptr_q <= {ADDR_WIDTH{1'b0}};
    direct_sld_target_q <= {VECTOR_COUNT_WIDTH{1'b0}};
    direct_sld_issued_q <= {VECTOR_COUNT_WIDTH{1'b0}};
    direct_sld_received_q <= {VECTOR_COUNT_WIDTH{1'b0}};
    copy_active_q <= 1'b0;
    copy_write_q <= 1'b0;
    copy_in_q <= {ADDR_WIDTH{1'b0}};
    copy_out_q <= {ADDR_WIDTH{1'b0}};
    copy_bytes_q <= {VECTOR_COUNT_WIDTH{1'b0}};
    copy_offset_q <= {VECTOR_COUNT_WIDTH{1'b0}};
    copy_data_q <= {DATA_WIDTH{1'b0}};
  end else begin
    if (copy_start_accept) begin
      copy_active_q <= (start_data_run_count != 0);
      copy_write_q <= 1'b0;
      copy_in_q <= start_data_in[ADDR_WIDTH-1:0];
      copy_out_q <= start_data_out[ADDR_WIDTH-1:0];
      copy_bytes_q <= start_data_run_count[VECTOR_COUNT_WIDTH-1:0];
      copy_offset_q <= {VECTOR_COUNT_WIDTH{1'b0}};
    end else if (copy_active_q && !copy_write_q && engine_host_rvalid) begin
      copy_data_q <= engine_host_rdata[DATA_WIDTH-1:0];
      copy_write_q <= 1'b1;
    end else if (copy_active_q && copy_write_q && copy_host_req) begin
      if (copy_offset_q + BYTE_WIDTH >= copy_bytes_q) begin
        copy_active_q <= 1'b0;
        copy_write_q <= 1'b0;
      end else begin
        copy_offset_q <= copy_offset_q + BYTE_WIDTH;
        copy_write_q <= 1'b0;
      end
    end

    if (cmd_sld_stream_setup_req && tensor_cmd_ready) begin
      direct_sld_setup_valid_q <= 1'b1;
      direct_sld_next_ptr_q <= cmd_sld_stream_setup_ptr[ADDR_WIDTH-1:0];
    end

    if (direct_sld_launch) begin
      sld_pending_q <= 1'b1;
      sld_ptr_q <= direct_sld_next_ptr_q[ADDR_WIDTH-1:0];
      sld_stream_q <= 1'b1;
      direct_sld_next_ptr_q <= direct_sld_next_ptr_q +
                               {{ADDR_WIDTH-2{1'b0}}, 2'b10};
      direct_sld_issued_q <= direct_sld_issued_q + 1'b1;
    end else if (sld_reuse_accept) begin
      // Reuse is an explicit parameter token.  It snapshots the active scale
      // slot without issuing a DTCM read or changing the ping-pong selector.
      scale_pending_sel_q <= scale_active_sel_q;
      scale_pending_valid_q <= 1'b1;
    end else if (cmd_sld_req && tensor_sld_cmd_ready) begin
      sld_pending_q <= 1'b1;
      sld_ptr_q <= cmd_sld_ptr[ADDR_WIDTH-1:0];
      sld_load_sel_q <= scale_active_valid_q ? !scale_active_sel_q : 1'b0;
      sld_stream_q <= cmd_sld_stream;
    end
    if (tensor_sld_req && tensor_sld_ready) begin
      sld_pending_q <= 1'b0;
      sld_wait_q <= 1'b1;
    end
    if (tensor_sld_rvalid && sld_wait_q) begin
      if (sld_stream_q) begin
        scale_stream_fifo_q[scale_stream_tail_q] <= tensor_sld_rdata[127:0];
        scale_stream_tail_q <= scale_stream_tail_q + 1'b1;
        if (direct_sld_active_q) begin
          direct_sld_received_q <= direct_sld_received_q + 1'b1;
          if ((direct_sld_received_q + 1'b1) >= direct_sld_target_q) begin
            direct_sld_active_q <= 1'b0;
            direct_sld_setup_valid_q <= 1'b0;
          end
        end
      end else begin
        scale_buf_q[sld_load_sel_q] <= tensor_sld_rdata[127:0];
        scale_pending_sel_q <= sld_load_sel_q;
        scale_pending_valid_q <= 1'b1;
      end
      sld_wait_q <= 1'b0;
    end

    if (engine_scale_stream_ready)
      scale_stream_head_q <= scale_stream_head_q + 1'b1;
    case ({scale_stream_push, engine_scale_stream_ready})
      2'b10: scale_stream_count_q <= scale_stream_count_q + 1'b1;
      2'b01: scale_stream_count_q <= scale_stream_count_q - 1'b1;
      default: begin end
    endcase

    if (cmd_setcsr_req) begin
      cfg_dtype_q[cfg_write_sel_q] <= cmd_setcsr_dtype[3:0];
      cfg_wtype_q[cfg_write_sel_q] <= cmd_setcsr_wtype[3:0];
    end
    if (cmd_setin_req)
      cfg_in_ptr_q[cfg_write_sel_q] <= cmd_setin_ptr[ADDR_WIDTH-1:0];
    if (cmd_setout_req)
      cfg_out_ptr_q[cfg_write_sel_q] <= cmd_setout_ptr[ADDR_WIDTH-1:0];
    if (cmd_setpsum_req)
      cfg_psum_ptr_q[cfg_write_sel_q] <= cmd_setpsum_ptr[ADDR_WIDTH-1:0];
    if (cmd_setn_req)
      cfg_run_count_q[cfg_write_sel_q] <= cmd_setn_value[VECTOR_COUNT_WIDTH-1:0];
    if (wld_cmd_pending_launch) begin
      wld_cmd_pending_q <= wld_cmd_pending_next_q;
      wld_cmd_pending_transpose_q <= wld_cmd_pending_next_transpose_q;
      wld_cmd_pending_bf16_q <= wld_cmd_pending_next_bf16_q;
      wld_cmd_pending_ptr_q <= wld_cmd_pending_next_ptr_q[ADDR_WIDTH-1:0];
      wld_cmd_pending_next_q <= 1'b0;
      start_pending_wld_pending_q <= 1'b0;
    end

    if (wld_cmd_accept && !wld_cmd_immediate_launch) begin
      if (wld_cmd_pending_q && !wld_cmd_pending_launch) begin
        wld_cmd_pending_next_q <= 1'b1;
        wld_cmd_pending_next_transpose_q <= cmd_wld_trans_req;
        wld_cmd_pending_next_bf16_q <=
            cfg_wtype_q[cfg_write_sel_q][3:0] == 4'd1;
        wld_cmd_pending_next_ptr_q <= cmd_wld_ptr[ADDR_WIDTH-1:0];
      end else if (wld_cmd_pending_q && wld_cmd_pending_launch
                   && wld_cmd_pending_next_q) begin
        wld_cmd_pending_next_q <= 1'b1;
        wld_cmd_pending_next_transpose_q <= cmd_wld_trans_req;
        wld_cmd_pending_next_bf16_q <=
            cfg_wtype_q[cfg_write_sel_q][3:0] == 4'd1;
        wld_cmd_pending_next_ptr_q <= cmd_wld_ptr[ADDR_WIDTH-1:0];
      end else begin
        wld_cmd_pending_q <= 1'b1;
        wld_cmd_pending_transpose_q <= cmd_wld_trans_req;
        wld_cmd_pending_bf16_q <=
            cfg_wtype_q[cfg_write_sel_q][3:0] == 4'd1;
        wld_cmd_pending_ptr_q <= cmd_wld_ptr[ADDR_WIDTH-1:0];
      end
    end

    if (wld_cmd_launch) begin
      weight_loaded_q <= 1'b0;
      wld_active_q <= 1'b1;
      wld_active_bf16_q <= wld_cmd_launch_bf16;
      wld_base_q <= wld_cmd_launch_ptr[ADDR_WIDTH-1:0];
      wld_issue_idx_q <= 3'b0;
      wld_read_count_q <= 4'b0;
    end

    if (wld_read_fire) begin
      wld_issue_idx_q <= wld_issue_idx_q + 3'd1;
      wld_read_count_q <= wld_read_count_q + 4'd1;
    end

    if (wld_fill_done) begin
      weight_loaded_q <= 1'b1;
      wld_active_q <= 1'b0;
    end

    if (wld_reuse_accept)
      // The descriptor bit carried by the next start is the slot snapshot.
      // No weight-fill request is generated and the active selector stays put.
      weight_reuse_token_q <= 1'b1;

    if (queued_weight_preactivate)
      queued_start_preactivated_q <= 1'b1;

    if (wld_replace_preactivate)
      weight_loaded_q <= 1'b0;

    if (start_queue_launch) begin
      queued_start_valid_q <= 1'b0;
      queued_start_preactivated_q <= 1'b0;
    end

    if (start_pending_direct_launch || start_pending_queue_launch) begin
      start_pending_q <= 1'b0;
      start_pending_wld_pending_q <= 1'b0;
    end

    if (start_queue_accept || start_pending_queue_launch) begin
      queued_start_valid_q <= 1'b1;
      queued_start_preactivated_q <= 1'b0;
      queued_in_q <= start_pending_queue_launch
                   ? start_pending_in_q[ADDR_WIDTH-1:0]
                   : start_data_in[ADDR_WIDTH-1:0];
      queued_out_q <= start_pending_queue_launch
                    ? start_pending_out_q[ADDR_WIDTH-1:0]
                    : start_data_out[ADDR_WIDTH-1:0];
      queued_psum_q <= start_pending_queue_launch
                     ? start_pending_psum_q[ADDR_WIDTH-1:0]
                     : start_data_psum[ADDR_WIDTH-1:0];
      queued_count_q <= start_pending_queue_launch
                      ? start_pending_count_q[VECTOR_COUNT_WIDTH-1:0]
                      : start_data_run_count[VECTOR_COUNT_WIDTH-1:0];
      queued_start_mode_q <= start_pending_queue_launch
                           ? start_pending_mode_q[7:0]
                           : cmd_start_mode[7:0];
      queued_start_reuse_weight_q <= start_pending_queue_launch
                                   ? start_pending_reuse_weight_q
                                   : weight_reuse_token_q;
      queued_start_scale_sel_q <= start_pending_queue_launch
                                ? start_pending_scale_sel_q
                                : start_data_scale_sel;
      queued_start_seq_id_q <= start_pending_queue_launch ?
                               start_pending_seq_id_q : cmd_start_seq_id;
      queued_start_epoch_q <= start_pending_queue_launch ?
                              start_pending_epoch_q : cmd_start_epoch;
    end

    if (start_wait_accept) begin
      start_pending_q <= 1'b1;
      start_pending_in_q <= start_data_in[ADDR_WIDTH-1:0];
      start_pending_out_q <= start_data_out[ADDR_WIDTH-1:0];
      start_pending_psum_q <= start_data_psum[ADDR_WIDTH-1:0];
      start_pending_count_q <= start_data_run_count[VECTOR_COUNT_WIDTH-1:0];
      start_pending_wld_pending_q <= wld_cmd_pending_q
                                  && !wld_active_q
                                  && !weight_loaded_q;
      start_pending_mode_q <= cmd_start_mode[7:0];
      start_pending_reuse_weight_q <= weight_reuse_token_q;
      start_pending_scale_sel_q <= start_data_scale_sel;
      start_pending_seq_id_q <= cmd_start_seq_id;
      start_pending_epoch_q <= cmd_start_epoch;
    end

    if (start_accept) begin
      cfg_dtype_q[!cfg_write_sel_q] <= cfg_dtype_q[cfg_write_sel_q];
      cfg_wtype_q[!cfg_write_sel_q] <= cfg_wtype_q[cfg_write_sel_q];
      cfg_in_ptr_q[!cfg_write_sel_q] <= cfg_in_ptr_q[cfg_write_sel_q];
      cfg_out_ptr_q[!cfg_write_sel_q] <= cfg_out_ptr_q[cfg_write_sel_q];
      cfg_psum_ptr_q[!cfg_write_sel_q] <= cfg_psum_ptr_q[cfg_write_sel_q];
      cfg_run_count_q[!cfg_write_sel_q] <= cfg_run_count_q[cfg_write_sel_q];
      cfg_write_sel_q <= !cfg_write_sel_q;
      if (cmd_start_mode[0] && !cmd_start_mode[3] && !cmd_start_mode[4]
          && scale_pending_valid_q) begin
        scale_active_sel_q <= scale_pending_sel_q;
        scale_active_valid_q <= 1'b1;
        scale_pending_valid_q <= 1'b0;
      end
    end

    if (engine_start && engine_start_mode[3] && !engine_start_mode[4]
        && direct_sld_setup_valid_q) begin
      direct_sld_active_q <= (engine_start_count != 0);
      direct_sld_target_q <= engine_start_count;
      direct_sld_issued_q <= {VECTOR_COUNT_WIDTH{1'b0}};
      direct_sld_received_q <= {VECTOR_COUNT_WIDTH{1'b0}};
      if (engine_start_count == 0)
        direct_sld_setup_valid_q <= 1'b0;
    end

    if (start_consume_weight) begin
      weight_loaded_q <= 1'b0;
    end

    if (start_uses_reuse_weight)
      weight_reuse_token_q <= 1'b0;

    if (unused_cmd_bits) begin
    end
  end
end

endmodule
