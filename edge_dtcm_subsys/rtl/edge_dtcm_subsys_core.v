module edge_dtcm_subsys_core #(
  parameter ADDR_WIDTH = 14,
  parameter DATA_WIDTH = 64,
  parameter BYTE_WIDTH = DATA_WIDTH / 8,
  parameter DMA_DATA_WIDTH = 128,
  parameter DMA_BYTE_WIDTH = DMA_DATA_WIDTH / 8,
  parameter BANK_NUM = 16,
  parameter BANK_INDEX_WIDTH = 4,
  parameter SEGMENT_NUM = 1,
  parameter SEGMENT_INDEX_WIDTH = 1,
  parameter SRAM_ADDR_WIDTH = 10,
  parameter [3:0] LSU_LOOKAHEAD = 4'd1,
  parameter [3:0] TENSOR_IO_LOOKAHEAD = 4'd2,
  parameter [3:0] TENSOR_WLD_LOOKAHEAD = 4'd2,
  parameter [3:0] DMA_LOOKAHEAD = 4'd3,
  // Standalone legacy/proxy harnesses retain inferred SRAM. The product
  // edge_dtcm_subsys boundary explicitly selects H4 by default.
  parameter SRAM_H4 = 0,
  parameter TENSOR_PACKED_WEIGHT = 1
)(
  clk,
  cpurst_b,
  cp0_lsu_dtcm_base,
  cp0_lsu_dtcm_enable,
  cp0_lsu_dtcm_mask,
  dma_axi_araddr,
  dma_axi_arlen,
  dma_axi_arready,
  dma_axi_arvalid,
  dma_axi_awaddr,
  dma_axi_awlen,
  dma_axi_awready,
  dma_axi_awvalid,
  dma_axi_bready,
  dma_axi_bvalid,
  dma_axi_rdata,
  dma_axi_rready,
  dma_axi_rlast,
  dma_axi_rvalid,
  dma_axi_wdata,
  dma_axi_wlast,
  dma_axi_wready,
  dma_axi_wstrb,
  dma_axi_wvalid,
  dma_busy,
  lsu_addr,
  lsu_rdata,
  lsu_ready,
  lsu_req,
  lsu_store_block,
  lsu_rvalid,
  lsu_we,
  lsu_wdata,
  lsu_wstrb,
  tensor_cmd_setcsr_dtype,
  tensor_cmd_setcsr_req,
  tensor_cmd_setcsr_wtype,
  tensor_cmd_setin_ptr,
  tensor_cmd_setin_req,
  tensor_cmd_setn_req,
  tensor_cmd_setn_value,
  tensor_cmd_setout_ptr,
  tensor_cmd_setout_req,
  tensor_cmd_setpsum_ptr,
  tensor_cmd_setpsum_req,
  tensor_cmd_start_req,
  tensor_cmd_start_tile_req,
  tensor_cmd_start_mode,
  tensor_cmd_start_seq_id,
  tensor_cmd_start_epoch,
  tensor_cmd_wld_ptr,
  tensor_cmd_wld_req,
  tensor_cmd_wld_trans_req,
  tensor_cmd_wld_reuse,
  tensor_cmd_sld_ptr,
  tensor_cmd_sld_req,
  tensor_cmd_sld_reuse,
  tensor_cmd_sld_stream,
  tensor_cmd_sld_stream_setup_ptr,
  tensor_cmd_sld_stream_setup_req,
  tensor_busy,
  tensor_cmd_ready,
  tensor_start_ready,
  tensor_sync_stall,
  tensor_start_retire_valid,
  tensor_start_retire_seq_id,
  tensor_start_retire_epoch,
  tensor_wld_cmd_ready,
  tensor_sld_cmd_ready,
  tensor_sld_fill_done,
  tensor_wld_fill_done,
  tensor_wld_tile_words,
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
  actu_cmd_ready,
  actu_start_ready,
  actu_sync_stall,
  actu_busy,
  actu_last_sum_bits,
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
  cmpu_cmd_ready,
  cmpu_start_ready,
  cmpu_sync_stall,
  cmpu_busy,
  cmpu_result_update,
  cmpu_max_value,
  cmpu_argmax_idx,
  cmpu_min_value,
  cmpu_argmin_idx,
  edge_dma_start_addr_dst,
  edge_dma_start_addr_src,
  edge_dma_start_len,
  edge_dma_start_req,
  dma_stream_cmd_valid,
  dma_stream_cmd_ready,
  dma_stream_cmd_axi_addr,
  dma_stream_cmd_dtcm_addr,
  dma_stream_beat_done,
  dma_stream_busy,
  edge_tensor_io_lease_channel_mask,
  edge_tensor_io_lease_cycles,
  edge_tensor_io_lease_delay,
  edge_tensor_io_lease1_channel_mask,
  edge_tensor_io_lease1_cycles,
  edge_tensor_io_lease1_delay,
  edge_tensor_io_lease1_valid,
  edge_tensor_io_lease2_channel_mask,
  edge_tensor_io_lease2_cycles,
  edge_tensor_io_lease2_delay,
  edge_tensor_io_lease2_valid,
  edge_tensor_io_lease_valid,
  edge_tensor_wld_lease_channel_mask,
  edge_tensor_wld_lease_cycles,
  edge_tensor_wld_lease_delay,
  edge_tensor_wld_lease_valid
);

