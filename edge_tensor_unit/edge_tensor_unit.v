module edge_tensor_unit(
  clk,
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
  cmd_sync_req,
  cmd_wld_ptr,
  cmd_wld_req,
  cmd_wld_trans_req,
  cpurst_b,
  cur_tensor_in_req_mask,
  cur_tensor_out_req_mask,
  cur_tensor_prefetch_req_mask,
  dbg_dtype,
  dbg_i_comp_delay,
  dbg_i_lease_channel,
  dbg_i_lease_cycles,
  dbg_i_lease_delay,
  dbg_iopsum_plan_valid,
  dbg_o_comp_delay,
  dbg_o_lease_channel,
  dbg_o_lease_cycles,
  dbg_o_lease_delay,
  dbg_phase,
  dbg_psum_comp_delay,
  dbg_psum_lease_channel,
  dbg_psum_lease_cycles,
  dbg_psum_lease_delay,
  dbg_step,
  dbg_start_phase,
  dbg_wtype,
  dma_delay_req,
  lsu_resv_plus1,
  tensor_busy,
  tensor_addr,
  tensor_cmd_ready,
  tensor_start_ready,
  tensor_io_lease_channel_mask,
  tensor_io_lease_cycles,
  tensor_io_lease_delay,
  tensor_io_lease1_channel_mask,
  tensor_io_lease1_cycles,
  tensor_io_lease1_delay,
  tensor_io_lease1_valid,
  tensor_io_lease2_channel_mask,
  tensor_io_lease2_cycles,
  tensor_io_lease2_delay,
  tensor_io_lease2_valid,
  tensor_io_lease_valid,
  tensor_lane1_addr,
  tensor_lane1_data,
  tensor_lane1_hi,
  tensor_lane1_pair_rdata,
  tensor_lane1_pair_rvalid,
  tensor_lane1_ready,
  tensor_lane1_req,
  tensor_lane1_role,
  tensor_lane1_valid,
  tensor_lane1_wdata,
  tensor_lane1_we,
  tensor_lane1_wstrb,
  tensor_lane2_addr,
  tensor_lane2_data,
  tensor_lane2_hi,
  tensor_lane2_ready,
  tensor_lane2_req,
  tensor_lane2_role,
  tensor_lane2_valid,
  tensor_lane2_pair_wdata,
  tensor_lane2_pair_wstrb,
  tensor_lane2_wdata,
  tensor_lane2_we,
  tensor_lane2_wstrb,
  tensor_pair_rdata,
  tensor_pair_rvalid,
  tensor_pair_rsp_high,
  tensor_rdata,
  tensor_ready,
  tensor_req,
  tensor_resv_plus2_mask,
  tensor_resv_plus2_req,
  tensor_rvalid,
  tensor_sync_stall,
  tensor_wdata,
  tensor_we,
  tensor_wstrb,
  tensor_wld_cmd_ready,
  tensor_wld_addr,
  tensor_wld_lease_channel_mask,
  tensor_wld_lease_cycles,
  tensor_wld_lease_delay,
  tensor_wld_lease_valid,
  tensor_wld_rdata,
  tensor_wld_ready,
  tensor_wld_req,
  tensor_wld_rvalid
);

parameter ADDR_WIDTH       = 16;
parameter BANK_NUM         = 16;
parameter BANK_INDEX_WIDTH = 4;
parameter [ADDR_WIDTH-1:0] PIPELINE_LATENCY = 30;
parameter STEP_NUM         = 4;
parameter STEP_WIDTH       = 3;
parameter [3:0] LEASE_DELAY = 4'd2;
parameter [3:0] TENSOR_IO_LEASE_DELAY = LEASE_DELAY;
parameter [3:0] TENSOR_WLD_LEASE_DELAY = LEASE_DELAY;
parameter [8:0] TENSOR_IO_PLAN_CYCLES = 9'd100;
parameter [3:0] TENSOR_I_BASE_DELAY = 4'd1;
parameter [3:0] TENSOR_PSUM_BASE_DELAY = 4'd6;
parameter [3:0] TENSOR_O_BASE_DELAY = 4'd7;
parameter STREAM_FIFO_DEPTH = 8;
parameter STREAM_FIFO_INDEX_WIDTH = 3;
localparam RUN_COUNT_WIDTH = 16;

input                         clk;
input  [3:0]                  cmd_setcsr_dtype;
input                         cmd_setcsr_req;
input  [3:0]                  cmd_setcsr_wtype;
input  [ADDR_WIDTH-1:0]       cmd_setin_ptr;
input                         cmd_setin_req;
input                         cmd_setn_req;
input  [15:0]                 cmd_setn_value;
input  [ADDR_WIDTH-1:0]       cmd_setout_ptr;
input                         cmd_setout_req;
input  [ADDR_WIDTH-1:0]       cmd_setpsum_ptr;
input                         cmd_setpsum_req;
input                         cmd_start_req;
input                         cmd_start_tile_req;
input                         cmd_sync_req;
input  [ADDR_WIDTH-1:0]       cmd_wld_ptr;
input                         cmd_wld_req;
input                         cmd_wld_trans_req;
input                         cpurst_b;
input  [BANK_NUM-1:0]         lsu_resv_plus1;
input  [63:0]                 tensor_lane1_data;
input                         tensor_lane1_hi;
input  [127:0]                tensor_lane1_pair_rdata;
input                         tensor_lane1_pair_rvalid;
input                         tensor_lane1_ready;
input  [1:0]                  tensor_lane1_role;
input                         tensor_lane1_valid;
input  [63:0]                 tensor_lane2_data;
input                         tensor_lane2_hi;
input                         tensor_lane2_ready;
input  [1:0]                  tensor_lane2_role;
input                         tensor_lane2_valid;
input  [127:0]                tensor_pair_rdata;
input                         tensor_pair_rvalid;
input                         tensor_pair_rsp_high;
input  [63:0]                 tensor_rdata;
input                         tensor_ready;
input                         tensor_rvalid;
input  [127:0]                tensor_wld_rdata;
input                         tensor_wld_ready;
input                         tensor_wld_rvalid;

output [BANK_NUM-1:0]         cur_tensor_in_req_mask;
output [BANK_NUM-1:0]         cur_tensor_out_req_mask;
output [BANK_NUM-1:0]         cur_tensor_prefetch_req_mask;
output [3:0]                  dbg_dtype;
output [1:0]                  dbg_i_comp_delay;
output [2:0]                  dbg_i_lease_channel;
output [8:0]                  dbg_i_lease_cycles;
output [3:0]                  dbg_i_lease_delay;
output                        dbg_iopsum_plan_valid;
output [1:0]                  dbg_o_comp_delay;
output [2:0]                  dbg_o_lease_channel;
output [8:0]                  dbg_o_lease_cycles;
output [3:0]                  dbg_o_lease_delay;
output [2:0]                  dbg_phase;
output [1:0]                  dbg_psum_comp_delay;
output [2:0]                  dbg_psum_lease_channel;
output [8:0]                  dbg_psum_lease_cycles;
output [3:0]                  dbg_psum_lease_delay;
output [STEP_WIDTH-1:0]       dbg_step;
output [2:0]                  dbg_start_phase;
output [3:0]                  dbg_wtype;
output                        dma_delay_req;
output                        tensor_busy;
output [ADDR_WIDTH-1:0]       tensor_addr;
output                        tensor_cmd_ready;
output                        tensor_start_ready;
output [7:0]                  tensor_io_lease_channel_mask;
output [8:0]                  tensor_io_lease_cycles;
output [3:0]                  tensor_io_lease_delay;
output [7:0]                  tensor_io_lease1_channel_mask;
output [8:0]                  tensor_io_lease1_cycles;
output [3:0]                  tensor_io_lease1_delay;
output                        tensor_io_lease1_valid;
output [7:0]                  tensor_io_lease2_channel_mask;
output [8:0]                  tensor_io_lease2_cycles;
output [3:0]                  tensor_io_lease2_delay;
output                        tensor_io_lease2_valid;
output                        tensor_io_lease_valid;
output [ADDR_WIDTH-1:0]       tensor_lane1_addr;
output                        tensor_lane1_req;
output [63:0]                 tensor_lane1_wdata;
output                        tensor_lane1_we;
output [7:0]                  tensor_lane1_wstrb;
output [ADDR_WIDTH-1:0]       tensor_lane2_addr;
output                        tensor_lane2_req;
output [127:0]                tensor_lane2_pair_wdata;
output [15:0]                 tensor_lane2_pair_wstrb;
output [63:0]                 tensor_lane2_wdata;
output                        tensor_lane2_we;
output [7:0]                  tensor_lane2_wstrb;
output                        tensor_req;
output [BANK_NUM-1:0]         tensor_resv_plus2_mask;
output                        tensor_resv_plus2_req;
output                        tensor_sync_stall;
output [63:0]                 tensor_wdata;
output                        tensor_we;
output [7:0]                  tensor_wstrb;
output                        tensor_wld_cmd_ready;
output [ADDR_WIDTH-1:0]       tensor_wld_addr;
output [7:0]                  tensor_wld_lease_channel_mask;
output [8:0]                  tensor_wld_lease_cycles;
output [3:0]                  tensor_wld_lease_delay;
output                        tensor_wld_lease_valid;
output                        tensor_wld_req;

