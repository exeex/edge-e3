module edge_tensor_engine(
  clk, cpurst_b, start, in_base_addr, psum_base_addr, out_base_addr,
  weight_base_addr, vector_count, start_mode, scale_bf16,
  scale_stream_valid, scale_stream_data, scale_stream_ready,
  weight_fill_bf16_mode, weight_fill_start, weight_fill_start_ready,
  weight_fill_valid, weight_fill_ready, weight_fill_pair_idx,
  weight_fill_data, weight_fill_last, weight_pending_valid,
  weight_active_valid, weight_preactivate, start_use_active, weight_idle,
  next_input_prefetch_valid, next_input_prefetch_base_addr,
  next_input_prefetch_vector_count,
  handoff_ready, busy, done, host_req, host_we, host_addr, host_wdata,
  host_wstrb, host_ready, host_rdata, host_rvalid, fabric_phase,
  host_bank_req, host_bank_we, host_bank, host_bank_addr, host_bank_wdata,
  host_bank_wstrb, host_bank_rdata, i_pair_req, i_pair_bank0,
  i_pair_bank1, i_pair_addr, i_pair_rsp_bank0, i_pair_rsp_bank1,
  i_pair_rdata, psum_pair_req, psum_pair_bank0, psum_pair_bank1,
  psum_pair_addr, psum_pair_rsp_bank0, psum_pair_rsp_bank1,
  psum_pair_rdata, o_pair_req, o_pair_bank0, o_pair_bank1, o_pair_addr,
  o_pair_wdata, stream_out_push, stream_i_prefetch_accept,
  stream_psum_prefetch_accept
);

parameter ADDR_WIDTH = 16;
parameter SRAM_ADDR_WIDTH = 10;
parameter DATA_WIDTH = 64;
parameter BANK_NUM = 16;
parameter BANK_INDEX_WIDTH = 4;
parameter VECTOR_COUNT_WIDTH = 16;

localparam BYTE_WIDTH = DATA_WIDTH / 8;
localparam PAIR_WIDTH = DATA_WIDTH * 2;
localparam PSUM_FIFO_DEPTH = 8;
localparam PSUM_FIFO_INDEX_WIDTH = 3;
localparam INPUT_FIFO_DEPTH = 4;
localparam INPUT_FIFO_INDEX_WIDTH = 2;
localparam META_FIFO_DEPTH = 16;
localparam META_FIFO_INDEX_WIDTH = 4;

input clk;
input cpurst_b;
input start;
input [ADDR_WIDTH-1:0] in_base_addr;
input [ADDR_WIDTH-1:0] psum_base_addr;
input [ADDR_WIDTH-1:0] out_base_addr;
input [ADDR_WIDTH-1:0] weight_base_addr;
input [VECTOR_COUNT_WIDTH-1:0] vector_count;
input [7:0] start_mode;
input [127:0] scale_bf16;
input scale_stream_valid;
input [127:0] scale_stream_data;
output scale_stream_ready;
input weight_fill_bf16_mode;
input weight_fill_start;
output weight_fill_start_ready;
input weight_fill_valid;
output weight_fill_ready;
input [1:0] weight_fill_pair_idx;
input [PAIR_WIDTH-1:0] weight_fill_data;
input weight_fill_last;
output weight_pending_valid;
output weight_active_valid;
input weight_preactivate;
input start_use_active;
output weight_idle;
input next_input_prefetch_valid;
input [ADDR_WIDTH-1:0] next_input_prefetch_base_addr;
input [VECTOR_COUNT_WIDTH-1:0] next_input_prefetch_vector_count;
output handoff_ready;
output busy;
output done;
input host_req;
input host_we;
input [ADDR_WIDTH-1:0] host_addr;
input [DATA_WIDTH-1:0] host_wdata;
input [BYTE_WIDTH-1:0] host_wstrb;
output host_ready;
output [DATA_WIDTH-1:0] host_rdata;
output host_rvalid;
input [BANK_INDEX_WIDTH-1:0] fabric_phase;
output host_bank_req;
output host_bank_we;
output [BANK_INDEX_WIDTH-1:0] host_bank;
output [SRAM_ADDR_WIDTH-1:0] host_bank_addr;
output [DATA_WIDTH-1:0] host_bank_wdata;
output [BYTE_WIDTH-1:0] host_bank_wstrb;
input [DATA_WIDTH-1:0] host_bank_rdata;
output i_pair_req;
output [BANK_INDEX_WIDTH-1:0] i_pair_bank0;
output [BANK_INDEX_WIDTH-1:0] i_pair_bank1;
output [SRAM_ADDR_WIDTH-1:0] i_pair_addr;
output [BANK_INDEX_WIDTH-1:0] i_pair_rsp_bank0;
output [BANK_INDEX_WIDTH-1:0] i_pair_rsp_bank1;
input [PAIR_WIDTH-1:0] i_pair_rdata;
output psum_pair_req;
output [BANK_INDEX_WIDTH-1:0] psum_pair_bank0;
output [BANK_INDEX_WIDTH-1:0] psum_pair_bank1;
output [SRAM_ADDR_WIDTH-1:0] psum_pair_addr;
output [BANK_INDEX_WIDTH-1:0] psum_pair_rsp_bank0;
output [BANK_INDEX_WIDTH-1:0] psum_pair_rsp_bank1;
input [PAIR_WIDTH-1:0] psum_pair_rdata;
output o_pair_req;
output [BANK_INDEX_WIDTH-1:0] o_pair_bank0;
output [BANK_INDEX_WIDTH-1:0] o_pair_bank1;
output [SRAM_ADDR_WIDTH-1:0] o_pair_addr;
output [PAIR_WIDTH-1:0] o_pair_wdata;
output stream_out_push;
output stream_i_prefetch_accept;
output stream_psum_prefetch_accept;