input                         clk;
input                         cpurst_b;
input  [39:0]                 cp0_lsu_dtcm_base;
input                         cp0_lsu_dtcm_enable;
input  [39:0]                 cp0_lsu_dtcm_mask;
input                         dma_axi_arready;
input                         dma_axi_awready;
input                         dma_axi_bvalid;
input  [DMA_DATA_WIDTH-1:0]   dma_axi_rdata;
input                         dma_axi_rlast;
input                         dma_axi_rvalid;
input                         dma_axi_wready;
input  [ADDR_WIDTH-1:0]       lsu_addr;
input                         lsu_req;
input                         lsu_store_block;
input                         lsu_we;
input  [DATA_WIDTH-1:0]       lsu_wdata;
input  [BYTE_WIDTH-1:0]       lsu_wstrb;
input  [3:0]                  tensor_cmd_setcsr_dtype;
input                         tensor_cmd_setcsr_req;
input  [3:0]                  tensor_cmd_setcsr_wtype;
input  [15:0]                 tensor_cmd_setin_ptr;
input                         tensor_cmd_setin_req;
input                         tensor_cmd_setn_req;
input  [15:0]                 tensor_cmd_setn_value;
input  [15:0]                 tensor_cmd_setout_ptr;
input                         tensor_cmd_setout_req;
input  [15:0]                 tensor_cmd_setpsum_ptr;
input                         tensor_cmd_setpsum_req;
input                         tensor_cmd_start_req;
input                         tensor_cmd_start_tile_req;
input [7:0]                   tensor_cmd_start_mode;
input  [7:0]                  tensor_cmd_start_seq_id;
input  [3:0]                  tensor_cmd_start_epoch;
input  [15:0]                 tensor_cmd_wld_ptr;
input                         tensor_cmd_wld_req;
input                         tensor_cmd_wld_trans_req;
input                         tensor_cmd_wld_reuse;
input  [15:0]                 tensor_cmd_sld_ptr;
input                         tensor_cmd_sld_req;
input                         tensor_cmd_sld_reuse;
input                         tensor_cmd_sld_stream;
input  [15:0]                 tensor_cmd_sld_stream_setup_ptr;
input                         tensor_cmd_sld_stream_setup_req;
input  [3:0]                  actu_cmd_setcsr_dtype;
input  [3:0]                  actu_cmd_setcsr_mode;
input                         actu_cmd_setcsr_req;
input  [15:0]                 actu_cmd_setin_ptr;
input                         actu_cmd_setin_req;
input                         actu_cmd_setn_req;
input  [15:0]                 actu_cmd_setn_value;
input  [15:0]                 actu_cmd_setout_ptr;
input                         actu_cmd_setout_req;
input                         actu_cmd_setscalar_req;
input  [63:0]                 actu_cmd_setscalar_value;
input                         actu_cmd_start_req;
input                         actu_cmd_sync_req;
input  [3:0]                  cmpu_cmd_setcsr_mode;
input                         cmpu_cmd_setcsr_req;
input  [15:0]                 cmpu_cmd_setlhs_ptr;
input                         cmpu_cmd_setlhs_req;
input  [15:0]                 cmpu_cmd_setrhs_ptr;
input                         cmpu_cmd_setrhs_req;
input  [15:0]                 cmpu_cmd_setmask_ptr;
input                         cmpu_cmd_setmask_req;
input  [15:0]                 cmpu_cmd_setout_ptr;
input                         cmpu_cmd_setout_req;
input                         cmpu_cmd_setn_req;
input  [15:0]                 cmpu_cmd_setn_value;
input                         cmpu_cmd_start_req;
input                         cmpu_cmd_sync_req;
input  [39:0]                 edge_dma_start_addr_dst;
input  [39:0]                 edge_dma_start_addr_src;
input  [31:0]                 edge_dma_start_len;
input                         edge_dma_start_req;
input                         dma_stream_cmd_valid;
output                        dma_stream_cmd_ready;
input  [39:0]                 dma_stream_cmd_axi_addr;
input  [ADDR_WIDTH-1:0]       dma_stream_cmd_dtcm_addr;
output                        dma_stream_beat_done;
output                        dma_stream_busy;
output [39:0]                 dma_axi_araddr;
output [7:0]                  dma_axi_arlen;
output                        dma_axi_arvalid;
output [39:0]                 dma_axi_awaddr;
output [7:0]                  dma_axi_awlen;
output                        dma_axi_awvalid;
output                        dma_axi_bready;
output                        dma_axi_rready;
output [DMA_DATA_WIDTH-1:0]   dma_axi_wdata;
output                        dma_axi_wlast;
output [DMA_BYTE_WIDTH-1:0]   dma_axi_wstrb;
output                        dma_axi_wvalid;
output                        dma_busy;
output [DATA_WIDTH-1:0]       lsu_rdata;
output                        lsu_ready;
output                        lsu_rvalid;
output                        tensor_busy;
output                        tensor_cmd_ready;
output                        tensor_start_ready;
output                        tensor_sync_stall;
output                        tensor_start_retire_valid;
output [7:0]                  tensor_start_retire_seq_id;
output [3:0]                  tensor_start_retire_epoch;
output                        tensor_wld_cmd_ready;
output                        tensor_sld_cmd_ready;
output                        tensor_sld_fill_done;
output                        tensor_wld_fill_done;
output [4:0]                  tensor_wld_tile_words;
output                        actu_cmd_ready;
output                        actu_start_ready;
output                        actu_sync_stall;
output                        actu_busy;
output [31:0]                 actu_last_sum_bits;
output                        cmpu_cmd_ready;
output                        cmpu_start_ready;
output                        cmpu_sync_stall;
output                        cmpu_busy;
output                        cmpu_result_update;
output [15:0]                 cmpu_max_value;
output [15:0]                 cmpu_argmax_idx;
output [15:0]                 cmpu_min_value;
output [15:0]                 cmpu_argmin_idx;
output [7:0]                  edge_tensor_io_lease_channel_mask;
output [8:0]                  edge_tensor_io_lease_cycles;
output [3:0]                  edge_tensor_io_lease_delay;
output [7:0]                  edge_tensor_io_lease1_channel_mask;
output [8:0]                  edge_tensor_io_lease1_cycles;
output [3:0]                  edge_tensor_io_lease1_delay;
output                        edge_tensor_io_lease1_valid;
output [7:0]                  edge_tensor_io_lease2_channel_mask;
output [8:0]                  edge_tensor_io_lease2_cycles;
output [3:0]                  edge_tensor_io_lease2_delay;
output                        edge_tensor_io_lease2_valid;
output                        edge_tensor_io_lease_valid;
output [7:0]                  edge_tensor_wld_lease_channel_mask;
output [8:0]                  edge_tensor_wld_lease_cycles;
output [3:0]                  edge_tensor_wld_lease_delay;
output                        edge_tensor_wld_lease_valid;