reg  [3:0]                    dtype;
reg  [3:0]                    wtype;
reg                           setup_buf_sel;
reg  [3:0]                    setup_dtype [0:1];
reg  [3:0]                    setup_wtype [0:1];
reg  [ADDR_WIDTH-1:0]         setup_in_ptr [0:1];
reg  [ADDR_WIDTH-1:0]         setup_out_ptr [0:1];
reg  [ADDR_WIDTH-1:0]         setup_psum_ptr [0:1];
reg  [RUN_COUNT_WIDTH-1:0]    setup_run_count [0:1];
reg                           setup_run_count_valid [0:1];
reg  [ADDR_WIDTH-1:0]         active_in_ptr;
reg  [ADDR_WIDTH-1:0]         active_out_ptr;
reg  [ADDR_WIDTH-1:0]         active_psum_ptr;
reg  [ADDR_WIDTH-1:0]         weight_ptr;
reg  [RUN_COUNT_WIDTH-1:0]                    run_count;
reg                           run_count_valid;
reg  [RUN_COUNT_WIDTH-1:0]                    data_run_remaining;
reg  [RUN_COUNT_WIDTH-1:0]                    data_vec_index;
reg  [RUN_COUNT_WIDTH-1:0]                    stream_i_issue_index;
reg  [RUN_COUNT_WIDTH-1:0]                    stream_psum_issue_index;
reg  [RUN_COUNT_WIDTH-1:0]                    stream_compute_index;
reg  [RUN_COUNT_WIDTH-1:0]                    stream_out_write_index;
reg  [RUN_COUNT_WIDTH-1:0]                    stream_out_push_index;
reg  [RUN_COUNT_WIDTH-1:0]                    queued_i_issue_index;
reg  [RUN_COUNT_WIDTH-1:0]                    queued_psum_issue_index;
reg  [ADDR_WIDTH-1:0]         cycles_left;
reg  [STEP_WIDTH-1:0]         step;
reg                           busy;
reg  [3:0]                    dtcm_state;
reg                           compute_valid_q;
reg  [1:0]                    rsp_tag_role [0:3];
reg  [3:0]                    rsp_tag_hi;
reg  [1:0]                    rsp_tag_head;
reg  [1:0]                    rsp_tag_tail;
reg  [2:0]                    rsp_tag_count;
reg  [2:0]                    wld_read_idx;
reg  [2:0]                    wld_load_idx;
reg  [63:0]                   wld_read_lo;
reg                           wld_reg_drain_transpose;
reg                           wld_cmd_pending;
reg                           wld_cmd_pending_transpose;
reg                           wld_cmd_pending_bf16;
reg  [ADDR_WIDTH-1:0]         wld_cmd_pending_ptr;
reg                           wld_fetch_active;
reg                           wld_fetch_wait;
reg                           wld_active_bf16;
reg                           weight_active_buf_q;
reg                           weight_active_valid;
reg                           weight_load_buf_q;
reg                           weight_loaded_buf_q;
reg                           weight_loaded_valid;
reg                           queued_start_valid;
reg                           queued_start_tile;
reg  [3:0]                    queued_dtype;
reg  [3:0]                    queued_wtype;
reg  [ADDR_WIDTH-1:0]         queued_in_ptr;
reg  [ADDR_WIDTH-1:0]         queued_out_ptr;
reg  [ADDR_WIDTH-1:0]         queued_psum_ptr;
reg  [RUN_COUNT_WIDTH-1:0]    queued_run_count;
reg                           queued_weight_buf;
reg  [127:0]                  wld_reg_load_data_q;
reg  [2:0]                    wld_reg_load_idx_q;
reg                           wld_reg_load_valid_q;
reg                           wld_ready;
reg  [2:0]                    phase;
reg  [2:0]                    start_phase;
reg                           iopsum_plan_valid;
reg  [3:0]                    i_lease_delay;
reg  [3:0]                    psum_lease_delay;
reg  [3:0]                    o_lease_delay;
reg  [2:0]                    i_lease_channel;
reg  [2:0]                    psum_lease_channel;
reg  [2:0]                    o_lease_channel;
reg  [8:0]                    i_lease_cycles;
reg  [8:0]                    psum_lease_cycles;
reg  [8:0]                    o_lease_cycles;
reg  [1:0]                    i_comp_delay;
reg  [1:0]                    psum_comp_delay;
reg  [1:0]                    o_comp_delay;
reg  [7:0]                    tensor_io_lease_channel_mask_q;
reg  [8:0]                    tensor_io_lease_cycles_q;
reg  [3:0]                    tensor_io_lease_delay_q;
reg                           tensor_io_lease_valid_q;
reg  [7:0]                    tensor_io_lease1_channel_mask_q;
reg  [8:0]                    tensor_io_lease1_cycles_q;
reg  [3:0]                    tensor_io_lease1_delay_q;
reg                           tensor_io_lease1_valid_q;
reg  [7:0]                    tensor_io_lease2_channel_mask_q;
reg  [8:0]                    tensor_io_lease2_cycles_q;
reg  [3:0]                    tensor_io_lease2_delay_q;
reg                           tensor_io_lease2_valid_q;
reg                           plan_table_valid;
reg  [3:0]                    plan_table_i_delay [0:7];
reg  [3:0]                    plan_table_psum_delay [0:7];
reg  [3:0]                    plan_table_o_delay [0:7];
reg  [2:0]                    plan_table_i_channel [0:7];
reg  [2:0]                    plan_table_psum_channel [0:7];
reg  [2:0]                    plan_table_o_channel [0:7];
reg  [8:0]                    plan_table_i_cycles [0:7];
reg  [8:0]                    plan_table_psum_cycles [0:7];
reg  [8:0]                    plan_table_o_cycles [0:7];
reg  [1:0]                    plan_table_i_comp [0:7];
reg  [1:0]                    plan_table_psum_comp [0:7];
reg  [1:0]                    plan_table_o_comp [0:7];
reg  [127:0]                  stream_i_fifo [0:STREAM_FIFO_DEPTH-1];
reg  [127:0]                  stream_psum_fifo [0:STREAM_FIFO_DEPTH-1];
reg  [127:0]                  stream_out_fifo [0:STREAM_FIFO_DEPTH-1];
reg  [ADDR_WIDTH-1:0]         stream_out_addr_fifo [0:STREAM_FIFO_DEPTH-1];
reg  [127:0]                  stream_compute_input_q;
reg  [127:0]                  stream_compute_psum_q;
reg  [STREAM_FIFO_INDEX_WIDTH-1:0] stream_i_head;
reg  [STREAM_FIFO_INDEX_WIDTH-1:0] stream_i_tail;
reg  [STREAM_FIFO_INDEX_WIDTH:0]   stream_i_count;
reg  [STREAM_FIFO_INDEX_WIDTH:0]   stream_i_inflight_count;
reg  [STREAM_FIFO_INDEX_WIDTH-1:0] stream_psum_head;
reg  [STREAM_FIFO_INDEX_WIDTH-1:0] stream_psum_tail;
reg  [STREAM_FIFO_INDEX_WIDTH:0]   stream_psum_count;
reg  [STREAM_FIFO_INDEX_WIDTH:0]   stream_psum_inflight_count;
reg  [STREAM_FIFO_INDEX_WIDTH-1:0] stream_out_head;
reg  [STREAM_FIFO_INDEX_WIDTH-1:0] stream_out_tail;
reg  [STREAM_FIFO_INDEX_WIDTH:0]   stream_out_count;
reg  [STREAM_FIFO_INDEX_WIDTH:0]   stream_out_inflight_count;
reg                                stream_out_skid_valid;
reg  [127:0]                       stream_out_skid_data;
reg  [ADDR_WIDTH-1:0]              stream_out_skid_addr;

wire [ADDR_WIDTH-1:0]         in_step_addr;
wire [ADDR_WIDTH-1:0]         out_step_addr;
wire [ADDR_WIDTH-1:0]         psum_step_addr;
wire [ADDR_WIDTH-1:0]         weight_step_addr;
wire [ADDR_WIDTH-1:0]         data_vec_word_offset;
wire [ADDR_WIDTH-1:0]         stream_i_word_offset;
wire [ADDR_WIDTH-1:0]         stream_psum_word_offset;
wire [ADDR_WIDTH-1:0]         stream_out_word_offset;
wire [ADDR_WIDTH-1:0]         stream_out_push_word_offset;
wire [ADDR_WIDTH-1:0]         stream_i_addr;
wire [ADDR_WIDTH-1:0]         stream_psum_addr;
wire [ADDR_WIDTH-1:0]         stream_out_addr;
wire [ADDR_WIDTH-1:0]         stream_out_push_addr;
wire [ADDR_WIDTH-1:0]         queued_i_word_offset;
wire [ADDR_WIDTH-1:0]         queued_psum_word_offset;
wire [ADDR_WIDTH-1:0]         queued_i_addr;
wire [ADDR_WIDTH-1:0]         queued_psum_addr;
wire [RUN_COUNT_WIDTH-1:0]                    start_data_run_count;
wire [3:0]                    iopsum_union_lease_delay;
wire [8:0]                    iopsum_union_lease_cycles;
wire [2:0]                    iopsum_union_i_channel;
wire [2:0]                    iopsum_union_psum_channel;
wire [2:0]                    iopsum_union_o_channel;
wire [7:0]                    iopsum_union_channel_mask;
wire [BANK_NUM-1:0]           in_mask;
wire [BANK_NUM-1:0]           out_mask;
wire [BANK_NUM-1:0]           psum_mask;
wire [BANK_NUM-1:0]           weight_mask;
wire [BANK_NUM-1:0]           step_mask;
wire                          step_conflict;
wire                          step_fire;
wire [ADDR_WIDTH-1:0]         start_cycles;
wire                          start_cmd_req;
wire                          start_accept;
wire                          start_queue_accept;
wire                          start_direct_launch;
wire                          start_queue_launch;
wire                          start_launch;
wire                          launch_start_tile;
wire [ADDR_WIDTH-1:0]         launch_in_ptr;
wire [ADDR_WIDTH-1:0]         launch_out_ptr;
wire [ADDR_WIDTH-1:0]         launch_psum_ptr;
wire [RUN_COUNT_WIDTH-1:0]    launch_run_count;
wire                          launch_weight_buf;
wire                          tensor_read_req;
wire                          tensor_iopsum_read_req;
wire                          tensor_lane0_i_read_req;
wire                          tensor_lane1_psum_read_req;
wire                          tensor_lane1_read_accept;
wire                          tensor_lane2_write_req;
wire                          tensor_lane2_write_accept;
wire                          tensor_wld_read_req;
wire                          tensor_write_req;
wire                          dtcm_active;
wire                          tensor_start_base_ready;
wire [2:0]                    start_phase_next;
wire [2:0]                    in_pair;
wire [2:0]                    psum_pair;
wire [2:0]                    out_pair;
wire                          setup_buf_next;
wire [3:0]                    setup_cur_dtype;
wire [3:0]                    setup_cur_wtype;
wire [ADDR_WIDTH-1:0]         setup_cur_in_ptr;
wire [ADDR_WIDTH-1:0]         setup_cur_psum_ptr;
wire [ADDR_WIDTH-1:0]         setup_cur_out_ptr;
wire [RUN_COUNT_WIDTH-1:0]    setup_cur_run_count;
wire                          setup_cur_run_count_valid;
wire [3:0]                    plan_next_dtype;
wire [3:0]                    plan_next_wtype;
wire [ADDR_WIDTH-1:0]         plan_next_in_ptr;
wire [ADDR_WIDTH-1:0]         plan_next_psum_ptr;
wire [ADDR_WIDTH-1:0]         plan_next_out_ptr;
wire [RUN_COUNT_WIDTH-1:0]                    plan_next_run_count;
wire                          plan_next_run_count_valid;
wire                          plan_ptr_update;
wire                          cmd_wld_any_req;
wire                          tensor_core_output_valid;
wire [127:0]                  tensor_core_output;
wire [127:0]                  iopsum_input_vec;
wire                          iopsum_input_ready;
wire [127:0]                  iopsum_output_vec;
wire                          iopsum_output_ready;
wire [127:0]                  iopsum_psum_vec;
wire                          iopsum_psum_ready;
wire                          iopsum_clear_i_psum;
wire                          iopsum_clear_o;
wire                          iopsum_output_push_valid;
wire                          tensor_read_accept;
wire                          tensor_wld_read_accept;
wire                          tensor_write_accept;
wire                          tensor_read_issue_req;
wire                          stream_active;
wire                          stream_i_base_req;
wire                          stream_i_current_req;
wire                          stream_i_prefetch_base_req;
wire                          stream_i_prefetch_req;
wire                          stream_i_req;
wire                          stream_psum_base_req;
wire                          stream_psum_current_req;
wire                          stream_psum_prefetch_base_req;
wire                          stream_psum_prefetch_req;
wire                          stream_psum_req;
wire                          stream_out_base_req;
wire                          stream_out_req;
wire [STREAM_FIFO_INDEX_WIDTH:0] stream_out_total_pending;
wire                          stream_i_current_accept;
wire                          stream_i_prefetch_accept;
wire                          stream_psum_current_accept;
wire                          stream_psum_prefetch_accept;
wire                          stream_i_push;
wire                          stream_psum_push;
wire                          stream_out_push;
wire                          stream_compute_fire;
wire                          stream_out_pop;
wire                          stream_current_done;
wire                          stream_done;
wire                          rsp_tag_push;
wire                          rsp_tag_pop;
wire                          rsp_tag_full;
wire                          rsp_tag_empty;
wire [1:0]                    rsp_pop_role;
wire                          rsp_pop_hi;
wire                          tensor_pair_lane_valid;
wire [63:0]                   tensor_pair_lane_data;
wire                          tensor_pair_lane_hi;
wire [1:0]                    tensor_pair_lane_role;
wire                          wld_fill_start_req;
wire                          wld_fill_start_ready;
wire                          wld_fill_busy;
wire                          wld_fill_done;
wire                          wld_fill_load_done;
wire                          wld_cmd_can_launch;
wire                          wld_cmd_immediate_launch;
wire                          wld_cmd_pending_launch;
wire                          wld_cmd_launch;
wire                          wld_cmd_queue_accept;
wire [ADDR_WIDTH-1:0]         wld_cmd_launch_ptr;
wire                          wld_cmd_launch_transpose;
wire                          wld_cmd_launch_bf16;
wire                          wld_reg_load_done;
wire                          wld_reg_drain_busy;
wire                          wld_reg_drain_done;
wire                          tensor_weight_fill_start;
wire                          tensor_weight_fill_bf16_mode;
wire                          tensor_weight_fill_start_ready;
wire                          tensor_weight_fill_valid;
wire                          tensor_weight_fill_ready;
wire [1:0]                    tensor_weight_fill_pair_idx;
wire [127:0]                  tensor_weight_fill_data;
wire                          tensor_weight_fill_last;
wire                          tensor_weight_activate_ready;
wire                          tensor_weight_fill_busy;
wire                          tensor_weight_pending_valid;
wire [127:0]                  tensor_core_input_vec;
wire [127:0]                  tensor_core_psum_vec;
integer                       plan_phase_i;
integer                       rsp_tag_i;
integer                       setup_i;

