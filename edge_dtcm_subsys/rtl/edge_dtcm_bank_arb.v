// DTCM fixed-phase rotating-channel scheduler.
//
// The DTCM has 16 banks grouped as eight 128-bit bank pairs. The scheduler
// exposes eight logical channels. A channel keeps its logical identity while
// the visible physical bank pair rotates every cycle:
//
//   pair = channel + phase
//
// There is no dynamic reservation or priority path in this arbiter. Each
// client owns a fixed channel and must phase-lock its request stream before
// presenting it:
//
//   tensor lanes: 0, 2, 4, 6
//   LSU:          1
//   DMA:          3
//   WLD:          5
//   reserved:     7
//
// Legacy lease/reservation inputs are accepted for compatibility, but they do
// not block fixed-phase current requests.

module edge_dtcm_bank_arb(
  clk,
  cpurst_b,
  cur_dma_a2d_advance,
  cur_dma_a2d_grant_mask,
  cur_dma_a2d_req_mask,
  cur_dma_a2d_stall,
  cur_dma_d2a_advance,
  cur_dma_d2a_grant_mask,
  cur_dma_d2a_req_mask,
  cur_dma_d2a_stall,
  cur_lsu_advance,
  cur_lsu_grant_mask,
  cur_lsu_req_mask,
  cur_tensor_in_advance,
  cur_tensor_in_grant_mask,
  cur_tensor_in_req_mask,
  cur_tensor_in_stall,
  cur_tensor_out_advance,
  cur_tensor_out_grant_mask,
  cur_tensor_out_req_mask,
  cur_tensor_out_stall,
  cur_tensor_prefetch_advance,
  cur_tensor_prefetch_grant_mask,
  cur_tensor_prefetch_req_mask,
  cur_tensor_prefetch_stall,
  cur_tensor_wld_advance,
  cur_tensor_wld_grant_mask,
  cur_tensor_wld_req_mask,
  cur_tensor_wld_stall,
  dma_lease_channel,
  dma_lease_cycles,
  dma_lease_delay,
  dma_lease_valid,
  dma_resv_accepted,
  dbg_phase,
  dma_resv_mask,
  dma_resv_req,
  lsu_lease_channel,
  lsu_lease_cycles,
  lsu_lease_delay,
  lsu_lease_valid,
  lsu_resv_accepted,
  lsu_resv_mask,
  repair_overflow,
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
  tensor_lease_channel,
  tensor_lease_cycles,
  tensor_lease_delay,
  tensor_lease_valid,
  tensor_resv_accepted,
  tensor_resv_mask,
  tensor_resv_req,
  tensor_wld_lease_channel_mask,
  tensor_wld_lease_cycles,
  tensor_wld_lease_delay,
  tensor_wld_lease_valid,
  win_current_busy_mask,
  win_current_dma_mask,
  win_current_lsu_mask,
  win_current_tensor_mask
);

parameter BANK_NUM         = 16;
parameter [3:0] LSU_LOOKAHEAD    = 4'd1;
parameter [3:0] TENSOR_IO_LOOKAHEAD  = 4'd2;
parameter [3:0] TENSOR_WLD_LOOKAHEAD = 4'd2;
parameter [3:0] DMA_LOOKAHEAD    = 4'd3;