wire [DMA_DATA_WIDTH-1:0]     dma_rdata;
wire                          dma_ready;
wire                          dma_rvalid;
wire [ADDR_WIDTH-1:0]         dma_dtcm_addr;
wire                          dma_dtcm_req;
wire                          dma_dtcm_we;
wire [DMA_DATA_WIDTH-1:0]     dma_dtcm_wdata;
wire [DMA_BYTE_WIDTH-1:0]     dma_dtcm_wstrb;
wire [ADDR_WIDTH-1:0]         legacy_dma_dtcm_addr;
wire                          legacy_dma_dtcm_req;
wire                          legacy_dma_dtcm_we;
wire [DMA_DATA_WIDTH-1:0]     legacy_dma_dtcm_wdata;
wire [DMA_BYTE_WIDTH-1:0]     legacy_dma_dtcm_wstrb;
wire [39:0]                   legacy_dma_axi_araddr;
wire [7:0]                    legacy_dma_axi_arlen;
wire                          legacy_dma_axi_arvalid;
wire                          legacy_dma_axi_rready;
wire                          legacy_dma_busy;
wire [ADDR_WIDTH-1:0]         stream_dma_dtcm_addr;
wire                          stream_dma_dtcm_req;
wire [DMA_DATA_WIDTH-1:0]     stream_dma_dtcm_wdata;
wire [DMA_BYTE_WIDTH-1:0]     stream_dma_dtcm_wstrb;
wire [39:0]                   stream_dma_axi_araddr;
wire [7:0]                    stream_dma_axi_arlen;
wire                          stream_dma_axi_arvalid;
wire                          stream_dma_axi_rready;
wire [2:0]                    stream_dma_lease_channel;
wire [8:0]                    stream_dma_lease_cycles;
wire [3:0]                    stream_dma_lease_delay;
wire                          stream_dma_lease_valid;
wire                          stream_select;
wire                          dma_done;
wire [2:0]                    dma_lease_channel;
wire [8:0]                    dma_lease_cycles;
wire [3:0]                    dma_lease_delay;
wire                          dma_lease_valid;
wire [2:0]                    legacy_dma_lease_channel;
wire [8:0]                    legacy_dma_lease_cycles;
wire [3:0]                    legacy_dma_lease_delay;
wire                          legacy_dma_lease_valid;
wire                          dma_start_a2d;
wire                          dma_start_d2a;
wire [39:0]                   dma_start_axi_addr;
wire [39:0]                   dma_start_dtcm_pa;
wire [39:0]                   dma_start_dtcm_offset;
wire [ADDR_WIDTH-1:0]         dma_start_dtcm_addr;
wire [BANK_NUM-1:0]           tensor_native_active_mask;
wire [BANK_NUM*SRAM_ADDR_WIDTH-1:0] tensor_native_bank_addr;
wire [BANK_NUM-1:0]           tensor_native_bank_req;
wire [BANK_NUM*DATA_WIDTH-1:0] tensor_native_bank_rdata;
wire [BANK_NUM*DATA_WIDTH-1:0] tensor_native_bank_wdata;
wire [BANK_NUM-1:0]           tensor_native_bank_we;
wire [BANK_NUM*BYTE_WIDTH-1:0] tensor_native_bank_wstrb;
wire [BANK_INDEX_WIDTH-1:0]   tensor_native_phase;
wire [BANK_NUM-1:0]           dtcm_lower_owned_mask;
wire                          actu_done_valid;
wire                          actu_dtcm_rd_req;
wire                          actu_dtcm_rd_ready;
wire [15:0]                   actu_dtcm_rd_addr;
wire                          actu_dtcm_rd_rvalid;
wire [127:0]                  actu_dtcm_rd_rdata;
wire                          actu_dtcm_wr_req;
wire                          actu_dtcm_wr_ready;
wire [15:0]                   actu_dtcm_wr_addr;
wire [127:0]                  actu_dtcm_wr_wdata;
wire [15:0]                   actu_dtcm_wr_wstrb;
wire [BANK_NUM-1:0]           actu_active_mask;
wire [BANK_NUM*SRAM_ADDR_WIDTH-1:0] actu_bank_addr;
wire [BANK_NUM-1:0]           actu_bank_req;
wire [BANK_NUM*DATA_WIDTH-1:0] actu_bank_rdata;
wire [BANK_NUM*DATA_WIDTH-1:0] actu_bank_wdata;
wire [BANK_NUM-1:0]           actu_bank_we;
wire [BANK_NUM*BYTE_WIDTH-1:0] actu_bank_wstrb;
wire [15:0]                   tensor_sld_addr;
wire                          tensor_sld_req;
wire                          tensor_sld_ready;
wire [127:0]                  tensor_sld_rdata;
wire                          tensor_sld_rvalid;
wire [15:0]                   tensor_wld_addr;
wire                          tensor_wld_req;
wire                          tensor_wld_ready;
wire [127:0]                  tensor_wld_rdata;
wire                          tensor_wld_rvalid;
function dtcm_addr_hit;
  input [39:0] pa;