localparam DTCM_IDLE         = 4'd0;
localparam DTCM_RD_IN_LO     = 4'd1;
localparam DTCM_WAIT_IN_LO   = 4'd2;
localparam DTCM_RD_IN_HI     = 4'd3;
localparam DTCM_WAIT_IN_HI   = 4'd4;
localparam DTCM_RD_PSUM_LO   = 4'd5;
localparam DTCM_WAIT_PSUM_LO = 4'd6;
localparam DTCM_RD_PSUM_HI   = 4'd7;
localparam DTCM_WAIT_PSUM_HI = 4'd8;
localparam DTCM_COMPUTE      = 4'd9;
localparam DTCM_WAIT_COMPUTE = 4'd10;
localparam DTCM_WR_OUT_LO    = 4'd11;
localparam DTCM_WR_OUT_HI    = 4'd12;
localparam DTCM_STREAM       = 4'd15;

localparam [1:0] TENSOR_RSP_ROLE_NONE = 2'd0;
localparam [1:0] TENSOR_RSP_ROLE_I    = 2'd1;
localparam [1:0] TENSOR_RSP_ROLE_PSUM = 2'd2;
localparam [1:0] TENSOR_RSP_ROLE_O    = 2'd3;

localparam [2:0] TENSOR_STREAM_I_CHANNEL    = 3'd0;
localparam [2:0] TENSOR_STREAM_PSUM_CHANNEL = 3'd2;
localparam [2:0] TENSOR_STREAM_OUT_CHANNEL  = 3'd4;

function [BANK_NUM-1:0] tensor_bank_pair_mask;
  input [ADDR_WIDTH-1:0] addr;
  integer                mask_idx;
  reg [ADDR_WIDTH-1:0]   addr_next;