reg busy_q;
reg compute_busy_q;
reg done_q;
reg handoff_ready_q;
reg stream_started_q;
reg psum_stream_started_q;
reg [4:0] stream_cycle_q;
reg [3:0] psum_offset_q;
reg [VECTOR_COUNT_WIDTH-1:0] target_count_q;
reg [VECTOR_COUNT_WIDTH-1:0] read_issue_count_q;
reg [VECTOR_COUNT_WIDTH-1:0] input_consume_count_q;
reg [VECTOR_COUNT_WIDTH-1:0] psum_issue_count_q;
reg [ADDR_WIDTH-1:0] in_base_q;
reg [ADDR_WIDTH-1:0] psum_base_q;
reg [ADDR_WIDTH-1:0] out_base_q;
reg iop_rsp_valid_q;
reg psum_rsp_valid_q;
reg [BANK_INDEX_WIDTH-1:0] i_rsp_bank0_q;
reg [BANK_INDEX_WIDTH-1:0] i_rsp_bank1_q;
reg [BANK_INDEX_WIDTH-1:0] psum_rsp_bank0_q;
reg [BANK_INDEX_WIDTH-1:0] psum_rsp_bank1_q;
reg [VECTOR_COUNT_WIDTH-1:0] i_rsp_index_q;
reg i_rsp_next_input_q;
reg [VECTOR_COUNT_WIDTH-1:0] next_input_issue_count_q;
reg [PAIR_WIDTH-1:0] psum_data_fifo [0:PSUM_FIFO_DEPTH-1];
reg [PSUM_FIFO_INDEX_WIDTH-1:0] psum_head_q;
reg [PSUM_FIFO_INDEX_WIDTH-1:0] psum_tail_q;
reg [PSUM_FIFO_INDEX_WIDTH:0] psum_count_q;
reg [ADDR_WIDTH-1:0] meta_addr_fifo [0:META_FIFO_DEPTH-1];
reg meta_scale_fifo [0:META_FIFO_DEPTH-1];
reg meta_first_fifo [0:META_FIFO_DEPTH-1];
reg [META_FIFO_INDEX_WIDTH-1:0] meta_head_q;
reg [META_FIFO_INDEX_WIDTH-1:0] meta_tail_q;
reg [META_FIFO_INDEX_WIDTH:0] meta_count_q;
reg [META_FIFO_INDEX_WIDTH:0] scaled_inflight_count_q;
reg [3:0] output_skew_inflight_q;
reg [5:0] psum_stream_mode_pipe_q;
reg host_rvalid_q;
reg [BANK_INDEX_WIDTH-1:0] host_rsp_bank_q;
reg scale_enable_q;
reg scale_stream_enable_q;
reg [127:0] scale_bf16_q;
reg psum_once_mode_q;
reg psum_none_mode_q;
reg rsum_mode_q;
reg psum_once_valid_q;
reg [PAIR_WIDTH-1:0] psum_once_data_q;