begin
  dtcm_addr_hit = cp0_lsu_dtcm_enable
               && ((pa[39:0] & cp0_lsu_dtcm_mask[39:0])
                   == cp0_lsu_dtcm_base[39:0]);
end
endfunction

assign dma_start_d2a = edge_dma_start_req
                    && dtcm_addr_hit(edge_dma_start_addr_src[39:0])
                    && !dtcm_addr_hit(edge_dma_start_addr_dst[39:0]);
assign dma_start_a2d = edge_dma_start_req
                    && !dtcm_addr_hit(edge_dma_start_addr_src[39:0])
                    && dtcm_addr_hit(edge_dma_start_addr_dst[39:0]);
assign dma_start_axi_addr[39:0] =
       dma_start_d2a ? edge_dma_start_addr_dst[39:0]
                     : edge_dma_start_addr_src[39:0];
assign dma_start_dtcm_pa[39:0] =
       dma_start_d2a ? edge_dma_start_addr_src[39:0]
                     : edge_dma_start_addr_dst[39:0];
assign dma_start_dtcm_offset[39:0] =
       dma_start_dtcm_pa[39:0] - cp0_lsu_dtcm_base[39:0];
assign dma_start_dtcm_addr[ADDR_WIDTH-1:0] =
       dma_start_dtcm_offset[ADDR_WIDTH+2:3];