input                 clk;
input                 cpurst_b;
input  [BANK_NUM-1:0] cur_dma_a2d_req_mask;
input  [BANK_NUM-1:0] cur_dma_d2a_req_mask;
input  [BANK_NUM-1:0] cur_lsu_req_mask;
input  [BANK_NUM-1:0] cur_tensor_in_req_mask;
input  [BANK_NUM-1:0] cur_tensor_out_req_mask;
input  [BANK_NUM-1:0] cur_tensor_prefetch_req_mask;
input  [BANK_NUM-1:0] cur_tensor_wld_req_mask;
input  [BANK_NUM-1:0] dma_resv_mask;
input                 dma_resv_req;
input  [2:0]          dma_lease_channel;
input  [8:0]          dma_lease_cycles;
input  [3:0]          dma_lease_delay;
input                 dma_lease_valid;
input  [2:0]          lsu_lease_channel;
input  [8:0]          lsu_lease_cycles;
input  [3:0]          lsu_lease_delay;
input                 lsu_lease_valid;
input  [BANK_NUM-1:0] lsu_resv_mask;
input  [7:0]          tensor_io_lease_channel_mask;
input  [8:0]          tensor_io_lease_cycles;
input  [3:0]          tensor_io_lease_delay;
input  [7:0]          tensor_io_lease1_channel_mask;
input  [8:0]          tensor_io_lease1_cycles;
input  [3:0]          tensor_io_lease1_delay;
input                 tensor_io_lease1_valid;
input  [7:0]          tensor_io_lease2_channel_mask;
input  [8:0]          tensor_io_lease2_cycles;
input  [3:0]          tensor_io_lease2_delay;
input                 tensor_io_lease2_valid;
input                 tensor_io_lease_valid;
input  [2:0]          tensor_lease_channel;
input  [8:0]          tensor_lease_cycles;
input  [3:0]          tensor_lease_delay;
input                 tensor_lease_valid;
input  [BANK_NUM-1:0] tensor_resv_mask;
input                 tensor_resv_req;
input  [7:0]          tensor_wld_lease_channel_mask;
input  [8:0]          tensor_wld_lease_cycles;
input  [3:0]          tensor_wld_lease_delay;
input                 tensor_wld_lease_valid;

output                cur_dma_a2d_advance;
output [BANK_NUM-1:0] cur_dma_a2d_grant_mask;
output                cur_dma_a2d_stall;
output                cur_dma_d2a_advance;
output [BANK_NUM-1:0] cur_dma_d2a_grant_mask;
output                cur_dma_d2a_stall;
output                cur_lsu_advance;
output [BANK_NUM-1:0] cur_lsu_grant_mask;
output                cur_tensor_in_advance;
output [BANK_NUM-1:0] cur_tensor_in_grant_mask;
output                cur_tensor_in_stall;
output                cur_tensor_out_advance;
output [BANK_NUM-1:0] cur_tensor_out_grant_mask;
output                cur_tensor_out_stall;
output                cur_tensor_prefetch_advance;
output [BANK_NUM-1:0] cur_tensor_prefetch_grant_mask;
output                cur_tensor_prefetch_stall;
output                cur_tensor_wld_advance;
output [BANK_NUM-1:0] cur_tensor_wld_grant_mask;
output                cur_tensor_wld_stall;
output                dma_resv_accepted;
output [2:0]          dbg_phase;
output                lsu_resv_accepted;
output                repair_overflow;
output                tensor_resv_accepted;
output [BANK_NUM-1:0] win_current_busy_mask;
output [BANK_NUM-1:0] win_current_dma_mask;
output [BANK_NUM-1:0] win_current_lsu_mask;
output [BANK_NUM-1:0] win_current_tensor_mask;

localparam CHANNEL_NUM = 8;

reg [2:0]              phase;

wire                   lsu_req_vld;
wire                   tensor_out_req_vld;
wire                   tensor_in_req_vld;
wire                   tensor_prefetch_req_vld;
wire                   tensor_wld_req_vld;
wire                   dma_a2d_req_vld;
wire                   dma_d2a_req_vld;
wire [2:0]             lsu_req_pair;
wire [2:0]             tensor_out_req_pair;
wire [2:0]             tensor_in_req_pair;
wire [2:0]             tensor_prefetch_req_pair;
wire [2:0]             tensor_wld_req_pair;
wire [2:0]             dma_a2d_req_pair;
wire [2:0]             dma_d2a_req_pair;
wire                   lsu_fire;
wire                   tensor_out_fire;
wire                   tensor_in_fire;
wire                   tensor_prefetch_fire;
wire                   tensor_wld_fire;
wire                   dma_a2d_fire;
wire                   dma_d2a_fire;
wire                   lsu_grant_fire;
wire                   tensor_out_grant_fire;
wire                   tensor_in_grant_fire;
wire                   tensor_prefetch_grant_fire;
wire                   tensor_wld_grant_fire;
wire                   dma_a2d_grant_fire;
wire                   dma_d2a_grant_fire;
wire [BANK_NUM-1:0]    current_lsu_mask;
wire [BANK_NUM-1:0]    current_tensor_mask;
wire [BANK_NUM-1:0]    current_dma_mask;
wire [2:0]             issue_phase;

