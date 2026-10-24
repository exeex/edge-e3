module edge_tensor_engine(
  clk, cpurst_b, start, in_base_addr, psum_base_addr, out_base_addr,
  vector_count, start_mode, start_dtype, scale_bf16,
  scale_stream_valid, scale_stream_data, scale_stream_ready,
  weight_fill_bf16_mode, weight_fill_start, weight_fill_start_ready,
  weight_fill_valid, weight_fill_ready, weight_fill_pair_idx,
  weight_fill_data, weight_fill_last, weight_pending_valid,
  weight_active_valid, weight_preactivate, start_use_active, weight_idle,
  packed_weight_start, packed_weight_start_ready,
  packed_weight_wtype, packed_weight_transpose,
  packed_weight_busy, packed_weight_done,
  packed_weight_load_valid, packed_weight_load_ready,
  packed_weight_load_idx, packed_weight_load_data,
  next_input_prefetch_valid, next_input_prefetch_base_addr,
  next_input_prefetch_psum_base_addr, next_input_prefetch_mode,
  next_input_prefetch_vector_count,
  handoff_ready, busy, done, host_req, host_we, host_addr, host_wdata,
  host_wstrb, host_ready, host_rdata, host_rvalid, host_rsp_bank, fabric_phase,
  host_bank_req, host_bank_we, host_bank, host_bank_addr, host_bank_wdata,
  host_bank_wstrb, host_bank_rdata, i_pair_req, i_pair_bank0,
  i_pair_bank1, i_pair_addr, i_pair_rsp_bank0, i_pair_rsp_bank1,
  i_pair_rdata, psum_pair_req, psum_pair_bank0, psum_pair_bank1,
  psum_pair_addr, psum_pair_rsp_bank0, psum_pair_rsp_bank1,
  psum_pair_rdata, psum_pair_extra_rdata, psum_pair_req_fp32,
  psum_pair_bank2, psum_pair_bank3, psum_pair_extra_addr,
  psum_pair_rsp_bank2, psum_pair_rsp_bank3,
  o_pair_req, o_pair_bank0, o_pair_bank1, o_pair_bank2, o_pair_bank3,
  o_pair_fp32, o_pair_addr, o_pair_extra_addr, o_pair_wdata,
  stream_out_push, stream_i_prefetch_accept,
  stream_psum_prefetch_accept
);

parameter LOWER_SIX = 0;
// Opt-in wide H4 backend. fabric_phase carries {wide_phase[2:0],1'b0}.
parameter WIDE_H4 = 0;
parameter ADDR_WIDTH = 16;
parameter SRAM_ADDR_WIDTH = 10;
parameter DATA_WIDTH = 64;
parameter BANK_NUM = 16;
parameter BANK_INDEX_WIDTH = 4;
parameter VECTOR_COUNT_WIDTH = 16;
parameter PACKED_WEIGHT = 0;
parameter READ_LATENCY = 1;

`ifndef SYNTHESIS
initial if (WIDE_H4 && (!LOWER_SIX || READ_LATENCY != 4 || BANK_NUM != 16 || DATA_WIDTH != 64))
  $fatal(1,"wide H4 tensor requires LOWER_SIX, latency 4 and sixteen 64-bit banks");
`endif

localparam BYTE_WIDTH = DATA_WIDTH / 8;
localparam PAIR_WIDTH = DATA_WIDTH * 2;
localparam PSUM_FIFO_DEPTH = WIDE_H4 ? 16 : 8;
localparam PSUM_FIFO_INDEX_WIDTH = $clog2(PSUM_FIFO_DEPTH);
// Wide I visits eight bank pairs in permuted order. Keep a complete tour
// ahead of the consumer plus the four in-flight read edges; four entries
// repeatedly miss owned banks even though the raw lane has one beat/cycle.
localparam INPUT_FIFO_DEPTH = WIDE_H4 ? 16 : 4;
localparam INPUT_FIFO_INDEX_WIDTH = $clog2(INPUT_FIFO_DEPTH);
localparam INPUT_KEEP_WIDTH = INPUT_FIFO_INDEX_WIDTH + 1;
localparam META_FIFO_DEPTH = 16;
localparam META_FIFO_INDEX_WIDTH = 4;
// Launch credits reserve both pipeline results and queued output. Eight
// total credits throttle a one-vector/cycle dot/scale/psum pipeline even
// when wide O drains every cycle. Sixteen retain bounded backpressure.
localparam OUTPUT_FIFO_DEPTH = WIDE_H4 ? 16 : 8;
localparam OUTPUT_FIFO_INDEX_WIDTH = $clog2(OUTPUT_FIFO_DEPTH);
localparam [VECTOR_COUNT_WIDTH:0] INPUT_PSUM_LEAD = 6;
localparam [VECTOR_COUNT_WIDTH:0] PSUM_URGENT_BACKLOG = 2;

input clk;
input cpurst_b;
input start;
input [ADDR_WIDTH-1:0] in_base_addr;
input [ADDR_WIDTH-1:0] psum_base_addr;
input [ADDR_WIDTH-1:0] out_base_addr;
input [VECTOR_COUNT_WIDTH-1:0] vector_count;
input [7:0] start_mode;
input [3:0] start_dtype;
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
input packed_weight_start;
output packed_weight_start_ready;
input [3:0] packed_weight_wtype;
input packed_weight_transpose;
output packed_weight_busy, packed_weight_done;
input packed_weight_load_valid;
output packed_weight_load_ready;
input [2:0] packed_weight_load_idx;
input [PAIR_WIDTH-1:0] packed_weight_load_data;
input next_input_prefetch_valid;
input [ADDR_WIDTH-1:0] next_input_prefetch_base_addr;
input [ADDR_WIDTH-1:0] next_input_prefetch_psum_base_addr;
input [7:0] next_input_prefetch_mode;
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
output [BANK_INDEX_WIDTH-1:0] host_rsp_bank;
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
input [PAIR_WIDTH-1:0] psum_pair_extra_rdata;
output psum_pair_req_fp32;
output [BANK_INDEX_WIDTH-1:0] psum_pair_bank2, psum_pair_bank3;
output [SRAM_ADDR_WIDTH-1:0] psum_pair_extra_addr;
output [BANK_INDEX_WIDTH-1:0] psum_pair_rsp_bank2, psum_pair_rsp_bank3;
output o_pair_req;
output [BANK_INDEX_WIDTH-1:0] o_pair_bank0;
output [BANK_INDEX_WIDTH-1:0] o_pair_bank1;
output [BANK_INDEX_WIDTH-1:0] o_pair_bank2, o_pair_bank3;
output o_pair_fp32;
output [SRAM_ADDR_WIDTH-1:0] o_pair_addr;
output [SRAM_ADDR_WIDTH-1:0] o_pair_extra_addr;
output [2*PAIR_WIDTH-1:0] o_pair_wdata;
output stream_out_push;
output stream_i_prefetch_accept;
output stream_psum_prefetch_accept;

reg busy_q;
reg compute_busy_q;
reg done_q;
reg handoff_ready_q;
reg stream_started_q;
reg psum_stream_started_q;
// Unscaled dot output arrives eight edges after launch. At READ_LATENCY=4,
// queued I may issue through last-MAC+3, then return by +7 so the I pipe is
// empty on the +8 weight-release edge. Do not change other mode latencies.
reg [1:0] next_input_tail_q;
wire next_input_deadline_mode = WIDE_H4 && LOWER_SIX && READ_LATENCY == 4
    && !scale_enable_q && !scale_stream_enable_q && !rsum_mode_q
    && !psum_once_mode_q && !psum_none_mode_q;
wire next_input_before_deadline = !next_input_deadline_mode
    || input_consume_count_q != target_count_q || next_input_tail_q != 0;