assign dtcm_lower_owned_mask[BANK_NUM-1:0] =
       SRAM_H4 ? ((16'h03ff << tensor_native_phase) |
                   (16'h03ff >> (16-tensor_native_phase))) :
       (tensor_native_phase[1] ? 16'hcccc : 16'h3333);
assign stream_select = dma_stream_busy_raw || dma_stream_cmd_valid;
assign dma_axi_araddr = stream_select ? stream_dma_axi_araddr :
                                          legacy_dma_axi_araddr;
assign dma_axi_arlen = stream_select ? stream_dma_axi_arlen :
                                         legacy_dma_axi_arlen;
assign dma_axi_arvalid = stream_select ? stream_dma_axi_arvalid :
                                           legacy_dma_axi_arvalid;
assign dma_axi_rready = stream_select ? stream_dma_axi_rready :
                                          legacy_dma_axi_rready;
assign dma_dtcm_addr = stream_select ? stream_dma_dtcm_addr :
                                       legacy_dma_dtcm_addr;
assign dma_dtcm_req = stream_select ? stream_dma_dtcm_req :
                                      legacy_dma_dtcm_req;
assign dma_dtcm_we = stream_select ? 1'b1 : legacy_dma_dtcm_we;
assign dma_dtcm_wdata = stream_select ? stream_dma_dtcm_wdata :
                                        legacy_dma_dtcm_wdata;
assign dma_dtcm_wstrb = stream_select ? stream_dma_dtcm_wstrb :
                                        legacy_dma_dtcm_wstrb;
assign dma_lease_channel = stream_select ? stream_dma_lease_channel :
                                           legacy_dma_lease_channel;
assign dma_lease_cycles = stream_select ? stream_dma_lease_cycles :
                                          legacy_dma_lease_cycles;
assign dma_lease_delay = stream_select ? stream_dma_lease_delay :
                                         legacy_dma_lease_delay;
assign dma_lease_valid = stream_select ? stream_dma_lease_valid :
                                         legacy_dma_lease_valid;
assign dma_busy = legacy_dma_busy || dma_stream_busy || dma_write_pending;

localparam DTCM_READ_LATENCY = SRAM_H4 ? 4 : 1;
wire memory_ready;
wire tensor_start_ready_raw;
assign tensor_start_ready = tensor_start_ready_raw && memory_ready;

// Completion includes the physical write tail, including ACTU/CMPU and DMA.
wire actu_busy_raw, actu_sync_stall_raw, actu_start_ready_raw;
wire cmpu_busy_raw, cmpu_sync_stall_raw, cmpu_start_ready_raw;
wire dma_stream_busy_raw;
reg [DTCM_READ_LATENCY-1:0] accel_write_pipe, dma_write_pipe, stream_write_pipe;
integer write_stage;
always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    accel_write_pipe <= 0;
    dma_write_pipe <= 0;
    stream_write_pipe <= 0;
  end else begin
    accel_write_pipe[0] <= actu_dtcm_wr_req && actu_dtcm_wr_ready;
    dma_write_pipe[0] <= dma_dtcm_req && dma_ready && dma_dtcm_we;
    stream_write_pipe[0] <= dma_dtcm_req && dma_ready && dma_dtcm_we && stream_select;
    for (write_stage=1; write_stage<DTCM_READ_LATENCY; write_stage=write_stage+1) begin
      accel_write_pipe[write_stage] <= accel_write_pipe[write_stage-1];
      dma_write_pipe[write_stage] <= dma_write_pipe[write_stage-1];
      stream_write_pipe[write_stage] <= stream_write_pipe[write_stage-1];
    end
  end
end
wire accel_write_pending = SRAM_H4 && (|accel_write_pipe);
wire dma_write_pending = SRAM_H4 && (|dma_write_pipe);
assign actu_busy = actu_busy_raw || accel_write_pending;
assign cmpu_busy = cmpu_busy_raw || accel_write_pending;
assign actu_sync_stall = actu_sync_stall_raw || accel_write_pending;
assign cmpu_sync_stall = cmpu_sync_stall_raw || accel_write_pending;
assign actu_start_ready = actu_start_ready_raw && memory_ready && !accel_write_pending;
assign cmpu_start_ready = cmpu_start_ready_raw && memory_ready && !accel_write_pending;
assign dma_stream_busy = dma_stream_busy_raw || (SRAM_H4 && (|stream_write_pipe));

edge_tensor_unit_bank16 #(
  .LOWER_SIX(SRAM_H4),
  .READ_LATENCY(DTCM_READ_LATENCY),
  .ADDR_WIDTH(16),
  .BANK_NUM(BANK_NUM),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .VECTOR_COUNT_WIDTH(16),
  .PACKED_WEIGHT(TENSOR_PACKED_WEIGHT)
) x_edge_tensor_unit_bank16 (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .cmd_setcsr_dtype(tensor_cmd_setcsr_dtype[3:0]),
  .cmd_setcsr_req(tensor_cmd_setcsr_req),
  .cmd_setcsr_wtype(tensor_cmd_setcsr_wtype[3:0]),
  .cmd_setin_ptr(tensor_cmd_setin_ptr[15:0]),
  .cmd_setin_req(tensor_cmd_setin_req),
  .cmd_setn_req(tensor_cmd_setn_req),
  .cmd_setn_value(tensor_cmd_setn_value[15:0]),
  .cmd_setout_ptr(tensor_cmd_setout_ptr[15:0]),
  .cmd_setout_req(tensor_cmd_setout_req),
  .cmd_setpsum_ptr(tensor_cmd_setpsum_ptr[15:0]),
  .cmd_setpsum_req(tensor_cmd_setpsum_req),
  .cmd_start_req(tensor_cmd_start_req && memory_ready),
  .cmd_start_tile_req(tensor_cmd_start_tile_req && memory_ready),
  .cmd_start_mode(tensor_cmd_start_mode),
  .cmd_start_seq_id(tensor_cmd_start_seq_id),
  .cmd_start_epoch(tensor_cmd_start_epoch),
  .cmd_wld_ptr(tensor_cmd_wld_ptr[15:0]),
  .cmd_wld_req(tensor_cmd_wld_req),
  .cmd_wld_trans_req(tensor_cmd_wld_trans_req),
  .cmd_wld_reuse(tensor_cmd_wld_reuse),
  .cmd_sld_ptr(tensor_cmd_sld_ptr[15:0]),
  .cmd_sld_req(tensor_cmd_sld_req),
  .cmd_sld_reuse(tensor_cmd_sld_reuse),
  .cmd_sld_stream(tensor_cmd_sld_stream),
  .cmd_sld_stream_setup_ptr(tensor_cmd_sld_stream_setup_ptr),
  .cmd_sld_stream_setup_req(tensor_cmd_sld_stream_setup_req),
  .tensor_busy(tensor_busy),
  .tensor_cmd_ready(tensor_cmd_ready),
  .tensor_start_ready(tensor_start_ready_raw),
  .tensor_wld_cmd_ready(tensor_wld_cmd_ready),
  .tensor_sld_cmd_ready(tensor_sld_cmd_ready),
  .tensor_sld_fill_done(tensor_sld_fill_done),
  .tensor_sld_addr(tensor_sld_addr[15:0]),
  .tensor_sld_req(tensor_sld_req),
  .tensor_sld_ready(tensor_sld_ready),
  .tensor_sld_rdata(tensor_sld_rdata[127:0]),
  .tensor_sld_rvalid(tensor_sld_rvalid),
  .tensor_wld_addr(tensor_wld_addr[15:0]),
  .tensor_wld_req(tensor_wld_req),
  .tensor_wld_ready(tensor_wld_ready),
  .tensor_wld_rdata(tensor_wld_rdata[127:0]),
  .tensor_wld_rvalid(tensor_wld_rvalid),
  .tensor_wld_fill_done(tensor_wld_fill_done),
  .tensor_wld_tile_words(tensor_wld_tile_words[4:0]),
  .tensor_sync_stall(tensor_sync_stall),
  .tensor_start_retire_valid(tensor_start_retire_valid),
  .tensor_start_retire_seq_id(tensor_start_retire_seq_id),
  .tensor_start_retire_epoch(tensor_start_retire_epoch),
  .tensor_io_lease_channel_mask(edge_tensor_io_lease_channel_mask[7:0]),
  .tensor_io_lease_cycles(edge_tensor_io_lease_cycles[8:0]),
  .tensor_io_lease_delay(edge_tensor_io_lease_delay[3:0]),
  .tensor_io_lease1_channel_mask(edge_tensor_io_lease1_channel_mask[7:0]),
  .tensor_io_lease1_cycles(edge_tensor_io_lease1_cycles[8:0]),
  .tensor_io_lease1_delay(edge_tensor_io_lease1_delay[3:0]),
  .tensor_io_lease1_valid(edge_tensor_io_lease1_valid),
  .tensor_io_lease2_channel_mask(edge_tensor_io_lease2_channel_mask[7:0]),
  .tensor_io_lease2_cycles(edge_tensor_io_lease2_cycles[8:0]),
  .tensor_io_lease2_delay(edge_tensor_io_lease2_delay[3:0]),
  .tensor_io_lease2_valid(edge_tensor_io_lease2_valid),
  .tensor_io_lease_valid(edge_tensor_io_lease_valid),
  .tensor_wld_lease_channel_mask(edge_tensor_wld_lease_channel_mask[7:0]),
  .tensor_wld_lease_cycles(edge_tensor_wld_lease_cycles[8:0]),
  .tensor_wld_lease_delay(edge_tensor_wld_lease_delay[3:0]),
  .tensor_wld_lease_valid(edge_tensor_wld_lease_valid),
  .tensor_bank_req(tensor_native_bank_req[BANK_NUM-1:0]),
  .tensor_bank_we(tensor_native_bank_we[BANK_NUM-1:0]),
  .tensor_bank_addr(tensor_native_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0]),
  .tensor_bank_wdata(tensor_native_bank_wdata[BANK_NUM*DATA_WIDTH-1:0]),
  .tensor_bank_wstrb(tensor_native_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0]),
  .tensor_bank_rdata(tensor_native_bank_rdata[BANK_NUM*DATA_WIDTH-1:0]),
  .tensor_active_mask(tensor_native_active_mask[BANK_NUM-1:0]),
  .tensor_phase(tensor_native_phase[BANK_INDEX_WIDTH-1:0])
);