begin
  addr_next = addr + {{ADDR_WIDTH-1{1'b0}}, 1'b1};
  tensor_bank_pair_mask[BANK_NUM-1:0] = {BANK_NUM{1'b0}};
  for (mask_idx = 0; mask_idx < BANK_NUM; mask_idx = mask_idx + 1) begin
    if (addr[BANK_INDEX_WIDTH-1:0] == mask_idx[BANK_INDEX_WIDTH-1:0])
      tensor_bank_pair_mask[mask_idx] = 1'b1;
    if (addr_next[BANK_INDEX_WIDTH-1:0] == mask_idx[BANK_INDEX_WIDTH-1:0])
      tensor_bank_pair_mask[mask_idx] = 1'b1;
  end
end
endfunction

function [7:0] tensor_channel_onehot;
  input [ADDR_WIDTH-1:0] addr;
begin
  tensor_channel_onehot[7:0] = 8'b0;
  tensor_channel_onehot[addr[3:1]] = 1'b1;
end
endfunction

function [2:0] tensor_plan_channel;
  input [2:0] pair;
  input [2:0] phase_at_start;
  input [3:0] delay;
begin
  tensor_plan_channel[2:0] = pair[2:0]
                           - (phase_at_start[2:0] + delay[2:0]);
end
endfunction

function tensor_stream_phase_match;
  input [2:0] phase_in;
  input [2:0] channel_in;
  input [ADDR_WIDTH-1:0] addr;
begin
  tensor_stream_phase_match = ((phase_in[2:0] + channel_in[2:0])
                               === addr[3:1]);
end
endfunction

function [7:0] tensor_channel_id_onehot;
  input [2:0] channel_id;
begin
  tensor_channel_id_onehot[7:0] = 8'b0;
  tensor_channel_id_onehot[channel_id[2:0]] = 1'b1;
end
endfunction

function [1:0] tensor_plan_o_comp;
  input [2:0] i_pair_in;
  input [2:0] out_pair_in;
  input [2:0] phase_in;
  reg [2:0] i_ch;
  reg [2:0] out_ch;
begin
  i_ch = tensor_plan_channel(i_pair_in, phase_in,
                             TENSOR_I_BASE_DELAY[3:0]);
  out_ch = tensor_plan_channel(out_pair_in, phase_in,
                               TENSOR_O_BASE_DELAY[3:0]);
  tensor_plan_o_comp = (out_ch == i_ch) ? 2'd1 : 2'd0;
end
endfunction

function [1:0] tensor_plan_psum_comp;
  input [2:0] i_pair_in;
  input [2:0] out_pair_in;
  input [2:0] psum_pair_in;
  input [2:0] phase_in;
  input [1:0] o_comp_in;
  reg [2:0] i_ch;
  reg [2:0] out_ch;
  reg [2:0] psum_ch;
  reg [3:0] out_delay;
  reg [3:0] psum_delay;
  integer loop_i;
begin
  i_ch = tensor_plan_channel(i_pair_in, phase_in,
                             TENSOR_I_BASE_DELAY[3:0]);
  out_delay = TENSOR_O_BASE_DELAY[3:0] + {2'b0, o_comp_in[1:0]};
  out_ch = tensor_plan_channel(out_pair_in, phase_in,
                               out_delay[3:0]);
  tensor_plan_psum_comp = 2'd0;
  for (loop_i = 0; loop_i < 2; loop_i = loop_i + 1) begin
    psum_delay = TENSOR_PSUM_BASE_DELAY[3:0]
               + {2'b0, tensor_plan_psum_comp[1:0]};
    psum_ch = tensor_plan_channel(psum_pair_in, phase_in,
                                  psum_delay[3:0]);
    if ((psum_ch == i_ch || psum_ch == out_ch)
        && tensor_plan_psum_comp != 2'd2)
      tensor_plan_psum_comp = tensor_plan_psum_comp + 2'd1;
  end
end
endfunction

function [8:0] tensor_plan_cycles;
  input [3:0] delay_in;
  input [8:0] run_cycles_in;
  reg [3:0] delay_delta;
begin
  delay_delta = (delay_in > TENSOR_I_BASE_DELAY[3:0])
              ? (delay_in - TENSOR_I_BASE_DELAY[3:0])
              : 4'b0;
  tensor_plan_cycles = run_cycles_in[8:0] + {5'b0, delay_delta[3:0]};
end
endfunction

assign dtcm_active = dtcm_state[3:0] != DTCM_IDLE;
assign cmd_wld_any_req = cmd_wld_req || cmd_wld_trans_req;
assign tensor_cmd_ready = !wld_fetch_active
                        && !wld_cmd_pending
                        && !wld_fill_busy
                        && wld_ready;
assign wld_cmd_can_launch = !wld_fetch_active
                          && !queued_start_valid
                          && wld_fill_start_ready;
assign tensor_wld_cmd_ready = !wld_cmd_pending && wld_cmd_can_launch;
assign wld_cmd_immediate_launch = cmd_wld_any_req
                                && !wld_cmd_pending
                                && wld_cmd_can_launch;
assign wld_cmd_pending_launch = wld_cmd_pending && wld_cmd_can_launch;
assign wld_cmd_launch = wld_cmd_pending_launch || wld_cmd_immediate_launch;
assign wld_cmd_queue_accept = cmd_wld_any_req
                            && !wld_cmd_pending
                            && !wld_cmd_can_launch;
assign wld_cmd_launch_ptr[ADDR_WIDTH-1:0] =
       wld_cmd_pending_launch ? wld_cmd_pending_ptr[ADDR_WIDTH-1:0]
                              : cmd_wld_ptr[ADDR_WIDTH-1:0];
assign wld_cmd_launch_transpose =
       wld_cmd_pending_launch ? wld_cmd_pending_transpose
                              : cmd_wld_trans_req;
assign wld_cmd_launch_bf16 =
       wld_cmd_pending_launch ? wld_cmd_pending_bf16
                              : (setup_cur_wtype[3:0] == 4'd1);
assign wld_fill_start_req = wld_cmd_launch;
assign wld_reg_load_done = wld_fill_load_done;
assign wld_reg_drain_busy = wld_fill_busy;
assign wld_reg_drain_done = wld_fill_done;
assign tensor_start_base_ready = !busy && !dtcm_active;
assign tensor_start_ready = wld_ready && weight_loaded_valid
                          && (tensor_start_base_ready || !queued_start_valid);
assign start_cmd_req = cmd_start_req || cmd_start_tile_req;
assign start_accept = start_cmd_req && tensor_start_ready;
assign start_queue_accept = start_accept && !tensor_start_base_ready;
assign start_direct_launch = start_accept && tensor_start_base_ready;
assign start_queue_launch = stream_done && queued_start_valid;
assign start_launch = start_direct_launch || start_queue_launch;
assign start_phase_next[2:0] = phase[2:0];
assign setup_buf_next = !setup_buf_sel;
assign setup_cur_dtype[3:0] = setup_dtype[setup_buf_sel][3:0];
assign setup_cur_wtype[3:0] = setup_wtype[setup_buf_sel][3:0];
assign setup_cur_in_ptr[ADDR_WIDTH-1:0] =
       setup_in_ptr[setup_buf_sel][ADDR_WIDTH-1:0];
assign setup_cur_psum_ptr[ADDR_WIDTH-1:0] =
       setup_psum_ptr[setup_buf_sel][ADDR_WIDTH-1:0];
assign setup_cur_out_ptr[ADDR_WIDTH-1:0] =
       setup_out_ptr[setup_buf_sel][ADDR_WIDTH-1:0];
assign setup_cur_run_count[RUN_COUNT_WIDTH-1:0] =
       setup_run_count[setup_buf_sel][RUN_COUNT_WIDTH-1:0];
assign setup_cur_run_count_valid = setup_run_count_valid[setup_buf_sel];
assign plan_next_dtype[3:0] =
       cmd_setcsr_req ? cmd_setcsr_dtype[3:0]
                      : setup_cur_dtype[3:0];
assign plan_next_wtype[3:0] =
       cmd_setcsr_req ? cmd_setcsr_wtype[3:0]
                      : setup_cur_wtype[3:0];
assign plan_next_in_ptr[ADDR_WIDTH-1:0] =
       cmd_setin_req ? cmd_setin_ptr[ADDR_WIDTH-1:0]
                     : setup_cur_in_ptr[ADDR_WIDTH-1:0];
assign plan_next_psum_ptr[ADDR_WIDTH-1:0] =
       cmd_setpsum_req ? cmd_setpsum_ptr[ADDR_WIDTH-1:0]
                       : setup_cur_psum_ptr[ADDR_WIDTH-1:0];
assign plan_next_out_ptr[ADDR_WIDTH-1:0] =
       cmd_setout_req ? cmd_setout_ptr[ADDR_WIDTH-1:0]
                      : setup_cur_out_ptr[ADDR_WIDTH-1:0];
assign plan_next_run_count[RUN_COUNT_WIDTH-1:0] =
       cmd_setn_req ? cmd_setn_value[RUN_COUNT_WIDTH-1:0]
                    : setup_cur_run_count[RUN_COUNT_WIDTH-1:0];
assign plan_next_run_count_valid =
       cmd_setn_req || setup_cur_run_count_valid;
assign plan_ptr_update = cmd_setin_req || cmd_setout_req || cmd_setpsum_req
                       || cmd_setn_req;
assign start_data_run_count[RUN_COUNT_WIDTH-1:0] =
       cmd_start_tile_req ? {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1} :
       (plan_next_run_count_valid ? plan_next_run_count[RUN_COUNT_WIDTH-1:0]
                                  : {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1});
assign launch_start_tile = start_queue_launch ? queued_start_tile
                                               : cmd_start_tile_req;
assign launch_in_ptr[ADDR_WIDTH-1:0] =
       start_queue_launch ? queued_in_ptr[ADDR_WIDTH-1:0]
                          : plan_next_in_ptr[ADDR_WIDTH-1:0];
assign launch_out_ptr[ADDR_WIDTH-1:0] =
       start_queue_launch ? queued_out_ptr[ADDR_WIDTH-1:0]
                          : plan_next_out_ptr[ADDR_WIDTH-1:0];
assign launch_psum_ptr[ADDR_WIDTH-1:0] =
       start_queue_launch ? queued_psum_ptr[ADDR_WIDTH-1:0]
                          : plan_next_psum_ptr[ADDR_WIDTH-1:0];
assign launch_run_count[RUN_COUNT_WIDTH-1:0] =
       launch_start_tile ? {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1} :
       (start_queue_launch ? queued_run_count[RUN_COUNT_WIDTH-1:0]
                           : start_data_run_count[RUN_COUNT_WIDTH-1:0]);
assign launch_weight_buf = start_queue_launch ? queued_weight_buf
                                              : weight_loaded_buf_q;
assign iopsum_union_lease_delay[3:0] = TENSOR_IO_LEASE_DELAY[3:0];
assign iopsum_union_lease_cycles[8:0] =
       launch_run_count[8:0] + 9'd16;
assign iopsum_union_i_channel[2:0] =
       tensor_plan_channel(launch_in_ptr[3:1],
                           start_phase_next[2:0],
                           iopsum_union_lease_delay[3:0]);
assign iopsum_union_psum_channel[2:0] =
       tensor_plan_channel(launch_psum_ptr[3:1],
                           start_phase_next[2:0],
                           iopsum_union_lease_delay[3:0]);
assign iopsum_union_o_channel[2:0] =
       tensor_plan_channel(launch_out_ptr[3:1],
                           start_phase_next[2:0],
                           iopsum_union_lease_delay[3:0]);
assign iopsum_union_channel_mask[7:0] =
       tensor_channel_id_onehot(iopsum_union_i_channel[2:0])
     | tensor_channel_id_onehot(iopsum_union_psum_channel[2:0])
     | tensor_channel_id_onehot(iopsum_union_o_channel[2:0]);
assign data_vec_word_offset[ADDR_WIDTH-1:0] =
       {data_vec_index[ADDR_WIDTH-2:0], 1'b0};
assign stream_i_word_offset[ADDR_WIDTH-1:0] =
       {stream_i_issue_index[ADDR_WIDTH-2:0], 1'b0};
assign stream_psum_word_offset[ADDR_WIDTH-1:0] =
       {stream_psum_issue_index[ADDR_WIDTH-2:0], 1'b0};
assign stream_out_word_offset[ADDR_WIDTH-1:0] =
       {stream_out_write_index[ADDR_WIDTH-2:0], 1'b0};
assign stream_out_push_word_offset[ADDR_WIDTH-1:0] =
       {stream_out_push_index[ADDR_WIDTH-2:0], 1'b0};
assign queued_i_word_offset[ADDR_WIDTH-1:0] =
       {queued_i_issue_index[ADDR_WIDTH-2:0], 1'b0};
assign queued_psum_word_offset[ADDR_WIDTH-1:0] =
       {queued_psum_issue_index[ADDR_WIDTH-2:0], 1'b0};
assign stream_i_addr[ADDR_WIDTH-1:0] =
       active_in_ptr[ADDR_WIDTH-1:0] + stream_i_word_offset[ADDR_WIDTH-1:0];
assign stream_psum_addr[ADDR_WIDTH-1:0] =
       active_psum_ptr[ADDR_WIDTH-1:0] + stream_psum_word_offset[ADDR_WIDTH-1:0];
assign stream_out_addr[ADDR_WIDTH-1:0] =
       stream_out_addr_fifo[stream_out_head][ADDR_WIDTH-1:0];
assign stream_out_push_addr[ADDR_WIDTH-1:0] =
       active_out_ptr[ADDR_WIDTH-1:0]
     + stream_out_push_word_offset[ADDR_WIDTH-1:0];
assign queued_i_addr[ADDR_WIDTH-1:0] =
       queued_in_ptr[ADDR_WIDTH-1:0] + queued_i_word_offset[ADDR_WIDTH-1:0];
assign queued_psum_addr[ADDR_WIDTH-1:0] =
       queued_psum_ptr[ADDR_WIDTH-1:0] + queued_psum_word_offset[ADDR_WIDTH-1:0];

assign out_step_addr[ADDR_WIDTH-1:0] =
       active_out_ptr[ADDR_WIDTH-1:0] + {{ADDR_WIDTH-STEP_WIDTH{1'b0}}, step};
assign in_step_addr[ADDR_WIDTH-1:0] =
       active_in_ptr[ADDR_WIDTH-1:0] + {{ADDR_WIDTH-STEP_WIDTH{1'b0}}, step};
assign psum_step_addr[ADDR_WIDTH-1:0] =
       active_psum_ptr[ADDR_WIDTH-1:0] + {{ADDR_WIDTH-STEP_WIDTH{1'b0}}, step};
assign weight_step_addr[ADDR_WIDTH-1:0] =
       weight_ptr[ADDR_WIDTH-1:0] + {{ADDR_WIDTH-STEP_WIDTH{1'b0}}, step};

assign out_mask[BANK_NUM-1:0] =
       tensor_bank_pair_mask(out_step_addr[ADDR_WIDTH-1:0]);
assign in_mask[BANK_NUM-1:0] =
       tensor_bank_pair_mask(in_step_addr[ADDR_WIDTH-1:0]);
assign psum_mask[BANK_NUM-1:0] =
       tensor_bank_pair_mask(psum_step_addr[ADDR_WIDTH-1:0]);
assign weight_mask[BANK_NUM-1:0] =
       tensor_bank_pair_mask(weight_step_addr[ADDR_WIDTH-1:0]);
assign step_mask[BANK_NUM-1:0] =
       out_mask[BANK_NUM-1:0]
     | in_mask[BANK_NUM-1:0]
     | psum_mask[BANK_NUM-1:0]
     | weight_mask[BANK_NUM-1:0];

assign step_conflict = busy
                    && ((step_mask[BANK_NUM-1:0]
                         & lsu_resv_plus1[BANK_NUM-1:0])
                        != {BANK_NUM{1'b0}});
assign step_fire = busy && !step_conflict;
assign start_cycles[ADDR_WIDTH-1:0] =
       {{ADDR_WIDTH-1{1'b0}}, 1'b1}
     + PIPELINE_LATENCY[ADDR_WIDTH-1:0];

assign tensor_resv_plus2_req = step_fire;
assign tensor_resv_plus2_mask[BANK_NUM-1:0] =
       step_fire ? step_mask[BANK_NUM-1:0] : {BANK_NUM{1'b0}};
assign dma_delay_req = step_conflict;
assign tensor_sync_stall = dtcm_active || wld_fetch_active || !wld_ready
                         || queued_start_valid;
assign tensor_busy = tensor_sync_stall;
assign stream_active = dtcm_state == DTCM_STREAM;
assign stream_current_done =
       stream_active
    && (stream_i_issue_index[RUN_COUNT_WIDTH-1:0] >= data_run_remaining[RUN_COUNT_WIDTH-1:0])
    && (stream_psum_issue_index[RUN_COUNT_WIDTH-1:0] >= data_run_remaining[RUN_COUNT_WIDTH-1:0])
    && (stream_compute_index[RUN_COUNT_WIDTH-1:0] >= data_run_remaining[RUN_COUNT_WIDTH-1:0])
    && (stream_out_push_index[RUN_COUNT_WIDTH-1:0] >= data_run_remaining[RUN_COUNT_WIDTH-1:0])
    && (stream_out_inflight_count[STREAM_FIFO_INDEX_WIDTH:0]
        == {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}});
assign stream_i_base_req = stream_active
                        && (stream_i_issue_index[RUN_COUNT_WIDTH-1:0]
                            < data_run_remaining[RUN_COUNT_WIDTH-1:0])
                        && ((stream_i_count[STREAM_FIFO_INDEX_WIDTH:0]
                             + stream_i_inflight_count[STREAM_FIFO_INDEX_WIDTH:0])
                            < STREAM_FIFO_DEPTH[STREAM_FIFO_INDEX_WIDTH:0]);
assign stream_i_current_req = stream_i_base_req
                           && tensor_stream_phase_match(
                                phase[2:0],
                                TENSOR_STREAM_I_CHANNEL[2:0],
                                stream_i_addr[ADDR_WIDTH-1:0]);
assign stream_i_prefetch_base_req = stream_active
                                 && queued_start_valid
                                 && !stream_current_done
                                 && (stream_i_issue_index[RUN_COUNT_WIDTH-1:0]
                                     >= data_run_remaining[RUN_COUNT_WIDTH-1:0])
                                 && (queued_i_issue_index[RUN_COUNT_WIDTH-1:0]
                                     < queued_run_count[RUN_COUNT_WIDTH-1:0])
                                 && ((stream_i_count[STREAM_FIFO_INDEX_WIDTH:0]
                                      + stream_i_inflight_count[STREAM_FIFO_INDEX_WIDTH:0])
                                     < STREAM_FIFO_DEPTH[STREAM_FIFO_INDEX_WIDTH:0]);
assign stream_i_prefetch_req = !stream_i_current_req
                            && stream_i_prefetch_base_req
                            && tensor_stream_phase_match(
                                 phase[2:0],
                                 TENSOR_STREAM_I_CHANNEL[2:0],
                                 queued_i_addr[ADDR_WIDTH-1:0]);
assign stream_i_req = stream_i_current_req || stream_i_prefetch_req;
assign stream_psum_base_req = stream_active
                           && (stream_psum_issue_index[RUN_COUNT_WIDTH-1:0]
                               < data_run_remaining[RUN_COUNT_WIDTH-1:0])
                           && ((stream_psum_count[STREAM_FIFO_INDEX_WIDTH:0]
                                + stream_psum_inflight_count[STREAM_FIFO_INDEX_WIDTH:0])
                               < STREAM_FIFO_DEPTH[STREAM_FIFO_INDEX_WIDTH:0]);
assign stream_psum_current_req = stream_psum_base_req
                              && tensor_stream_phase_match(
                                   phase[2:0],
                                   TENSOR_STREAM_PSUM_CHANNEL[2:0],
                                   stream_psum_addr[ADDR_WIDTH-1:0]);
assign stream_psum_prefetch_base_req = stream_active
                                    && queued_start_valid
                                    && !stream_current_done
                                    && (stream_psum_issue_index[RUN_COUNT_WIDTH-1:0]
                                        >= data_run_remaining[RUN_COUNT_WIDTH-1:0])
                                    && (queued_psum_issue_index[RUN_COUNT_WIDTH-1:0]
                                        < queued_run_count[RUN_COUNT_WIDTH-1:0])
                                    && ((stream_psum_count[STREAM_FIFO_INDEX_WIDTH:0]
                                         + stream_psum_inflight_count[STREAM_FIFO_INDEX_WIDTH:0])
                                        < STREAM_FIFO_DEPTH[STREAM_FIFO_INDEX_WIDTH:0]);
assign stream_psum_prefetch_req = !stream_psum_current_req
                               && stream_psum_prefetch_base_req
                               && tensor_stream_phase_match(
                                    phase[2:0],
                                    TENSOR_STREAM_PSUM_CHANNEL[2:0],
                                    queued_psum_addr[ADDR_WIDTH-1:0]);
assign stream_psum_req = stream_psum_current_req || stream_psum_prefetch_req;
assign stream_out_base_req = stream_active
                          && (stream_out_count[STREAM_FIFO_INDEX_WIDTH:0]
                              != {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}});
assign stream_out_req = stream_out_base_req
                     && tensor_stream_phase_match(
                          phase[2:0],
                          TENSOR_STREAM_OUT_CHANNEL[2:0],
                          stream_out_addr[ADDR_WIDTH-1:0]);
assign tensor_lane0_i_read_req = stream_i_req
                              || (dtcm_state == DTCM_RD_IN_LO)
                              || (dtcm_state == DTCM_RD_IN_HI);
assign tensor_lane1_psum_read_req = stream_psum_req
                                 || (dtcm_state == DTCM_RD_PSUM_LO)
                                 || (dtcm_state == DTCM_RD_PSUM_HI);
assign tensor_iopsum_read_req = tensor_lane0_i_read_req;
assign tensor_wld_read_req = wld_fetch_active && !wld_fetch_wait;
assign tensor_read_req = tensor_iopsum_read_req;
assign tensor_lane2_write_req = stream_out_req
                             || (dtcm_state == DTCM_WR_OUT_LO)
                             || (dtcm_state == DTCM_WR_OUT_HI);
assign tensor_write_req = 1'b0;
assign rsp_tag_empty = rsp_tag_count[2:0] == 3'b0;
assign rsp_tag_full = rsp_tag_count[2:0] == 3'd4;
assign tensor_read_issue_req = tensor_read_req && !rsp_tag_full;
assign tensor_read_accept = tensor_read_issue_req && tensor_ready;
assign tensor_wld_read_accept = tensor_wld_read_req && tensor_wld_ready;
assign tensor_lane1_read_accept =
       tensor_lane1_psum_read_req && tensor_lane1_ready;
assign tensor_lane2_write_accept =
       tensor_lane2_write_req && tensor_lane2_ready;
assign tensor_write_accept = tensor_lane2_write_accept;
assign stream_i_current_accept = tensor_read_accept && stream_i_current_req;
assign stream_i_prefetch_accept = tensor_read_accept && stream_i_prefetch_req;
assign stream_psum_current_accept =
       tensor_lane1_read_accept && stream_psum_current_req;
assign stream_psum_prefetch_accept =
       tensor_lane1_read_accept && stream_psum_prefetch_req;
assign rsp_tag_push = tensor_read_accept && tensor_iopsum_read_req;
assign rsp_tag_pop = tensor_rvalid && !rsp_tag_empty;
assign tensor_req = tensor_read_issue_req || tensor_write_req;
assign tensor_we = tensor_write_req;
assign tensor_addr[ADDR_WIDTH-1:0] =
       stream_i_current_req              ? stream_i_addr[ADDR_WIDTH-1:0]
     : stream_i_prefetch_req             ? queued_i_addr[ADDR_WIDTH-1:0]
     : (dtcm_state == DTCM_RD_IN_LO)     ? active_in_ptr[ADDR_WIDTH-1:0]
                                           + data_vec_word_offset[ADDR_WIDTH-1:0]
     : (dtcm_state == DTCM_RD_IN_HI)     ? active_in_ptr[ADDR_WIDTH-1:0]
                                           + data_vec_word_offset[ADDR_WIDTH-1:0]
                                           + {{ADDR_WIDTH-1{1'b0}}, 1'b1}
                                        : {ADDR_WIDTH{1'b0}};
assign tensor_wld_req = tensor_wld_read_req;
assign tensor_wld_addr[ADDR_WIDTH-1:0] =
       weight_ptr[ADDR_WIDTH-1:0]
     + {{ADDR_WIDTH-4{1'b0}}, wld_read_idx[2:0], 1'b0};
assign tensor_wdata[63:0] = 64'b0;
assign tensor_wstrb[7:0] = tensor_write_req ? 8'hff : 8'h00;
assign tensor_io_lease_valid = tensor_io_lease_valid_q;
assign tensor_io_lease_channel_mask[7:0] =
       tensor_io_lease_channel_mask_q[7:0];
assign tensor_io_lease_cycles[8:0] = tensor_io_lease_cycles_q[8:0];
assign tensor_io_lease_delay[3:0] = tensor_io_lease_delay_q[3:0];
assign tensor_io_lease1_valid = tensor_io_lease1_valid_q;
assign tensor_io_lease1_channel_mask[7:0] =
       tensor_io_lease1_channel_mask_q[7:0];
assign tensor_io_lease1_cycles[8:0] = tensor_io_lease1_cycles_q[8:0];
assign tensor_io_lease1_delay[3:0] = tensor_io_lease1_delay_q[3:0];
assign tensor_io_lease2_valid = tensor_io_lease2_valid_q;
assign tensor_io_lease2_channel_mask[7:0] =
       tensor_io_lease2_channel_mask_q[7:0];
assign tensor_io_lease2_cycles[8:0] = tensor_io_lease2_cycles_q[8:0];
assign tensor_io_lease2_delay[3:0] = tensor_io_lease2_delay_q[3:0];
assign tensor_wld_lease_valid = cmd_wld_any_req;
assign tensor_lane1_addr[ADDR_WIDTH-1:0] =
       stream_psum_current_req
       ? stream_psum_addr[ADDR_WIDTH-1:0]
       : stream_psum_prefetch_req
       ? queued_psum_addr[ADDR_WIDTH-1:0]
       : (dtcm_state == DTCM_RD_PSUM_HI)
       ? active_psum_ptr[ADDR_WIDTH-1:0]
       + data_vec_word_offset[ADDR_WIDTH-1:0]
       + {{ADDR_WIDTH-1{1'b0}}, 1'b1}
       : active_psum_ptr[ADDR_WIDTH-1:0]
       + data_vec_word_offset[ADDR_WIDTH-1:0];
assign tensor_lane1_req = tensor_lane1_psum_read_req;
assign tensor_lane1_wdata[63:0] = 64'b0;
assign tensor_lane1_we = 1'b0;
assign tensor_lane1_wstrb[7:0] = 8'b0;
assign tensor_lane2_addr[ADDR_WIDTH-1:0] =
       stream_out_req
       ? stream_out_addr[ADDR_WIDTH-1:0]
       : (dtcm_state == DTCM_WR_OUT_HI)
       ? active_out_ptr[ADDR_WIDTH-1:0]
       + data_vec_word_offset[ADDR_WIDTH-1:0]
       + {{ADDR_WIDTH-1{1'b0}}, 1'b1}
       : active_out_ptr[ADDR_WIDTH-1:0]
       + data_vec_word_offset[ADDR_WIDTH-1:0];
assign tensor_lane2_req = tensor_lane2_write_req;
assign tensor_lane2_wdata[63:0] =
       stream_out_req ? stream_out_fifo[stream_out_head][63:0]
     : (dtcm_state == DTCM_WR_OUT_HI) ? iopsum_output_vec[127:64]
                                      : iopsum_output_vec[63:0];
assign tensor_lane2_we = tensor_lane2_write_req;
assign tensor_lane2_wstrb[7:0] = tensor_lane2_write_req ? 8'hff : 8'h00;
assign tensor_lane2_pair_wdata[127:0] =
       stream_out_req ? stream_out_fifo[stream_out_head][127:0]
                      : iopsum_output_vec[127:0];
assign tensor_lane2_pair_wstrb[15:0] =
       stream_out_req ? 16'hffff
     : tensor_lane2_write_req && (dtcm_state == DTCM_WR_OUT_LO)
       ? 16'hffff : 16'h0000;
assign tensor_wld_lease_channel_mask[7:0] =
       tensor_channel_onehot(cmd_wld_ptr[ADDR_WIDTH-1:0]);
assign tensor_wld_lease_cycles[8:0] =
       (setup_cur_wtype[3:0] == 4'd1) ? 9'd8 : 9'd4;
assign tensor_wld_lease_delay[3:0] = TENSOR_WLD_LEASE_DELAY[3:0];

assign in_pair[2:0] = active_in_ptr[3:1];
assign psum_pair[2:0] = active_psum_ptr[3:1];
assign out_pair[2:0] = active_out_ptr[3:1];

assign cur_tensor_out_req_mask[BANK_NUM-1:0] =
       step_fire ? out_mask[BANK_NUM-1:0] : {BANK_NUM{1'b0}};
assign cur_tensor_in_req_mask[BANK_NUM-1:0] =
       step_fire ? in_mask[BANK_NUM-1:0] : {BANK_NUM{1'b0}};
assign cur_tensor_prefetch_req_mask[BANK_NUM-1:0] =
       step_fire ? weight_mask[BANK_NUM-1:0] : {BANK_NUM{1'b0}};

assign dbg_dtype[3:0] = setup_cur_dtype[3:0];
assign dbg_wtype[3:0] = setup_cur_wtype[3:0];
assign dbg_step[STEP_WIDTH-1:0] = step[STEP_WIDTH-1:0];
assign dbg_phase[2:0] = phase[2:0];
assign dbg_start_phase[2:0] = start_phase[2:0];
assign dbg_iopsum_plan_valid = iopsum_plan_valid;
assign dbg_i_lease_delay[3:0] = i_lease_delay[3:0];
assign dbg_psum_lease_delay[3:0] = psum_lease_delay[3:0];
assign dbg_o_lease_delay[3:0] = o_lease_delay[3:0];
assign dbg_i_lease_channel[2:0] = i_lease_channel[2:0];
assign dbg_psum_lease_channel[2:0] = psum_lease_channel[2:0];
assign dbg_o_lease_channel[2:0] = o_lease_channel[2:0];
assign dbg_i_lease_cycles[8:0] = i_lease_cycles[8:0];
assign dbg_psum_lease_cycles[8:0] = psum_lease_cycles[8:0];
assign dbg_o_lease_cycles[8:0] = o_lease_cycles[8:0];
assign dbg_i_comp_delay[1:0] = i_comp_delay[1:0];
assign dbg_psum_comp_delay[1:0] = psum_comp_delay[1:0];
assign dbg_o_comp_delay[1:0] = o_comp_delay[1:0];
assign rsp_pop_role[1:0] =
       rsp_tag_empty ? TENSOR_RSP_ROLE_NONE : rsp_tag_role[rsp_tag_head];
assign rsp_pop_hi = rsp_tag_empty ? 1'b0 : rsp_tag_hi[rsp_tag_head];
assign tensor_pair_lane_valid = rsp_tag_pop
                             && tensor_pair_rvalid
                             && (rsp_pop_role[1:0] != TENSOR_RSP_ROLE_NONE)
                             && (tensor_pair_rsp_high == rsp_pop_hi);
assign tensor_pair_lane_data[63:0] =
       rsp_pop_hi ? tensor_pair_rdata[63:0]
                  : tensor_pair_rdata[127:64];
assign tensor_pair_lane_hi = !rsp_pop_hi;
assign tensor_pair_lane_role[1:0] = rsp_pop_role[1:0];
assign iopsum_clear_i_psum = compute_valid_q || start_launch;
assign iopsum_clear_o = tensor_write_accept
                     && (dtcm_state == DTCM_WR_OUT_LO)
                     || start_launch;
assign iopsum_output_push_valid = tensor_core_output_valid;
assign tensor_core_input_vec[127:0] =
       stream_active ? stream_compute_input_q[127:0]
                     : iopsum_input_vec[127:0];
assign tensor_core_psum_vec[127:0] =
       stream_active ? stream_compute_psum_q[127:0]
                     : iopsum_psum_vec[127:0];
assign stream_i_push = stream_active && tensor_pair_rvalid;
assign stream_psum_push = stream_active && tensor_lane1_pair_rvalid;
assign stream_compute_fire =
       stream_active
    && (stream_compute_index[RUN_COUNT_WIDTH-1:0] < data_run_remaining[RUN_COUNT_WIDTH-1:0])
    && (stream_i_count[STREAM_FIFO_INDEX_WIDTH:0]
        != {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}})
    && (stream_psum_count[STREAM_FIFO_INDEX_WIDTH:0]
        != {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}})
    && ((stream_out_total_pending[STREAM_FIFO_INDEX_WIDTH:0]
         <= STREAM_FIFO_DEPTH[STREAM_FIFO_INDEX_WIDTH:0])
        || stream_out_pop);
assign stream_out_push = stream_active && tensor_core_output_valid;
assign stream_out_pop = stream_active && tensor_write_accept;
assign stream_out_total_pending[STREAM_FIFO_INDEX_WIDTH:0] =
       stream_out_count[STREAM_FIFO_INDEX_WIDTH:0]
     + stream_out_inflight_count[STREAM_FIFO_INDEX_WIDTH:0]
     + {{STREAM_FIFO_INDEX_WIDTH{1'b0}}, stream_out_skid_valid};
assign stream_done =
       stream_current_done
    && (queued_start_valid
        || ((stream_i_count[STREAM_FIFO_INDEX_WIDTH:0]
             == {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}})
            && (stream_i_inflight_count[STREAM_FIFO_INDEX_WIDTH:0]
                == {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}})
            && (stream_psum_count[STREAM_FIFO_INDEX_WIDTH:0]
                == {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}})
            && (stream_psum_inflight_count[STREAM_FIFO_INDEX_WIDTH:0]
                == {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}})
            && (stream_out_count[STREAM_FIFO_INDEX_WIDTH:0]
                == {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}})
            && !stream_out_skid_valid));

edge_tensor_iopsum_remux x_edge_tensor_iopsum_remux (
  .clk              (clk),
  .clear_i_psum     (iopsum_clear_i_psum),
  .clear_o          (iopsum_clear_o),
  .input_vec        (iopsum_input_vec[127:0]),
  .input_vec_ready  (iopsum_input_ready),
  .lane0_data       (tensor_rdata[63:0]),
  .lane0_hi         (rsp_pop_hi),
  .lane0_role       (rsp_pop_role[1:0]),
  .lane0_valid      (rsp_tag_pop),
  .lane1_data       (tensor_pair_lane_valid
                     ? tensor_pair_lane_data[63:0]
                     : tensor_lane1_data[63:0]),
  .lane1_hi         (tensor_pair_lane_valid
                     ? tensor_pair_lane_hi
                     : tensor_lane1_hi),
  .lane1_role       (tensor_pair_lane_valid
                     ? tensor_pair_lane_role[1:0]
                     : tensor_lane1_role[1:0]),
  .lane1_valid      (tensor_pair_lane_valid || tensor_lane1_valid),
  .lane1_pair_data  (tensor_lane1_pair_rdata[127:0]),
  .lane1_pair_role  (TENSOR_RSP_ROLE_PSUM),
  .lane1_pair_valid (tensor_lane1_pair_rvalid),
  .lane2_data       (tensor_lane2_data[63:0]),
  .lane2_hi         (tensor_lane2_hi),
  .lane2_role       (tensor_lane2_role[1:0]),
  .lane2_valid      (tensor_lane2_valid),
  .output_push_data (tensor_core_output[127:0]),
  .output_push_valid(iopsum_output_push_valid),
  .output_vec       (iopsum_output_vec[127:0]),
  .output_vec_ready (iopsum_output_ready),
  .psum_vec         (iopsum_psum_vec[127:0]),
  .psum_vec_ready   (iopsum_psum_ready),
  .rst_b            (cpurst_b)
);

edge_tensor_wld8x8_fill x_edge_tensor_wld8x8_fill (
  .clk                    (clk),
  .rst_b                  (cpurst_b),
  .start                  (wld_fill_start_req),
  .start_ready            (wld_fill_start_ready),
  .start_bf16_mode        (wld_cmd_launch_bf16),
  .start_transpose        (wld_cmd_launch_transpose),
  .busy                   (wld_fill_busy),
  .done                   (wld_fill_done),
  .load_valid             (wld_reg_load_valid_q),
  .load_idx               (wld_reg_load_idx_q[2:0]),
  .load_data              (wld_reg_load_data_q[127:0]),
  .load_done              (wld_fill_load_done),
  .weight_fill_start      (tensor_weight_fill_start),
  .weight_fill_bf16_mode  (tensor_weight_fill_bf16_mode),
  .weight_fill_start_ready(tensor_weight_fill_start_ready),
  .weight_fill_valid      (tensor_weight_fill_valid),
  .weight_fill_ready      (tensor_weight_fill_ready),
  .weight_fill_pair_idx   (tensor_weight_fill_pair_idx[1:0]),
  .weight_fill_data       (tensor_weight_fill_data[127:0]),
  .weight_fill_last       (tensor_weight_fill_last)
);

edge_tile8x8_unit x_tile8x8 (
  .clk                 (clk),
  .rst_b               (cpurst_b),
  .compute_valid       (compute_valid_q),
  .late_psum_mode_i    (1'b0),
  .late_psum_valid_i   (1'b1),
  .input_bf16_i        (tensor_core_input_vec[127:0]),
  .scale_enable_i      (1'b0),
  .scale_bf16_i        (128'b0),
  .rsum_enable_i       (1'b0),
  .rsum_first_i        (1'b0),
  .rsum_last_i         (1'b0),
  .weight_fill_bf16_mode_i(tensor_weight_fill_bf16_mode),
  .output_bf16_o       (tensor_core_output[127:0]),
  .output_valid        (tensor_core_output_valid),
  .psum_bf16_i         (tensor_core_psum_vec[127:0]),
  .weight_fill_start   (tensor_weight_fill_start),
  .weight_fill_start_ready(tensor_weight_fill_start_ready),
  .weight_fill_valid   (tensor_weight_fill_valid),
  .weight_fill_ready   (tensor_weight_fill_ready),
  .weight_fill_pair_idx(tensor_weight_fill_pair_idx[1:0]),
  .weight_fill_data    (tensor_weight_fill_data[127:0]),
  .weight_fill_last    (tensor_weight_fill_last),
  .weight_activate     (start_launch),
  .weight_activate_ready(tensor_weight_activate_ready),
  .weight_fill_busy    (tensor_weight_fill_busy),
  .weight_pending_valid(tensor_weight_pending_valid),
  .dot_ready_o         ()
);

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    dtype[3:0] <= 4'b0;
    wtype[3:0] <= 4'b0;
    setup_buf_sel <= 1'b0;
    for (setup_i = 0; setup_i < 2; setup_i = setup_i + 1) begin
      setup_dtype[setup_i][3:0] <= 4'b0;
      setup_wtype[setup_i][3:0] <= 4'b0;
      setup_in_ptr[setup_i][ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
      setup_out_ptr[setup_i][ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
      setup_psum_ptr[setup_i][ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
      setup_run_count[setup_i][RUN_COUNT_WIDTH-1:0] <= {{RUN_COUNT_WIDTH-9{1'b0}}, TENSOR_IO_PLAN_CYCLES[8:0]};
      setup_run_count_valid[setup_i] <= 1'b0;
    end
    active_in_ptr[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
    active_out_ptr[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
    active_psum_ptr[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
    weight_ptr[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
    run_count[RUN_COUNT_WIDTH-1:0] <= {{RUN_COUNT_WIDTH-9{1'b0}}, TENSOR_IO_PLAN_CYCLES[8:0]};
    run_count_valid <= 1'b0;
    data_run_remaining[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
    data_vec_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
    stream_i_issue_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
    stream_psum_issue_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
    stream_compute_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
    stream_out_write_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
    stream_out_push_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
    queued_i_issue_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
    queued_psum_issue_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
    cycles_left[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
    step[STEP_WIDTH-1:0] <= {STEP_WIDTH{1'b0}};
    busy <= 1'b0;
    dtcm_state[3:0] <= DTCM_IDLE;
    compute_valid_q <= 1'b0;
    rsp_tag_hi[3:0] <= 4'b0;
    rsp_tag_head[1:0] <= 2'b0;
    rsp_tag_tail[1:0] <= 2'b0;
    rsp_tag_count[2:0] <= 3'b0;
    wld_read_idx[2:0] <= 3'b0;
    wld_load_idx[2:0] <= 3'b0;
    wld_read_lo[63:0] <= 64'b0;
    wld_reg_drain_transpose <= 1'b0;
    wld_cmd_pending <= 1'b0;
    wld_cmd_pending_transpose <= 1'b0;
    wld_cmd_pending_bf16 <= 1'b0;
    wld_cmd_pending_ptr[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
    wld_fetch_active <= 1'b0;
    wld_fetch_wait <= 1'b0;
    wld_active_bf16 <= 1'b0;
    weight_active_buf_q <= 1'b0;
    weight_active_valid <= 1'b0;
    weight_load_buf_q <= 1'b1;
    weight_loaded_buf_q <= 1'b0;
    weight_loaded_valid <= 1'b0;
    queued_start_valid <= 1'b0;
    queued_start_tile <= 1'b0;
    queued_dtype[3:0] <= 4'b0;
    queued_wtype[3:0] <= 4'b0;
    queued_in_ptr[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
    queued_out_ptr[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
    queued_psum_ptr[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
    queued_run_count[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
    queued_weight_buf <= 1'b0;
    wld_reg_load_data_q[127:0] <= 128'b0;
    wld_reg_load_idx_q[2:0] <= 3'b0;
    wld_reg_load_valid_q <= 1'b0;
    wld_ready <= 1'b1;
    phase[2:0] <= 3'b0;
    start_phase[2:0] <= 3'b0;
    iopsum_plan_valid <= 1'b0;
    i_lease_delay[3:0] <= 4'b0;
    psum_lease_delay[3:0] <= 4'b0;
    o_lease_delay[3:0] <= 4'b0;
    i_lease_channel[2:0] <= 3'b0;
    psum_lease_channel[2:0] <= 3'b0;
    o_lease_channel[2:0] <= 3'b0;
    i_lease_cycles[8:0] <= 9'b0;
    psum_lease_cycles[8:0] <= 9'b0;
    o_lease_cycles[8:0] <= 9'b0;
    i_comp_delay[1:0] <= 2'b0;
    psum_comp_delay[1:0] <= 2'b0;
    o_comp_delay[1:0] <= 2'b0;
    tensor_io_lease_channel_mask_q[7:0] <= 8'b0;
    tensor_io_lease_cycles_q[8:0] <= 9'b0;
    tensor_io_lease_delay_q[3:0] <= 4'b0;
    tensor_io_lease_valid_q <= 1'b0;
    tensor_io_lease1_channel_mask_q[7:0] <= 8'b0;
    tensor_io_lease1_cycles_q[8:0] <= 9'b0;
    tensor_io_lease1_delay_q[3:0] <= 4'b0;
    tensor_io_lease1_valid_q <= 1'b0;
    tensor_io_lease2_channel_mask_q[7:0] <= 8'b0;
    tensor_io_lease2_cycles_q[8:0] <= 9'b0;
    tensor_io_lease2_delay_q[3:0] <= 4'b0;
    tensor_io_lease2_valid_q <= 1'b0;
    plan_table_valid <= 1'b0;
    stream_i_head <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
    stream_i_tail <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
    stream_i_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
    stream_i_inflight_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
    stream_psum_head <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
    stream_psum_tail <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
    stream_psum_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
    stream_psum_inflight_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
    stream_out_head <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
    stream_out_tail <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
    stream_out_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
    stream_out_inflight_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
    stream_out_skid_valid <= 1'b0;
    stream_out_skid_data[127:0] <= 128'b0;
    stream_out_skid_addr[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
    stream_compute_input_q[127:0] <= 128'b0;
    stream_compute_psum_q[127:0] <= 128'b0;
    for (plan_phase_i = 0; plan_phase_i < 8; plan_phase_i = plan_phase_i + 1) begin
      plan_table_i_delay[plan_phase_i] <= 4'b0;
      plan_table_psum_delay[plan_phase_i] <= 4'b0;
      plan_table_o_delay[plan_phase_i] <= 4'b0;
      plan_table_i_channel[plan_phase_i] <= 3'b0;
      plan_table_psum_channel[plan_phase_i] <= 3'b0;
      plan_table_o_channel[plan_phase_i] <= 3'b0;
      plan_table_i_cycles[plan_phase_i] <= 9'b0;
      plan_table_psum_cycles[plan_phase_i] <= 9'b0;
      plan_table_o_cycles[plan_phase_i] <= 9'b0;
      plan_table_i_comp[plan_phase_i] <= 2'b0;
      plan_table_psum_comp[plan_phase_i] <= 2'b0;
      plan_table_o_comp[plan_phase_i] <= 2'b0;
    end
    for (rsp_tag_i = 0; rsp_tag_i < 4; rsp_tag_i = rsp_tag_i + 1) begin
      rsp_tag_role[rsp_tag_i] <= TENSOR_RSP_ROLE_NONE;
    end
  end else begin
    phase[2:0] <= phase[2:0] + 3'd1;
    tensor_io_lease_valid_q <= 1'b0;
    tensor_io_lease1_valid_q <= 1'b0;
    tensor_io_lease2_valid_q <= 1'b0;
    compute_valid_q <= 1'b0;
    wld_reg_load_valid_q <= 1'b0;

    if (wld_fill_done) begin
      wld_ready <= 1'b1;
      weight_loaded_valid <= 1'b1;
      weight_loaded_buf_q <= weight_load_buf_q;
    end

    if (wld_fetch_active && tensor_wld_rvalid) begin
      wld_reg_load_data_q[127:0] <= tensor_wld_rdata[127:0];
      wld_reg_load_idx_q[2:0] <= wld_load_idx[2:0];
      wld_reg_load_valid_q <= 1'b1;
      wld_load_idx[2:0] <= wld_load_idx[2:0] + 3'd1;
      if (wld_fetch_wait
          && wld_load_idx[2:0] == (wld_active_bf16 ? 3'd7 : 3'd3)) begin
        wld_fetch_active <= 1'b0;
        wld_fetch_wait <= 1'b0;
      end
    end

    if (rsp_tag_pop) begin
      rsp_tag_role[rsp_tag_head] <= TENSOR_RSP_ROLE_NONE;
      rsp_tag_hi[rsp_tag_head] <= 1'b0;
      rsp_tag_head[1:0] <= rsp_tag_head[1:0] + 2'd1;
    end

    if (rsp_tag_push) begin
      rsp_tag_tail[1:0] <= rsp_tag_tail[1:0] + 2'd1;
    end

    case ({rsp_tag_push, rsp_tag_pop})
      2'b10: rsp_tag_count[2:0] <= rsp_tag_count[2:0] + 3'd1;
      2'b01: rsp_tag_count[2:0] <= rsp_tag_count[2:0] - 3'd1;
      default: begin
      end
    endcase

    if (cmd_setcsr_req) begin
      setup_dtype[setup_buf_sel][3:0] <= cmd_setcsr_dtype[3:0];
      setup_wtype[setup_buf_sel][3:0] <= cmd_setcsr_wtype[3:0];
    end

    if (stream_active) begin
      if (stream_i_current_accept)
        stream_i_issue_index[RUN_COUNT_WIDTH-1:0] <= stream_i_issue_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
      if (stream_i_prefetch_accept)
        queued_i_issue_index[RUN_COUNT_WIDTH-1:0] <= queued_i_issue_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
      case ({tensor_read_accept && stream_i_req, stream_i_push})
        2'b10: stream_i_inflight_count <= stream_i_inflight_count + 1'b1;
        2'b01: stream_i_inflight_count <= stream_i_inflight_count - 1'b1;
        default: begin
        end
      endcase

      if (stream_psum_current_accept)
        stream_psum_issue_index[RUN_COUNT_WIDTH-1:0] <= stream_psum_issue_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
      if (stream_psum_prefetch_accept)
        queued_psum_issue_index[RUN_COUNT_WIDTH-1:0] <= queued_psum_issue_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
      case ({tensor_lane1_read_accept && stream_psum_req, stream_psum_push})
        2'b10: stream_psum_inflight_count <= stream_psum_inflight_count + 1'b1;
        2'b01: stream_psum_inflight_count <= stream_psum_inflight_count - 1'b1;
        default: begin
        end
      endcase

      if (stream_i_push) begin
        stream_i_fifo[stream_i_tail][127:0] <= tensor_pair_rdata[127:0];
        stream_i_tail <= stream_i_tail + 1'b1;
      end
      if (stream_compute_fire)
        stream_i_head <= stream_i_head + 1'b1;
      case ({stream_i_push, stream_compute_fire})
        2'b10: stream_i_count <= stream_i_count + 1'b1;
        2'b01: stream_i_count <= stream_i_count - 1'b1;
        default: begin
        end
      endcase

      if (stream_psum_push) begin
        stream_psum_fifo[stream_psum_tail][127:0]
          <= tensor_lane1_pair_rdata[127:0];
        stream_psum_tail <= stream_psum_tail + 1'b1;
      end
      if (stream_compute_fire)
        stream_psum_head <= stream_psum_head + 1'b1;
      case ({stream_psum_push, stream_compute_fire})
        2'b10: stream_psum_count <= stream_psum_count + 1'b1;
        2'b01: stream_psum_count <= stream_psum_count - 1'b1;
        default: begin
        end
      endcase

      if (stream_compute_fire) begin
        stream_compute_input_q[127:0] <= stream_i_fifo[stream_i_head][127:0];
        stream_compute_psum_q[127:0] <= stream_psum_fifo[stream_psum_head][127:0];
        stream_compute_index[RUN_COUNT_WIDTH-1:0] <= stream_compute_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
      end
      case ({stream_compute_fire, stream_out_push})
        2'b10: stream_out_inflight_count <= stream_out_inflight_count + 1'b1;
        2'b01: stream_out_inflight_count <= stream_out_inflight_count - 1'b1;
        default: begin
        end
      endcase

      if (stream_out_pop) begin
        stream_out_head <= stream_out_head + 1'b1;
        stream_out_write_index[RUN_COUNT_WIDTH-1:0] <= stream_out_write_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
      end

      if (stream_out_skid_valid) begin
        if (stream_out_pop) begin
          stream_out_fifo[stream_out_tail][127:0] <= stream_out_skid_data[127:0];
          stream_out_addr_fifo[stream_out_tail][ADDR_WIDTH-1:0] <= stream_out_skid_addr[ADDR_WIDTH-1:0];
          stream_out_tail <= stream_out_tail + 1'b1;
          if (stream_out_push) begin
            stream_out_skid_data[127:0] <= tensor_core_output[127:0];
            stream_out_skid_addr[ADDR_WIDTH-1:0] <= stream_out_push_addr[ADDR_WIDTH-1:0];
            stream_out_push_index[RUN_COUNT_WIDTH-1:0] <= stream_out_push_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
          end else begin
            stream_out_skid_valid <= 1'b0;
          end
        end
      end else if (stream_out_push) begin
        if ((stream_out_count[STREAM_FIFO_INDEX_WIDTH:0]
             == STREAM_FIFO_DEPTH[STREAM_FIFO_INDEX_WIDTH:0])
            && !stream_out_pop) begin
          stream_out_skid_valid <= 1'b1;
          stream_out_skid_data[127:0] <= tensor_core_output[127:0];
          stream_out_skid_addr[ADDR_WIDTH-1:0] <= stream_out_push_addr[ADDR_WIDTH-1:0];
          stream_out_push_index[RUN_COUNT_WIDTH-1:0] <= stream_out_push_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
        end else begin
          stream_out_fifo[stream_out_tail][127:0] <= tensor_core_output[127:0];
          stream_out_addr_fifo[stream_out_tail][ADDR_WIDTH-1:0] <= stream_out_push_addr[ADDR_WIDTH-1:0];
          stream_out_tail <= stream_out_tail + 1'b1;
          stream_out_push_index[RUN_COUNT_WIDTH-1:0] <= stream_out_push_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
        end
      end

      if (!stream_out_skid_valid) begin
        case ({stream_out_push
               && !((stream_out_count[STREAM_FIFO_INDEX_WIDTH:0]
                     == STREAM_FIFO_DEPTH[STREAM_FIFO_INDEX_WIDTH:0])
                    && !stream_out_pop),
               stream_out_pop})
          2'b10: stream_out_count <= stream_out_count + 1'b1;
          2'b01: stream_out_count <= stream_out_count - 1'b1;
          default: begin
          end
        endcase
      end

      if (stream_done) begin
        dtcm_state[3:0] <= DTCM_IDLE;
        data_run_remaining[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
        busy <= 1'b0;
      end
    end

    if (cmd_setn_req) begin
      setup_run_count[setup_buf_sel][RUN_COUNT_WIDTH-1:0] <=
        cmd_setn_value[RUN_COUNT_WIDTH-1:0];
      setup_run_count_valid[setup_buf_sel] <= 1'b1;
    end

    if (wld_cmd_pending_launch)
      wld_cmd_pending <= 1'b0;

    if (wld_cmd_queue_accept) begin
      wld_cmd_pending <= 1'b1;
      wld_cmd_pending_transpose <= cmd_wld_trans_req;
      wld_cmd_pending_bf16 <= setup_cur_wtype[3:0] == 4'd1;
      wld_cmd_pending_ptr[ADDR_WIDTH-1:0] <= cmd_wld_ptr[ADDR_WIDTH-1:0];
      weight_loaded_valid <= 1'b0;
      wld_ready <= 1'b0;
    end

    if (wld_fill_start_req) begin
      weight_ptr[ADDR_WIDTH-1:0] <= wld_cmd_launch_ptr[ADDR_WIDTH-1:0];
      wld_fetch_active <= 1'b1;
      wld_fetch_wait <= 1'b0;
      wld_active_bf16 <= wld_cmd_launch_bf16;
      wld_read_idx[2:0] <= 3'b0;
      wld_load_idx[2:0] <= 3'b0;
      wld_reg_drain_transpose <= wld_cmd_launch_transpose;
      weight_load_buf_q <= !weight_active_buf_q;
      weight_loaded_valid <= 1'b0;
      wld_ready <= 1'b0;
    end

    if (cmd_setin_req)
      setup_in_ptr[setup_buf_sel][ADDR_WIDTH-1:0] <=
        cmd_setin_ptr[ADDR_WIDTH-1:0];

    if (cmd_setout_req)
      setup_out_ptr[setup_buf_sel][ADDR_WIDTH-1:0] <=
        cmd_setout_ptr[ADDR_WIDTH-1:0];

    if (cmd_setpsum_req)
      setup_psum_ptr[setup_buf_sel][ADDR_WIDTH-1:0] <=
        cmd_setpsum_ptr[ADDR_WIDTH-1:0];

    if (start_accept) begin
      setup_buf_sel <= setup_buf_next;
      setup_dtype[setup_buf_next][3:0] <= plan_next_dtype[3:0];
      setup_wtype[setup_buf_next][3:0] <= plan_next_wtype[3:0];
      setup_in_ptr[setup_buf_next][ADDR_WIDTH-1:0] <=
        plan_next_in_ptr[ADDR_WIDTH-1:0];
      setup_out_ptr[setup_buf_next][ADDR_WIDTH-1:0] <=
        plan_next_out_ptr[ADDR_WIDTH-1:0];
      setup_psum_ptr[setup_buf_next][ADDR_WIDTH-1:0] <=
        plan_next_psum_ptr[ADDR_WIDTH-1:0];
      setup_run_count[setup_buf_next][RUN_COUNT_WIDTH-1:0] <=
        plan_next_run_count[RUN_COUNT_WIDTH-1:0];
      setup_run_count_valid[setup_buf_next] <= plan_next_run_count_valid;
    end

    if (start_queue_accept) begin
      queued_start_valid <= 1'b1;
      queued_start_tile <= cmd_start_tile_req;
      queued_dtype[3:0] <= plan_next_dtype[3:0];
      queued_wtype[3:0] <= plan_next_wtype[3:0];
      queued_in_ptr[ADDR_WIDTH-1:0] <= plan_next_in_ptr[ADDR_WIDTH-1:0];
      queued_out_ptr[ADDR_WIDTH-1:0] <= plan_next_out_ptr[ADDR_WIDTH-1:0];
      queued_psum_ptr[ADDR_WIDTH-1:0] <= plan_next_psum_ptr[ADDR_WIDTH-1:0];
      queued_run_count[RUN_COUNT_WIDTH-1:0] <= start_data_run_count[RUN_COUNT_WIDTH-1:0];
      queued_weight_buf <= weight_loaded_buf_q;
      queued_i_issue_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
      queued_psum_issue_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
      weight_loaded_valid <= 1'b0;
    end

    if (plan_ptr_update) begin
      plan_table_valid <= 1'b1;
      for (plan_phase_i = 0; plan_phase_i < 8; plan_phase_i = plan_phase_i + 1) begin
        plan_table_i_comp[plan_phase_i] <= 2'b0;
        plan_table_o_comp[plan_phase_i] <=
          tensor_plan_o_comp(plan_next_in_ptr[3:1],
                             plan_next_out_ptr[3:1],
                             plan_phase_i[2:0]);
        plan_table_psum_comp[plan_phase_i] <=
          tensor_plan_psum_comp(
              plan_next_in_ptr[3:1],
              plan_next_out_ptr[3:1],
              plan_next_psum_ptr[3:1],
              plan_phase_i[2:0],
              tensor_plan_o_comp(plan_next_in_ptr[3:1],
                                 plan_next_out_ptr[3:1],
                                 plan_phase_i[2:0]));
        plan_table_i_delay[plan_phase_i] <= TENSOR_I_BASE_DELAY[3:0];
        plan_table_psum_delay[plan_phase_i] <=
          TENSOR_PSUM_BASE_DELAY[3:0]
        + {2'b0, tensor_plan_psum_comp(plan_next_in_ptr[3:1],
                                       plan_next_out_ptr[3:1],
                                       plan_next_psum_ptr[3:1],
                                       plan_phase_i[2:0],
                                       tensor_plan_o_comp(
                                         plan_next_in_ptr[3:1],
                                         plan_next_out_ptr[3:1],
                                         plan_phase_i[2:0]))};
        plan_table_o_delay[plan_phase_i] <=
          TENSOR_O_BASE_DELAY[3:0]
        + {2'b0, tensor_plan_o_comp(plan_next_in_ptr[3:1],
                                    plan_next_out_ptr[3:1],
                                    plan_phase_i[2:0])};
        plan_table_i_channel[plan_phase_i] <=
          tensor_plan_channel(plan_next_in_ptr[3:1],
                              plan_phase_i[2:0],
                              TENSOR_I_BASE_DELAY[3:0]);
        plan_table_psum_channel[plan_phase_i] <=
          tensor_plan_channel(
              plan_next_psum_ptr[3:1],
              plan_phase_i[2:0],
              TENSOR_PSUM_BASE_DELAY[3:0]
            + {2'b0, tensor_plan_psum_comp(plan_next_in_ptr[3:1],
                                           plan_next_out_ptr[3:1],
                                           plan_next_psum_ptr[3:1],
                                           plan_phase_i[2:0],
                                           tensor_plan_o_comp(
                                             plan_next_in_ptr[3:1],
                                             plan_next_out_ptr[3:1],
                                             plan_phase_i[2:0]))});
        plan_table_o_channel[plan_phase_i] <=
          tensor_plan_channel(
              plan_next_out_ptr[3:1],
              plan_phase_i[2:0],
              TENSOR_O_BASE_DELAY[3:0]
            + {2'b0, tensor_plan_o_comp(plan_next_in_ptr[3:1],
                                        plan_next_out_ptr[3:1],
                                        plan_phase_i[2:0])});
        plan_table_i_cycles[plan_phase_i] <=
          plan_next_run_count[8:0];
        plan_table_psum_cycles[plan_phase_i] <=
          plan_next_run_count[8:0]
        + {7'b0, tensor_plan_psum_comp(plan_next_in_ptr[3:1],
                                       plan_next_out_ptr[3:1],
                                       plan_next_psum_ptr[3:1],
                                       plan_phase_i[2:0],
                                       tensor_plan_o_comp(
                                         plan_next_in_ptr[3:1],
                                         plan_next_out_ptr[3:1],
                                         plan_phase_i[2:0]))};
        plan_table_o_cycles[plan_phase_i] <=
          plan_next_run_count[8:0]
        + {7'b0, tensor_plan_o_comp(plan_next_in_ptr[3:1],
                                    plan_next_out_ptr[3:1],
                                    plan_phase_i[2:0])};
      end
    end

    if (start_launch) begin
      dtype[3:0] <= start_queue_launch ? queued_dtype[3:0]
                                       : plan_next_dtype[3:0];
      wtype[3:0] <= start_queue_launch ? queued_wtype[3:0]
                                       : plan_next_wtype[3:0];
      active_in_ptr[ADDR_WIDTH-1:0] <= launch_in_ptr[ADDR_WIDTH-1:0];
      active_out_ptr[ADDR_WIDTH-1:0] <= launch_out_ptr[ADDR_WIDTH-1:0];
      active_psum_ptr[ADDR_WIDTH-1:0] <= launch_psum_ptr[ADDR_WIDTH-1:0];
      run_count[RUN_COUNT_WIDTH-1:0] <= launch_run_count[RUN_COUNT_WIDTH-1:0];
      run_count_valid <= 1'b1;
      cycles_left[ADDR_WIDTH-1:0] <= start_cycles[ADDR_WIDTH-1:0];
      step[STEP_WIDTH-1:0] <= {STEP_WIDTH{1'b0}};
      data_run_remaining[RUN_COUNT_WIDTH-1:0] <= launch_run_count[RUN_COUNT_WIDTH-1:0];
      data_vec_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
      if (start_queue_launch) begin
        stream_i_issue_index[RUN_COUNT_WIDTH-1:0] <= queued_i_issue_index[RUN_COUNT_WIDTH-1:0];
        stream_psum_issue_index[RUN_COUNT_WIDTH-1:0] <= queued_psum_issue_index[RUN_COUNT_WIDTH-1:0];
      end else begin
        stream_i_issue_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
        stream_psum_issue_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
      end
      queued_i_issue_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
      queued_psum_issue_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
      stream_compute_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
      stream_out_write_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
      stream_out_push_index[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
      if (!start_queue_launch) begin
        stream_i_head <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
        stream_i_tail <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
        stream_i_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
        stream_i_inflight_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
        stream_psum_head <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
        stream_psum_tail <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
        stream_psum_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
        stream_psum_inflight_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
      end
      if (!start_queue_launch) begin
        stream_out_head <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
        stream_out_tail <= {STREAM_FIFO_INDEX_WIDTH{1'b0}};
        stream_out_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
        stream_out_inflight_count <= {(STREAM_FIFO_INDEX_WIDTH+1){1'b0}};
        stream_out_skid_valid <= 1'b0;
        stream_out_skid_data[127:0] <= 128'b0;
        stream_out_skid_addr[ADDR_WIDTH-1:0] <= {ADDR_WIDTH{1'b0}};
      end
      stream_compute_input_q[127:0] <= 128'b0;
      stream_compute_psum_q[127:0] <= 128'b0;
      busy <= 1'b1;
      dtcm_state[3:0] <= DTCM_STREAM;
      weight_active_buf_q <= launch_weight_buf;
      weight_active_valid <= 1'b1;
      weight_loaded_valid <= 1'b0;
      if (start_queue_launch)
        queued_start_valid <= 1'b0;
      rsp_tag_hi[3:0] <= 4'b0;
      rsp_tag_head[1:0] <= 2'b0;
      rsp_tag_tail[1:0] <= 2'b0;
      rsp_tag_count[2:0] <= 3'b0;
      for (rsp_tag_i = 0; rsp_tag_i < 4; rsp_tag_i = rsp_tag_i + 1) begin
        rsp_tag_role[rsp_tag_i] <= TENSOR_RSP_ROLE_NONE;
      end
      start_phase[2:0] <= start_phase_next[2:0];
      iopsum_plan_valid <= 1'b1;
      i_lease_delay[3:0] <= iopsum_union_lease_delay[3:0];
      psum_lease_delay[3:0] <= iopsum_union_lease_delay[3:0];
      o_lease_delay[3:0] <= iopsum_union_lease_delay[3:0];
      i_lease_channel[2:0] <= iopsum_union_i_channel[2:0];
      psum_lease_channel[2:0] <= iopsum_union_psum_channel[2:0];
      o_lease_channel[2:0] <= iopsum_union_o_channel[2:0];
      i_lease_cycles[8:0] <= iopsum_union_lease_cycles[8:0];
      psum_lease_cycles[8:0] <= iopsum_union_lease_cycles[8:0];
      o_lease_cycles[8:0] <= iopsum_union_lease_cycles[8:0];
      i_comp_delay[1:0] <= 2'b0;
      psum_comp_delay[1:0] <= 2'b0;
      o_comp_delay[1:0] <= 2'b0;
      tensor_io_lease_channel_mask_q[7:0] <= iopsum_union_channel_mask[7:0];
      tensor_io_lease_cycles_q[8:0] <= iopsum_union_lease_cycles[8:0];
      tensor_io_lease_delay_q[3:0] <= iopsum_union_lease_delay[3:0];
      tensor_io_lease_valid_q <= 1'b1;
      tensor_io_lease1_channel_mask_q[7:0] <= 8'b0;
      tensor_io_lease1_cycles_q[8:0] <= 9'b0;
      tensor_io_lease1_delay_q[3:0] <= 4'b0;
      tensor_io_lease1_valid_q <= 1'b0;
      tensor_io_lease2_channel_mask_q[7:0] <= 8'b0;
      tensor_io_lease2_cycles_q[8:0] <= 9'b0;
      tensor_io_lease2_delay_q[3:0] <= 4'b0;
      tensor_io_lease2_valid_q <= 1'b0;
    end else if (step_fire) begin
      if (cycles_left[ADDR_WIDTH-1:0] <= {{ADDR_WIDTH-1{1'b0}}, 1'b1})
        busy <= 1'b0;
      else
        cycles_left[ADDR_WIDTH-1:0] <= cycles_left[ADDR_WIDTH-1:0]
                                     - {{ADDR_WIDTH-1{1'b0}}, 1'b1};
      step[STEP_WIDTH-1:0] <= step[STEP_WIDTH-1:0]
                            + {{STEP_WIDTH-1{1'b0}}, 1'b1};
    end

    case (dtcm_state[3:0])
      DTCM_IDLE: begin
        if (start_launch)
          dtcm_state[3:0] <= DTCM_STREAM;
      end
      DTCM_RD_IN_LO: begin
        if (tensor_read_accept) begin
          rsp_tag_role[rsp_tag_tail] <= TENSOR_RSP_ROLE_I;
          rsp_tag_hi[rsp_tag_tail] <= 1'b0;
          dtcm_state[3:0] <= DTCM_RD_IN_HI;
        end
      end
      DTCM_WAIT_IN_LO: begin
        if (tensor_rvalid) begin
          dtcm_state[3:0] <= DTCM_RD_IN_HI;
        end
      end
      DTCM_RD_IN_HI: begin
        if (iopsum_input_ready) begin
          dtcm_state[3:0] <= DTCM_RD_PSUM_LO;
        end else if (tensor_read_accept) begin
          rsp_tag_role[rsp_tag_tail] <= TENSOR_RSP_ROLE_I;
          rsp_tag_hi[rsp_tag_tail] <= 1'b1;
          dtcm_state[3:0] <= DTCM_RD_PSUM_LO;
        end
      end
      DTCM_WAIT_IN_HI: begin
        if (tensor_rvalid) begin
          dtcm_state[3:0] <= DTCM_RD_PSUM_LO;
        end
      end
      DTCM_RD_PSUM_LO: begin
        if (tensor_lane1_read_accept) begin
          dtcm_state[3:0] <= DTCM_WAIT_PSUM_LO;
        end
      end
      DTCM_WAIT_PSUM_LO: begin
        if (iopsum_psum_ready) begin
          dtcm_state[3:0] <= DTCM_COMPUTE;
        end
      end
      DTCM_RD_PSUM_HI: begin
        if (iopsum_psum_ready) begin
          dtcm_state[3:0] <= DTCM_COMPUTE;
        end else if (tensor_lane1_read_accept) begin
          dtcm_state[3:0] <= DTCM_COMPUTE;
        end
      end
      DTCM_WAIT_PSUM_HI: begin
        if (tensor_rvalid) begin
          dtcm_state[3:0] <= DTCM_COMPUTE;
        end
      end
      DTCM_COMPUTE: begin
        if (iopsum_input_ready && iopsum_psum_ready) begin
          compute_valid_q <= 1'b1;
          dtcm_state[3:0] <= DTCM_WAIT_COMPUTE;
        end
      end
      DTCM_WAIT_COMPUTE: begin
        if (iopsum_output_ready) begin
          dtcm_state[3:0] <= DTCM_WR_OUT_LO;
        end
      end
      DTCM_WR_OUT_LO: begin
        if (tensor_write_accept) begin
          if (data_run_remaining[RUN_COUNT_WIDTH-1:0] <= {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1}) begin
            data_run_remaining[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
            dtcm_state[3:0] <= DTCM_IDLE;
          end else begin
            data_run_remaining[RUN_COUNT_WIDTH-1:0] <= data_run_remaining[RUN_COUNT_WIDTH-1:0] - {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
            data_vec_index[RUN_COUNT_WIDTH-1:0] <= data_vec_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
            dtcm_state[3:0] <= DTCM_RD_IN_LO;
          end
        end
      end
      DTCM_WR_OUT_HI: begin
        if (tensor_write_accept) begin
          if (data_run_remaining[RUN_COUNT_WIDTH-1:0] <= {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1}) begin
            data_run_remaining[RUN_COUNT_WIDTH-1:0] <= {RUN_COUNT_WIDTH{1'b0}};
            dtcm_state[3:0] <= DTCM_IDLE;
          end else begin
            data_run_remaining[RUN_COUNT_WIDTH-1:0] <= data_run_remaining[RUN_COUNT_WIDTH-1:0] - {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
            data_vec_index[RUN_COUNT_WIDTH-1:0] <= data_vec_index[RUN_COUNT_WIDTH-1:0] + {{RUN_COUNT_WIDTH-1{1'b0}}, 1'b1};
            dtcm_state[3:0] <= DTCM_RD_IN_LO;
          end
        end
      end
      DTCM_STREAM: begin
        if (stream_compute_fire)
          compute_valid_q <= 1'b1;
      end
      default: begin
        dtcm_state[3:0] <= DTCM_IDLE;
      end
    endcase

    if (tensor_wld_read_accept) begin
      if (wld_read_idx[2:0] == (wld_active_bf16 ? 3'd7 : 3'd3))
        wld_fetch_wait <= 1'b1;
      else
        wld_read_idx[2:0] <= wld_read_idx[2:0] + 3'd1;
    end
  end
end

endmodule