wire [ADDR_WIDTH-1:0] i_req_addr;
wire [ADDR_WIDTH-1:0] psum_req_addr;
wire [BANK_NUM-1:0] i_req_mask;
wire [BANK_NUM-1:0] psum_req_mask;
wire [BANK_NUM-1:0] out_req_mask;
wire [BANK_NUM-1:0] lower_owned_mask;
wire i_req_owned;
wire psum_req_owned;
wire out_req_owned;
wire i_psum_conflict;
wire i_output_conflict;
wire psum_output_conflict;
wire read_conflicts_output;
wire psum_read_conflicts_output;
wire read_candidate;
wire psum_candidate;
wire output_candidate;
wire read_fire;
wire psum_read_fire;
wire output_write_fire;
wire output_pending;
wire output_skew_push;
wire output_skew_pop;
wire output_skew_cfg_valid;
wire [1:0] output_skew_cfg_extra;
wire output_skew_cfg_mid_valid;
wire [1:0] output_skew_cfg_mid_extra;
wire output_skew_cfg_out_valid;
wire [1:0] output_skew_cfg_out_extra;
wire output_skew_mid_valid;
wire [143:0] output_skew_mid_payload;
wire output_skew_valid;
wire [143:0] output_skew_payload;
wire [ADDR_WIDTH-1:0] output_skew_addr;
wire [PAIR_WIDTH-1:0] output_skew_data;
wire psum_fifo_push;
wire psum_fifo_pop;
wire meta_fifo_push;
wire meta_fifo_pop;
wire compute_valid_q;
wire input_head_valid;
wire input_head_from_rsp;
wire input_compute_fire;
wire input_fifo_rsp_store;
wire next_input_fifo_rsp_store;
wire [INPUT_FIFO_INDEX_WIDTH-1:0] input_head_slot;
wire [PAIR_WIDTH-1:0] input_compute_data;
wire [PAIR_WIDTH-1:0] input_window_read_data;
wire [INPUT_FIFO_DEPTH-1:0] input_slot_issued_q;
wire [INPUT_FIFO_DEPTH-1:0] input_slot_valid_q;
wire [INPUT_FIFO_DEPTH-1:0] next_input_slot_issued_q;
wire [INPUT_FIFO_DEPTH-1:0] next_input_slot_valid_q;
wire [ADDR_WIDTH-1:0] input_compute_out_addr;
wire aligned_psum_valid;
wire [PAIR_WIDTH-1:0] aligned_psum_data;
wire compute_psum_valid;
wire [PAIR_WIDTH-1:0] compute_psum_data;
wire [VECTOR_COUNT_WIDTH-1:0] psum_target_count;
wire psum_stream_mode;
wire dot_ready;
wire dot_needs_psum;
wire tensor_output_valid;
wire [PAIR_WIDTH-1:0] tensor_output_data;
wire start_accept;
wire handoff_ready_next;
wire drain_done_next;
wire tensor_weight_fill_start_ready;
wire tensor_weight_fill_ready;
wire tensor_weight_activate_ready;
wire tensor_weight_fill_busy;
wire tensor_weight_active_valid;
wire tensor_weight_pending_valid;
wire [2:0] start_i_pair;
wire [2:0] start_psum_pair;
wire [3:0] start_psum_offset;

integer psum_fifo_i;
integer meta_fifo_i;
integer input_select_offset;
integer next_input_select_offset;

reg input_select_valid;
reg [VECTOR_COUNT_WIDTH-1:0] input_select_index;
reg [INPUT_FIFO_INDEX_WIDTH-1:0] input_select_slot;
reg [ADDR_WIDTH-1:0] input_select_addr;
reg [BANK_NUM-1:0] input_select_mask;
reg [VECTOR_COUNT_WIDTH-1:0] input_select_index_try;
reg [INPUT_FIFO_INDEX_WIDTH-1:0] input_select_slot_try;
reg [ADDR_WIDTH-1:0] input_select_addr_try;
reg [BANK_NUM-1:0] input_select_mask_try;
reg next_input_select_valid;
reg [VECTOR_COUNT_WIDTH-1:0] next_input_select_index;
reg [INPUT_FIFO_INDEX_WIDTH-1:0] next_input_select_slot;
reg [ADDR_WIDTH-1:0] next_input_select_addr;
reg [BANK_NUM-1:0] next_input_select_mask;
reg [VECTOR_COUNT_WIDTH-1:0] next_input_select_index_try;
reg [INPUT_FIFO_INDEX_WIDTH-1:0] next_input_select_slot_try;
reg [ADDR_WIDTH-1:0] next_input_select_addr_try;
reg [BANK_NUM-1:0] next_input_select_mask_try;
wire active_input_select;
wire next_input_select;

function [BANK_NUM-1:0] pair_mask;
  input [ADDR_WIDTH-1:0] addr;
  integer i;
  reg [ADDR_WIDTH-1:0] addr_next;