edge_accel_unit #(
  .ADDR_WIDTH(16)
) x_edge_accel_unit (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .actu_cmd_setcsr_dtype(actu_cmd_setcsr_dtype[3:0]),
  .actu_cmd_setcsr_mode(actu_cmd_setcsr_mode[3:0]),
  .actu_cmd_setcsr_req(actu_cmd_setcsr_req),
  .actu_cmd_setin_ptr(actu_cmd_setin_ptr[15:0]),
  .actu_cmd_setin_req(actu_cmd_setin_req),
  .actu_cmd_setout_ptr(actu_cmd_setout_ptr[15:0]),
  .actu_cmd_setout_req(actu_cmd_setout_req),
  .actu_cmd_setn_req(actu_cmd_setn_req),
  .actu_cmd_setn_value(actu_cmd_setn_value[15:0]),
  .actu_cmd_setscalar_req(actu_cmd_setscalar_req),
  .actu_cmd_setscalar_value(actu_cmd_setscalar_value[63:0]),
  .actu_cmd_start_req(actu_cmd_start_req && memory_ready && !accel_write_pending),
  .actu_cmd_sync_req(actu_cmd_sync_req),
  .actu_cmd_ready(actu_cmd_ready),
  .actu_start_ready(actu_start_ready_raw),
  .actu_sync_stall(actu_sync_stall_raw),
  .actu_busy(actu_busy_raw),
  .actu_done_valid(actu_done_valid),
  .cmpu_cmd_setcsr_mode(cmpu_cmd_setcsr_mode),
  .cmpu_cmd_setcsr_req(cmpu_cmd_setcsr_req),
  .cmpu_cmd_setlhs_ptr(cmpu_cmd_setlhs_ptr),
  .cmpu_cmd_setlhs_req(cmpu_cmd_setlhs_req),
  .cmpu_cmd_setrhs_ptr(cmpu_cmd_setrhs_ptr),
  .cmpu_cmd_setrhs_req(cmpu_cmd_setrhs_req),
  .cmpu_cmd_setmask_ptr(cmpu_cmd_setmask_ptr),
  .cmpu_cmd_setmask_req(cmpu_cmd_setmask_req),
  .cmpu_cmd_setout_ptr(cmpu_cmd_setout_ptr),
  .cmpu_cmd_setout_req(cmpu_cmd_setout_req),
  .cmpu_cmd_setn_req(cmpu_cmd_setn_req),
  .cmpu_cmd_setn_value(cmpu_cmd_setn_value),
  .cmpu_cmd_start_req(cmpu_cmd_start_req && memory_ready && !accel_write_pending),
  .cmpu_cmd_sync_req(cmpu_cmd_sync_req),
  .cmpu_cmd_ready(cmpu_cmd_ready),
  .cmpu_start_ready(cmpu_start_ready_raw),
  .cmpu_sync_stall(cmpu_sync_stall_raw),
  .cmpu_busy(cmpu_busy_raw),
  .cmpu_done_valid(),
  .cmpu_result_update(cmpu_result_update),
  .cmpu_max_value(cmpu_max_value),
  .cmpu_argmax_idx(cmpu_argmax_idx),
  .cmpu_min_value(cmpu_min_value),
  .cmpu_argmin_idx(cmpu_argmin_idx),
  .dtcm_rd_req(actu_dtcm_rd_req),
  .dtcm_rd_ready(actu_dtcm_rd_ready),
  .dtcm_rd_addr(actu_dtcm_rd_addr[15:0]),
  .dtcm_rd_rvalid(actu_dtcm_rd_rvalid),
  .dtcm_rd_rdata(actu_dtcm_rd_rdata[127:0]),
  .dtcm_wr_req(actu_dtcm_wr_req),
  .dtcm_wr_ready(actu_dtcm_wr_ready),
  .dtcm_wr_addr(actu_dtcm_wr_addr[15:0]),
  .dtcm_wr_wdata(actu_dtcm_wr_wdata[127:0]),
  .dtcm_wr_wstrb(actu_dtcm_wr_wstrb[15:0]),
  .actu_last_sum_bits(actu_last_sum_bits)
);

edge_actu_dtcm_bank16_adapter #(
  .LOWER_SIX(SRAM_H4),
  .READ_LATENCY(DTCM_READ_LATENCY),
  .ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH(DATA_WIDTH),
  .BANK_NUM(BANK_NUM),
  .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH)
) x_edge_actu_dtcm_adapter (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .phase(tensor_native_phase[BANK_INDEX_WIDTH-1:0]),
  .lower_owned_mask(dtcm_lower_owned_mask[BANK_NUM-1:0]),
  .rd_req(actu_dtcm_rd_req && memory_ready),
  .rd_ready(actu_dtcm_rd_ready),
  .rd_addr(actu_dtcm_rd_addr[ADDR_WIDTH-1:0]),
  .rd_rvalid(actu_dtcm_rd_rvalid),
  .rd_rdata(actu_dtcm_rd_rdata[127:0]),
  .wr_req(actu_dtcm_wr_req && memory_ready),
  .wr_ready(actu_dtcm_wr_ready),
  .wr_addr(actu_dtcm_wr_addr[ADDR_WIDTH-1:0]),
  .wr_wdata(actu_dtcm_wr_wdata[127:0]),
  .wr_wstrb(actu_dtcm_wr_wstrb[15:0]),
  .bank_req(actu_bank_req[BANK_NUM-1:0]),
  .bank_we(actu_bank_we[BANK_NUM-1:0]),
  .bank_addr(actu_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0]),
  .bank_wdata(actu_bank_wdata[BANK_NUM*DATA_WIDTH-1:0]),
  .bank_wstrb(actu_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0]),
  .bank_rdata(actu_bank_rdata[BANK_NUM*DATA_WIDTH-1:0]),
  .active_mask(actu_active_mask[BANK_NUM-1:0])
);