function [2:0] mask_to_pair;
  input [BANK_NUM-1:0] mask;
  integer              idx;
  reg                  found;
  begin
    mask_to_pair = 3'b0;
    found = 1'b0;
    for (idx = 0; idx < BANK_NUM; idx = idx + 1) begin
      if (!found && mask[idx]) begin
        mask_to_pair = idx[3:1];
        found = 1'b1;
      end
    end
  end
endfunction

function [BANK_NUM-1:0] channel_pair_mask;
  input [2:0] channel;
  input [2:0] phase_i;
  reg [2:0]   pair;
  begin
    pair = channel + phase_i;
    channel_pair_mask = {BANK_NUM{1'b0}};
    channel_pair_mask[{pair, 1'b0}] = 1'b1;
    channel_pair_mask[{pair, 1'b1}] = 1'b1;
end
endfunction

localparam [2:0] FIXED_CH_TENSOR0 = 3'd0;
localparam [2:0] FIXED_CH_LSU     = 3'd1;
localparam [2:0] FIXED_CH_TENSOR1 = 3'd2;
localparam [2:0] FIXED_CH_DMA     = 3'd3;
localparam [2:0] FIXED_CH_TENSOR2 = 3'd4;
localparam [2:0] FIXED_CH_WLD     = 3'd5;
localparam [2:0] FIXED_CH_TENSOR3 = 3'd6;

initial begin
  phase = 3'b0;
end

function channel_matches_pair;
  input [2:0] channel;
  input [2:0] phase_i;
  input [2:0] pair;
begin
  channel_matches_pair = ((channel + phase_i) === pair);
end
endfunction

assign lsu_req_vld = |cur_lsu_req_mask[BANK_NUM-1:0];
assign tensor_out_req_vld = |cur_tensor_out_req_mask[BANK_NUM-1:0];
assign tensor_in_req_vld = |cur_tensor_in_req_mask[BANK_NUM-1:0];
assign tensor_prefetch_req_vld = |cur_tensor_prefetch_req_mask[BANK_NUM-1:0];
assign tensor_wld_req_vld = |cur_tensor_wld_req_mask[BANK_NUM-1:0];
assign dma_a2d_req_vld = |cur_dma_a2d_req_mask[BANK_NUM-1:0];
assign dma_d2a_req_vld = |cur_dma_d2a_req_mask[BANK_NUM-1:0];

assign lsu_req_pair[2:0] = mask_to_pair(cur_lsu_req_mask[BANK_NUM-1:0]);
assign tensor_out_req_pair[2:0] =
       mask_to_pair(cur_tensor_out_req_mask[BANK_NUM-1:0]);
assign tensor_in_req_pair[2:0] =
       mask_to_pair(cur_tensor_in_req_mask[BANK_NUM-1:0]);
assign tensor_prefetch_req_pair[2:0] =
       mask_to_pair(cur_tensor_prefetch_req_mask[BANK_NUM-1:0]);
assign tensor_wld_req_pair[2:0] =
       mask_to_pair(cur_tensor_wld_req_mask[BANK_NUM-1:0]);
assign dma_a2d_req_pair[2:0] =
       mask_to_pair(cur_dma_a2d_req_mask[BANK_NUM-1:0]);
assign dma_d2a_req_pair[2:0] =
       mask_to_pair(cur_dma_d2a_req_mask[BANK_NUM-1:0]);
assign issue_phase[2:0] = phase[2:0];

assign lsu_fire =
       (lsu_req_vld === 1'b1)
    && channel_matches_pair(FIXED_CH_LSU[2:0], issue_phase[2:0],
                            lsu_req_pair[2:0]);
assign tensor_out_fire =
       (tensor_out_req_vld === 1'b1)
    && channel_matches_pair(FIXED_CH_TENSOR0[2:0], issue_phase[2:0],
                            tensor_out_req_pair[2:0]);
assign tensor_in_fire =
       (tensor_in_req_vld === 1'b1)
    && channel_matches_pair(FIXED_CH_TENSOR1[2:0], issue_phase[2:0],
                            tensor_in_req_pair[2:0]);
assign tensor_prefetch_fire =
       (tensor_prefetch_req_vld === 1'b1)
    && channel_matches_pair(FIXED_CH_TENSOR2[2:0], issue_phase[2:0],
                            tensor_prefetch_req_pair[2:0]);
assign tensor_wld_fire =
       (tensor_wld_req_vld === 1'b1)
    && channel_matches_pair(FIXED_CH_WLD[2:0], issue_phase[2:0],
                            tensor_wld_req_pair[2:0]);
assign dma_a2d_fire =
       (dma_a2d_req_vld === 1'b1)
    && channel_matches_pair(FIXED_CH_DMA[2:0], issue_phase[2:0],
                            dma_a2d_req_pair[2:0]);
assign dma_d2a_fire =
       (dma_d2a_req_vld === 1'b1)
    && channel_matches_pair(FIXED_CH_DMA[2:0], issue_phase[2:0],
                            dma_d2a_req_pair[2:0]);

assign tensor_out_grant_fire = tensor_out_fire;
assign tensor_in_grant_fire = tensor_in_fire;
assign dma_a2d_grant_fire = dma_a2d_fire;
assign dma_d2a_grant_fire = dma_d2a_fire;
assign tensor_prefetch_grant_fire = tensor_prefetch_fire;
assign tensor_wld_grant_fire = tensor_wld_fire;
assign lsu_grant_fire = lsu_fire;

assign cur_lsu_advance = lsu_grant_fire;
assign cur_tensor_out_advance = tensor_out_grant_fire;
assign cur_tensor_in_advance = tensor_in_grant_fire;
assign cur_tensor_prefetch_advance = tensor_prefetch_grant_fire;
assign cur_tensor_wld_advance = tensor_wld_grant_fire;
assign cur_dma_a2d_advance = dma_a2d_grant_fire;
assign cur_dma_d2a_advance = dma_d2a_grant_fire;

assign cur_lsu_grant_mask[BANK_NUM-1:0] =
       lsu_grant_fire ? cur_lsu_req_mask[BANK_NUM-1:0]
                      : {BANK_NUM{1'b0}};
assign cur_tensor_out_grant_mask[BANK_NUM-1:0] =
       tensor_out_grant_fire ? cur_tensor_out_req_mask[BANK_NUM-1:0]
                             : {BANK_NUM{1'b0}};
assign cur_tensor_in_grant_mask[BANK_NUM-1:0] =
       tensor_in_grant_fire ? cur_tensor_in_req_mask[BANK_NUM-1:0]
                            : {BANK_NUM{1'b0}};
assign cur_tensor_prefetch_grant_mask[BANK_NUM-1:0] =
       tensor_prefetch_grant_fire ? cur_tensor_prefetch_req_mask[BANK_NUM-1:0]
                                  : {BANK_NUM{1'b0}};
assign cur_tensor_wld_grant_mask[BANK_NUM-1:0] =
       tensor_wld_grant_fire ? cur_tensor_wld_req_mask[BANK_NUM-1:0]
                             : {BANK_NUM{1'b0}};
assign cur_dma_a2d_grant_mask[BANK_NUM-1:0] =
       dma_a2d_grant_fire ? cur_dma_a2d_req_mask[BANK_NUM-1:0]
                           : {BANK_NUM{1'b0}};
assign cur_dma_d2a_grant_mask[BANK_NUM-1:0] =
       dma_d2a_grant_fire ? cur_dma_d2a_req_mask[BANK_NUM-1:0]
                           : {BANK_NUM{1'b0}};

assign cur_tensor_out_stall =
       (tensor_out_req_vld === 1'b1) && !tensor_out_grant_fire;
assign cur_tensor_in_stall =
       (tensor_in_req_vld === 1'b1) && !tensor_in_grant_fire;
assign cur_tensor_prefetch_stall =
       (tensor_prefetch_req_vld === 1'b1) && !tensor_prefetch_grant_fire;
assign cur_tensor_wld_stall =
       (tensor_wld_req_vld === 1'b1) && !tensor_wld_grant_fire;
assign cur_dma_a2d_stall =
       (dma_a2d_req_vld === 1'b1) && !dma_a2d_grant_fire;
assign cur_dma_d2a_stall =
       (dma_d2a_req_vld === 1'b1) && !dma_d2a_grant_fire;

assign tensor_resv_accepted = tensor_resv_req
                           || tensor_lease_valid
                           || tensor_io_lease_valid
                           || tensor_io_lease1_valid
                           || tensor_io_lease2_valid
                           || tensor_wld_lease_valid;
assign lsu_resv_accepted = (|lsu_resv_mask[BANK_NUM-1:0])
                        || lsu_lease_valid;
assign dma_resv_accepted = dma_resv_req || dma_lease_valid;
assign repair_overflow = 1'b0;

assign current_lsu_mask[BANK_NUM-1:0] =
       (lsu_req_vld === 1'b1)
       ? channel_pair_mask(FIXED_CH_LSU[2:0], phase[2:0])
       : {BANK_NUM{1'b0}};
assign current_tensor_mask[BANK_NUM-1:0] =
       ((tensor_out_req_vld === 1'b1)
        ? channel_pair_mask(FIXED_CH_TENSOR0[2:0], phase[2:0])
        : {BANK_NUM{1'b0}})
     | ((tensor_in_req_vld === 1'b1)
        ? channel_pair_mask(FIXED_CH_TENSOR1[2:0], phase[2:0])
        : {BANK_NUM{1'b0}})
     | ((tensor_prefetch_req_vld === 1'b1)
        ? channel_pair_mask(FIXED_CH_TENSOR2[2:0], phase[2:0])
        : {BANK_NUM{1'b0}})
     | ((tensor_wld_req_vld === 1'b1)
        ? channel_pair_mask(FIXED_CH_WLD[2:0], phase[2:0])
        : {BANK_NUM{1'b0}});
assign current_dma_mask[BANK_NUM-1:0] =
       ((dma_a2d_req_vld === 1'b1) || (dma_d2a_req_vld === 1'b1)
        ? channel_pair_mask(FIXED_CH_DMA[2:0], phase[2:0])
        : {BANK_NUM{1'b0}});
assign win_current_lsu_mask[BANK_NUM-1:0] = current_lsu_mask[BANK_NUM-1:0];
assign win_current_tensor_mask[BANK_NUM-1:0] =
       current_tensor_mask[BANK_NUM-1:0]
     | (tensor_io_lease_valid
        ? channel_pair_mask(FIXED_CH_TENSOR3[2:0], phase[2:0])
        : {BANK_NUM{1'b0}});
assign win_current_dma_mask[BANK_NUM-1:0] = current_dma_mask[BANK_NUM-1:0];
assign win_current_busy_mask[BANK_NUM-1:0] =
       win_current_lsu_mask[BANK_NUM-1:0]
     | win_current_tensor_mask[BANK_NUM-1:0]
     | win_current_dma_mask[BANK_NUM-1:0];
assign dbg_phase[2:0] = phase[2:0];

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    phase <= 3'b0;
  end else begin
    phase <= phase[2:0] + 3'b1;
  end
end

wire unused_cfg = (LSU_LOOKAHEAD != 0)
                || (TENSOR_IO_LOOKAHEAD != 0)
                || (TENSOR_WLD_LOOKAHEAD != 0)
                || (DMA_LOOKAHEAD != 0)
                || dma_resv_req
                || tensor_resv_req
                || (|dma_resv_mask[BANK_NUM-1:0])
                || (|tensor_resv_mask[BANK_NUM-1:0])
                || (|lsu_resv_mask[BANK_NUM-1:0])
                || (|dma_lease_channel[2:0])
                || (|dma_lease_cycles[8:0])
                || (|dma_lease_delay[3:0])
                || dma_lease_valid
                || (|lsu_lease_channel[2:0])
                || (|lsu_lease_cycles[8:0])
                || (|lsu_lease_delay[3:0])
                || lsu_lease_valid
                || (|tensor_io_lease_channel_mask[7:0])
                || (|tensor_io_lease_cycles[8:0])
                || (|tensor_io_lease_delay[3:0])
                || (|tensor_io_lease1_channel_mask[7:0])
                || (|tensor_io_lease1_cycles[8:0])
                || (|tensor_io_lease1_delay[3:0])
                || tensor_io_lease1_valid
                || (|tensor_io_lease2_channel_mask[7:0])
                || (|tensor_io_lease2_cycles[8:0])
                || (|tensor_io_lease2_delay[3:0])
                || tensor_io_lease2_valid
                || (|tensor_lease_channel[2:0])
                || (|tensor_lease_cycles[8:0])
                || (|tensor_lease_delay[3:0])
                || tensor_lease_valid
                || (|tensor_wld_lease_channel_mask[7:0])
                || (|tensor_wld_lease_cycles[8:0])
                || (|tensor_wld_lease_delay[3:0])
                || tensor_wld_lease_valid
                || FIXED_CH_WLD[0]
                || FIXED_CH_TENSOR3[0];

endmodule