reg [4:0] stream_cycle_q;
reg [3:0] psum_offset_q;
reg [VECTOR_COUNT_WIDTH-1:0] target_count_q;
reg [VECTOR_COUNT_WIDTH-1:0] read_issue_count_q;
reg [VECTOR_COUNT_WIDTH-1:0] input_consume_count_q;
reg [VECTOR_COUNT_WIDTH-1:0] psum_issue_count_q;
reg [ADDR_WIDTH-1:0] in_base_q;
reg [ADDR_WIDTH-1:0] psum_base_q;
reg [ADDR_WIDTH-1:0] out_base_q;
wire iop_rsp_valid_q;
wire psum_rsp_valid_q;
wire [BANK_INDEX_WIDTH-1:0] i_rsp_bank0_q;
wire [BANK_INDEX_WIDTH-1:0] i_rsp_bank1_q;
wire [BANK_INDEX_WIDTH-1:0] psum_rsp_bank0_q;
wire [BANK_INDEX_WIDTH-1:0] psum_rsp_bank1_q;
wire [VECTOR_COUNT_WIDTH-1:0] i_rsp_index_q;
wire i_rsp_next_input_q;
reg [VECTOR_COUNT_WIDTH-1:0] next_input_issue_count_q;
reg [2*PAIR_WIDTH-1:0] psum_data_fifo [0:PSUM_FIFO_DEPTH-1];
reg [PSUM_FIFO_INDEX_WIDTH-1:0] psum_head_q;
reg [PSUM_FIFO_INDEX_WIDTH-1:0] psum_tail_q;
reg [PSUM_FIFO_INDEX_WIDTH:0] psum_count_q;
reg [ADDR_WIDTH-1:0] meta_addr_fifo [0:META_FIFO_DEPTH-1];
reg meta_old_fifo [0:META_FIFO_DEPTH-1];
reg meta_scale_fifo [0:META_FIFO_DEPTH-1];
reg meta_first_fifo [0:META_FIFO_DEPTH-1];
reg meta_fp32_fifo [0:META_FIFO_DEPTH-1];
reg meta_tile_fifo [0:META_FIFO_DEPTH-1];
reg [META_FIFO_INDEX_WIDTH-1:0] meta_head_q;
reg [META_FIFO_INDEX_WIDTH-1:0] meta_tail_q;
reg [META_FIFO_INDEX_WIDTH:0] meta_count_q;
reg [META_FIFO_INDEX_WIDTH:0] scaled_inflight_count_q;
reg [OUTPUT_FIFO_INDEX_WIDTH:0] output_skew_inflight_q;
// Wide P is issued by bank phase and joined by absolute vector index.
reg [PSUM_FIFO_DEPTH-1:0] psum_slot_issued_q, psum_slot_valid_q;
reg [VECTOR_COUNT_WIDTH-1:0] psum_consume_count_q;
reg [VECTOR_COUNT_WIDTH-1:0] p_index_pipe [0:READ_LATENCY-1];
wire [VECTOR_COUNT_WIDTH-1:0] psum_rsp_index=p_index_pipe[READ_LATENCY-1];
reg psum_select_valid;
reg [VECTOR_COUNT_WIDTH-1:0] psum_select_index, psum_try_index;
reg [ADDR_WIDTH-1:0] psum_select_addr, psum_try_addr;
integer psum_select_offset;
wire psum_input_issued = psum_slot_issued_q[input_consume_count_q[PSUM_FIFO_INDEX_WIDTH-1:0]];
wire psum_input_issuing = psum_read_fire && psum_select_index==input_consume_count_q;
wire psum_head_from_rsp=psum_rsp_valid_q && psum_rsp_index==psum_consume_count_q;
// The ring is anchored at P consumption (the late dot join), not I issue.
// Issued bits reserve slots while responses are still in flight.
always @* begin
  psum_select_valid=0;
  psum_select_index=psum_consume_count_q;
  psum_select_addr=psum_base_q;
  psum_try_index=0; psum_try_addr=0;
  for(psum_select_offset=0;psum_select_offset<PSUM_FIFO_DEPTH;psum_select_offset=psum_select_offset+1) begin
    psum_try_index=psum_consume_count_q+VECTOR_COUNT_WIDTH'(psum_select_offset);
    psum_try_addr=psum_base_q+(ADDR_WIDTH'(psum_try_index) << (psum_fp32_q ? 2 : 1));
    if(!psum_select_valid && psum_consume_count_q<psum_target_count
        && VECTOR_COUNT_WIDTH'(psum_select_offset)<psum_target_count-psum_consume_count_q
        && !psum_slot_issued_q[psum_try_index[PSUM_FIFO_INDEX_WIDTH-1:0]]
        && psum_try_addr[3:2]==psum_channel_bank[3:2]) begin
      psum_select_valid=1;
      psum_select_index=psum_try_index;
      psum_select_addr=psum_try_addr;
    end
  end
  if(start_accept) begin
    psum_select_valid=1;
    psum_select_index=0;
    psum_select_addr=psum_base_addr;
  end
end
reg [273:0] output_fifo_q [0:OUTPUT_FIFO_DEPTH-1];
reg output_old_fifo [0:OUTPUT_FIFO_DEPTH-1];
reg [OUTPUT_FIFO_INDEX_WIDTH-1:0] output_fifo_head_q;
reg [OUTPUT_FIFO_INDEX_WIDTH-1:0] output_fifo_tail_q;
reg [OUTPUT_FIFO_INDEX_WIDTH:0] output_fifo_count_q;
// Sparse age-ordered ring: writes may leave holes; retirement remains in order.
reg [OUTPUT_FIFO_DEPTH-1:0] output_live_q;
reg output_select_valid;
reg [OUTPUT_FIFO_INDEX_WIDTH-1:0] output_select_slot;
reg [OUTPUT_FIFO_INDEX_WIDTH-1:0] output_scan_slot;
integer output_scan_i;
wire output_ring_retire;
function output_overlap;
  input [ADDR_WIDTH-1:0] a, b;
  input a_wide, b_wide;
  begin
    output_overlap = a == b || (a_wide && a + ADDR_WIDTH'(2) == b)
                           || (b_wide && b + ADDR_WIDTH'(2) == a);
  end
endfunction
always @* begin
  output_select_valid=0;
  output_select_slot=output_fifo_head_q;
  output_scan_slot=0;
  // All aligned overlapping writes share a 256-bit group. Oldest eligible
  // in that group preserves WAW order without an all-pairs address CAM.
  for (output_scan_i=0;output_scan_i<OUTPUT_FIFO_DEPTH;output_scan_i=output_scan_i+1) begin
    output_scan_slot=output_fifo_head_q+OUTPUT_FIFO_INDEX_WIDTH'(output_scan_i);
    if (!output_select_valid && output_scan_i<output_fifo_count_q
        && output_live_q[output_scan_slot]
        && output_fifo_q[output_scan_slot][260:259]==output_channel_bank[3:2]) begin
      output_select_valid=1;
      output_select_slot=output_scan_slot;
    end
  end
end
assign output_ring_retire = output_fifo_count_q!=0 &&
    (WIDE_H4 ? (!output_live_q[output_fifo_head_q] ||
       (output_write_fire && output_select_slot==output_fifo_head_q)) : output_write_fire);
reg [6:0] psum_stream_mode_pipe_q;
wire host_rvalid_q;
wire [BANK_INDEX_WIDTH-1:0] host_rsp_bank_q;
// Native E3 RSUM performs the numerical merge in the dot kernel. Keep the
// E4-style post-input drain boundary before publishing that final value.
reg rsum_drain_pending_q;
reg [PAIR_WIDTH-1:0] rsum_drain_data_q;
reg scale_enable_q;
reg scale_stream_enable_q;
reg [127:0] scale_bf16_q;
reg psum_once_mode_q;
reg psum_none_mode_q;
reg rsum_mode_q;
reg output_fp32_q;
reg psum_fp32_q;
reg tile_mode_q;
reg psum_once_valid_q;
reg [2*PAIR_WIDTH-1:0] psum_once_data_q;

wire [ADDR_WIDTH-1:0] i_req_addr;
wire [ADDR_WIDTH-1:0] psum_req_addr;
wire [ADDR_WIDTH-1:0] psum_req_hi_addr;
wire [BANK_NUM-1:0] i_req_mask;
wire [BANK_NUM-1:0] psum_req_mask;
wire [BANK_NUM-1:0] out_req_mask;
wire [BANK_NUM-1:0] lower_owned_mask;
wire [BANK_NUM-1:0] input_owned_mask, psum_owned_mask, output_owned_mask;
wire [3:0] psum_channel_bank = WIDE_H4 ? {fabric_phase[2:1],2'b00}
    : 2 * 3'(fabric_phase[3:1] + 3'd1);
wire [3:0] psum_other_channel_bank = WIDE_H4 ? psum_channel_bank+4'd2
    : 2 * 3'(fabric_phase[3:1] + 3'd5);
wire [3:0] output_channel_bank = WIDE_H4 ? {2'(fabric_phase[2:1]+2'd1),2'b00}
    : 2 * 3'(fabric_phase[3:1] + (LOWER_SIX ? 3'd2 : 3'd3));
wire [3:0] output_other_channel_bank = WIDE_H4 ? output_channel_bank+4'd2
    : 2 * 3'(fabric_phase[3:1] + 3'd6);
wire [3:0] wide_input_bank = {2'(fabric_phase[2:1]+2'd2),fabric_phase[3],1'b0};
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
wire psum_start_prefetch;
reg psum_req_addr_pending;
reg input_psum_addr_pending;
wire [ADDR_WIDTH-1:0] input_psum_addr;
integer psum_meta_scan_i;
integer psum_output_scan_i;
reg [META_FIFO_INDEX_WIDTH-1:0] psum_meta_scan_slot;
reg [OUTPUT_FIFO_INDEX_WIDTH-1:0] psum_output_scan_slot;
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
wire [273:0] output_skew_payload;
wire output_skew_tile;
wire [ADDR_WIDTH-1:0] output_skew_hi_addr;
wire output_skew_pipe_valid;
wire [143:0] output_skew_pipe_payload;
wire output_skew_fifo_push;
wire output_skew_fifo_pop;
wire output_queue_push_valid;
wire [273:0] output_queue_push_payload;
wire [ADDR_WIDTH-1:0] output_skew_addr;
wire [2*PAIR_WIDTH-1:0] output_skew_data;
wire output_skew_fp32;
wire [2*PAIR_WIDTH-1:0] fp32_output_data;
wire [2*PAIR_WIDTH-1:0] converted_psum_data;
wire psum_fifo_push;
wire psum_fifo_pop;
wire psum_fifo_credit;
wire psum_urgent;
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
wire [2*PAIR_WIDTH-1:0] aligned_psum_data;
wire compute_psum_valid;
wire [2*PAIR_WIDTH-1:0] compute_psum_data;
wire [VECTOR_COUNT_WIDTH-1:0] psum_target_count;
wire psum_stream_mode;
wire dot_ready;
wire dot_needs_psum;
wire tensor_core_output_valid;
wire [PAIR_WIDTH-1:0] tensor_core_output_data;
wire [255:0] tensor_core_output_fp32;
reg [255:0] rsum_drain_fp32_q;
wire [127:0] compute_psum_bf16;
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
integer output_fifo_i;
integer input_select_offset;
integer next_input_select_offset;
reg [INPUT_KEEP_WIDTH-1:0] input_keep_q;
wire [INPUT_KEEP_WIDTH-1:0] start_input_keep;
wire [INPUT_KEEP_WIDTH-1:0] next_input_keep;

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

function [BANK_NUM-1:0] quad_mask;
  input [ADDR_WIDTH-1:0] addr;
  integer j;
begin
  quad_mask = 0;
  for (j=0; j<4; j=j+1)
    quad_mask[(addr[BANK_INDEX_WIDTH-1:0] + j) % BANK_NUM] = 1'b1;
end
endfunction

// Four vectors occupy two 512-bit planes: L0..L3 then H0..H3.
// Opposite channels exchange low/high roles every four phase steps.
function [ADDR_WIDTH-1:0] striped_low_addr;
  input [ADDR_WIDTH-1:0] base;
  input [VECTOR_COUNT_WIDTH-1:0] index;
begin
  striped_low_addr = WIDE_H4 ? base + (index << 2)
      : base + ((index >> 2) << 4) + ((index & 3) << 1);
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

// Preserve legacy short-stream tuning; wide H4 needs its full reorder window.
function [INPUT_KEEP_WIDTH-1:0] choose_input_keep;
  input [ADDR_WIDTH-1:0] i_addr;
  input [ADDR_WIDTH-1:0] p_addr;
  input [7:0] mode;
  input [VECTOR_COUNT_WIDTH-1:0] count;
begin
  if (WIDE_H4)
    choose_input_keep = INPUT_KEEP_WIDTH'(INPUT_FIFO_DEPTH);
  else if (count <= 16'd8 && !mode[1] && !mode[2] && !mode[4]
      && i_addr[3:1] != p_addr[3:1]
      && (i_addr[1] == p_addr[1]
          || p_addr[3:1] == i_addr[3:1] + 3'd1))
    choose_input_keep = 3'd3;
  else
    choose_input_keep = 3'd4;
end
endfunction

assign start_i_pair = in_base_addr[3:1];
assign start_psum_pair = psum_base_addr[3:1];
assign start_psum_offset = choose_psum_offset(start_i_pair, start_psum_pair);
assign start_input_keep = choose_input_keep(in_base_addr, psum_base_addr,
                                           start_mode, vector_count);
assign next_input_keep = choose_input_keep(
    next_input_prefetch_base_addr, next_input_prefetch_psum_base_addr,
    next_input_prefetch_mode, next_input_prefetch_vector_count);

// Fixed-latency memory tags. Reserve every outstanding P response, and
// finish sync only after the final output has reached the SRAM array.
reg [READ_LATENCY-1:0] i_valid_pipe, p_valid_pipe, host_valid_pipe, write_pipe;
localparam I_TAG_WIDTH = 2*BANK_INDEX_WIDTH + VECTOR_COUNT_WIDTH + 1;
reg [I_TAG_WIDTH-1:0] i_tag_pipe [0:READ_LATENCY-1];
reg [4*BANK_INDEX_WIDTH-1:0] p_tag_pipe [0:READ_LATENCY-1];
reg [BANK_INDEX_WIDTH-1:0] host_tag_pipe [0:READ_LATENCY-1];
integer response_stage;
integer psum_inflight;
always @* begin
  psum_inflight = 0;
  for (integer s=0; s<READ_LATENCY; s=s+1)
    psum_inflight = psum_inflight + int'(p_valid_pipe[s]);
end
assign iop_rsp_valid_q = i_valid_pipe[READ_LATENCY-1];
assign psum_rsp_valid_q = p_valid_pipe[READ_LATENCY-1];
assign host_rvalid_q = host_valid_pipe[READ_LATENCY-1];
assign {i_rsp_bank0_q, i_rsp_bank1_q, i_rsp_index_q, i_rsp_next_input_q} =
    i_tag_pipe[READ_LATENCY-1];
assign {psum_rsp_bank0_q, psum_rsp_bank1_q,
        psum_pair_rsp_bank2, psum_pair_rsp_bank3} = p_tag_pipe[READ_LATENCY-1];
assign host_rsp_bank_q = host_tag_pipe[READ_LATENCY-1];
always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    i_valid_pipe <= 0; p_valid_pipe <= 0; host_valid_pipe <= 0; write_pipe <= 0;
    for (response_stage=0; response_stage<READ_LATENCY; response_stage=response_stage+1) begin
      i_tag_pipe[response_stage] <= 0;
      p_tag_pipe[response_stage] <= 0;
      p_index_pipe[response_stage] <= 0;
      host_tag_pipe[response_stage] <= 0;
    end
  end else begin
    i_valid_pipe[0] <= read_fire;
    p_valid_pipe[0] <= psum_read_fire;
    host_valid_pipe[0] <= host_bank_req && !host_we;
    write_pipe[0] <= output_write_fire || (host_bank_req && host_we);
    i_tag_pipe[0] <= {i_req_addr[BANK_INDEX_WIDTH-1:0], next_bank(i_req_addr),
        (next_input_select ? next_input_select_index : input_select_index), next_input_select};
    p_index_pipe[0] <= psum_select_index;
    p_tag_pipe[0] <= {psum_pair_bank0, psum_pair_bank1,
                      psum_pair_bank2, psum_pair_bank3};
    host_tag_pipe[0] <= host_addr[BANK_INDEX_WIDTH-1:0];
    for (response_stage=1; response_stage<READ_LATENCY; response_stage=response_stage+1) begin
      i_valid_pipe[response_stage] <= i_valid_pipe[response_stage-1];
      p_valid_pipe[response_stage] <= p_valid_pipe[response_stage-1];
      host_valid_pipe[response_stage] <= host_valid_pipe[response_stage-1];
      write_pipe[response_stage] <= write_pipe[response_stage-1];
      i_tag_pipe[response_stage] <= i_tag_pipe[response_stage-1];
      p_tag_pipe[response_stage] <= p_tag_pipe[response_stage-1];
      p_index_pipe[response_stage] <= p_index_pipe[response_stage-1];
      host_tag_pipe[response_stage] <= host_tag_pipe[response_stage-1];
    end
  end
end

assign busy = busy_q || ((READ_LATENCY > 1) && (|write_pipe));
assign done = done_q;
assign handoff_ready = handoff_ready_q;
assign host_ready = !busy_q && !(|host_valid_pipe);
assign host_rsp_bank = host_rsp_bank_q;
assign host_rvalid = host_rvalid_q;
assign host_rdata = host_bank_rdata;
assign stream_out_push = output_skew_push;
assign stream_i_prefetch_accept = read_fire;
assign stream_psum_prefetch_accept = psum_read_fire;

assign start_accept = start && !compute_busy_q
                   && !(|i_valid_pipe) && !(|host_valid_pipe)
                   && (start_use_active ? tensor_weight_active_valid
                                        : tensor_weight_pending_valid);
assign weight_fill_start_ready = tensor_weight_fill_start_ready;
assign weight_fill_ready = tensor_weight_fill_ready;
assign weight_pending_valid = tensor_weight_pending_valid;
assign weight_active_valid = tensor_weight_active_valid;
assign weight_idle = !compute_busy_q
                  || handoff_ready_next;

// The input window may fetch around a temporarily unavailable
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
        && (input_select_offset < input_keep_q)
        && (input_select_index_try < target_count_q)
        && !input_slot_issued_q[input_select_slot_try]
        && ((input_select_mask_try & ~input_owned_mask) == 0)) begin
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
        && (next_input_select_offset < next_input_keep)
        && (next_input_select_index_try < next_input_prefetch_vector_count)
        && !next_input_slot_issued_q[next_input_select_slot_try]
        && ((next_input_select_mask_try & ~input_owned_mask) == 0)) begin
      next_input_select_valid = 1'b1;
      next_input_select_index = next_input_select_index_try;
      next_input_select_slot = next_input_select_slot_try;
      next_input_select_addr = next_input_select_addr_try;
      next_input_select_mask = next_input_select_mask_try;
    end
  end
end

assign active_input_select = input_select_valid;
// Handoff waits for every outstanding response before changing the active
// input window. Do not issue another prefetch on the handoff edge.
assign next_input_select = !active_input_select
                        && next_input_select_valid
                        && !handoff_ready_next
                        && next_input_before_deadline;
assign i_req_addr = active_input_select ? input_select_addr
                                        : next_input_select_addr;
assign psum_req_addr = WIDE_H4 ? psum_select_addr : start_accept ? psum_base_addr
                     : tile_mode_q ? striped_low_addr(psum_base_q, psum_issue_count_q)
                     : psum_base_q + (psum_fp32_q
                         ? {psum_issue_count_q[ADDR_WIDTH-3:0], 2'b00}
                         : {psum_issue_count_q[ADDR_WIDTH-2:0], 1'b0});
assign psum_req_hi_addr = psum_req_addr +
    (!WIDE_H4 && (start_accept ? start_mode[7] : tile_mode_q) ? ADDR_WIDTH'(8) : ADDR_WIDTH'(2));
assign input_psum_addr = tile_mode_q
    ? striped_low_addr(psum_base_q, input_consume_count_q)
    : psum_base_q + (psum_fp32_q
    ? {input_consume_count_q[ADDR_WIDTH-3:0], 2'b00}
    : {input_consume_count_q[ADDR_WIDTH-2:0], 1'b0});
assign i_req_mask = active_input_select ? input_select_mask
                                        : next_input_select_mask;
assign psum_req_mask = (start_accept ? start_mode[7] : tile_mode_q)
    ? (pair_mask(psum_req_addr) | pair_mask(psum_req_hi_addr))
    : ((start_accept ? start_dtype != 4'd0 : psum_fp32_q)
       ? quad_mask(psum_req_addr) : pair_mask(psum_req_addr));
assign output_pending = output_skew_inflight_q != 0;
assign output_skew_valid = WIDE_H4 ? output_select_valid : output_fifo_count_q != 0;
assign output_skew_payload = output_fifo_q[WIDE_H4 ? output_select_slot : output_fifo_head_q];
assign output_skew_tile = output_skew_payload[273];
assign output_skew_hi_addr = output_skew_addr +
    (!WIDE_H4 && output_skew_tile ? ADDR_WIDTH'(8) : ADDR_WIDTH'(2));
assign output_skew_addr = output_skew_payload[272:257];
assign output_skew_fp32 = output_skew_payload[256];
assign output_skew_data = output_skew_payload[255:0];
assign out_req_mask = output_skew_valid ?
    (output_skew_fp32
      ? (output_skew_tile
          ? (pair_mask(output_skew_addr) | pair_mask(output_skew_hi_addr))
          : quad_mask(output_skew_addr))
      : pair_mask(output_skew_addr)) : {BANK_NUM{1'b0}};
assign lower_owned_mask = fabric_phase[1] ? 16'hcccc : 16'h3333;
assign input_owned_mask = WIDE_H4 ? (16'h0003 << wide_input_bank)
    : LOWER_SIX ? (16'h0003 << fabric_phase) : lower_owned_mask;
assign psum_owned_mask = WIDE_H4 ? (16'h000f << psum_channel_bank) : LOWER_SIX ?
    ((start_accept ? start_mode[7] : tile_mode_q)
       ? ((16'h0003 << psum_channel_bank) |
          (16'h0003 << psum_other_channel_bank))
       : (start_accept ? start_dtype != 4'd0 : psum_fp32_q)
       ? ((16'h000f << psum_channel_bank) | (16'h000f >> (16-psum_channel_bank)))
       : (16'h0003 << psum_channel_bank)) : lower_owned_mask;
assign output_owned_mask = WIDE_H4 ? (16'h000f << output_channel_bank) : LOWER_SIX ?
    (output_skew_tile
       ? ((16'h0003 << output_channel_bank) |
          (output_skew_fp32 ? (16'h0003 << output_other_channel_bank) : 16'h0000))
       : output_skew_fp32
       ? ((16'h000f << output_channel_bank) | (16'h000f >> (16-output_channel_bank)))
       : (16'h0003 << output_channel_bank)) : lower_owned_mask;
assign i_req_owned = (i_req_mask & ~input_owned_mask) == 0;
assign psum_req_owned = (psum_req_mask & ~psum_owned_mask) == 0;
assign out_req_owned = (out_req_mask & ~output_owned_mask) == 0;
assign i_psum_conflict = (i_req_mask & psum_req_mask) != 0;
assign i_output_conflict = output_pending && ((i_req_mask & out_req_mask) != 0);
assign psum_output_conflict = output_pending
                           && ((psum_req_mask & out_req_mask) != 0);
assign read_conflicts_output = i_output_conflict;
assign psum_read_conflicts_output = psum_output_conflict;
assign read_candidate = compute_busy_q
                     && (active_input_select || next_input_select)
                     && i_req_owned;
// At each start, pending outputs become older than the new descriptor. Hold
// dependent P reads until those older results reach SRAM. Current descriptor
// outputs may alias future P addresses and must not create a false dependency.
always @* begin
  psum_req_addr_pending = 1'b0;
  input_psum_addr_pending = 1'b0;
  for (psum_meta_scan_i = 0; psum_meta_scan_i < META_FIFO_DEPTH;
       psum_meta_scan_i = psum_meta_scan_i + 1) begin
    psum_meta_scan_slot = meta_head_q
                        + psum_meta_scan_i[META_FIFO_INDEX_WIDTH-1:0];
    if (psum_meta_scan_i < meta_count_q) begin
      if ((start_accept || meta_old_fifo[psum_meta_scan_slot])
          && (WIDE_H4 ? output_overlap(meta_addr_fifo[psum_meta_scan_slot], psum_req_addr,
               meta_fp32_fifo[psum_meta_scan_slot],
               start_accept ? (start_mode[7] || start_dtype!=0) : (tile_mode_q || psum_fp32_q))
              : meta_addr_fifo[psum_meta_scan_slot] == psum_req_addr))
        psum_req_addr_pending = 1'b1;
      if (meta_old_fifo[psum_meta_scan_slot]
          && (WIDE_H4 ? output_overlap(meta_addr_fifo[psum_meta_scan_slot], input_psum_addr,
               meta_fp32_fifo[psum_meta_scan_slot], tile_mode_q || psum_fp32_q)
              : meta_addr_fifo[psum_meta_scan_slot] == input_psum_addr))
        input_psum_addr_pending = 1'b1;
    end
  end
  for (psum_output_scan_i = 0; psum_output_scan_i < OUTPUT_FIFO_DEPTH;
       psum_output_scan_i = psum_output_scan_i + 1) begin
    psum_output_scan_slot = output_fifo_head_q
                           + psum_output_scan_i[OUTPUT_FIFO_INDEX_WIDTH-1:0];
    if (psum_output_scan_i < output_fifo_count_q
        && (!WIDE_H4 || output_live_q[psum_output_scan_slot])) begin
      if ((start_accept || output_old_fifo[psum_output_scan_slot])
          && (WIDE_H4 ? output_overlap(output_fifo_q[psum_output_scan_slot][272:257], psum_req_addr,
               output_fifo_q[psum_output_scan_slot][256],
               start_accept ? (start_mode[7] || start_dtype!=0) : (tile_mode_q || psum_fp32_q))
              : output_fifo_q[psum_output_scan_slot][272:257] == psum_req_addr))
        psum_req_addr_pending = 1'b1;
      if (output_old_fifo[psum_output_scan_slot]
          && (WIDE_H4 ? output_overlap(output_fifo_q[psum_output_scan_slot][272:257], input_psum_addr,
               output_fifo_q[psum_output_scan_slot][256], tile_mode_q || psum_fp32_q)
              : output_fifo_q[psum_output_scan_slot][272:257] == input_psum_addr))
        input_psum_addr_pending = 1'b1;
    end
  end
end

// Issue the first stream PSUM read on the descriptor start edge when the bank
// and its source data are available, before input consumes the window.
assign psum_start_prefetch = start_accept
                          && (vector_count != 0)
                          && !start_mode[1] && !start_mode[2]
                          && !start_mode[4];
// Reserve space for every response already in flight.  The P request stream
// can outrun the late dot join when an I or O bank pauses; permit a new
// request at full occupancy only if the dot consumes a P beat this cycle.
assign psum_fifo_credit = ({1'b0, psum_count_q} + psum_inflight
                           < PSUM_FIFO_DEPTH) || psum_fifo_pop;
assign psum_candidate = ((compute_busy_q && stream_started_q
                       && (psum_stream_started_q
                           || (stream_cycle_q >= {1'b0, psum_offset_q}))
                       && (psum_issue_count_q < psum_target_count))
                       || psum_start_prefetch)
                     && (!WIDE_H4 || psum_select_valid)
                     && psum_req_owned && psum_fifo_credit
                     && !psum_req_addr_pending;
assign psum_urgent = psum_stream_mode && compute_busy_q
                  && ({1'b0, input_consume_count_q}
                      >= {1'b0, psum_issue_count_q}
                         + PSUM_URGENT_BACKLOG);
assign output_candidate = busy_q && output_skew_valid && out_req_owned;
assign read_fire = read_candidate
                && !(output_candidate && i_output_conflict)
                && !(next_input_select && psum_candidate
                     && i_psum_conflict)
                && !(psum_urgent && psum_candidate && i_psum_conflict);
assign output_write_fire = output_candidate
                        && !(read_fire && i_output_conflict)
                        && !(psum_urgent && psum_candidate
                             && psum_output_conflict);
// Keep the address/data pair in the engine FIFO until the DTCM fabric owns
// the destination bank.  The skew blocks above are retained for the legacy
// timing path, but their global tap cannot safely be reconfigured while an
// older descriptor is still in flight.
assign output_queue_push_valid = tensor_output_valid;
for (genvar lane=0; lane<8; lane=lane+1) begin: FP32_OUTPUT_PACK
  assign fp32_output_data[lane*32 +: 32] =
      (rsum_mode_q ? rsum_drain_fp32_q[lane*32+:32] : tensor_core_output_fp32[lane*32+:32]);
end
assign output_queue_push_payload = {meta_tile_fifo[meta_head_q],
    meta_addr_fifo[meta_head_q],
    meta_fp32_fifo[meta_head_q],
    meta_fp32_fifo[meta_head_q] ? fp32_output_data :
                                  {{PAIR_WIDTH{1'b0}}, tensor_output_data}};
assign output_skew_fifo_push = output_queue_push_valid
                             && ((output_fifo_count_q < OUTPUT_FIFO_DEPTH)
                                 || output_ring_retire);
assign output_skew_fifo_pop = output_write_fire;
assign output_skew_pop = output_skew_fifo_pop;
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
// Reserve an output slot before launching compute. Metadata counts all
// results still inside the dot/scale pipeline; FIFO count covers arrived
// results. Wide BF16 drain owns only one group per cycle and can be slower
// than input, so fixed pipeline latency alone does not bound FIFO occupancy.
wire output_launch_credit = !WIDE_H4
    || (rsum_mode_q && input_consume_count_q != 0)
    || ({1'b0,meta_count_q} + {2'b0,output_fifo_count_q} < OUTPUT_FIFO_DEPTH)
    || output_ring_retire;
assign input_compute_fire = compute_busy_q
                         && output_launch_credit
                         && (input_consume_count_q < target_count_q)
                         && input_head_valid
                         && (!scale_stream_enable_q || scale_stream_valid)
                         && (psum_stream_mode || compute_psum_valid)
                         // H4: issue this vector's P no later than I enters
                         // compute. Four memory edges then fit before the
                         // seven-cycle dot join even through bank conflicts.
                         && (!psum_stream_mode
                             || (WIDE_H4 ? (psum_input_issued || psum_input_issuing)
                                 : ((READ_LATENCY > 1)
                                 ? (psum_issue_count_q > input_consume_count_q)
                                 : ({1'b0, psum_issue_count_q} + INPUT_PSUM_LEAD
                                    > {1'b0, input_consume_count_q})))
                             || (!WIDE_H4 && psum_read_fire))
                         && (!psum_stream_mode
                             || (WIDE_H4 ? (psum_input_issued || psum_input_issuing)
                                 : ((psum_issue_count_q > input_consume_count_q)
                                    || (!input_psum_addr_pending && !psum_req_addr_pending))))
                         && !((input_consume_count_q == 0)
                              && !scale_enable_q
                              && (scaled_inflight_count_q != 0));
assign input_compute_data = input_slot_valid_q[input_head_slot]
                          ? input_window_read_data
                          : i_pair_rdata;
assign input_compute_out_addr = tile_mode_q && output_fp32_q
    ? striped_low_addr(out_base_q, input_consume_count_q)
    : out_base_q + (output_fp32_q
        ? {input_consume_count_q[ADDR_WIDTH-3:0], 2'b00}
        : {input_consume_count_q[ADDR_WIDTH-2:0], 1'b0});
assign input_fifo_rsp_store = iop_rsp_valid_q
                           && !i_rsp_next_input_q
                           && !(input_head_from_rsp && input_compute_fire);
assign next_input_fifo_rsp_store = iop_rsp_valid_q && i_rsp_next_input_q;
assign compute_valid_q = input_compute_fire;
assign scale_stream_ready = input_compute_fire && scale_stream_enable_q;
assign aligned_psum_valid = WIDE_H4
    ? (psum_slot_valid_q[psum_consume_count_q[PSUM_FIFO_INDEX_WIDTH-1:0]] || psum_head_from_rsp)
    : ((psum_count_q != 0) || psum_rsp_valid_q);
for (genvar lane=0; lane<8; lane=lane+1) begin: FP32_PSUM_UNPACK
  wire [255:0] raw_data = {psum_pair_extra_rdata, psum_pair_rdata};
  assign converted_psum_data[lane*32 +: 32] = psum_fp32_q
      ? raw_data[lane*32 +: 32] : {psum_pair_rdata[lane*16 +: 16],16'b0};
  assign compute_psum_bf16[lane*16+:16] = compute_psum_data[lane*32+16+:16];
end
assign aligned_psum_data = WIDE_H4
    ? (psum_slot_valid_q[psum_consume_count_q[PSUM_FIFO_INDEX_WIDTH-1:0]]
       ? psum_data_fifo[psum_consume_count_q[PSUM_FIFO_INDEX_WIDTH-1:0]] : converted_psum_data)
    : ((psum_count_q != 0) ? psum_data_fifo[psum_head_q] : converted_psum_data);
assign psum_target_count = psum_none_mode_q ? {VECTOR_COUNT_WIDTH{1'b0}}
                         : psum_once_mode_q
                           ? {{VECTOR_COUNT_WIDTH-1{1'b0}}, 1'b1}
                           : target_count_q;
assign psum_stream_mode = !psum_none_mode_q && !psum_once_mode_q;
assign dot_needs_psum = psum_stream_mode_pipe_q[6];
assign compute_psum_valid = psum_none_mode_q ? 1'b1
                          : psum_once_mode_q ? psum_once_valid_q
                          : aligned_psum_valid;
assign compute_psum_data = psum_none_mode_q ? {2*PAIR_WIDTH{1'b0}}
                         : psum_once_mode_q ? psum_once_data_q
                         : aligned_psum_data;

assign output_skew_push = tensor_output_valid;
assign output_skew_cfg_valid = 1'b0;
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
                         && !(|i_valid_pipe)
                         && !(|p_valid_pipe)
                         // Fixed I windows can finish a run while the dot
                         // pipeline still uses the active weights. Do not
                         // preactivate the next tile until the last result
                         // has captured those weights; SRAM writes may drain.
                         && (!LOWER_SIX || meta_count_q == 0
                             || (meta_count_q == 1 && tensor_output_valid))
                         && (input_slot_valid_q == {INPUT_FIFO_DEPTH{1'b0}})
                         // Output addresses and data remain in the FIFO, so
                         // a younger descriptor can start while older writes
                         // drain through the bank conflict arbiter.
                         && (!rsum_mode_q || tensor_output_valid);
assign drain_done_next = busy_q && !compute_busy_q && !output_pending
                      && (meta_count_q == 0) && (psum_count_q == 0)
                      && (output_fifo_count_q == 0)
                      && !output_skew_push && !start_accept
                      && !(|write_pipe);

// E4 exposes one extra rsum_merge_pending cycle after the final tile. E3's
// dot kernel already contains the accumulator, so this register is the
// equivalent ordering fence: capture the final value, then publish it on the
// following cycle while the output path drains the descriptor.
assign tensor_output_valid = rsum_mode_q
                           ? rsum_drain_pending_q
                           : tensor_core_output_valid;
assign tensor_output_data = rsum_mode_q
                          ? rsum_drain_data_q
                          : tensor_core_output_data;

assign host_bank_req = host_ready && host_req;
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
assign psum_pair_req_fp32 = psum_read_fire &&
    (start_accept ? (start_mode[7] || start_dtype != 4'd0) : psum_fp32_q);
assign psum_pair_bank0 = psum_req_addr[BANK_INDEX_WIDTH-1:0];
assign psum_pair_bank1 = next_bank(psum_req_addr);
assign psum_pair_bank2 = psum_req_hi_addr[BANK_INDEX_WIDTH-1:0];
assign psum_pair_bank3 = next_bank(psum_req_hi_addr);
assign psum_pair_addr = psum_req_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign psum_pair_extra_addr = psum_req_hi_addr[SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign psum_pair_rsp_bank0 = psum_rsp_bank0_q;
assign psum_pair_rsp_bank1 = psum_rsp_bank1_q;
assign o_pair_req = output_write_fire;
assign o_pair_bank0 = output_skew_addr[BANK_INDEX_WIDTH-1:0];
assign o_pair_bank1 = next_bank(output_skew_addr);
assign o_pair_bank2 = output_skew_hi_addr[BANK_INDEX_WIDTH-1:0];
assign o_pair_bank3 = next_bank(output_skew_hi_addr);
assign o_pair_fp32 = output_skew_fp32;
assign o_pair_addr = output_skew_addr
                   [SRAM_ADDR_WIDTH+BANK_INDEX_WIDTH-1:BANK_INDEX_WIDTH];
assign o_pair_extra_addr = output_skew_hi_addr
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
  .out_valid(output_skew_pipe_valid),
  .out_data(output_skew_pipe_payload)
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

edge_tensor_tile_backend #(.PACKED_WEIGHT(PACKED_WEIGHT)) x_tile8x8 (
  .clk(clk), .rst_b(cpurst_b), .compute_valid(compute_valid_q),
  .late_psum_mode_i(dot_needs_psum),
  .late_psum_valid_i(dot_needs_psum ? aligned_psum_valid : 1'b1),
  .input_bf16_i(input_compute_data), .psum_bf16_i(compute_psum_bf16),
  .psum_fp32_i(compute_psum_data), .wide_enable_i(psum_fp32_q || output_fp32_q),
  .output_fp32_o(tensor_core_output_fp32),
  .scale_enable_i(scale_enable_q),
  .scale_bf16_i(scale_stream_enable_q ? scale_stream_data : scale_bf16_q),
  .rsum_enable_i(rsum_mode_q),
  .rsum_first_i(rsum_mode_q
                && (input_consume_count_q == {VECTOR_COUNT_WIDTH{1'b0}})),
  .rsum_last_i(rsum_mode_q
               && (input_consume_count_q + {{VECTOR_COUNT_WIDTH-1{1'b0}}, 1'b1}
                   == target_count_q)),
  .legacy_fill_bf16_mode_i(weight_fill_bf16_mode),
  .legacy_fill_start_i(weight_fill_start),
  .legacy_fill_start_ready_o(tensor_weight_fill_start_ready),
  .legacy_fill_valid_i(weight_fill_valid),
  .legacy_fill_ready_o(tensor_weight_fill_ready),
  .legacy_fill_pair_idx_i(weight_fill_pair_idx),
  .legacy_fill_data_i(weight_fill_data), .legacy_fill_last_i(weight_fill_last),
  .packed_start_i(packed_weight_start),
  .packed_start_ready_o(packed_weight_start_ready),
  .packed_wtype_i(packed_weight_wtype),
  .packed_transpose_i(packed_weight_transpose),
  .packed_busy_o(packed_weight_busy), .packed_done_o(packed_weight_done),
  .packed_load_valid_i(packed_weight_load_valid),
  .packed_load_ready_o(packed_weight_load_ready),
  .packed_load_idx_i(packed_weight_load_idx),
  .packed_load_data_i(packed_weight_load_data),
  .weight_activate_i(weight_preactivate || (start_accept && !start_use_active)),
  .weight_activate_ready_o(tensor_weight_activate_ready),
  .weight_fill_busy_o(tensor_weight_fill_busy),
  .weight_active_valid_o(tensor_weight_active_valid),
  .weight_pending_valid_o(tensor_weight_pending_valid),
  .dot_ready_o(dot_ready),
  .output_valid_o(tensor_core_output_valid),
  .output_bf16_o(tensor_core_output_data)
);

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    busy_q <= 1'b0;
    compute_busy_q <= 1'b0;
    done_q <= 1'b0;
    handoff_ready_q <= 1'b0;
    stream_started_q <= 1'b0;
    psum_stream_started_q <= 1'b0;
    next_input_tail_q <= 0;
    stream_cycle_q <= 5'b0;
    psum_offset_q <= 4'b0;
    input_keep_q <= INPUT_KEEP_WIDTH'(INPUT_FIFO_DEPTH);
    target_count_q <= 0;
    read_issue_count_q <= 0;
    input_consume_count_q <= 0;
    psum_issue_count_q <= 0;
    in_base_q <= 0;
    psum_base_q <= 0;
    out_base_q <= 0;
    next_input_issue_count_q <= 0;
    psum_head_q <= 0;
    psum_tail_q <= 0;
    psum_count_q <= 0;
    psum_slot_issued_q <= 0; psum_slot_valid_q <= 0;
    psum_consume_count_q <= 0;
    meta_head_q <= 0;
    meta_tail_q <= 0;
    meta_count_q <= 0;
    scaled_inflight_count_q <= 0;
    output_skew_inflight_q <= 0;
    output_fifo_head_q <= 0;
    output_fifo_tail_q <= 0;
    output_fifo_count_q <= 0;
    output_live_q <= 0;
    for (output_fifo_i = 0; output_fifo_i < OUTPUT_FIFO_DEPTH;
         output_fifo_i = output_fifo_i + 1) begin
      output_fifo_q[output_fifo_i] <= 0;
      output_old_fifo[output_fifo_i] <= 1'b0;
    end
    psum_stream_mode_pipe_q <= 7'b0;
    rsum_drain_pending_q <= 1'b0;
    rsum_drain_data_q <= 0; rsum_drain_fp32_q <= 0;
    scale_enable_q <= 1'b0;
    scale_stream_enable_q <= 1'b0;
    scale_bf16_q <= 0;
    psum_once_mode_q <= 1'b0;
    psum_none_mode_q <= 1'b0;
    rsum_mode_q <= 1'b0;
    output_fp32_q <= 1'b0;
    psum_fp32_q <= 1'b0;
    tile_mode_q <= 1'b0;
    psum_once_valid_q <= 1'b0;
    psum_once_data_q <= 0;
    for (psum_fifo_i = 0; psum_fifo_i < PSUM_FIFO_DEPTH;
         psum_fifo_i = psum_fifo_i + 1)
      psum_data_fifo[psum_fifo_i] <= 0;
    for (meta_fifo_i = 0; meta_fifo_i < META_FIFO_DEPTH;
         meta_fifo_i = meta_fifo_i + 1) begin
      meta_addr_fifo[meta_fifo_i] <= 0;
      meta_old_fifo[meta_fifo_i] <= 1'b0;
      meta_scale_fifo[meta_fifo_i] <= 1'b0;
      meta_first_fifo[meta_fifo_i] <= 1'b0;
      meta_tile_fifo[meta_fifo_i] <= 1'b0;
    end
  end else begin
    psum_stream_mode_pipe_q <=
        {psum_stream_mode_pipe_q[5:0],
         input_compute_fire && psum_stream_mode};
    done_q <= 1'b0;
    handoff_ready_q <= 1'b0;

    if (rsum_mode_q) begin
      rsum_drain_pending_q <= tensor_core_output_valid;
      if (tensor_core_output_valid)
        begin rsum_drain_data_q <= tensor_core_output_data; rsum_drain_fp32_q <= tensor_core_output_fp32; end
    end else begin
      rsum_drain_pending_q <= 1'b0;
    end

    if (start_accept) begin
      for (meta_fifo_i = 0; meta_fifo_i < META_FIFO_DEPTH;
           meta_fifo_i = meta_fifo_i + 1)
        meta_old_fifo[meta_fifo_i] <= 1'b1;
      for (output_fifo_i = 0; output_fifo_i < OUTPUT_FIFO_DEPTH;
           output_fifo_i = output_fifo_i + 1)
        output_old_fifo[output_fifo_i] <= 1'b1;
      busy_q <= 1'b1;
      compute_busy_q <= 1'b1;
      stream_started_q <= next_input_prefetch_valid
                       && (next_input_issue_count_q != 0);
      // A queued I window already started its stream. The legacy phase
      // offset must not restart P warmup after the window-bank swap; bank
      // ownership, indexed credit and older-output RAW checks still apply.
      psum_stream_started_q <= WIDE_H4 && LOWER_SIX && READ_LATENCY == 4
          && !(|start_mode[4:0]) && next_input_prefetch_valid
          && next_input_issue_count_q != 0;
      next_input_tail_q <= 0;
      stream_cycle_q <= 0;
      psum_offset_q <= start_psum_offset;
      input_keep_q <= start_input_keep;
      target_count_q <= vector_count;
      read_issue_count_q <= next_input_prefetch_valid
                          ? next_input_issue_count_q : 0;
      input_consume_count_q <= 0;
      psum_issue_count_q <= psum_read_fire
                         ? {{VECTOR_COUNT_WIDTH-1{1'b0}}, 1'b1} : 0;
      in_base_q <= in_base_addr;
      psum_base_q <= psum_base_addr;
      out_base_q <= out_base_addr;
      next_input_issue_count_q <= 0;
      scale_enable_q <= start_mode[0] && !start_mode[4];
      scale_stream_enable_q <= start_mode[3] && !start_mode[4];
      scale_bf16_q <= scale_bf16;
      psum_once_mode_q <= start_mode[1] && !start_mode[2]
                       && !start_mode[4];
      psum_none_mode_q <= start_mode[2] || start_mode[4];
      rsum_mode_q <= start_mode[4];
      output_fp32_q <= start_mode[7] ? start_mode[6] : (start_dtype == 4'd2);
      psum_fp32_q <= start_mode[7] || (start_dtype != 4'd0);
      tile_mode_q <= start_mode[7];
      psum_once_valid_q <= 1'b0;
    end else if (stream_started_q) begin
      stream_cycle_q <= stream_cycle_q + 5'd1;
    end

    if (read_fire) begin
      if (next_input_select) begin
        next_input_issue_count_q <= next_input_issue_count_q + 1'b1;
      end else begin
        read_issue_count_q <= read_issue_count_q + 1'b1;
        if (!stream_started_q) begin
          stream_started_q <= 1'b1;
          stream_cycle_q <= 5'd1;
        end
      end
    end

    if (!start_accept && next_input_tail_q != 0)
      next_input_tail_q <= next_input_tail_q - 1'b1;
    if (input_compute_fire) begin
      if (input_consume_count_q + 1'b1 == target_count_q)
        next_input_tail_q <= 2'd3;
      input_consume_count_q <= input_consume_count_q + 1'b1;
    end

    if (psum_read_fire) begin
      psum_stream_started_q <= 1'b1;
      if (!start_accept)
        psum_issue_count_q <= psum_issue_count_q + 1'b1;
    end

    if (psum_rsp_valid_q && psum_once_mode_q) begin
      psum_once_data_q <= converted_psum_data;
      psum_once_valid_q <= 1'b1;
    end

    if (meta_fifo_push) begin
      meta_addr_fifo[meta_tail_q] <= input_compute_out_addr;
      meta_old_fifo[meta_tail_q] <= 1'b0;
      meta_scale_fifo[meta_tail_q] <= scale_enable_q;
      meta_fp32_fifo[meta_tail_q] <= output_fp32_q;
      meta_tile_fifo[meta_tail_q] <= tile_mode_q;
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

    if (WIDE_H4) begin
      if (start_accept) begin
        psum_slot_issued_q <= psum_read_fire ? {{(PSUM_FIFO_DEPTH-1){1'b0}},1'b1} : 0;
        psum_slot_valid_q <= 0;
        psum_consume_count_q <= 0;
      end else if (psum_read_fire)
        psum_slot_issued_q[psum_select_index[PSUM_FIFO_INDEX_WIDTH-1:0]] <= 1;
      if (psum_fifo_push)
        psum_slot_valid_q[psum_rsp_index[PSUM_FIFO_INDEX_WIDTH-1:0]] <= 1;
      if (psum_fifo_pop) begin
        psum_slot_issued_q[psum_consume_count_q[PSUM_FIFO_INDEX_WIDTH-1:0]] <= 0;
        psum_slot_valid_q[psum_consume_count_q[PSUM_FIFO_INDEX_WIDTH-1:0]] <= 0;
        psum_consume_count_q <= psum_consume_count_q + 1'b1;
      end
    end
    if (psum_fifo_push) begin
      psum_data_fifo[WIDE_H4 ? psum_rsp_index[PSUM_FIFO_INDEX_WIDTH-1:0] : psum_tail_q] <= converted_psum_data;
      psum_tail_q <= psum_tail_q + 1'b1;
    end
    if (psum_fifo_pop)
      psum_head_q <= psum_head_q + 1'b1;
    case ({psum_fifo_push, psum_fifo_pop})
      2'b10: psum_count_q <= psum_count_q + 1'b1;
      2'b01: psum_count_q <= psum_count_q - 1'b1;
      default: begin end
    endcase

    if (output_skew_fifo_pop)
      output_live_q[WIDE_H4 ? output_select_slot : output_fifo_head_q] <= 0;
    if (output_ring_retire)
      output_live_q[output_fifo_head_q] <= 0;
    if (output_skew_fifo_push) begin
      output_live_q[output_fifo_tail_q] <= 1;
      output_fifo_q[output_fifo_tail_q] <= output_queue_push_payload;
      output_old_fifo[output_fifo_tail_q] <=
          meta_old_fifo[meta_head_q] || start_accept;
      output_fifo_tail_q <= output_fifo_tail_q + 1'b1;
    end
    if (output_ring_retire)
      output_fifo_head_q <= output_fifo_head_q + 1'b1;
    case ({output_skew_fifo_push, output_ring_retire})
      2'b10: output_fifo_count_q <= output_fifo_count_q + 1'b1;
      2'b01: output_fifo_count_q <= output_fifo_count_q - 1'b1;
      default: begin end
    endcase

    case ({output_skew_push, output_skew_pop})
      2'b10: output_skew_inflight_q <= output_skew_inflight_q + 1'b1;
      2'b01: output_skew_inflight_q <= output_skew_inflight_q - 1'b1;
      default: begin end
    endcase

`ifndef SYNTHESIS
    if (WIDE_H4 && start_accept && (psum_count_q!=0 || (|p_valid_pipe)))
      $fatal(1,"P descriptor handoff before old responses drained");
    if (WIDE_H4 && psum_read_fire && !start_accept &&
        psum_slot_issued_q[psum_select_index[PSUM_FIFO_INDEX_WIDTH-1:0]])
      $fatal(1,"P issued a reserved vector slot twice");
    if (WIDE_H4 && psum_fifo_push &&
        (!psum_slot_issued_q[psum_rsp_index[PSUM_FIFO_INDEX_WIDTH-1:0]] ||
         psum_slot_valid_q[psum_rsp_index[PSUM_FIFO_INDEX_WIDTH-1:0]]))
      $fatal(1,"P response without reserved empty slot");
    if (WIDE_H4 && psum_fifo_pop &&
        !psum_slot_issued_q[psum_consume_count_q[PSUM_FIFO_INDEX_WIDTH-1:0]])
      $fatal(1,"P join consumed an unissued vector");
    // Reordering is permitted only across disjoint destinations. The
    // group selector should imply this; keep an independent address check.
    if (WIDE_H4 && output_write_fire) begin
      for (integer age=0;age<OUTPUT_FIFO_DEPTH;age=age+1) begin
        if (age<output_fifo_count_q &&
            age<int'(OUTPUT_FIFO_INDEX_WIDTH'(output_select_slot-output_fifo_head_q)) &&
            output_live_q[OUTPUT_FIFO_INDEX_WIDTH'(output_fifo_head_q+age)] &&
            output_overlap(output_fifo_q[OUTPUT_FIFO_INDEX_WIDTH'(output_fifo_head_q+age)][272:257],
                           output_skew_addr,
                           output_fifo_q[OUTPUT_FIFO_INDEX_WIDTH'(output_fifo_head_q+age)][256],
                           output_skew_fp32))
          $fatal(1,"wide output reordered overlapping writes");
      end
    end
    if (WIDE_H4 && output_skew_fifo_push &&
        (output_queue_push_payload[257] ||
         (output_queue_push_payload[256] && output_queue_push_payload[258])))
      $fatal(1,"wide output queue requires vector-aligned addresses");
    if (WIDE_H4 && output_skew_fifo_pop && !output_live_q[output_select_slot])
      $fatal(1,"wide output selected a retired slot");
    if (WIDE_H4 && start_accept &&
        (((start_mode[7] || start_dtype != 0) && !start_mode[2] && !start_mode[4]
          && psum_base_addr[1:0]!=0) ||
         ((start_mode[7] ? start_mode[6] : start_dtype==2) && out_base_addr[1:0]!=0)))
      $fatal(1,"wide H4 P/O requires 32-byte alignment");
    if (LOWER_SIX && start_accept &&
        (((start_mode[7] || start_dtype != 4'd0) && !start_mode[2] && !start_mode[4]
          && psum_base_addr[0]) ||
         ((start_mode[7] ? start_mode[6] : start_dtype == 4'd2)
          && out_base_addr[0])))
      $fatal(1, "32-bit tensor P/O vectors require 16-byte alignment");
    if (dot_ready && dot_needs_psum && !aligned_psum_valid)
      $fatal(1, "tensor P response missed dot join");
    if (psum_fifo_push && (psum_count_q == PSUM_FIFO_DEPTH)
        && !psum_fifo_pop) begin
      $display("tensor P FIFO overflow");
      $fatal(1,"tensor FIFO/skew invariant violated");
    end
    if (output_queue_push_valid && !output_skew_fifo_push) begin
      $display("tensor output FIFO overflow addr=%h phase=%h count=%0d",
               output_queue_push_payload[272:257], fabric_phase,
               output_fifo_count_q);
      $fatal(1,"tensor FIFO/skew invariant violated");
    end
    if (output_skew_cfg_valid && (output_skew_inflight_q != 0)) begin
      $display("tensor output skew reconfigured with %0d old beats in flight",
               output_skew_inflight_q);
      $fatal(1,"tensor FIFO/skew invariant violated");
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