edge_dtcm_arb #(
  .SRAM_H4(SRAM_H4),
  .ADDR_WIDTH         (ADDR_WIDTH),
  .DATA_WIDTH         (DATA_WIDTH),
  .DMA_DATA_WIDTH     (DMA_DATA_WIDTH),
  .BANK_NUM           (BANK_NUM),
  .BANK_INDEX_WIDTH   (BANK_INDEX_WIDTH),
  .SEGMENT_NUM        (SEGMENT_NUM),
  .SEGMENT_INDEX_WIDTH(SEGMENT_INDEX_WIDTH),
  .SRAM_ADDR_WIDTH    (SRAM_ADDR_WIDTH),
  .LSU_LOOKAHEAD      (LSU_LOOKAHEAD),
  .TENSOR_IO_LOOKAHEAD(TENSOR_IO_LOOKAHEAD),
  .TENSOR_WLD_LOOKAHEAD(TENSOR_WLD_LOOKAHEAD),
  .DMA_LOOKAHEAD      (DMA_LOOKAHEAD)
) x_edge_dtcm_arb (
  .memory_ready(memory_ready),
  .clk           (clk),
  .cpurst_b      (cpurst_b),
  .dma_addr      (dma_dtcm_addr[ADDR_WIDTH-1:0]),
  .dma_rdata     (dma_rdata[DMA_DATA_WIDTH-1:0]),
  .dma_ready     (dma_ready),
  .dma_req       (dma_dtcm_req),
  .dma_rvalid    (dma_rvalid),
  .dma_lease_channel(dma_lease_channel[2:0]),
  .dma_lease_cycles (dma_lease_cycles[8:0]),
  .dma_lease_delay  (dma_lease_delay[3:0]),
  .dma_lease_valid  (dma_lease_valid),
  .dma_we        (dma_dtcm_we),
  .dma_wdata     (dma_dtcm_wdata[DMA_DATA_WIDTH-1:0]),
  .dma_wstrb     (dma_dtcm_wstrb[DMA_BYTE_WIDTH-1:0]),
  .lsu_addr      (lsu_addr[ADDR_WIDTH-1:0]),
  .lsu_rdata     (lsu_rdata[DATA_WIDTH-1:0]),
  .lsu_ready     (lsu_ready),
  .lsu_req       (lsu_req),
  .lsu_store_block(lsu_store_block),
  .lsu_rvalid    (lsu_rvalid),
  .lsu_we        (lsu_we),
  .lsu_wdata     (lsu_wdata[DATA_WIDTH-1:0]),
  .lsu_wstrb     (lsu_wstrb[BYTE_WIDTH-1:0]),
  .sld_addr      (tensor_sld_addr[ADDR_WIDTH-1:0]),
  .sld_rdata     (tensor_sld_rdata[127:0]),
  .sld_ready     (tensor_sld_ready),
  .sld_req       (tensor_sld_req),
  .sld_rvalid    (tensor_sld_rvalid),
  .wld_addr      (tensor_wld_addr[ADDR_WIDTH-1:0]),
  .wld_rdata     (tensor_wld_rdata[127:0]),
  .wld_ready     (tensor_wld_ready),
  .wld_req       (tensor_wld_req),
  .wld_rvalid    (tensor_wld_rvalid),
  .tensor_native_active_mask(tensor_native_active_mask[BANK_NUM-1:0]),
  .tensor_native_bank_addr(tensor_native_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0]),
  .tensor_native_bank_req(tensor_native_bank_req[BANK_NUM-1:0]),
  .tensor_native_bank_rdata(tensor_native_bank_rdata[BANK_NUM*DATA_WIDTH-1:0]),
  .tensor_native_bank_wdata(tensor_native_bank_wdata[BANK_NUM*DATA_WIDTH-1:0]),
  .tensor_native_bank_we(tensor_native_bank_we[BANK_NUM-1:0]),
  .tensor_native_bank_wstrb(tensor_native_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0]),
  .tensor_native_phase(tensor_native_phase[BANK_INDEX_WIDTH-1:0]),
  .actu_active_mask(actu_active_mask[BANK_NUM-1:0]),
  .actu_bank_addr(actu_bank_addr[BANK_NUM*SRAM_ADDR_WIDTH-1:0]),
  .actu_bank_req(actu_bank_req[BANK_NUM-1:0]),
  .actu_bank_rdata(actu_bank_rdata[BANK_NUM*DATA_WIDTH-1:0]),
  .actu_bank_wdata(actu_bank_wdata[BANK_NUM*DATA_WIDTH-1:0]),
  .actu_bank_we(actu_bank_we[BANK_NUM-1:0]),
  .actu_bank_wstrb(actu_bank_wstrb[BANK_NUM*BYTE_WIDTH-1:0]),
  .tensor_io_lease_channel_mask(edge_tensor_io_lease_channel_mask[7:0]),
  .tensor_io_lease_cycles(edge_tensor_io_lease_cycles[8:0]),
  .tensor_io_lease_delay(edge_tensor_io_lease_delay[3:0]),
  .tensor_io_lease1_channel_mask(edge_tensor_io_lease1_channel_mask[7:0]),
  .tensor_io_lease1_cycles(edge_tensor_io_lease1_cycles[8:0]),
  .tensor_io_lease1_delay(edge_tensor_io_lease1_delay[3:0]),
  .tensor_io_lease1_valid(edge_tensor_io_lease1_valid),
  .tensor_io_lease2_channel_mask(edge_tensor_io_lease2_channel_mask[7:0]),
  .tensor_io_lease2_cycles(edge_tensor_io_lease2_cycles[8:0]),
  .tensor_io_lease2_delay(edge_tensor_io_lease2_delay[3:0]),
  .tensor_io_lease2_valid(edge_tensor_io_lease2_valid),
  .tensor_io_lease_valid(edge_tensor_io_lease_valid),
  .tensor_wld_lease_channel_mask(edge_tensor_wld_lease_channel_mask[7:0]),
  .tensor_wld_lease_cycles(edge_tensor_wld_lease_cycles[8:0]),
  .tensor_wld_lease_delay(edge_tensor_wld_lease_delay[3:0]),
  .tensor_wld_lease_valid(edge_tensor_wld_lease_valid)
);