begin
  addr_next = addr + {{ADDR_WIDTH-1{1'b0}}, 1'b1};
  pair_mask = {BANK_NUM{1'b0}};
  for (i = 0; i < BANK_NUM; i = i + 1) begin
    if (addr[BANK_INDEX_WIDTH-1:0] == i[BANK_INDEX_WIDTH-1:0])
      pair_mask[i] = 1'b1;
    if (addr_next[BANK_INDEX_WIDTH-1:0] == i[BANK_INDEX_WIDTH-1:0])
      pair_mask[i] = 1'b1;
  end
end
endfunction

function [BANK_INDEX_WIDTH-1:0] next_bank;
  input [ADDR_WIDTH-1:0] addr;
begin
  next_bank = addr[BANK_INDEX_WIDTH-1:0]
            + {{BANK_INDEX_WIDTH-1{1'b0}}, 1'b1};
end
endfunction

function [3:0] choose_psum_offset;
  input [2:0] i_pair;
  input [2:0] p_pair;
  integer d;
  reg found;
  reg [2:0] effective_pair;
begin
  choose_psum_offset = 4'd0;
  found = 1'b0;
  for (d = 0; d <= 6; d = d + 1) begin
    effective_pair = p_pair - d[2:0];
    if (!found && effective_pair[0] == i_pair[0]
        && effective_pair != i_pair) begin
      choose_psum_offset = d[3:0];
      found = 1'b1;
    end
  end
end
endfunction

assign start_i_pair = in_base_addr[3:1];
assign start_psum_pair = psum_base_addr[3:1];
assign start_psum_offset = choose_psum_offset(start_i_pair, start_psum_pair);

assign busy = busy_q;
assign done = done_q;
assign handoff_ready = handoff_ready_q;
assign host_ready = !busy_q;
assign host_rvalid = host_rvalid_q;
assign host_rdata = host_bank_rdata;
assign stream_out_push = output_skew_push;
assign stream_i_prefetch_accept = read_fire;
assign stream_psum_prefetch_accept = psum_read_fire;

assign start_accept = start && !compute_busy_q
                   && (start_use_active ? tensor_weight_active_valid
                                        : tensor_weight_pending_valid);
assign weight_fill_start_ready = tensor_weight_fill_start_ready;
assign weight_fill_ready = tensor_weight_fill_ready;
assign weight_pending_valid = tensor_weight_pending_valid;
assign weight_active_valid = tensor_weight_active_valid;
assign weight_idle = !compute_busy_q
                  || handoff_ready_next;

// The four-entry input window may fetch around a temporarily unavailable
// oldest bank pair.  Slots are tagged by the low bits of the absolute vector
// index and are consumed strictly in order, so DTCM phase selection is
// decoupled from dot8 ordering without adding a general response reorderer.
always @* begin
  input_select_valid = 1'b0;
  input_select_index = input_consume_count_q;
  input_select_slot = input_consume_count_q[INPUT_FIFO_INDEX_WIDTH-1:0];
  input_select_addr = in_base_q
                    + {input_consume_count_q[ADDR_WIDTH-2:0], 1'b0};
  input_select_mask = pair_mask(input_select_addr);
  input_select_index_try = input_consume_count_q;
  input_select_slot_try = input_consume_count_q[INPUT_FIFO_INDEX_WIDTH-1:0];
  input_select_addr_try = input_select_addr;
  input_select_mask_try = input_select_mask;
  for (input_select_offset = 0;
       input_select_offset < INPUT_FIFO_DEPTH;
       input_select_offset = input_select_offset + 1) begin
    input_select_index_try = input_consume_count_q
                           + input_select_offset[VECTOR_COUNT_WIDTH-1:0];
    input_select_slot_try =
        input_select_index_try[INPUT_FIFO_INDEX_WIDTH-1:0];
    input_select_addr_try = in_base_q
                          + {input_select_index_try[ADDR_WIDTH-2:0], 1'b0};
    input_select_mask_try = pair_mask(input_select_addr_try);
    if (!input_select_valid
        && (input_select_index_try < target_count_q)
        && !input_slot_issued_q[input_select_slot_try]
        && ((input_select_mask_try & ~lower_owned_mask) == 0)) begin
      input_select_valid = 1'b1;
      input_select_index = input_select_index_try;
      input_select_slot = input_select_slot_try;
      input_select_addr = input_select_addr_try;
      input_select_mask = input_select_mask_try;
    end
  end
end

always @* begin
  next_input_select_valid = 1'b0;
  next_input_select_index = {VECTOR_COUNT_WIDTH{1'b0}};
  next_input_select_slot = {INPUT_FIFO_INDEX_WIDTH{1'b0}};
  next_input_select_addr = next_input_prefetch_base_addr;
  next_input_select_mask = pair_mask(next_input_select_addr);
  next_input_select_index_try = {VECTOR_COUNT_WIDTH{1'b0}};
  next_input_select_slot_try = {INPUT_FIFO_INDEX_WIDTH{1'b0}};
  next_input_select_addr_try = next_input_prefetch_base_addr;
  next_input_select_mask_try = next_input_select_mask;
  for (next_input_select_offset = 0;
       next_input_select_offset < INPUT_FIFO_DEPTH;
       next_input_select_offset = next_input_select_offset + 1) begin
    next_input_select_index_try =
        next_input_select_offset[VECTOR_COUNT_WIDTH-1:0];
    next_input_select_slot_try =
        next_input_select_index_try[INPUT_FIFO_INDEX_WIDTH-1:0];
    next_input_select_addr_try = next_input_prefetch_base_addr
        + {next_input_select_index_try[ADDR_WIDTH-2:0], 1'b0};
    next_input_select_mask_try = pair_mask(next_input_select_addr_try);
    if (!next_input_select_valid
        && next_input_prefetch_valid
        && (next_input_select_index_try < next_input_prefetch_vector_count)
        && !next_input_slot_issued_q[next_input_select_slot_try]
        && ((next_input_select_mask_try & ~lower_owned_mask) == 0)) begin
      next_input_select_valid = 1'b1;
      next_input_select_index = next_input_select_index_try;
      next_input_select_slot = next_input_select_slot_try;
      next_input_select_addr = next_input_select_addr_try;
      next_input_select_mask = next_input_select_mask_try;
    end
  end
end

assign active_input_select = input_select_valid;
// Stop issuing one cycle before handoff.  This guarantees the queued response
// is resident in the next-input FIFO before start_accept copies its slots into
// the active window.
assign next_input_select = !active_input_select
                        && next_input_select_valid
                        && !handoff_ready_next;
assign i_req_addr = active_input_select ? input_select_addr
                                        : next_input_select_addr;
assign psum_req_addr = psum_base_q
                     + {psum_issue_count_q[ADDR_WIDTH-2:0], 1'b0};
assign i_req_mask = active_input_select ? input_select_mask
                                        : next_input_select_mask;
assign psum_req_mask = pair_mask(psum_req_addr);
assign output_pending = output_skew_inflight_q != 0;
assign output_skew_addr = output_skew_payload[143:128];
assign output_skew_data = output_skew_payload[127:0];
assign out_req_mask = output_skew_valid ? pair_mask(output_skew_addr)
                                     : {BANK_NUM{1'b0}};
assign lower_owned_mask = fabric_phase[1] ? 16'hcccc : 16'h3333;
assign i_req_owned = (i_req_mask & ~lower_owned_mask) == 0;
assign psum_req_owned = (psum_req_mask & ~lower_owned_mask) == 0;
assign out_req_owned = (out_req_mask & ~lower_owned_mask) == 0;
assign i_psum_conflict = (i_req_mask & psum_req_mask) != 0;
assign i_output_conflict = output_pending && ((i_req_mask & out_req_mask) != 0);
assign psum_output_conflict = output_pending
                           && ((psum_req_mask & out_req_mask) != 0);
assign read_conflicts_output = i_output_conflict;
assign psum_read_conflicts_output = psum_output_conflict;
assign read_candidate = compute_busy_q
                     && (active_input_select || next_input_select)
                     && i_req_owned;
assign psum_candidate = compute_busy_q && stream_started_q
                     && (psum_stream_started_q
                         || (stream_cycle_q >= {1'b0, psum_offset_q}))
                     && (psum_issue_count_q < psum_target_count)
                     && psum_req_owned;
assign output_candidate = busy_q && output_skew_valid && out_req_owned;
assign read_fire = read_candidate
                && !(output_candidate && i_output_conflict)
                && !(next_input_select && psum_candidate
                     && i_psum_conflict);
assign output_write_fire = output_candidate
                        && !(read_fire && i_output_conflict);
assign psum_read_fire = psum_candidate
                     && !(read_fire && i_psum_conflict)
                     && !(output_write_fire && psum_output_conflict);

assign input_head_slot =
    input_consume_count_q[INPUT_FIFO_INDEX_WIDTH-1:0];
assign input_head_from_rsp = iop_rsp_valid_q
                          && !i_rsp_next_input_q
                          && (i_rsp_index_q == input_consume_count_q);
assign input_head_valid = input_slot_valid_q[input_head_slot]
                       || input_head_from_rsp;
assign input_compute_fire = compute_busy_q
                         && (input_consume_count_q < target_count_q)
                         && input_head_valid
                         && (!scale_stream_enable_q || scale_stream_valid)
                         && (psum_stream_mode || compute_psum_valid)
                         && !((input_consume_count_q == 0)
                              && !scale_enable_q
                              && (scaled_inflight_count_q != 0));
assign input_compute_data = input_slot_valid_q[input_head_slot]
                          ? input_window_read_data
                          : i_pair_rdata;
assign input_compute_out_addr = out_base_q
                              + {input_consume_count_q[ADDR_WIDTH-2:0], 1'b0};
assign input_fifo_rsp_store = iop_rsp_valid_q
                           && !i_rsp_next_input_q
                           && !(input_head_from_rsp && input_compute_fire);
assign next_input_fifo_rsp_store = iop_rsp_valid_q && i_rsp_next_input_q;
assign compute_valid_q = input_compute_fire;
assign scale_stream_ready = input_compute_fire && scale_stream_enable_q;
assign aligned_psum_valid = (psum_count_q != 0) || psum_rsp_valid_q;
assign aligned_psum_data = (psum_count_q != 0)
                         ? psum_data_fifo[psum_head_q] : psum_pair_rdata;
assign psum_target_count = psum_none_mode_q ? {VECTOR_COUNT_WIDTH{1'b0}}
                         : psum_once_mode_q
                           ? {{VECTOR_COUNT_WIDTH-1{1'b0}}, 1'b1}
                           : target_count_q;
assign psum_stream_mode = !psum_none_mode_q && !psum_once_mode_q;
assign dot_needs_psum = psum_stream_mode_pipe_q[5];
assign compute_psum_valid = psum_none_mode_q ? 1'b1
                          : psum_once_mode_q ? psum_once_valid_q
                          : aligned_psum_valid;
assign compute_psum_data = psum_none_mode_q ? {PAIR_WIDTH{1'b0}}
                         : psum_once_mode_q ? psum_once_data_q
                         : aligned_psum_data;

assign output_skew_push = tensor_output_valid;
assign output_skew_pop = output_skew_valid;
assign output_skew_cfg_valid = tensor_output_valid
                            && meta_first_fifo[meta_head_q];
// Two registered stations preserve the current pair parity. Select the
// optional third cycle when the first output pair is on the opposite parity.
assign output_skew_cfg_extra =
    (meta_addr_fifo[meta_head_q][1] == fabric_phase[1]) ? 2'd0 : 2'd1;
assign psum_fifo_push = psum_rsp_valid_q && !psum_once_mode_q;
assign psum_fifo_pop = dot_ready && dot_needs_psum && aligned_psum_valid;
// RSUM produces one output for the whole run. Keep exactly one destination
// metadata entry instead of one entry per consumed input vector.
assign meta_fifo_push = compute_valid_q
                     && (!rsum_mode_q
                         || (input_consume_count_q
                             == {VECTOR_COUNT_WIDTH{1'b0}}));
assign meta_fifo_pop = tensor_output_valid;
assign handoff_ready_next = compute_busy_q
                         && (read_issue_count_q == target_count_q)
                         && (input_consume_count_q == target_count_q)
                         && (psum_issue_count_q == psum_target_count)
                         && !iop_rsp_valid_q
                         && !psum_rsp_valid_q
                         && (input_slot_valid_q == {INPUT_FIFO_DEPTH{1'b0}})
                         && (!rsum_mode_q || tensor_output_valid);
assign drain_done_next = busy_q && !compute_busy_q && !output_pending
                      && (meta_count_q == 0) && (psum_count_q == 0)
                      && !output_skew_push && !start_accept;

assign host_bank_req = !busy_q && host_req;
assign host_bank_we = host_we;
assign host_bank = host_addr[BANK_INDEX_WIDTH-1:0];
assign host_bank_addr = host_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign host_bank_wdata = host_wdata;
assign host_bank_wstrb = host_wstrb;

assign i_pair_req = read_fire;
assign i_pair_bank0 = i_req_addr[BANK_INDEX_WIDTH-1:0];
assign i_pair_bank1 = next_bank(i_req_addr);
assign i_pair_addr = i_req_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign i_pair_rsp_bank0 = i_rsp_bank0_q;
assign i_pair_rsp_bank1 = i_rsp_bank1_q;
assign psum_pair_req = psum_read_fire;
assign psum_pair_bank0 = psum_req_addr[BANK_INDEX_WIDTH-1:0];
assign psum_pair_bank1 = next_bank(psum_req_addr);
assign psum_pair_addr = psum_req_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign psum_pair_rsp_bank0 = psum_rsp_bank0_q;
assign psum_pair_rsp_bank1 = psum_rsp_bank1_q;
assign o_pair_req = output_write_fire;
assign o_pair_bank0 = output_skew_addr[BANK_INDEX_WIDTH-1:0];
assign o_pair_bank1 = next_bank(output_skew_addr);
assign o_pair_addr = output_skew_addr
                   [SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign o_pair_wdata = output_skew_data;

edge_tensor_skew_buffer #(
  .LANE_WIDTH(16), .LANE_COUNT(9), .SLOT_COUNT(2), .CFG_WIDTH(2)
) x_output_skew0 (
  .clk(clk), .resetn(cpurst_b),
  .cfg_valid_i(output_skew_cfg_valid),
  .cfg_extra_i(output_skew_cfg_extra),
  .cfg_valid_o(output_skew_cfg_mid_valid),
  .cfg_extra_o(output_skew_cfg_mid_extra),
  .in_valid(tensor_output_valid),
  .in_data({meta_addr_fifo[meta_head_q], tensor_output_data}),
  .out_valid(output_skew_mid_valid),
  .out_data(output_skew_mid_payload)
);

edge_tensor_skew_buffer #(
  .LANE_WIDTH(16), .LANE_COUNT(9), .SLOT_COUNT(2), .CFG_WIDTH(2)
) x_output_skew1 (
  .clk(clk), .resetn(cpurst_b),
  .cfg_valid_i(output_skew_cfg_mid_valid),
  .cfg_extra_i(output_skew_cfg_mid_extra),
  .cfg_valid_o(output_skew_cfg_out_valid),
  .cfg_extra_o(output_skew_cfg_out_extra),
  .in_valid(output_skew_mid_valid),
  .in_data(output_skew_mid_payload),
  .out_valid(output_skew_valid),
  .out_data(output_skew_payload)
);

edge_tensor_input_window #(
  .LANE_WIDTH(16),
  .LANE_COUNT(8),
  .SLOT_COUNT(INPUT_FIFO_DEPTH),
  .SLOT_WIDTH(INPUT_FIFO_INDEX_WIDTH)
) x_input_window (
  .clk(clk),
  .resetn(cpurst_b),
  .start(start_accept),
  .start_from_prefetch(next_input_prefetch_valid),
  .active_issue(read_fire && !next_input_select),
  .active_issue_slot(input_select_slot),
  .prefetch_issue(read_fire && next_input_select),
  .prefetch_issue_slot(next_input_select_slot),
  .response_write(input_fifo_rsp_store || next_input_fifo_rsp_store),
  .response_prefetch(i_rsp_next_input_q),
  .response_slot(i_rsp_index_q[INPUT_FIFO_INDEX_WIDTH-1:0]),
  .response_data(i_pair_rdata),
  .active_consume(input_compute_fire),
  .active_consume_slot(input_head_slot),
  .active_read_slot(input_head_slot),
  .active_read_data(input_window_read_data),
  .active_issued(input_slot_issued_q),
  .active_valid(input_slot_valid_q),
  .prefetch_issued(next_input_slot_issued_q),
  .prefetch_valid(next_input_slot_valid_q)
);

edge_tile8x8_unit x_tile8x8 (
  .clk(clk), .rst_b(cpurst_b), .compute_valid(compute_valid_q),
  .late_psum_mode_i(dot_needs_psum),
  .late_psum_valid_i(dot_needs_psum ? aligned_psum_valid : 1'b1),
  .input_bf16_i(input_compute_data), .psum_bf16_i(compute_psum_data),
  .scale_enable_i(scale_enable_q),
  .scale_bf16_i(scale_stream_enable_q ? scale_stream_data : scale_bf16_q),
  .rsum_enable_i(rsum_mode_q),
  .rsum_first_i(rsum_mode_q
                && (input_consume_count_q == {VECTOR_COUNT_WIDTH{1'b0}})),
  .rsum_last_i(rsum_mode_q
               && (input_consume_count_q + {{VECTOR_COUNT_WIDTH-1{1'b0}}, 1'b1}
                   == target_count_q)),
  .weight_fill_bf16_mode_i(weight_fill_bf16_mode),
  .weight_fill_start(weight_fill_start),
  .weight_fill_start_ready(tensor_weight_fill_start_ready),
  .weight_fill_valid(weight_fill_valid),
  .weight_fill_ready(tensor_weight_fill_ready),
  .weight_fill_pair_idx(weight_fill_pair_idx),
  .weight_fill_data(weight_fill_data), .weight_fill_last(weight_fill_last),
  .weight_activate(weight_preactivate || (start_accept && !start_use_active)),
  .weight_activate_ready(tensor_weight_activate_ready),
  .weight_fill_busy(tensor_weight_fill_busy),
  .weight_active_valid(tensor_weight_active_valid),
  .weight_pending_valid(tensor_weight_pending_valid),
  .dot_ready_o(dot_ready),
  .output_valid(tensor_output_valid), .output_bf16_o(tensor_output_data)
);

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    busy_q <= 1'b0;
    compute_busy_q <= 1'b0;
    done_q <= 1'b0;
    handoff_ready_q <= 1'b0;
    stream_started_q <= 1'b0;
    psum_stream_started_q <= 1'b0;
    stream_cycle_q <= 5'b0;
    psum_offset_q <= 4'b0;
    target_count_q <= 0;
    read_issue_count_q <= 0;
    input_consume_count_q <= 0;
    psum_issue_count_q <= 0;
    in_base_q <= 0;
    psum_base_q <= 0;
    out_base_q <= 0;
    iop_rsp_valid_q <= 1'b0;
    psum_rsp_valid_q <= 1'b0;
    i_rsp_bank0_q <= 0;
    i_rsp_bank1_q <= 0;
    psum_rsp_bank0_q <= 0;
    psum_rsp_bank1_q <= 0;
    i_rsp_index_q <= 0;
    i_rsp_next_input_q <= 1'b0;
    next_input_issue_count_q <= 0;
    psum_head_q <= 0;
    psum_tail_q <= 0;
    psum_count_q <= 0;
    meta_head_q <= 0;
    meta_tail_q <= 0;
    meta_count_q <= 0;
    scaled_inflight_count_q <= 0;
    output_skew_inflight_q <= 0;
    psum_stream_mode_pipe_q <= 6'b0;
    host_rvalid_q <= 1'b0;
    host_rsp_bank_q <= 0;
    scale_enable_q <= 1'b0;
    scale_stream_enable_q <= 1'b0;
    scale_bf16_q <= 0;
    psum_once_mode_q <= 1'b0;
    psum_none_mode_q <= 1'b0;
    rsum_mode_q <= 1'b0;
    psum_once_valid_q <= 1'b0;
    psum_once_data_q <= 0;
    for (psum_fifo_i = 0; psum_fifo_i < PSUM_FIFO_DEPTH;
         psum_fifo_i = psum_fifo_i + 1)
      psum_data_fifo[psum_fifo_i] <= 0;
    for (meta_fifo_i = 0; meta_fifo_i < META_FIFO_DEPTH;
         meta_fifo_i = meta_fifo_i + 1) begin
      meta_addr_fifo[meta_fifo_i] <= 0;
      meta_scale_fifo[meta_fifo_i] <= 1'b0;
      meta_first_fifo[meta_fifo_i] <= 1'b0;
    end
  end else begin
    psum_stream_mode_pipe_q <=
        {psum_stream_mode_pipe_q[4:0],
         input_compute_fire && psum_stream_mode};
    done_q <= 1'b0;
    handoff_ready_q <= 1'b0;
    iop_rsp_valid_q <= read_fire;
    psum_rsp_valid_q <= psum_read_fire;
    host_rvalid_q <= !busy_q && host_req && !host_we;
    if (host_req && !busy_q && !host_we)
      host_rsp_bank_q <= host_addr[BANK_INDEX_WIDTH-1:0];

    if (start_accept) begin
      busy_q <= 1'b1;
      compute_busy_q <= 1'b1;
      stream_started_q <= next_input_prefetch_valid
                       && (next_input_issue_count_q != 0);
      psum_stream_started_q <= 1'b0;
      stream_cycle_q <= 0;
      psum_offset_q <= start_psum_offset;
      target_count_q <= vector_count;
      read_issue_count_q <= next_input_prefetch_valid
                          ? next_input_issue_count_q : 0;
      input_consume_count_q <= 0;
      psum_issue_count_q <= 0;
      in_base_q <= in_base_addr;
      psum_base_q <= psum_base_addr;
      out_base_q <= out_base_addr;
      iop_rsp_valid_q <= 1'b0;
      psum_rsp_valid_q <= 1'b0;
      next_input_issue_count_q <= 0;
      scale_enable_q <= start_mode[0] && !start_mode[4];
      scale_stream_enable_q <= start_mode[3] && !start_mode[4];
      scale_bf16_q <= scale_bf16;
      psum_once_mode_q <= start_mode[1] && !start_mode[2]
                       && !start_mode[4];
      psum_none_mode_q <= start_mode[2] || start_mode[4];
      rsum_mode_q <= start_mode[4];
      psum_once_valid_q <= 1'b0;
    end else if (stream_started_q) begin
      stream_cycle_q <= stream_cycle_q + 5'd1;
    end

    if (read_fire) begin
      i_rsp_bank0_q <= i_req_addr[BANK_INDEX_WIDTH-1:0];
      i_rsp_bank1_q <= next_bank(i_req_addr);
      i_rsp_next_input_q <= next_input_select;
      if (next_input_select) begin
        i_rsp_index_q <= next_input_select_index;
        next_input_issue_count_q <= next_input_issue_count_q + 1'b1;
      end else begin
        i_rsp_index_q <= input_select_index;
        read_issue_count_q <= read_issue_count_q + 1'b1;
        if (!stream_started_q) begin
          stream_started_q <= 1'b1;
          stream_cycle_q <= 5'd1;
        end
      end
    end

    if (input_compute_fire) begin
      input_consume_count_q <= input_consume_count_q + 1'b1;
    end

    if (psum_read_fire) begin
      psum_stream_started_q <= 1'b1;
      psum_rsp_bank0_q <= psum_req_addr[BANK_INDEX_WIDTH-1:0];
      psum_rsp_bank1_q <= next_bank(psum_req_addr);
      psum_issue_count_q <= psum_issue_count_q + 1'b1;
    end

    if (psum_rsp_valid_q && psum_once_mode_q) begin
      psum_once_data_q <= psum_pair_rdata;
      psum_once_valid_q <= 1'b1;
    end

    if (meta_fifo_push) begin
      meta_addr_fifo[meta_tail_q] <= input_compute_out_addr;
      meta_scale_fifo[meta_tail_q] <= scale_enable_q;
      meta_first_fifo[meta_tail_q] <=
          input_consume_count_q == {VECTOR_COUNT_WIDTH{1'b0}};
      meta_tail_q <= meta_tail_q + 1'b1;
    end
    if (meta_fifo_pop)
      meta_head_q <= meta_head_q + 1'b1;
    case ({meta_fifo_push, meta_fifo_pop})
      2'b10: meta_count_q <= meta_count_q + 1'b1;
      2'b01: meta_count_q <= meta_count_q - 1'b1;
      default: begin end
    endcase
    case ({meta_fifo_push && scale_enable_q,
           meta_fifo_pop && meta_scale_fifo[meta_head_q]})
      2'b10: scaled_inflight_count_q <= scaled_inflight_count_q + 1'b1;
      2'b01: scaled_inflight_count_q <= scaled_inflight_count_q - 1'b1;
      default: begin end
    endcase

    if (psum_fifo_push) begin
      psum_data_fifo[psum_tail_q] <= psum_pair_rdata;
      psum_tail_q <= psum_tail_q + 1'b1;
    end
    if (psum_fifo_pop)
      psum_head_q <= psum_head_q + 1'b1;
    case ({psum_fifo_push, psum_fifo_pop})
      2'b10: psum_count_q <= psum_count_q + 1'b1;
      2'b01: psum_count_q <= psum_count_q - 1'b1;
      default: begin end
    endcase

    case ({output_skew_push, output_skew_pop})
      2'b10: output_skew_inflight_q <= output_skew_inflight_q + 1'b1;
      2'b01: output_skew_inflight_q <= output_skew_inflight_q - 1'b1;
      default: begin end
    endcase

`ifndef SYNTHESIS
    if (output_skew_valid && !output_write_fire) begin
      $display("tensor output skew write miss addr=%h phase=%h owned=%b read_conflict=%b",
               output_skew_addr, fabric_phase, out_req_owned,
               read_fire && i_output_conflict);
      $finish;
    end
    if (output_skew_cfg_valid && (output_skew_inflight_q != 0)) begin
      $display("tensor output skew reconfigured with %0d old beats in flight",
               output_skew_inflight_q);
      $finish;
    end
`endif

    if (handoff_ready_next) begin
      compute_busy_q <= 1'b0;
      handoff_ready_q <= 1'b1;
    end
    if (drain_done_next) begin
      busy_q <= 1'b0;
      done_q <= 1'b1;
    end
  end
end

endmodule