edge_dma_a2d_stream #(
  .AXI_ADDR_WIDTH(40),
  .DTCM_ADDR_WIDTH(ADDR_WIDTH),
  .FIFO_DEPTH(16)
) x_edge_dma_a2d_stream (
  .clk(clk),
  .reset_b(cpurst_b),
  .cmd_valid(dma_stream_cmd_valid),
  .cmd_ready(dma_stream_cmd_ready),
  .cmd_axi_addr(dma_stream_cmd_axi_addr),
  .cmd_dtcm_addr(dma_stream_cmd_dtcm_addr),
  .axi_araddr(stream_dma_axi_araddr),
  .axi_arlen(stream_dma_axi_arlen),
  .axi_arvalid(stream_dma_axi_arvalid),
  .axi_arready(dma_axi_arready && stream_select),
  .axi_rdata(dma_axi_rdata),
  .axi_rvalid(dma_axi_rvalid && stream_select),
  .axi_rready(stream_dma_axi_rready),
  .dtcm_req(stream_dma_dtcm_req),
  .dtcm_addr(stream_dma_dtcm_addr),
  .dtcm_wdata(stream_dma_dtcm_wdata),
  .dtcm_wstrb(stream_dma_dtcm_wstrb),
  .dtcm_ready(dma_ready && stream_select),
  .beat_done(dma_stream_beat_done),
  .busy(dma_stream_busy_raw),
  .lease_channel(stream_dma_lease_channel),
  .lease_cycles(stream_dma_lease_cycles),
  .lease_delay(stream_dma_lease_delay),
  .lease_valid(stream_dma_lease_valid),
  .outstanding_count(),
  .buffered_count()
);

edge_dtcm_dma #(
  .AXI_ADDR_WIDTH (40),
  .DTCM_ADDR_WIDTH(ADDR_WIDTH),
  .DATA_WIDTH     (DMA_DATA_WIDTH),
  .BURST_MAX_BEATS(4),
  .DMA_LEASE_DELAY(DMA_LOOKAHEAD)
) x_edge_dtcm_dma (
  .axi_araddr       (legacy_dma_axi_araddr[39:0]),
  .axi_arlen        (legacy_dma_axi_arlen[7:0]),
  .axi_arready      (dma_axi_arready && !stream_select),
  .axi_arvalid      (legacy_dma_axi_arvalid),
  .axi_awaddr       (dma_axi_awaddr[39:0]),
  .axi_awlen        (dma_axi_awlen[7:0]),
  .axi_awready      (dma_axi_awready),
  .axi_awvalid      (dma_axi_awvalid),
  .axi_bready       (dma_axi_bready),
  .axi_bvalid       (dma_axi_bvalid),
  .axi_rdata        (dma_axi_rdata[DMA_DATA_WIDTH-1:0]),
  .axi_rready       (legacy_dma_axi_rready),
  .axi_rlast        (dma_axi_rlast),
  .axi_rvalid       (dma_axi_rvalid && !stream_select),
  .axi_wdata        (dma_axi_wdata[DMA_DATA_WIDTH-1:0]),
  .axi_wlast        (dma_axi_wlast),
  .axi_wready       (dma_axi_wready),
  .axi_wstrb        (dma_axi_wstrb[DMA_BYTE_WIDTH-1:0]),
  .axi_wvalid       (dma_axi_wvalid),
  .clk              (clk),
  .cpurst_b         (cpurst_b),
  .dma_busy         (legacy_dma_busy),
  .dma_done         (dma_done),
  .dma_dtcm_addr    (legacy_dma_dtcm_addr[ADDR_WIDTH-1:0]),
  .dma_dtcm_rdata   (dma_rdata[DMA_DATA_WIDTH-1:0]),
  .dma_dtcm_ready   (dma_ready && !stream_select),
  .dma_dtcm_req     (legacy_dma_dtcm_req),
  .dma_dtcm_rvalid  (dma_rvalid),
  .dma_dtcm_we      (legacy_dma_dtcm_we),
  .dma_dtcm_wdata   (legacy_dma_dtcm_wdata[DMA_DATA_WIDTH-1:0]),
  .dma_dtcm_wstrb   (legacy_dma_dtcm_wstrb[DMA_BYTE_WIDTH-1:0]),
  .dma_lease_channel(legacy_dma_lease_channel[2:0]),
  .dma_lease_cycles (legacy_dma_lease_cycles[8:0]),
  .dma_lease_delay  (legacy_dma_lease_delay[3:0]),
  .dma_lease_valid  (legacy_dma_lease_valid),
  .start            ((dma_start_a2d || dma_start_d2a) && !legacy_dma_busy &&
                     !stream_select),
  .start_axi_addr   (dma_start_axi_addr[39:0]),
  .start_dir        (dma_start_d2a),
  .start_dtcm_addr  (dma_start_dtcm_addr[ADDR_WIDTH-1:0]),
  .start_len        (edge_dma_start_len[31:0])
);

endmodule
