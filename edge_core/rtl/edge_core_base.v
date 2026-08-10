`timescale 1ns/1ps
module edge_core_base #(
  parameter PC_WIDTH = 40,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter VALUE_WIDTH = 64,
  parameter PRODUCER_TAG_WIDTH = 16,
  parameter PSEUDO_WIDTH = 3,
  parameter AXI_DATA_WIDTH = 128,
  parameter AXI_ID_WIDTH = 8,
  parameter AXI_LEN_WIDTH = 8,
  parameter ENABLE_ICACHE_REFILL = 1,
  parameter ICACHE_BYTES = 16384,
  parameter DCACHE_BYTES = 16384,
  parameter ENABLE_EARLY_LOAD_RETIRE = 0
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,
  input  wire                       core_start,
  input  wire                       core_force_stop,
  input  wire [PC_WIDTH-1:0]        boot_pc,

  output wire                       imem_req_valid,
  input  wire                       imem_req_ready,
  output wire [PC_WIDTH-1:0]        imem_req_addr,
  input  wire                       imem_resp_valid,
  output wire                       imem_resp_ready,
  input  wire [127:0]               imem_resp_bits,

  input  wire [PC_WIDTH-1:0]        mem_region_base,
  input  wire [PC_WIDTH-1:0]        mem_region_mask,
  input  wire                       mem_region_enable,
  input  wire [PC_WIDTH-1:0]        edge_dma_start_addr_src,
  input  wire [PC_WIDTH-1:0]        edge_dma_start_addr_dst,
  input  wire [31:0]                edge_dma_start_len,
  input  wire                       edge_dma_start_req,
  output wire                       edge_dma_busy,

  input  wire [PC_WIDTH-1:0]        bringup_core_araddr,
  input  wire [1:0]                 bringup_core_arburst,
  input  wire [3:0]                 bringup_core_arcache,
  input  wire [AXI_ID_WIDTH-1:0]    bringup_core_arid,
  input  wire [AXI_LEN_WIDTH-1:0]   bringup_core_arlen,
  input  wire                       bringup_core_arlock,
  input  wire [2:0]                 bringup_core_arprot,
  input  wire [2:0]                 bringup_core_arsize,
  input  wire                       bringup_core_arvalid,
  output wire                       bringup_core_arready,
  output wire [AXI_DATA_WIDTH-1:0]  bringup_core_rdata,
  output wire [AXI_ID_WIDTH-1:0]    bringup_core_rid,
  output wire                       bringup_core_rlast,
  input  wire                       bringup_core_rready,
  output wire [1:0]                 bringup_core_rresp,
  output wire                       bringup_core_rvalid,

  input  wire [PC_WIDTH-1:0]        bringup_core_awaddr,
  input  wire [1:0]                 bringup_core_awburst,
  input  wire [3:0]                 bringup_core_awcache,
  input  wire [AXI_ID_WIDTH-1:0]    bringup_core_awid,
  input  wire [AXI_LEN_WIDTH-1:0]   bringup_core_awlen,
  input  wire                       bringup_core_awlock,
  input  wire [2:0]                 bringup_core_awprot,
  input  wire [2:0]                 bringup_core_awsize,
  input  wire                       bringup_core_awvalid,
  output wire                       bringup_core_awready,
  output wire [AXI_ID_WIDTH-1:0]    bringup_core_bid,
  input  wire                       bringup_core_bready,
  output wire [1:0]                 bringup_core_bresp,
  output wire                       bringup_core_bvalid,
  input  wire [AXI_DATA_WIDTH-1:0]  bringup_core_wdata,
  input  wire                       bringup_core_wlast,
  output wire                       bringup_core_wready,
  input  wire [(AXI_DATA_WIDTH/8)-1:0] bringup_core_wstrb,
  input  wire                       bringup_core_wvalid,

  input  wire [PC_WIDTH-1:0]        bringup_dma_araddr,
  input  wire [1:0]                 bringup_dma_arburst,
  input  wire [3:0]                 bringup_dma_arcache,
  input  wire [AXI_ID_WIDTH-1:0]    bringup_dma_arid,
  input  wire [AXI_LEN_WIDTH-1:0]   bringup_dma_arlen,
  input  wire                       bringup_dma_arlock,
  input  wire [2:0]                 bringup_dma_arprot,
  input  wire [2:0]                 bringup_dma_arsize,
  input  wire                       bringup_dma_arvalid,
  output wire                       bringup_dma_arready,
  output wire [AXI_DATA_WIDTH-1:0]  bringup_dma_rdata,
  output wire [AXI_ID_WIDTH-1:0]    bringup_dma_rid,
  output wire                       bringup_dma_rlast,
  input  wire                       bringup_dma_rready,
  output wire [1:0]                 bringup_dma_rresp,
  output wire                       bringup_dma_rvalid,

  input  wire [PC_WIDTH-1:0]        bringup_dma_awaddr,
  input  wire [1:0]                 bringup_dma_awburst,
  input  wire [3:0]                 bringup_dma_awcache,
  input  wire [AXI_ID_WIDTH-1:0]    bringup_dma_awid,
  input  wire [AXI_LEN_WIDTH-1:0]   bringup_dma_awlen,
  input  wire                       bringup_dma_awlock,
  input  wire [2:0]                 bringup_dma_awprot,
  input  wire [2:0]                 bringup_dma_awsize,
  input  wire                       bringup_dma_awvalid,
  output wire                       bringup_dma_awready,
  output wire [AXI_ID_WIDTH-1:0]    bringup_dma_bid,
  input  wire                       bringup_dma_bready,
  output wire [1:0]                 bringup_dma_bresp,
  output wire                       bringup_dma_bvalid,
  input  wire [AXI_DATA_WIDTH-1:0]  bringup_dma_wdata,
  input  wire                       bringup_dma_wlast,
  output wire                       bringup_dma_wready,
  input  wire [(AXI_DATA_WIDTH/8)-1:0] bringup_dma_wstrb,
  input  wire                       bringup_dma_wvalid,

  output wire [PC_WIDTH-1:0]        biu_pad_araddr,
  output wire [1:0]                 biu_pad_arburst,
  output wire [3:0]                 biu_pad_arcache,
  output wire [AXI_ID_WIDTH-1:0]    biu_pad_arid,
  output wire [AXI_LEN_WIDTH-1:0]   biu_pad_arlen,
  output wire                       biu_pad_arlock,
  output wire [2:0]                 biu_pad_arprot,
  output wire [2:0]                 biu_pad_arsize,
  output wire                       biu_pad_arvalid,
  input  wire                       pad_biu_arready,
  input  wire [AXI_DATA_WIDTH-1:0]  pad_biu_rdata,
  input  wire [AXI_ID_WIDTH-1:0]    pad_biu_rid,
  input  wire                       pad_biu_rlast,
  input  wire [1:0]                 pad_biu_rresp,
  input  wire                       pad_biu_rvalid,
  output wire                       biu_pad_rready,

  output wire [PC_WIDTH-1:0]        biu_pad_awaddr,
  output wire [1:0]                 biu_pad_awburst,
  output wire [3:0]                 biu_pad_awcache,
  output wire [AXI_ID_WIDTH-1:0]    biu_pad_awid,
  output wire [AXI_LEN_WIDTH-1:0]   biu_pad_awlen,
  output wire                       biu_pad_awlock,
  output wire [2:0]                 biu_pad_awprot,
  output wire [2:0]                 biu_pad_awsize,
  output wire                       biu_pad_awvalid,
  input  wire                       pad_biu_awready,
  input  wire [AXI_ID_WIDTH-1:0]    pad_biu_bid,
  input  wire [1:0]                 pad_biu_bresp,
  input  wire                       pad_biu_bvalid,
  output wire                       biu_pad_bready,
  output wire [AXI_DATA_WIDTH-1:0]  biu_pad_wdata,
  output wire                       biu_pad_wlast,
  output wire [(AXI_DATA_WIDTH/8)-1:0] biu_pad_wstrb,
  output wire                       biu_pad_wvalid,
  input  wire                       pad_biu_wready,

  input  wire                       dcache_backend_load_pause,
  input  wire                       dcache_backend_store_pause,

  output wire                       core_halted,
  output wire                       scalar_ebreak_valid,
  output wire [SEQ_ID_WIDTH-1:0]    scalar_ebreak_seq_id,
  output wire [EPOCH_WIDTH-1:0]     scalar_ebreak_epoch,
  output wire                       scalar_csr_break_valid,
  output wire [VALUE_WIDTH-1:0]     scalar_csr_break_code,
  output wire [SEQ_ID_WIDTH-1:0]    scalar_csr_break_seq_id,
  output wire [EPOCH_WIDTH-1:0]     scalar_csr_break_epoch
  ,output wire                       scalar_csr_putchar_valid
  ,output wire [7:0]                 scalar_csr_putchar_char

`ifdef EDGE_DEBUG
  ,

  output wire                       retire0_valid,
  output wire [SEQ_ID_WIDTH-1:0]    retire0_seq_id,
  output wire [EPOCH_WIDTH-1:0]     retire0_epoch,
  output wire [1:0]                 retire0_kind,
  output wire                       retire1_valid,
  output wire [SEQ_ID_WIDTH-1:0]    retire1_seq_id,
  output wire [EPOCH_WIDTH-1:0]     retire1_epoch,
  output wire [1:0]                 retire1_kind,

  output wire                       scalar_fatal_valid,
  output wire [3:0]                 scalar_fatal_code,
  output wire [VALUE_WIDTH-1:0]     scalar_fatal_inst,
  output wire [SEQ_ID_WIDTH-1:0]    scalar_fatal_seq_id,
  output wire [EPOCH_WIDTH-1:0]     scalar_fatal_epoch,

  output wire [31:0]                debug_gpr_busy,
  output wire [31:0]                debug_fpr_busy,
  output wire [31:0]                debug_retire_count,
  output wire [31:0]                debug_icache_bytes,
  output wire [31:0]                debug_dcache_bytes,
  output wire                       debug_token0_valid,
  output wire [1:0]                 debug_token0_kind,
  output wire                       debug_dcache_load_pending,
  output wire                       debug_dcache_store_fire,
  output wire                       debug_dcache_cache_op_fire,
  output wire [1:0]                 debug_dcache_cache_op_kind,
  output wire                       debug_dcache_cache_op_is_va,
  output wire                       debug_biu_read_owner_valid,
  output wire                       debug_biu_read_owner_dma,
  output wire                       debug_biu_write_owner_valid,
  output wire                       debug_biu_write_owner_dma
`endif
);

  function seq_is_younger;
    input [SEQ_ID_WIDTH-1:0] candidate;
    input [SEQ_ID_WIDTH-1:0] boundary;
    reg [SEQ_ID_WIDTH-1:0] distance;
    begin
      distance = candidate - boundary;
      seq_is_younger = (distance != {SEQ_ID_WIDTH{1'b0}}) &&
                       !distance[SEQ_ID_WIDTH-1];
    end
  endfunction

`ifndef EDGE_DEBUG
  wire                       retire0_valid;
  wire [SEQ_ID_WIDTH-1:0]    retire0_seq_id;
  wire [EPOCH_WIDTH-1:0]     retire0_epoch;
  wire [1:0]                 retire0_kind;
  wire                       retire1_valid;
  wire [SEQ_ID_WIDTH-1:0]    retire1_seq_id;
  wire [EPOCH_WIDTH-1:0]     retire1_epoch;
  wire [1:0]                 retire1_kind;
  wire                       scalar_fatal_valid;
  wire [3:0]                 scalar_fatal_code;
  wire [VALUE_WIDTH-1:0]     scalar_fatal_inst;
  wire [SEQ_ID_WIDTH-1:0]    scalar_fatal_seq_id;
  wire [EPOCH_WIDTH-1:0]     scalar_fatal_epoch;
  wire [31:0]                debug_fpr_busy;
  wire [31:0]                debug_retire_count;
  wire [31:0]                debug_icache_bytes;
  wire [31:0]                debug_dcache_bytes;
  wire                       debug_dcache_load_pending;
  wire                       debug_dcache_store_fire;
  wire                       debug_dcache_cache_op_fire;
  wire [1:0]                 debug_dcache_cache_op_kind;
  wire                       debug_dcache_cache_op_is_va;
  wire                       debug_biu_read_owner_valid;
  wire                       debug_biu_read_owner_dma;
  wire                       debug_biu_write_owner_valid;
  wire                       debug_biu_write_owner_dma;
`endif

  wire [31:0]                gpr_busy_status;

  localparam [1:0] TOKEN_KIND_SCALAR = 2'd0;
  localparam [1:0] TOKEN_KIND_TENSOR = 2'd2;
  localparam [6:0] TENSOR_SETCSR = 7'h10;
  localparam [6:0] TENSOR_WLD = 7'h11;
  localparam [6:0] TENSOR_SETIN = 7'h12;
  localparam [6:0] TENSOR_SETOUT = 7'h13;
  localparam [6:0] TENSOR_SETPSUM = 7'h14;
  localparam [6:0] TENSOR_SETN = 7'h17;
  localparam [6:0] ACTU_START = 7'h25;
  localparam [6:0] ACTU_SYNC = 7'h26;
  localparam [6:0] CMPU_START = 7'h2d;
  localparam [6:0] CMPU_SYNC = 7'h2e;
  localparam [6:0] TENSOR_WLD_T = 7'h18;
  localparam [6:0] DMA_START = 7'h01;
  localparam CAPTURE_SLOTS = 8;
  localparam CAPTURE_ID_WIDTH = 3;
  localparam REF_COUNT_WIDTH = 4;
  localparam CONSUME_PORTS = 2;
  localparam [11:0] EDGE_CSR_BREAK_ID = 12'h7e0;
  localparam [11:0] EDGE_CSR_PUTCHAR_ID = 12'h7e1;
  localparam [11:0] EDGE_CSR_DTCM_BASE_ID = 12'h7d8;
  localparam [11:0] EDGE_CSR_DTCM_MASK_ID = 12'h7d9;
  localparam [11:0] EDGE_CSR_DTCM_CTRL_ID = 12'h7da;

  reg [PC_WIDTH-1:0] mem_region_base_q;
  reg [PC_WIDTH-1:0] mem_region_mask_q;
  reg                mem_region_enable_q;

  wire                    ifu_redirect_valid;
  wire [PC_WIDTH-1:0]     ifu_redirect_pc;
  wire [EPOCH_WIDTH-1:0]  ifu_redirect_epoch;
  wire                    redirect_flush_valid;
  wire [SEQ_ID_WIDTH-1:0] redirect_kill_seq_id;
  wire [EPOCH_WIDTH-1:0]  redirect_kill_epoch;
  wire [EPOCH_WIDTH-1:0]  redirect_new_epoch;
  reg                     backend_redirect_kill_valid_q;
  reg [SEQ_ID_WIDTH-1:0]  backend_redirect_kill_seq_id_q;
  reg [EPOCH_WIDTH-1:0]   backend_redirect_kill_epoch_q;

  wire                    fetch_valid;
  wire                    fetch_ready;
  wire [PC_WIDTH-1:0]     fetch_block_pc;
  wire                    fetch_first_word;
  wire [63:0]             fetch_bits;
  wire [EPOCH_WIDTH-1:0]  fetch_epoch;
  wire                    ifu_fetch_valid;
  wire                    ifu_fetch_ready;
  wire [PC_WIDTH-1:0]     ifu_fetch_block_pc;
  wire [1:0]              ifu_fetch_start_word;
  wire [127:0]            ifu_fetch_bits;
  wire [EPOCH_WIDTH-1:0]  ifu_fetch_epoch;
  wire                    ifu_cache_req_valid;
  wire                    ifu_cache_req_ready;
  wire [PC_WIDTH-1:0]     ifu_cache_req_addr;
  wire                    ifu_cache_resp_valid;
  wire                    ifu_cache_resp_ready;
  wire [127:0]            ifu_cache_resp_bits;
  wire                    icache_refill_req_valid;
  wire                    icache_refill_req_ready;
  wire [PC_WIDTH-1:0]     icache_refill_req_addr;
  wire                    icache_refill_resp_valid;
  wire                    icache_refill_resp_ready;
  wire [127:0]            icache_refill_resp_bits;
  wire                    ifu_cache_debug_hit;
  wire                    ifu_cache_debug_miss_pending;
  wire [31:0]             dcache_debug_icache_bytes_unused;

  wire                    token0_valid;
  wire [1:0]              token0_kind;
  wire [31:0]             token0_inst32;

  wire                    frontend_scalar_valid;
  wire                    scalar_ready;
  wire                    frontend_scalar1_valid;
  wire                    pipe_issue1_ready;
  wire                    shim_issue_valid;
  wire [PC_WIDTH-1:0]     shim_issue_pc;
  wire [31:0]             shim_issue_inst;
  wire                    shim_issue_len;
  wire                    shim_issue_is_pseudo;
  wire [PSEUDO_WIDTH-1:0] shim_issue_pseudo_kind;
  wire [SEQ_ID_WIDTH-1:0] shim_issue_seq_id;
  wire [EPOCH_WIDTH-1:0]  shim_issue_epoch;
  wire                    shim_scalar_def_valid;
  wire                    shim_scalar_def_domain;
  wire [REG_INDEX_WIDTH-1:0] shim_scalar_def_dst_reg;
  wire [SEQ_ID_WIDTH-1:0] shim_scalar_def_seq_id;
  wire [EPOCH_WIDTH-1:0]  shim_scalar_def_epoch;
  wire                    shim_decode_illegal;
  wire                    frontend_scalar1_def_valid;
  wire [REG_INDEX_WIDTH-1:0] frontend_scalar1_def_dst_reg;
  wire                    frontend_scalar1_def_bank;

  wire [PC_WIDTH-1:0]     pre_scalar_pc;
  wire [31:0]             pre_scalar_inst;
  wire [SEQ_ID_WIDTH-1:0] pre_scalar_seq_id;
  wire [EPOCH_WIDTH-1:0]  pre_scalar_epoch;
  wire                    pre_scalar_is_pseudo;
  wire [PSEUDO_WIDTH-1:0] pre_scalar_pseudo_kind;
  wire                    pre_scalar_def_valid;
  wire                    pre_scalar_def_domain;
  wire [REG_INDEX_WIDTH-1:0] pre_scalar_def_dst_reg;
  wire                    pre_scalar_def_bank;
  wire [PC_WIDTH-1:0]     pre_scalar1_pc;
  wire [31:0]             pre_scalar1_inst;
  wire [SEQ_ID_WIDTH-1:0] pre_scalar1_seq_id;
  wire [EPOCH_WIDTH-1:0]  pre_scalar1_epoch;
  wire                    pre_scalar1_is_pseudo;
  wire [PSEUDO_WIDTH-1:0] pre_scalar1_pseudo_kind;
  wire                    pre_scalar1_def_valid;
  wire [REG_INDEX_WIDTH-1:0] pre_scalar1_def_dst_reg;
  wire                    pre_scalar1_def_bank;
  wire                    tensor_command_valid;
  wire                    tensor_command_is_tensor;
  wire [63:0]             tensor_command_inst64;
  wire [SEQ_ID_WIDTH-1:0] tensor_command_seq_id;
  wire [EPOCH_WIDTH-1:0]  tensor_command_epoch;
  wire [2:0]              tensor_command_capture_count;
  wire                    tensor_command_n_capture_valid;
  wire [CAPTURE_ID_WIDTH-1:0] tensor_command_n_capture_id;
  wire                    tensor_command_n_capture_bank;
  wire [PRODUCER_TAG_WIDTH-1:0] tensor_command_n_producer_tag;
  wire [REG_INDEX_WIDTH-1:0] tensor_command_n_src_gpr;
  wire                    tensor_command_base_capture_valid;
  wire [CAPTURE_ID_WIDTH-1:0] tensor_command_base_capture_id;
  wire                    tensor_command_base_capture_bank;
  wire [PRODUCER_TAG_WIDTH-1:0] tensor_command_base_producer_tag;
  wire [REG_INDEX_WIDTH-1:0] tensor_command_base_src_gpr;
  wire                    tensor_command_queue_valid;
  wire                    tensor_command_accept;
  wire                    tensor_cmd_queue_cmd_ready;
  wire [6:0]              tensor_command_subop;
  wire [6:0]              accel_pipe_done_subop;
  wire                    tensor_command_is_dma_start;
  wire                    tensor_command_is_dma_start_circular;
  wire                    tensor_command_is_dma_sync;
  wire                    tensor_command_is_start;
  wire                    tensor_command_is_wld;
  wire                    tensor_command_is_wld_circular;
  wire                    tensor_command_is_sync;
  reg                     tensor_sync_issue_fence_q;
  reg [SEQ_ID_WIDTH-1:0]  tensor_sync_issue_fence_seq_q;
  reg [EPOCH_WIDTH-1:0]   tensor_sync_issue_fence_epoch_q;
  wire                    tensor_sync_done_valid;

  wire                    scalar_producer_valid;
  wire                    scalar_producer_domain;
  wire [REG_INDEX_WIDTH-1:0] scalar_producer_reg;
  wire                    scalar_producer_bank;
  wire [PRODUCER_TAG_WIDTH-1:0] scalar_producer_tag;
  wire [VALUE_WIDTH-1:0]  scalar_producer_value;
  wire [EPOCH_WIDTH-1:0]  scalar_producer_epoch;
  wire                    tensor_gpr_snapshot_valid;
  wire [SEQ_ID_WIDTH-1:0] tensor_gpr_snapshot_seq_id;
  wire [EPOCH_WIDTH-1:0]  tensor_gpr_snapshot_epoch;
  wire [2:0]              tensor_gpr_snapshot_target;
  wire                    tensor_gpr_snapshot_operand_valid;
  wire [VALUE_WIDTH-1:0]  tensor_gpr_snapshot_operand_value;
  wire                    reverse_snapshot_alloc_valid;
  wire                    reverse_snapshot_alloc_ready;
  wire                    reverse_snapshot_alloc_id;
  wire [SEQ_ID_WIDTH-1:0] reverse_snapshot_alloc_seq_id;
  wire [EPOCH_WIDTH-1:0]  reverse_snapshot_alloc_epoch;
  wire                    reverse_snapshot_write_valid;
  wire                    reverse_snapshot_write_ready;
  wire                    reverse_snapshot_write_id;
  wire [VALUE_WIDTH-1:0]  reverse_snapshot_write_value;
  wire                    reverse_snapshot_read_ready;
  wire [VALUE_WIDTH-1:0]  reverse_snapshot_read_value;
  wire                    reverse_snapshot_read_id;
  wire                    reverse_snapshot_consume_valid;
  wire                    reverse_snapshot_consume_id;

  wire                    tensor_issue_valid;
  wire                    tensor_issue_ready;
  wire                    tensor_cmd_queue_issue_ready;
  wire [6:0]              tensor_issue_subop;
  wire                    tensor_issue_uses_dtcm;
  wire                    tensor_issue_store_order_ready;
  wire                    scalar_lsu_dtcm_store_pending;
  wire                    accel_pipe_cmd_valid;
  wire [3:0]              tensor_cmd_queue_count;
  // Reconstructed only for existing hierarchical harness observation. The
  // production queue-to-pipe control path uses opcode8/imm8 below.
  wire [63:0]             tensor_issue_inst64;
  wire [7:0]              tensor_issue_opcode8;
  wire [7:0]              tensor_issue_imm8;
  wire [SEQ_ID_WIDTH-1:0] tensor_issue_seq_id;
  wire [EPOCH_WIDTH-1:0]  tensor_issue_epoch;
  wire                    tensor_issue_n_valid;
  wire [VALUE_WIDTH-1:0]  tensor_issue_n_value;
  // Compatibility-only hierarchical debug signals. Accelerator commands now
  // carry one snapshot operand, so no base payload is stored in the queue.
  wire                    tensor_issue_base_valid;
  wire [VALUE_WIDTH-1:0]  tensor_issue_base_value;
  wire                    accel_pipe_done_valid;
  wire [SEQ_ID_WIDTH-1:0] accel_pipe_done_seq_id;
  wire [EPOCH_WIDTH-1:0]  accel_pipe_done_epoch;
  wire                    tensor_start_retire_valid;
  wire [SEQ_ID_WIDTH-1:0] tensor_start_retire_seq_id;
  wire [EPOCH_WIDTH-1:0]  tensor_start_retire_epoch;
  wire                    tensor_dma_start_req;
  wire                    tensor_dma_start_circular_req;
  wire [VALUE_WIDTH-1:0]  tensor_dma_start_src;
  wire [VALUE_WIDTH-1:0]  tensor_dma_start_dst;
  wire [31:0]             tensor_dma_start_len;
  wire [31:0]             tensor_dma_start_entry_bytes;
  wire [15:0]             tensor_dma_start_circular_tiles;
  wire                    tensor_dma_start_use_xy;
  wire                    tensor_dma_start_circular;
  wire [63:0]             tensor_dma_start_x;
  wire [63:0]             tensor_dma_start_y;
  wire                    tensor_dma_sync_req;
  wire [3:0]              tensor_cmd_setcsr_dtype;
  wire                    tensor_cmd_setcsr_req;
  wire [3:0]              tensor_cmd_setcsr_wtype;
  wire [15:0]             tensor_cmd_setin_ptr;
  wire                    tensor_cmd_setin_req;
  wire                    tensor_cmd_setn_req;
  wire [15:0]             tensor_cmd_setn_value;
  wire [15:0]             tensor_cmd_setout_ptr;
  wire                    tensor_cmd_setout_req;
  wire [15:0]             tensor_cmd_setpsum_ptr;
  wire                    tensor_cmd_setpsum_req;
  wire                    tensor_cmd_start_req;
  wire                    tensor_cmd_start_tile_req;
  wire [7:0]              tensor_cmd_start_mode;
  wire                    tensor_cmd_sync_req;
  wire [15:0]             tensor_cmd_wld_ptr;
  wire                    tensor_cmd_wld_req;
  wire                    tensor_cmd_wld_circular_req;
  wire                    tensor_cmd_wld_trans_req;
  wire                    tensor_cmd_wld_reuse;
  wire [15:0]             tensor_cmd_sld_ptr;
  wire                    tensor_cmd_sld_req;
  wire                    tensor_cmd_sld_reuse;
  wire [15:0]             tensor_cmd_sld_stream_ptr;
  wire                    tensor_cmd_sld_stream_req;
  wire                    tensor_sld_cmd_ready;
  wire                    tensor_sld_unit_cmd_ready;
  wire                    tensor_sld_fill_done;
  wire                    tensor_cmd_wsld_circular_req;
  wire                    tensor_cmd_wsld_circular_transpose;
  wire                    tensor_cmd_sld_circular_req;
  wire [3:0]              actu_cmd_setcsr_dtype;
  wire [3:0]              actu_cmd_setcsr_mode;
  wire                    actu_cmd_setcsr_req;
  wire [15:0]             actu_cmd_setin_ptr;
  wire                    actu_cmd_setin_req;
  wire                    actu_cmd_setn_req;
  wire [15:0]             actu_cmd_setn_value;
  wire [15:0]             actu_cmd_setout_ptr;
  wire                    actu_cmd_setout_req;
  wire                    actu_cmd_setscalar_req;
  wire [63:0]             actu_cmd_setscalar_value;
  wire                    actu_cmd_start_req;
  wire                    actu_cmd_sync_req;
  wire                    actu_cmd_ready;
  wire                    actu_start_ready;
  wire                    actu_sync_stall;
  wire                    actu_busy;
  wire [31:0]             actu_last_sum_bits;
  wire [3:0]              cmpu_cmd_setcsr_mode;
  wire                    cmpu_cmd_setcsr_req;
  wire [15:0]             cmpu_cmd_setlhs_ptr;
  wire                    cmpu_cmd_setlhs_req;
  wire [15:0]             cmpu_cmd_setrhs_ptr;
  wire                    cmpu_cmd_setrhs_req;
  wire [15:0]             cmpu_cmd_setmask_ptr;
  wire                    cmpu_cmd_setmask_req;
  wire [15:0]             cmpu_cmd_setout_ptr;
  wire                    cmpu_cmd_setout_req;
  wire                    cmpu_cmd_setn_req;
  wire [15:0]             cmpu_cmd_setn_value;
  wire                    cmpu_cmd_start_req;
  wire                    cmpu_cmd_sync_req;
  wire                    cmpu_cmd_ready;
  wire                    cmpu_start_ready;
  wire                    cmpu_sync_stall;
  wire                    cmpu_busy;
  wire                    cmpu_result_update;
  wire [15:0]             cmpu_max_value;
  wire [15:0]             cmpu_argmax_idx;
  wire [15:0]             cmpu_min_value;
  wire [15:0]             cmpu_argmin_idx;
  wire                    tensor_wsld_circular_ready;
  wire                    tensor_sld_circular_ready;
  wire [15:0]             tensor_unit_cmd_wld_ptr;
  wire                    tensor_unit_cmd_wld_req;
  wire                    tensor_unit_cmd_wld_trans_req;
  wire                    tensor_unit_cmd_wld_reuse;
  wire [15:0]             tensor_unit_cmd_sld_ptr;
  wire                    tensor_unit_cmd_sld_req;
  wire                    tensor_unit_cmd_sld_reuse;
  wire                    tensor_unit_cmd_sld_stream;
  wire                    tensor_cmd_ready;
  wire                    tensor_start_ready;
  wire                    tensor_wld_cmd_ready;
  wire                    tensor_wld_unit_cmd_ready;
  wire                    tensor_wld_circular_ready;
  wire                    tensor_wld_fill_done;
  wire [4:0]              tensor_wld_tile_words;
  wire                    tensor_sync_stall;
  wire                    tensor_unit_sync_stall;
  wire                    tensor_busy;
  wire [7:0]              tensor_io_lease_channel_mask;
  wire [8:0]              tensor_io_lease_cycles;
  wire [3:0]              tensor_io_lease_delay;
  wire [7:0]              tensor_io_lease1_channel_mask;
  wire [8:0]              tensor_io_lease1_cycles;
  wire [3:0]              tensor_io_lease1_delay;
  wire                    tensor_io_lease1_valid;
  wire [7:0]              tensor_io_lease2_channel_mask;
  wire [8:0]              tensor_io_lease2_cycles;
  wire [3:0]              tensor_io_lease2_delay;
  wire                    tensor_io_lease2_valid;
  wire                    tensor_io_lease_valid;
  wire [7:0]              tensor_wld_lease_channel_mask;
  wire [8:0]              tensor_wld_lease_cycles;
  wire [3:0]              tensor_wld_lease_delay;
  wire                    tensor_wld_lease_valid;
  wire [127:0]            tensor_wld_rdata;
  wire                    tensor_wld_ready;
  wire                    tensor_wld_rvalid;
  wire                    pipe_issue_ready;
  wire                    scalar_downstream_ready;
  wire                    lsu_load_req_valid;
  wire                    lsu_load_req_ready;
  wire [SEQ_ID_WIDTH-1:0] lsu_load_req_seq_id;
  wire [EPOCH_WIDTH-1:0]  lsu_load_req_epoch;
  wire [VALUE_WIDTH-1:0]  lsu_load_req_addr;
  wire [1:0]              lsu_load_req_size;
  wire                    lsu_load_req_signed;
  wire                    lsu_load_req1_valid;
  wire                    lsu_load_req1_ready;
  wire [SEQ_ID_WIDTH-1:0] lsu_load_req1_seq_id;
  wire [EPOCH_WIDTH-1:0]  lsu_load_req1_epoch;
  wire [VALUE_WIDTH-1:0]  lsu_load_req1_addr;
  wire [1:0]              lsu_load_req1_size;
  wire                    lsu_load_req1_signed;
  wire                    lsu_load_resp_valid;
  wire [SEQ_ID_WIDTH-1:0] lsu_load_resp_seq_id;
  wire [EPOCH_WIDTH-1:0]  lsu_load_resp_epoch;
  wire                    lsu_load_resp_error;
  wire [VALUE_WIDTH-1:0]  lsu_load_resp_value;
  wire                    lsu_store_req_valid;
  wire                    lsu_store_req_ready;
  wire [SEQ_ID_WIDTH-1:0] lsu_store_req_seq_id;
  wire [EPOCH_WIDTH-1:0]  lsu_store_req_epoch;
  wire [VALUE_WIDTH-1:0]  lsu_store_req_addr;
  wire [1:0]              lsu_store_req_size;
  wire [VALUE_WIDTH-1:0]  lsu_store_req_data;
  wire [(VALUE_WIDTH/8)-1:0] lsu_store_req_wstrb;
  wire                    lsu_store_req1_valid;
  wire                    lsu_store_req1_ready;
  wire [SEQ_ID_WIDTH-1:0] lsu_store_req1_seq_id;
  wire [EPOCH_WIDTH-1:0]  lsu_store_req1_epoch;
  wire [VALUE_WIDTH-1:0]  lsu_store_req1_addr;
  wire [1:0]              lsu_store_req1_size;
  wire [VALUE_WIDTH-1:0]  lsu_store_req1_data;
  wire [(VALUE_WIDTH/8)-1:0] lsu_store_req1_wstrb;

  wire                    dcache_load_req_valid;
  wire                    dcache_load_req_ready;
  wire                    dcache_load_req1_valid;
  wire                    dcache_load_req1_ready;
  wire                    dcache_load_resp_valid;
  wire [SEQ_ID_WIDTH-1:0] dcache_load_resp_seq_id;
  wire [EPOCH_WIDTH-1:0]  dcache_load_resp_epoch;
  wire                    dcache_load_resp_error;
  wire [VALUE_WIDTH-1:0]  dcache_load_resp_value;
  wire                    dcache_store_req_valid;
  wire                    dcache_store_req_ready;
  wire                    dcache_store_req1_valid;
  wire                    dcache_store_req1_ready;
  wire                    dcache_store_predict_phase;
  wire                    dcache_store_predict_mem_active;
  wire                    dcache_store_predict_backend_blocked;

  wire [PC_WIDTH-1:0]     mem_io_addr;
  wire                    mem_io_req;
  wire                    mem_io_we;
  wire [63:0]             mem_io_wdata;
  wire [7:0]              mem_io_wstrb;
  wire [63:0]             mem_io_rdata;
  wire                    mem_io_ready;
  wire                    mem_io_rvalid;
  wire                    mem_store_block;
  wire                    asic_store_block;
  wire [15:0]             dtcm_lsu_addr;
  wire                    dtcm_lsu_req;
  wire                    dtcm_lsu_we;
  wire [63:0]             dtcm_lsu_wdata;
  wire [7:0]              dtcm_lsu_wstrb;
  wire [63:0]             dtcm_lsu_rdata;
  wire                    dtcm_lsu_ready;
  wire                    dtcm_lsu_rvalid;

  wire                    scalar_dma_start_valid;
  wire                    scalar_dma_start_ready;
  wire [VALUE_WIDTH-1:0]  scalar_dma_start_src;
  wire [VALUE_WIDTH-1:0]  scalar_dma_start_dst;
  wire [VALUE_WIDTH-1:0]  scalar_dma_start_len;
  wire                    scalar_dma_sync_valid;
  wire                    scalar_dma_sync_ready;
  wire                    scalar_cache_op_valid;
  wire                    scalar_cache_op_ready;
  wire                    scalar_cache_op_is_va;
  wire [1:0]              scalar_cache_op_kind;
  wire [VALUE_WIDTH-1:0]  scalar_cache_op_addr;
  wire [SEQ_ID_WIDTH-1:0] scalar_cache_op_seq_id;
  wire [EPOCH_WIDTH-1:0]  scalar_cache_op_epoch;
  wire                    scalar_cache_op_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] scalar_cache_op_complete_seq_id;
  wire [EPOCH_WIDTH-1:0]  scalar_cache_op_complete_epoch;
  wire                    dcache_clean_wb_valid;
  wire                    dcache_clean_wb_ready;
  wire [VALUE_WIDTH-1:0]  dcache_clean_wb_addr;
  wire [127:0]            dcache_clean_wb_data;
  wire                    dcache_clean_wb_last;
  wire                    dcache_clean_wb_complete;
  wire                    dcache_refill_req_valid;
  wire                    dcache_refill_req_ready;
  wire [VALUE_WIDTH-1:0]  dcache_refill_req_addr;
  wire                    dcache_refill_resp_valid;
  wire                    dcache_refill_resp_ready;
  wire [AXI_DATA_WIDTH-1:0] dcache_refill_resp_data;
  wire                    dcache_refill_resp_last;
  wire                    dcache_refill_resp_error;
  wire                    dtcm_dma_start_req;
  wire [PC_WIDTH-1:0]     dtcm_dma_start_addr_src;
  wire [PC_WIDTH-1:0]     dtcm_dma_start_addr_dst;
  wire [31:0]             dtcm_dma_start_len;
  reg                     edge_dma_busy_q;
  reg                     tensor_circular_dma_active_q;
  reg                     tensor_circular_dma_inflight_q;
  reg [VALUE_WIDTH-1:0]   tensor_circular_dma_src_base_q;
  reg [VALUE_WIDTH-1:0]   tensor_circular_dma_src_addr_q;
  reg [VALUE_WIDTH-1:0]   tensor_circular_dma_group_base_q;
  reg [15:0]              tensor_circular_base_q;
  reg [15:0]              tensor_circular_ring_capacity_entries_q;
  reg [31:0]              tensor_circular_dma_total_fragments_q;
  reg [15:0]              tensor_circular_dma_inner_q;
  reg [15:0]              tensor_circular_dma_x_max_q;
  // The stream engine accepts one 16-byte AXI/DTCM beat per command. Keep its
  // position within a logical source item separate from the ring-entry offset:
  // one source item can span beats, and one entry can gather several items.
  reg [15:0]              tensor_circular_dma_source_offset_words_q;
  reg [15:0]              tensor_circular_dma_fragment_words_q;
  reg                     tensor_circular_dma_use_xy_q;
  reg [31:0]              tensor_circular_dma_len_q;
  reg [31:0]              tensor_circular_dma_stride_q;
  reg [31:0]              tensor_circular_dma_y_stride_q;
  reg [31:0]              tensor_circular_dma_issued_fragments_q;
  reg [15:0]              tensor_circular_produced_entries_q;
  reg [15:0]              tensor_circular_consumed_entries_q;
  reg [15:0]              tensor_circular_producer_entry_q;
  reg [15:0]              tensor_circular_consumer_entry_q;
  reg [15:0]              tensor_circular_producer_addr_q;
  reg [15:0]              tensor_circular_consumer_addr_q;
  reg [15:0]              tensor_circular_entry_words_q;
  reg [15:0]              tensor_circular_producer_entry_offset_words_q;
  reg [15:0]              tensor_circular_complete_entry_offset_words_q;
  reg [15:0]              tensor_circular_reserved_entries_q;
  reg                     tensor_circular_wld_active_q;
  reg                     tensor_wsld_active_q;
  reg                     tensor_sld_circular_active_q;
  reg                     tensor_sld_circular_inflight_q;
  reg                     tensor_wsld_group_active_q;
  reg                     tensor_wsld_transpose_q;
  reg [2:0]               tensor_wsld_sld_issued_q;
  reg                     tensor_wsld_sld_done_q;
  reg [2:0]               tensor_wsld_wld_issued_q;
  reg [2:0]               tensor_wsld_wld_done_q;
  reg [2:0]               tensor_wsld_start_done_q;
  reg [15:0]              tensor_wsld_group_addr_q;
  wire                    tensor_circular_config_valid;
  wire [15:0]             tensor_circular_occupied_entries;
  wire                    tensor_circular_ring_empty;
  wire                    tensor_circular_ring_full;
  wire                    tensor_circular_dma_done_pulse;
  wire                    tensor_circular_dma_launch;
  wire                    tensor_circular_entry_complete_on_done;
  wire                    tensor_circular_source_item_complete_on_launch;
  wire                    tensor_circular_stream_drained;
  wire                    tensor_circular_wld_launch;
  wire                    tensor_wsld_group_claim;
  wire                    tensor_wsld_sld_launch;
  wire                    tensor_wsld_wld_launch;
  wire                    tensor_wsld_group_release;
  wire                    tensor_sld_circular_launch;
  wire [15:0]             tensor_circular_producer_addr;
  wire [15:0]             tensor_circular_consumer_addr;
  wire [15:0]             tensor_circular_start_base;
  wire [PC_WIDTH-1:0]     tensor_circular_start_offset;
  wire [VALUE_WIDTH-1:0]  tensor_circular_dma_src_addr;
  wire [PC_WIDTH-1:0]     tensor_circular_dma_dst_addr;
  wire [63:0]             tensor_dma_start_xy_total;
  wire                    tensor_circular_busy;
  wire                    tensor_dma_direct_start_req;
  wire                    tensor_dma_strided_start_req;
  reg                     tensor_strided_dma_active_q;
  reg                     tensor_strided_dma_inflight_q;
  reg [VALUE_WIDTH-1:0]   tensor_strided_dma_src_q;
  reg [VALUE_WIDTH-1:0]   tensor_strided_dma_group_base_q;
  reg [VALUE_WIDTH-1:0]   tensor_strided_dma_dst_q;
  reg [31:0]              tensor_strided_dma_len_q;
  reg [31:0]              tensor_strided_dma_stride_q;
  reg [31:0]              tensor_strided_dma_y_stride_q;
  reg [31:0]              tensor_strided_dma_x_max_q;
  reg [31:0]              tensor_strided_dma_inner_q;
  reg [31:0]              tensor_strided_dma_total_q;
  reg [31:0]              tensor_strided_dma_issued_q;
  wire                    tensor_strided_dma_done_pulse;
  wire                    tensor_strided_dma_launch;
  wire                    tensor_strided_dma_busy;
  wire                    dma_stream_cmd_ready;
  wire                    dma_stream_beat_done;
  wire                    dma_stream_busy;
  wire                    tensor_circular_dma_cmd_valid;

  wire                    retire_alloc_ready;
  wire                    retire_alloc_valid;
  wire [SEQ_ID_WIDTH-1:0] retire_alloc_seq_id;
  wire [EPOCH_WIDTH-1:0]  retire_alloc_epoch;
  wire [1:0]              retire_alloc_kind;
  wire                    retire_alloc_serializing;
  wire                    retire_alloc1_valid;
  wire [SEQ_ID_WIDTH-1:0] retire_alloc1_seq_id;
  wire [EPOCH_WIDTH-1:0]  retire_alloc1_epoch;
  wire [1:0]              retire_alloc1_kind;
  wire                    retire_alloc1_serializing;
  wire                    retire_sync_alloc0_valid;
  wire [SEQ_ID_WIDTH-1:0] retire_sync_alloc0_seq_id;
  wire [EPOCH_WIDTH-1:0]  retire_sync_alloc0_epoch;
  wire [1:0]              retire_sync_alloc0_kind;
  wire                    retire_sync_alloc0_serializing;
  wire                    retire_sync_alloc1_valid;
  wire [SEQ_ID_WIDTH-1:0] retire_sync_alloc1_seq_id;
  wire [EPOCH_WIDTH-1:0]  retire_sync_alloc1_epoch;
  wire [1:0]              retire_sync_alloc1_kind;
  wire                    retire_sync_alloc1_serializing;
  wire                    scalar_retire_alloc1_valid;
  wire [SEQ_ID_WIDTH-1:0] scalar_retire_alloc1_seq_id;
  wire [EPOCH_WIDTH-1:0]  scalar_retire_alloc1_epoch;
  wire [1:0]              scalar_retire_alloc1_kind;
  wire                    scalar_retire_alloc1_serializing;
  wire                    retire_complete0_valid;
  wire [SEQ_ID_WIDTH-1:0] retire_complete0_seq_id;
  wire [EPOCH_WIDTH-1:0]  retire_complete0_epoch;
  wire                    retire_complete1_valid;
  wire [SEQ_ID_WIDTH-1:0] retire_complete1_seq_id;
  wire [EPOCH_WIDTH-1:0]  retire_complete1_epoch;
  wire                    retire_complete2_valid;
  wire [SEQ_ID_WIDTH-1:0] retire_complete2_seq_id;
  wire [EPOCH_WIDTH-1:0]  retire_complete2_epoch;
  wire                    retire_complete3_valid;
  wire [SEQ_ID_WIDTH-1:0] retire_complete3_seq_id;
  wire [EPOCH_WIDTH-1:0]  retire_complete3_epoch;
  wire                    retire_complete4_valid;
  wire [SEQ_ID_WIDTH-1:0] retire_complete4_seq_id;
  wire [EPOCH_WIDTH-1:0]  retire_complete4_epoch;
  wire                    scalar_retire_complete4_valid;
  wire [SEQ_ID_WIDTH-1:0] scalar_retire_complete4_seq_id;
  wire [EPOCH_WIDTH-1:0]  scalar_retire_complete4_epoch;
  wire                    scalar_retire_complete5_valid;
  wire [SEQ_ID_WIDTH-1:0] scalar_retire_complete5_seq_id;
  wire [EPOCH_WIDTH-1:0]  scalar_retire_complete5_epoch;
  wire                    scalar_system_placeholder_valid;
  wire [2:0]              scalar_system_placeholder_funct3;
  wire [11:0]             scalar_system_placeholder_csr;
  wire [REG_INDEX_WIDTH-1:0] scalar_system_placeholder_rd;
  wire [REG_INDEX_WIDTH-1:0] scalar_system_placeholder_rs1;
  wire [VALUE_WIDTH-1:0]  scalar_system_placeholder_rs1_value;
  wire [SEQ_ID_WIDTH-1:0] scalar_system_placeholder_seq_id;
  wire [EPOCH_WIDTH-1:0]  scalar_system_placeholder_epoch;

  wire                    control_placeholder_valid;
  wire                    control_placeholder_taken;
  wire [PC_WIDTH-1:0]     control_placeholder_target;
  wire [SEQ_ID_WIDTH-1:0] control_placeholder_seq_id;
  wire [EPOCH_WIDTH-1:0]  control_placeholder_epoch;

  wire [PC_WIDTH-1:0]     dtcm_dma_araddr;
  wire [1:0]              dtcm_dma_arburst;
  wire [3:0]              dtcm_dma_arcache;
  wire [AXI_ID_WIDTH-1:0] dtcm_dma_arid;
  wire [AXI_LEN_WIDTH-1:0] dtcm_dma_arlen;
  wire                    dtcm_dma_arlock;
  wire [2:0]              dtcm_dma_arprot;
  wire [2:0]              dtcm_dma_arsize;
  wire                    dtcm_dma_arvalid;
  wire                    dtcm_dma_arready;
  wire [AXI_DATA_WIDTH-1:0] dtcm_dma_rdata;
  wire                    dtcm_dma_rlast;
  wire                    dtcm_dma_rready;
  wire                    dtcm_dma_rvalid;
  wire [PC_WIDTH-1:0]     dtcm_dma_awaddr;
  wire [1:0]              dtcm_dma_awburst;
  wire [3:0]              dtcm_dma_awcache;
  wire [AXI_ID_WIDTH-1:0] dtcm_dma_awid;
  wire [AXI_LEN_WIDTH-1:0] dtcm_dma_awlen;
  wire                    dtcm_dma_awlock;
  wire [2:0]              dtcm_dma_awprot;
  wire [2:0]              dtcm_dma_awsize;
  wire                    dtcm_dma_awvalid;
  wire                    dtcm_dma_awready;
  wire                    dtcm_dma_bready;
  wire                    dtcm_dma_bvalid;
  wire [AXI_DATA_WIDTH-1:0] dtcm_dma_wdata;
  wire                    dtcm_dma_wlast;
  wire                    dtcm_dma_wready;
  wire [(AXI_DATA_WIDTH/8)-1:0] dtcm_dma_wstrb;
  wire                    dtcm_dma_wvalid;

  wire [PC_WIDTH-1:0]     biu_dma_araddr;
  wire [1:0]              biu_dma_arburst;
  wire [3:0]              biu_dma_arcache;
  wire [AXI_ID_WIDTH-1:0] biu_dma_arid;
  wire [AXI_LEN_WIDTH-1:0] biu_dma_arlen;
  wire                    biu_dma_arlock;
  wire [2:0]              biu_dma_arprot;
  wire [2:0]              biu_dma_arsize;
  wire                    biu_dma_arvalid;
  wire                    biu_dma_arready;
  wire [AXI_DATA_WIDTH-1:0] biu_dma_rdata;
  wire [AXI_ID_WIDTH-1:0] biu_dma_rid;
  wire                    biu_dma_rlast;
  wire                    biu_dma_rready;
  wire [1:0]              biu_dma_rresp;
  wire                    biu_dma_rvalid;
  wire [PC_WIDTH-1:0]     biu_dma_awaddr;
  wire [1:0]              biu_dma_awburst;
  wire [3:0]              biu_dma_awcache;
  wire [AXI_ID_WIDTH-1:0] biu_dma_awid;
  wire [AXI_LEN_WIDTH-1:0] biu_dma_awlen;
  wire                    biu_dma_awlock;
  wire [2:0]              biu_dma_awprot;
  wire [2:0]              biu_dma_awsize;
  wire                    biu_dma_awvalid;
  wire                    biu_dma_awready;
  wire [AXI_ID_WIDTH-1:0] biu_dma_bid;
  wire                    biu_dma_bready;
  wire [1:0]              biu_dma_bresp;
  wire                    biu_dma_bvalid;
  wire [AXI_DATA_WIDTH-1:0] biu_dma_wdata;
  wire                    biu_dma_wlast;
  wire                    biu_dma_wready;
  wire [(AXI_DATA_WIDTH/8)-1:0] biu_dma_wstrb;
  wire                    biu_dma_wvalid;

  wire [PC_WIDTH-1:0]     biu_core_araddr;
  wire [1:0]              biu_core_arburst;
  wire [3:0]              biu_core_arcache;
  wire [AXI_ID_WIDTH-1:0] biu_core_arid;
  wire [AXI_LEN_WIDTH-1:0] biu_core_arlen;
  wire                    biu_core_arlock;
  wire [2:0]              biu_core_arprot;
  wire [2:0]              biu_core_arsize;
  wire                    biu_core_arvalid;
  wire                    biu_core_arready;
  wire [AXI_DATA_WIDTH-1:0] biu_core_rdata;
  wire [AXI_ID_WIDTH-1:0] biu_core_rid;
  wire                    biu_core_rlast;
  wire                    biu_core_rready;
  wire [1:0]              biu_core_rresp;
  wire                    biu_core_rvalid;
  wire [PC_WIDTH-1:0]     biu_core_awaddr;
  wire [1:0]              biu_core_awburst;
  wire [3:0]              biu_core_awcache;
  wire [AXI_ID_WIDTH-1:0] biu_core_awid;
  wire [AXI_LEN_WIDTH-1:0] biu_core_awlen;
  wire                    biu_core_awlock;
  wire [2:0]              biu_core_awprot;
  wire [2:0]              biu_core_awsize;
  wire                    biu_core_awvalid;
  wire                    biu_core_awready;
  wire [AXI_ID_WIDTH-1:0] biu_core_bid;
  wire                    biu_core_bready;
  wire [1:0]              biu_core_bresp;
  wire                    biu_core_bvalid;
  wire [AXI_DATA_WIDTH-1:0] biu_core_wdata;
  wire                    biu_core_wlast;
  wire                    biu_core_wready;
  wire [(AXI_DATA_WIDTH/8)-1:0] biu_core_wstrb;
  wire                    biu_core_wvalid;
  reg                     clean_wb_buf_valid_q;
  reg                     clean_wb_aw_sent_q;
  reg                     clean_wb_w_sent_q;
  reg [PC_WIDTH-1:0]      clean_wb_addr_q;
  reg [AXI_DATA_WIDTH-1:0] clean_wb_data_q;
  reg                     clean_wb_last_q;
  reg                     edge_dma_active_q;
  reg                     scalar_cache_op_pending_q;


  assign retire_complete4_valid = scalar_retire_complete4_valid;
  assign retire_complete4_seq_id = scalar_retire_complete4_seq_id;
  assign retire_complete4_epoch = scalar_retire_complete4_epoch;
  assign retire_alloc1_valid = scalar_retire_alloc1_valid;
  assign retire_alloc1_seq_id = scalar_retire_alloc1_seq_id;
  assign retire_alloc1_epoch = scalar_retire_alloc1_epoch;
  assign retire_alloc1_kind = scalar_retire_alloc1_kind;
  assign retire_alloc1_serializing = scalar_retire_alloc1_serializing;
  assign retire_sync_alloc0_valid = retire_alloc_valid;
  assign retire_sync_alloc0_seq_id = retire_alloc_seq_id;
  assign retire_sync_alloc0_epoch = retire_alloc_epoch;
  assign retire_sync_alloc0_kind = retire_alloc_kind;
  assign retire_sync_alloc0_serializing = retire_alloc_serializing;
  assign retire_sync_alloc1_valid = retire_alloc_valid &&
                                    scalar_retire_alloc1_valid;
  assign retire_sync_alloc1_seq_id = scalar_retire_alloc1_seq_id;
  assign retire_sync_alloc1_epoch = scalar_retire_alloc1_epoch;
  assign retire_sync_alloc1_kind = scalar_retire_alloc1_kind;
  assign retire_sync_alloc1_serializing = scalar_retire_alloc1_serializing;
  assign core_halted = !cpurst_b;
`ifdef EDGE_DEBUG
  assign debug_token0_valid = token0_valid;
  assign debug_token0_kind = token0_kind;
`endif
  assign tensor_issue_subop = tensor_issue_opcode8[6:0];
  assign tensor_issue_base_valid = 1'b0;
  assign tensor_issue_base_value = {VALUE_WIDTH{1'b0}};
  assign tensor_issue_uses_dtcm = (tensor_issue_subop == 7'h11) ||
                                  (tensor_issue_subop == 7'h18) ||
                                  (tensor_issue_subop == 7'h1b) ||
                                  (tensor_issue_subop == 7'h1c) ||
                                  (tensor_issue_subop == 7'h1d) ||
                                  (tensor_issue_subop == 7'h1a) ||
                                  (tensor_issue_subop == 7'h1e) ||
                                  (tensor_issue_subop == 7'h15) ||
                                  (tensor_issue_subop == 7'h19);
  assign tensor_issue_store_order_ready =
         (!tensor_issue_uses_dtcm || !scalar_lsu_dtcm_store_pending) &&
         !scalar_cache_op_pending_q;
  assign tensor_cmd_queue_issue_ready = tensor_issue_ready &&
                                        tensor_issue_store_order_ready;
  // Valid describes the queue head independently of downstream backpressure.
  // Gating it with issue_ready creates a ready/valid combinational loop through
  // edge_accel_pipe, which can fail to converge when circular WLD waits for a
  // DMA-produced ring entry.
  assign accel_pipe_cmd_valid = tensor_issue_valid &&
                                 tensor_issue_store_order_ready;
  assign tensor_command_queue_valid = tensor_command_valid &&
                                      tensor_command_is_tensor;
  assign tensor_command_subop[6:0] = tensor_command_inst64[38:32];
  assign tensor_command_is_dma_start = (tensor_command_subop == 7'h01);
  assign tensor_command_is_dma_sync = (tensor_command_subop == 7'h02);
  assign tensor_command_is_dma_start_circular =
         tensor_command_is_dma_start && tensor_command_inst64[57];
  assign tensor_command_is_wld = (tensor_command_subop == 7'h11) ||
                                 (tensor_command_subop == 7'h18);
  assign tensor_command_is_start = (tensor_command_subop == 7'h15) ||
                                   (tensor_command_subop == 7'h19) ||
                                   (tensor_command_subop == ACTU_START) ||
                                   (tensor_command_subop == CMPU_START);
  assign tensor_command_is_sync = (tensor_command_subop == 7'h16) ||
                                  (tensor_command_subop == ACTU_SYNC) ||
                                  (tensor_command_subop == CMPU_SYNC) ||
                                  tensor_command_is_dma_sync;
  assign tensor_command_is_wld_circular = (tensor_command_subop == 7'h1b) ||
                                           (tensor_command_subop == 7'h1c);
  assign tensor_command_accept = tensor_command_queue_valid &&
                                 tensor_cmd_queue_cmd_ready;
  assign accel_pipe_done_subop = tensor_issue_opcode8[6:0];
  assign tensor_sync_done_valid = accel_pipe_done_valid &&
                                  ((accel_pipe_done_subop == 7'h02) ||
                                   (accel_pipe_done_subop == 7'h16) ||
                                   (accel_pipe_done_subop == ACTU_SYNC) ||
                                   (accel_pipe_done_subop == CMPU_SYNC));
  assign scalar_downstream_ready = pipe_issue_ready &&
                                   !tensor_sync_issue_fence_q;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      tensor_sync_issue_fence_q <= 1'b0;
      tensor_sync_issue_fence_seq_q <= {SEQ_ID_WIDTH{1'b0}};
      tensor_sync_issue_fence_epoch_q <= {EPOCH_WIDTH{1'b0}};
    end else if (redirect_flush_valid && tensor_sync_issue_fence_q &&
                 (tensor_sync_issue_fence_epoch_q == redirect_kill_epoch) &&
                 seq_is_younger(tensor_sync_issue_fence_seq_q,
                                redirect_kill_seq_id)) begin
      tensor_sync_issue_fence_q <= 1'b0;
    end else if (accel_pipe_done_valid &&
                 ((accel_pipe_done_subop == 7'h02) ||
                  (accel_pipe_done_subop == 7'h16) ||
                  (accel_pipe_done_subop == ACTU_SYNC) ||
                  (accel_pipe_done_subop == CMPU_SYNC)) &&
                 (accel_pipe_done_seq_id == tensor_sync_issue_fence_seq_q) &&
                 (accel_pipe_done_epoch == tensor_sync_issue_fence_epoch_q)) begin
      tensor_sync_issue_fence_q <= 1'b0;
    end else if (tensor_command_accept && tensor_command_is_sync) begin
      tensor_sync_issue_fence_q <= 1'b1;
      tensor_sync_issue_fence_seq_q <= tensor_command_seq_id;
      tensor_sync_issue_fence_epoch_q <= tensor_command_epoch;
    end
  end

  edge_core_dma_axi_mux #(
    .ADDR_WIDTH(PC_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_ID_WIDTH),
    .LEN_WIDTH(AXI_LEN_WIDTH)
  ) dma_axi_mux (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .dtcm_write_select_enable(edge_dma_active_q),
    .dtcm_read_is_stream(tensor_circular_dma_cmd_valid),
    .dtcm_stream_busy(dma_stream_busy),
    .dtcm_araddr(dtcm_dma_araddr),
    .dtcm_arburst(dtcm_dma_arburst),
    .dtcm_arcache(dtcm_dma_arcache),
    .dtcm_arid(dtcm_dma_arid),
    .dtcm_arlen(dtcm_dma_arlen),
    .dtcm_arlock(dtcm_dma_arlock),
    .dtcm_arprot(dtcm_dma_arprot),
    .dtcm_arsize(dtcm_dma_arsize),
    .dtcm_arvalid(dtcm_dma_arvalid),
    .dtcm_arready(dtcm_dma_arready),
    .dtcm_rdata(dtcm_dma_rdata),
    .dtcm_rlast(dtcm_dma_rlast),
    .dtcm_rready(dtcm_dma_rready),
    .dtcm_rvalid(dtcm_dma_rvalid),
    .dtcm_awaddr(dtcm_dma_awaddr),
    .dtcm_awburst(dtcm_dma_awburst),
    .dtcm_awcache(dtcm_dma_awcache),
    .dtcm_awid(dtcm_dma_awid),
    .dtcm_awlen(dtcm_dma_awlen),
    .dtcm_awlock(dtcm_dma_awlock),
    .dtcm_awprot(dtcm_dma_awprot),
    .dtcm_awsize(dtcm_dma_awsize),
    .dtcm_awvalid(dtcm_dma_awvalid),
    .dtcm_awready(dtcm_dma_awready),
    .dtcm_bvalid(dtcm_dma_bvalid),
    .dtcm_bready(dtcm_dma_bready),
    .dtcm_wdata(dtcm_dma_wdata),
    .dtcm_wlast(dtcm_dma_wlast),
    .dtcm_wready(dtcm_dma_wready),
    .dtcm_wstrb(dtcm_dma_wstrb),
    .dtcm_wvalid(dtcm_dma_wvalid),
    .bringup_araddr(bringup_dma_araddr),
    .bringup_arburst(bringup_dma_arburst),
    .bringup_arcache(bringup_dma_arcache),
    .bringup_arid(bringup_dma_arid),
    .bringup_arlen(bringup_dma_arlen),
    .bringup_arlock(bringup_dma_arlock),
    .bringup_arprot(bringup_dma_arprot),
    .bringup_arsize(bringup_dma_arsize),
    .bringup_arvalid(bringup_dma_arvalid),
    .bringup_arready(bringup_dma_arready),
    .bringup_rdata(bringup_dma_rdata),
    .bringup_rid(bringup_dma_rid),
    .bringup_rlast(bringup_dma_rlast),
    .bringup_rready(bringup_dma_rready),
    .bringup_rresp(bringup_dma_rresp),
    .bringup_rvalid(bringup_dma_rvalid),
    .bringup_awaddr(bringup_dma_awaddr),
    .bringup_awburst(bringup_dma_awburst),
    .bringup_awcache(bringup_dma_awcache),
    .bringup_awid(bringup_dma_awid),
    .bringup_awlen(bringup_dma_awlen),
    .bringup_awlock(bringup_dma_awlock),
    .bringup_awprot(bringup_dma_awprot),
    .bringup_awsize(bringup_dma_awsize),
    .bringup_awvalid(bringup_dma_awvalid),
    .bringup_awready(bringup_dma_awready),
    .bringup_bid(bringup_dma_bid),
    .bringup_bready(bringup_dma_bready),
    .bringup_bresp(bringup_dma_bresp),
    .bringup_bvalid(bringup_dma_bvalid),
    .bringup_wdata(bringup_dma_wdata),
    .bringup_wlast(bringup_dma_wlast),
    .bringup_wready(bringup_dma_wready),
    .bringup_wstrb(bringup_dma_wstrb),
    .bringup_wvalid(bringup_dma_wvalid),
    .dma_araddr(biu_dma_araddr),
    .dma_arburst(biu_dma_arburst),
    .dma_arcache(biu_dma_arcache),
    .dma_arid(biu_dma_arid),
    .dma_arlen(biu_dma_arlen),
    .dma_arlock(biu_dma_arlock),
    .dma_arprot(biu_dma_arprot),
    .dma_arsize(biu_dma_arsize),
    .dma_arvalid(biu_dma_arvalid),
    .dma_arready(biu_dma_arready),
    .dma_rdata(biu_dma_rdata),
    .dma_rid(biu_dma_rid),
    .dma_rlast(biu_dma_rlast),
    .dma_rready(biu_dma_rready),
    .dma_rresp(biu_dma_rresp),
    .dma_rvalid(biu_dma_rvalid),
    .dma_awaddr(biu_dma_awaddr),
    .dma_awburst(biu_dma_awburst),
    .dma_awcache(biu_dma_awcache),
    .dma_awid(biu_dma_awid),
    .dma_awlen(biu_dma_awlen),
    .dma_awlock(biu_dma_awlock),
    .dma_awprot(biu_dma_awprot),
    .dma_awsize(biu_dma_awsize),
    .dma_awvalid(biu_dma_awvalid),
    .dma_awready(biu_dma_awready),
    .dma_bid(biu_dma_bid),
    .dma_bready(biu_dma_bready),
    .dma_bresp(biu_dma_bresp),
    .dma_bvalid(biu_dma_bvalid),
    .dma_wdata(biu_dma_wdata),
    .dma_wlast(biu_dma_wlast),
    .dma_wready(biu_dma_wready),
    .dma_wstrb(biu_dma_wstrb),
    .dma_wvalid(biu_dma_wvalid)
  );

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b)
      edge_dma_active_q <= 1'b0;
    else if (dtcm_dma_start_req)
      edge_dma_active_q <= 1'b1;
    else if (edge_dma_active_q && !edge_dma_busy)
      edge_dma_active_q <= 1'b0;
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b)
      edge_dma_busy_q <= 1'b0;
    else
      edge_dma_busy_q <= edge_dma_busy;
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      tensor_circular_dma_active_q <= 1'b0;
      tensor_circular_dma_inflight_q <= 1'b0;
      tensor_circular_dma_src_base_q[VALUE_WIDTH-1:0] <= {VALUE_WIDTH{1'b0}};
      tensor_circular_dma_src_addr_q[VALUE_WIDTH-1:0] <= {VALUE_WIDTH{1'b0}};
      tensor_circular_dma_group_base_q[VALUE_WIDTH-1:0] <= {VALUE_WIDTH{1'b0}};
      tensor_circular_base_q[15:0] <= 16'd0;
      tensor_circular_ring_capacity_entries_q[15:0] <= 16'd0;
      tensor_circular_dma_total_fragments_q[31:0] <= 32'd0;
      tensor_circular_dma_inner_q[15:0] <= 16'd0;
      tensor_circular_dma_x_max_q[15:0] <= 16'd0;
      tensor_circular_dma_source_offset_words_q[15:0] <= 16'd0;
      tensor_circular_dma_fragment_words_q[15:0] <= 16'd2;
      tensor_circular_dma_use_xy_q <= 1'b0;
      tensor_circular_dma_len_q[31:0] <= 32'd64;
      tensor_circular_dma_stride_q[31:0] <= 32'd64;
      tensor_circular_dma_y_stride_q[31:0] <= 32'd0;
      tensor_circular_dma_issued_fragments_q[31:0] <= 32'd0;
      tensor_circular_produced_entries_q[15:0] <= 16'd0;
      tensor_circular_consumed_entries_q[15:0] <= 16'd0;
      tensor_circular_producer_entry_q[15:0] <= 16'd0;
      tensor_circular_consumer_entry_q[15:0] <= 16'd0;
      tensor_circular_producer_addr_q[15:0] <= 16'd0;
      tensor_circular_consumer_addr_q[15:0] <= 16'd0;
      tensor_circular_entry_words_q[15:0] <= 16'd8;
      tensor_circular_producer_entry_offset_words_q[15:0] <= 16'd0;
      tensor_circular_complete_entry_offset_words_q[15:0] <= 16'd0;
      tensor_circular_reserved_entries_q[15:0] <= 16'd0;
      tensor_circular_wld_active_q <= 1'b0;
      tensor_wsld_active_q <= 1'b0;
      tensor_sld_circular_active_q <= 1'b0;
      tensor_sld_circular_inflight_q <= 1'b0;
      tensor_wsld_group_active_q <= 1'b0;
      tensor_wsld_transpose_q <= 1'b0;
      tensor_wsld_sld_issued_q[2:0] <= 3'd0;
      tensor_wsld_sld_done_q <= 1'b0;
      tensor_wsld_wld_issued_q[2:0] <= 3'd0;
      tensor_wsld_wld_done_q[2:0] <= 3'd0;
      tensor_wsld_start_done_q[2:0] <= 3'd0;
      tensor_wsld_group_addr_q[15:0] <= 16'd0;
    end else begin
      if (tensor_dma_start_circular_req) begin
        tensor_circular_dma_active_q <=
          (tensor_dma_start_circular_tiles[15:0] != 16'b0) &&
          (!tensor_dma_start_use_xy ||
           ((tensor_dma_start_len[31:0] != 32'b0) &&
            (tensor_dma_start_entry_bytes[31:0] != 32'b0) &&
            (tensor_dma_start_len[2:0] == 3'b0) &&
            (tensor_dma_start_entry_bytes[2:0] == 3'b0) &&
            (tensor_dma_start_len[31:0] <=
             tensor_dma_start_entry_bytes[31:0]) &&
            (tensor_dma_start_x[63:32] != 32'b0) &&
            (tensor_dma_start_y[63:32] != 32'b0)));
        tensor_circular_dma_src_base_q[VALUE_WIDTH-1:0] <=
          tensor_dma_start_src[VALUE_WIDTH-1:0];
        tensor_circular_dma_src_addr_q[VALUE_WIDTH-1:0] <=
          tensor_dma_start_src[VALUE_WIDTH-1:0];
        tensor_circular_dma_group_base_q[VALUE_WIDTH-1:0] <=
          tensor_dma_start_src[VALUE_WIDTH-1:0];
        tensor_circular_base_q[15:0] <= tensor_circular_start_base[15:0];
        tensor_circular_ring_capacity_entries_q[15:0] <=
          tensor_dma_start_circular_tiles[15:0];
        tensor_circular_dma_total_fragments_q[31:0] <=
          (tensor_dma_start_use_xy
           ? {16'b0, tensor_dma_start_xy_total[15:0]}
           : {16'b0, tensor_dma_start_circular_tiles[15:0]}) *
          (tensor_dma_start_use_xy
           ? {17'b0, tensor_dma_start_len[18:4]}
           : {27'b0, tensor_wld_tile_words[4:1]});
        tensor_circular_dma_inner_q[15:0] <= 16'd0;
        tensor_circular_dma_x_max_q[15:0] <=
          tensor_dma_start_use_xy ? tensor_dma_start_x[47:32] :
                                    tensor_dma_start_circular_tiles[15:0];
        tensor_circular_dma_use_xy_q <= tensor_dma_start_use_xy;
        tensor_circular_dma_source_offset_words_q[15:0] <= 16'd0;
        tensor_circular_dma_fragment_words_q[15:0] <= 16'd2;
        tensor_circular_dma_len_q[31:0] <=
          tensor_dma_start_use_xy
          ? tensor_dma_start_len[31:0]
          : {24'b0, tensor_wld_tile_words[4:0], 3'b000};
        tensor_circular_dma_stride_q[31:0] <=
          tensor_dma_start_use_xy
          ? tensor_dma_start_x[31:0]
          : {24'b0, tensor_wld_tile_words[4:0], 3'b000};
        tensor_circular_dma_y_stride_q[31:0] <=
          tensor_dma_start_use_xy ? tensor_dma_start_y[31:0] : 32'd0;
        tensor_circular_dma_issued_fragments_q[31:0] <= 32'd0;
        tensor_circular_produced_entries_q[15:0] <= 16'd0;
        tensor_circular_consumed_entries_q[15:0] <= 16'd0;
        tensor_circular_producer_entry_q[15:0] <= 16'd0;
        tensor_circular_consumer_entry_q[15:0] <= 16'd0;
        tensor_circular_producer_addr_q[15:0] <= tensor_circular_start_base[15:0];
        tensor_circular_consumer_addr_q[15:0] <= tensor_circular_start_base[15:0];
        tensor_circular_entry_words_q[15:0] <=
          tensor_dma_start_use_xy
          ? tensor_dma_start_entry_bytes[18:3]
          : {11'b0, tensor_wld_tile_words[4:0]};
        tensor_circular_producer_entry_offset_words_q[15:0] <= 16'd0;
        tensor_circular_complete_entry_offset_words_q[15:0] <= 16'd0;
        tensor_circular_reserved_entries_q[15:0] <= 16'd0;
        tensor_circular_wld_active_q <= 1'b0;
        tensor_wsld_active_q <= 1'b0;
        tensor_sld_circular_active_q <= 1'b0;
        tensor_sld_circular_inflight_q <= 1'b0;
        tensor_wsld_group_active_q <= 1'b0;
      end

      if (tensor_circular_dma_launch) begin
        tensor_circular_dma_issued_fragments_q[31:0] <=
          tensor_circular_dma_issued_fragments_q[31:0] + 32'd1;
        if (tensor_circular_producer_entry_offset_words_q[15:0] == 16'd0)
          tensor_circular_reserved_entries_q[15:0] <=
            tensor_circular_reserved_entries_q[15:0] + 16'd1;
        if (tensor_circular_entry_complete_on_done) begin
          tensor_circular_producer_entry_offset_words_q[15:0] <= 16'd0;
          if (tensor_circular_producer_entry_q[15:0] ==
              (tensor_circular_ring_capacity_entries_q[15:0] - 16'd1)) begin
            tensor_circular_producer_entry_q[15:0] <= 16'd0;
            tensor_circular_producer_addr_q[15:0] <=
              tensor_circular_base_q[15:0];
          end else begin
            tensor_circular_producer_entry_q[15:0] <=
              tensor_circular_producer_entry_q[15:0] + 16'd1;
            tensor_circular_producer_addr_q[15:0] <=
              tensor_circular_producer_addr_q[15:0] +
              tensor_circular_entry_words_q[15:0];
          end
        end else begin
          tensor_circular_producer_entry_offset_words_q[15:0] <=
            tensor_circular_producer_entry_offset_words_q[15:0] +
            tensor_circular_dma_fragment_words_q[15:0];
        end
        if ((tensor_circular_dma_issued_fragments_q[31:0] + 32'd1) >=
            tensor_circular_dma_total_fragments_q[31:0])
          tensor_circular_dma_active_q <= 1'b0;
        if (tensor_circular_source_item_complete_on_launch) begin
          tensor_circular_dma_source_offset_words_q[15:0] <= 16'd0;
          if (tensor_circular_dma_use_xy_q) begin
            if (tensor_circular_dma_inner_q[15:0] ==
                (tensor_circular_dma_x_max_q[15:0] - 16'd1)) begin
              tensor_circular_dma_inner_q[15:0] <= 16'd0;
              tensor_circular_dma_group_base_q[VALUE_WIDTH-1:0] <=
                tensor_circular_dma_group_base_q[VALUE_WIDTH-1:0] +
                {{(VALUE_WIDTH-32){1'b0}},
                  tensor_circular_dma_y_stride_q[31:0]};
              tensor_circular_dma_src_addr_q[VALUE_WIDTH-1:0] <=
                tensor_circular_dma_group_base_q[VALUE_WIDTH-1:0] +
                {{(VALUE_WIDTH-32){1'b0}},
                  tensor_circular_dma_y_stride_q[31:0]};
            end else begin
              tensor_circular_dma_inner_q[15:0] <=
                tensor_circular_dma_inner_q[15:0] + 16'd1;
              tensor_circular_dma_src_addr_q[VALUE_WIDTH-1:0] <=
                tensor_circular_dma_src_addr_q[VALUE_WIDTH-1:0] +
                {{(VALUE_WIDTH-32){1'b0}},
                  tensor_circular_dma_stride_q[31:0]};
            end
          end else begin
            tensor_circular_dma_src_addr_q[VALUE_WIDTH-1:0] <=
              tensor_circular_dma_src_addr_q[VALUE_WIDTH-1:0] +
              {{(VALUE_WIDTH-32){1'b0}},
                tensor_circular_dma_stride_q[31:0]};
          end
        end else begin
          tensor_circular_dma_source_offset_words_q[15:0] <=
            tensor_circular_dma_source_offset_words_q[15:0] +
            tensor_circular_dma_fragment_words_q[15:0];
        end
      end

      if (tensor_circular_dma_done_pulse) begin
        if ((tensor_circular_complete_entry_offset_words_q[15:0] +
             tensor_circular_dma_fragment_words_q[15:0]) ==
            tensor_circular_entry_words_q[15:0]) begin
          tensor_circular_produced_entries_q[15:0] <=
            tensor_circular_produced_entries_q[15:0] + 16'd1;
          tensor_circular_complete_entry_offset_words_q[15:0] <= 16'd0;
        end else begin
          tensor_circular_complete_entry_offset_words_q[15:0] <=
            tensor_circular_complete_entry_offset_words_q[15:0] +
            tensor_circular_dma_fragment_words_q[15:0];
        end
      end

      tensor_circular_dma_inflight_q <= dma_stream_busy;

      if (tensor_wld_fill_done && tensor_circular_wld_active_q)
        tensor_circular_wld_active_q <= 1'b0;

      if (tensor_circular_wld_launch) begin
        tensor_circular_wld_active_q <= 1'b1;
        // Advance the read pointer at launch so a same-cycle fill completion
        // plus next launch addresses the following slot.  The occupancy/free
        // counter below still advances only after the complete WLD tile fill.
        if (tensor_circular_consumer_entry_q[15:0] ==
            (tensor_circular_ring_capacity_entries_q[15:0] - 16'd1)) begin
          tensor_circular_consumer_entry_q[15:0] <= 16'd0;
          tensor_circular_consumer_addr_q[15:0] <= tensor_circular_base_q[15:0];
        end else begin
          tensor_circular_consumer_entry_q[15:0] <=
            tensor_circular_consumer_entry_q[15:0] + 16'd1;
          tensor_circular_consumer_addr_q[15:0] <=
            tensor_circular_consumer_addr_q[15:0] +
            tensor_circular_entry_words_q[15:0];
        end
      end

      if (tensor_cmd_wsld_circular_req && tensor_wsld_circular_ready) begin
        tensor_wsld_active_q <= 1'b1;
        tensor_wsld_transpose_q <= tensor_cmd_wsld_circular_transpose;
      end

      if (tensor_cmd_sld_circular_req && tensor_sld_circular_ready)
        tensor_sld_circular_active_q <= 1'b1;

      if (tensor_sld_circular_launch) begin
        tensor_sld_circular_inflight_q <= 1'b1;
        if (tensor_circular_consumer_entry_q[15:0] ==
            (tensor_circular_ring_capacity_entries_q[15:0] - 16'd1)) begin
          tensor_circular_consumer_entry_q[15:0] <= 16'd0;
          tensor_circular_consumer_addr_q[15:0] <= tensor_circular_base_q[15:0];
        end else begin
          tensor_circular_consumer_entry_q[15:0] <=
            tensor_circular_consumer_entry_q[15:0] + 16'd1;
          tensor_circular_consumer_addr_q[15:0] <=
            tensor_circular_consumer_addr_q[15:0] + tensor_circular_entry_words_q[15:0];
        end
      end

      if (tensor_sld_circular_active_q && tensor_sld_circular_inflight_q &&
          tensor_sld_fill_done) begin
        tensor_sld_circular_inflight_q <= 1'b0;
        tensor_circular_consumed_entries_q[15:0] <=
          tensor_circular_consumed_entries_q[15:0] + 16'd1;
        if (tensor_circular_stream_drained)
          tensor_sld_circular_active_q <= 1'b0;
      end

      if (tensor_wsld_group_claim) begin
        tensor_wsld_group_active_q <= 1'b1;
        tensor_wsld_group_addr_q[15:0] <= tensor_circular_consumer_addr_q[15:0];
        tensor_wsld_sld_issued_q[2:0] <= 3'd0;
        tensor_wsld_sld_done_q <= 1'b0;
        tensor_wsld_wld_issued_q[2:0] <= 3'd0;
        tensor_wsld_wld_done_q[2:0] <= 3'd0;
        tensor_wsld_start_done_q[2:0] <= 3'd0;
        if (tensor_circular_consumer_entry_q[15:0] ==
            (tensor_circular_ring_capacity_entries_q[15:0] - 16'd1)) begin
          tensor_circular_consumer_entry_q[15:0] <= 16'd0;
          tensor_circular_consumer_addr_q[15:0] <= tensor_circular_base_q[15:0];
        end else begin
          tensor_circular_consumer_entry_q[15:0] <=
            tensor_circular_consumer_entry_q[15:0] + 16'd1;
          tensor_circular_consumer_addr_q[15:0] <=
            tensor_circular_consumer_addr_q[15:0] +
            tensor_circular_entry_words_q[15:0];
        end
      end

      if (tensor_wsld_sld_launch)
        tensor_wsld_sld_issued_q[2:0] <=
          tensor_wsld_sld_issued_q[2:0] + 3'd1;
      if (tensor_wsld_active_q && tensor_sld_fill_done)
        tensor_wsld_sld_done_q <= 1'b1;
      if (tensor_wsld_wld_launch)
        tensor_wsld_wld_issued_q[2:0] <= tensor_wsld_wld_issued_q[2:0] + 3'd1;
      if (tensor_wsld_group_active_q && tensor_wld_fill_done &&
          (tensor_wsld_wld_done_q[2:0] < 3'd4))
        tensor_wsld_wld_done_q[2:0] <= tensor_wsld_wld_done_q[2:0] + 3'd1;
      if (tensor_wsld_group_active_q && tensor_start_retire_valid &&
          (tensor_wsld_start_done_q[2:0] < 3'd4))
        tensor_wsld_start_done_q[2:0] <= tensor_wsld_start_done_q[2:0] + 3'd1;

      if (tensor_wsld_group_release) begin
        tensor_wsld_group_active_q <= 1'b0;
        tensor_circular_consumed_entries_q[15:0] <=
          tensor_circular_consumed_entries_q[15:0] + 16'd1;
        if (tensor_circular_stream_drained)
          tensor_wsld_active_q <= 1'b0;
      end

      // A ring slot remains reserved until its tagged WLD fill completes;
      // release at launch would permit wrapped DMA overwrite.
      if (!tensor_wsld_active_q && tensor_circular_wld_active_q &&
          tensor_wld_fill_done &&
          (tensor_circular_produced_entries_q !=
           tensor_circular_consumed_entries_q)) begin
        tensor_circular_consumed_entries_q[15:0] <=
          tensor_circular_consumed_entries_q[15:0] + 16'd1;
      end

      if (tensor_circular_config_valid &&
          ((tensor_circular_consumed_entries_q[15:0] +
            ((!tensor_wsld_active_q && tensor_circular_wld_active_q &&
              tensor_wld_fill_done &&
              (tensor_circular_produced_entries_q !=
               tensor_circular_consumed_entries_q)) ?
             16'd1 : 16'd0)) >=
           tensor_circular_produced_entries_q[15:0]) &&
          !tensor_circular_dma_active_q && !tensor_circular_dma_inflight_q)
        tensor_circular_wld_active_q <= 1'b0;
    end
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      tensor_strided_dma_active_q <= 1'b0;
      tensor_strided_dma_inflight_q <= 1'b0;
      tensor_strided_dma_src_q[VALUE_WIDTH-1:0] <= {VALUE_WIDTH{1'b0}};
      tensor_strided_dma_group_base_q[VALUE_WIDTH-1:0] <= {VALUE_WIDTH{1'b0}};
      tensor_strided_dma_dst_q[VALUE_WIDTH-1:0] <= {VALUE_WIDTH{1'b0}};
      tensor_strided_dma_len_q[31:0] <= 32'b0;
      tensor_strided_dma_stride_q[31:0] <= 32'b0;
      tensor_strided_dma_y_stride_q[31:0] <= 32'b0;
      tensor_strided_dma_x_max_q[31:0] <= 32'b0;
      tensor_strided_dma_inner_q[31:0] <= 32'b0;
      tensor_strided_dma_total_q[31:0] <= 32'b0;
      tensor_strided_dma_issued_q[31:0] <= 32'b0;
    end else begin
      if (tensor_dma_strided_start_req) begin
        tensor_strided_dma_active_q <=
          (tensor_dma_start_len[31:0] != 32'b0) &&
          (tensor_dma_start_x[63:32] != 32'b0) &&
          (tensor_dma_start_y[63:32] != 32'b0);
        tensor_strided_dma_inflight_q <= 1'b0;
        tensor_strided_dma_src_q[VALUE_WIDTH-1:0] <=
          tensor_dma_start_src[VALUE_WIDTH-1:0];
        tensor_strided_dma_group_base_q[VALUE_WIDTH-1:0] <=
          tensor_dma_start_src[VALUE_WIDTH-1:0];
        tensor_strided_dma_dst_q[VALUE_WIDTH-1:0] <=
          tensor_dma_start_dst[VALUE_WIDTH-1:0];
        tensor_strided_dma_len_q[31:0] <= tensor_dma_start_len[31:0];
        tensor_strided_dma_stride_q[31:0] <= tensor_dma_start_x[31:0];
        tensor_strided_dma_y_stride_q[31:0] <= tensor_dma_start_y[31:0];
        tensor_strided_dma_x_max_q[31:0] <= tensor_dma_start_x[63:32];
        tensor_strided_dma_inner_q[31:0] <= 32'b0;
        tensor_strided_dma_total_q[31:0] <= tensor_dma_start_xy_total[31:0];
        tensor_strided_dma_issued_q[31:0] <= 32'b0;
      end

      if (tensor_strided_dma_launch) begin
        tensor_strided_dma_inflight_q <= 1'b1;
        tensor_strided_dma_issued_q[31:0] <=
          tensor_strided_dma_issued_q[31:0] + 32'd1;
        if (tensor_strided_dma_inner_q[31:0] ==
            (tensor_strided_dma_x_max_q[31:0] - 32'd1)) begin
          tensor_strided_dma_inner_q[31:0] <= 32'b0;
          tensor_strided_dma_group_base_q[VALUE_WIDTH-1:0] <=
            tensor_strided_dma_group_base_q[VALUE_WIDTH-1:0] +
            {{(VALUE_WIDTH-32){1'b0}}, tensor_strided_dma_y_stride_q[31:0]};
          tensor_strided_dma_src_q[VALUE_WIDTH-1:0] <=
            tensor_strided_dma_group_base_q[VALUE_WIDTH-1:0] +
            {{(VALUE_WIDTH-32){1'b0}}, tensor_strided_dma_y_stride_q[31:0]};
        end else begin
          tensor_strided_dma_inner_q[31:0] <=
            tensor_strided_dma_inner_q[31:0] + 32'd1;
          tensor_strided_dma_src_q[VALUE_WIDTH-1:0] <=
            tensor_strided_dma_src_q[VALUE_WIDTH-1:0] +
            {{(VALUE_WIDTH-32){1'b0}}, tensor_strided_dma_stride_q[31:0]};
        end
        tensor_strided_dma_dst_q[VALUE_WIDTH-1:0] <=
          tensor_strided_dma_dst_q[VALUE_WIDTH-1:0] +
          {{(VALUE_WIDTH-32){1'b0}}, tensor_strided_dma_len_q[31:0]};
      end

      if (tensor_strided_dma_done_pulse) begin
        tensor_strided_dma_inflight_q <= 1'b0;
        if (tensor_strided_dma_issued_q[31:0] >=
            tensor_strided_dma_total_q[31:0])
          tensor_strided_dma_active_q <= 1'b0;
      end
    end
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b)
      scalar_cache_op_pending_q <= 1'b0;
    else begin
      if (scalar_cache_op_complete_valid)
        scalar_cache_op_pending_q <= 1'b0;
      if (scalar_cache_op_valid && scalar_cache_op_ready)
        scalar_cache_op_pending_q <= 1'b1;
    end
  end

  assign imem_req_valid = 1'b0;
  assign imem_req_addr[PC_WIDTH-1:0] = {PC_WIDTH{1'b0}};
  assign imem_resp_ready = 1'b0;

  edge_core_read_axi_mux #(
    .ADDR_WIDTH(PC_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_ID_WIDTH),
    .LEN_WIDTH(AXI_LEN_WIDTH),
    .ENABLE_ICACHE_REFILL(ENABLE_ICACHE_REFILL)
  ) read_axi_mux (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .icache_req_valid(icache_refill_req_valid),
    .icache_req_ready(icache_refill_req_ready),
    .icache_req_addr(icache_refill_req_addr),
    .icache_resp_valid(icache_refill_resp_valid),
    .icache_resp_ready(icache_refill_resp_ready),
    .icache_resp_bits(icache_refill_resp_bits),
    .icache_miss_pending(ifu_cache_debug_miss_pending),
    .dcache_req_valid(dcache_refill_req_valid),
    .dcache_req_ready(dcache_refill_req_ready),
    .dcache_req_addr(dcache_refill_req_addr[PC_WIDTH-1:0]),
    .dcache_resp_valid(dcache_refill_resp_valid),
    .dcache_resp_ready(dcache_refill_resp_ready),
    .dcache_resp_data(dcache_refill_resp_data),
    .dcache_resp_last(dcache_refill_resp_last),
    .dcache_resp_error(dcache_refill_resp_error),
    .bringup_araddr(bringup_core_araddr),
    .bringup_arburst(bringup_core_arburst),
    .bringup_arcache(bringup_core_arcache),
    .bringup_arid(bringup_core_arid),
    .bringup_arlen(bringup_core_arlen),
    .bringup_arlock(bringup_core_arlock),
    .bringup_arprot(bringup_core_arprot),
    .bringup_arsize(bringup_core_arsize),
    .bringup_arvalid(bringup_core_arvalid),
    .bringup_arready(bringup_core_arready),
    .bringup_rdata(bringup_core_rdata),
    .bringup_rid(bringup_core_rid),
    .bringup_rlast(bringup_core_rlast),
    .bringup_rready(bringup_core_rready),
    .bringup_rresp(bringup_core_rresp),
    .bringup_rvalid(bringup_core_rvalid),
    .core_araddr(biu_core_araddr),
    .core_arburst(biu_core_arburst),
    .core_arcache(biu_core_arcache),
    .core_arid(biu_core_arid),
    .core_arlen(biu_core_arlen),
    .core_arlock(biu_core_arlock),
    .core_arprot(biu_core_arprot),
    .core_arsize(biu_core_arsize),
    .core_arvalid(biu_core_arvalid),
    .core_arready(biu_core_arready),
    .core_rdata(biu_core_rdata),
    .core_rid(biu_core_rid),
    .core_rlast(biu_core_rlast),
    .core_rready(biu_core_rready),
    .core_rresp(biu_core_rresp),
    .core_rvalid(biu_core_rvalid)
  );

  assign tensor_circular_config_valid =
    (tensor_circular_ring_capacity_entries_q != 16'd0) &&
    (tensor_circular_entry_words_q != 16'd0);
  assign tensor_dma_start_xy_total =
    tensor_dma_start_x[63:32] * tensor_dma_start_y[63:32];
  assign tensor_circular_occupied_entries =
    tensor_circular_produced_entries_q - tensor_circular_consumed_entries_q;
  assign tensor_circular_ring_empty =
    (tensor_circular_produced_entries_q == tensor_circular_consumed_entries_q);
  assign tensor_circular_ring_full =
    tensor_circular_config_valid &&
    ((tensor_circular_reserved_entries_q -
      tensor_circular_consumed_entries_q) >=
     tensor_circular_ring_capacity_entries_q);
  assign tensor_circular_dma_done_pulse = dma_stream_beat_done;
  assign tensor_dma_direct_start_req = tensor_dma_start_req &&
                                       !tensor_dma_start_use_xy &&
                                       !tensor_dma_start_circular;
  assign tensor_dma_strided_start_req = tensor_dma_start_req &&
                                        tensor_dma_start_use_xy &&
                                        !tensor_dma_start_circular;
  assign tensor_strided_dma_done_pulse =
    tensor_strided_dma_inflight_q && edge_dma_busy_q && !edge_dma_busy;
  assign tensor_strided_dma_busy = tensor_strided_dma_active_q ||
                                    tensor_strided_dma_inflight_q;
  assign tensor_strided_dma_launch =
    tensor_strided_dma_active_q && !tensor_strided_dma_inflight_q &&
    (tensor_strided_dma_issued_q < tensor_strided_dma_total_q) &&
    !edge_dma_busy && !edge_dma_start_req && !tensor_dma_start_req &&
    !tensor_circular_dma_launch;
  assign tensor_circular_busy =
    tensor_circular_dma_active_q || dma_stream_busy ||
    (tensor_circular_produced_entries_q != tensor_circular_consumed_entries_q);
  assign tensor_circular_dma_cmd_valid =
    tensor_circular_dma_active_q && tensor_circular_config_valid &&
    (!tensor_circular_ring_full ||
     (tensor_circular_producer_entry_offset_words_q != 16'd0)) &&
    (tensor_circular_dma_issued_fragments_q <
     tensor_circular_dma_total_fragments_q) &&
    !edge_dma_start_req && !tensor_dma_start_req;
  assign tensor_circular_dma_launch =
    tensor_circular_dma_cmd_valid && dma_stream_cmd_ready;
  assign tensor_circular_producer_addr = tensor_circular_producer_addr_q[15:0];
  assign tensor_circular_consumer_addr = tensor_circular_consumer_addr_q[15:0];
  assign tensor_circular_dma_src_addr =
    tensor_circular_dma_src_addr_q[VALUE_WIDTH-1:0] +
    {{(VALUE_WIDTH-19){1'b0}},
      tensor_circular_dma_source_offset_words_q[15:0], 3'b000};
  assign tensor_circular_start_offset[PC_WIDTH-1:0] =
    tensor_dma_start_dst[PC_WIDTH-1:0] - mem_region_base_q;
  assign tensor_circular_start_base[15:0] =
    tensor_circular_start_offset[18:3];
  assign tensor_circular_dma_dst_addr =
    mem_region_base_q +
    {{(PC_WIDTH-19){1'b0}},
      (tensor_circular_producer_addr[15:0] +
       tensor_circular_producer_entry_offset_words_q[15:0]), 3'b000};
  assign tensor_circular_entry_complete_on_done =
    (tensor_circular_producer_entry_offset_words_q[15:0] +
     tensor_circular_dma_fragment_words_q[15:0]) ==
    tensor_circular_entry_words_q[15:0];
  assign tensor_circular_source_item_complete_on_launch =
    (tensor_circular_dma_source_offset_words_q[15:0] +
     tensor_circular_dma_fragment_words_q[15:0]) ==
    tensor_circular_dma_len_q[18:3];
  assign tensor_circular_stream_drained =
    !tensor_circular_dma_active_q && !dma_stream_busy &&
    ((tensor_circular_consumed_entries_q[15:0] + 16'd1) >=
     tensor_circular_produced_entries_q[15:0]);
  assign tensor_wld_circular_ready =
    tensor_wld_cmd_ready && tensor_circular_config_valid &&
    !tensor_circular_ring_empty &&
    (tensor_circular_entry_words_q[15:0] ==
     {11'b0, tensor_wld_tile_words[4:0]});
  assign tensor_wsld_circular_ready = tensor_circular_config_valid &&
                                      !tensor_wsld_active_q &&
                                      !tensor_circular_wld_active_q &&
                                      !tensor_unit_sync_stall &&
                                      tensor_wld_unit_cmd_ready &&
                                      tensor_sld_unit_cmd_ready &&
                                      (tensor_circular_entry_words_q == 16'd34);
  assign tensor_sld_circular_ready = tensor_circular_config_valid &&
                                     !tensor_sld_circular_active_q &&
                                     !tensor_wsld_active_q &&
                                     !tensor_circular_wld_active_q &&
                                     (tensor_circular_entry_words_q == 16'd2);
  assign tensor_wld_cmd_ready = tensor_wld_unit_cmd_ready &&
                                !tensor_wsld_active_q &&
                                !tensor_sld_circular_active_q;
  assign tensor_sld_cmd_ready = tensor_sld_unit_cmd_ready &&
                                !tensor_wsld_active_q &&
                                !tensor_sld_circular_active_q;
  assign tensor_sync_stall = tensor_unit_sync_stall || tensor_wsld_active_q ||
                             tensor_sld_circular_active_q;
  assign tensor_sld_circular_launch = tensor_sld_circular_active_q &&
                                      !tensor_sld_circular_inflight_q &&
                                      !tensor_circular_ring_empty &&
                                      tensor_sld_unit_cmd_ready;
  assign tensor_circular_wld_launch = tensor_cmd_wld_circular_req &&
                                      tensor_wld_circular_ready;
  assign tensor_wsld_group_claim = tensor_wsld_active_q &&
                                   !tensor_wsld_group_active_q &&
                                   !tensor_circular_ring_empty;
  assign tensor_wsld_sld_launch = tensor_wsld_group_active_q &&
                                  (tensor_wsld_sld_issued_q[2:0] < 3'd4) &&
                                  (tensor_wsld_sld_issued_q[2:0] <=
                                   tensor_wsld_start_done_q[2:0]) &&
                                  tensor_sld_unit_cmd_ready;
  assign tensor_wsld_wld_launch = tensor_wsld_group_active_q &&
                                  tensor_wsld_sld_done_q &&
                                  (tensor_wsld_wld_issued_q[2:0] < 3'd4) &&
                                  (tensor_wsld_wld_issued_q[2:0] <
                                   tensor_wsld_sld_issued_q[2:0]) &&
                                  (tensor_wsld_wld_issued_q[2:0] <=
                                   tensor_wsld_start_done_q[2:0]) &&
                                  tensor_wld_unit_cmd_ready;
  assign tensor_wsld_group_release = tensor_wsld_group_active_q &&
                                     (tensor_wsld_wld_done_q[2:0] == 3'd4) &&
                                     (tensor_wsld_start_done_q[2:0] == 3'd4);
  assign tensor_unit_cmd_wld_ptr =
    tensor_wsld_wld_launch ?
      (tensor_wsld_group_addr_q + 16'd2 +
       {tensor_wsld_wld_issued_q[2:0], 3'b000}) :
    tensor_circular_wld_launch ? tensor_circular_consumer_addr :
                                  tensor_cmd_wld_ptr;
  assign tensor_unit_cmd_wld_req =
    (tensor_cmd_wld_req && !tensor_wsld_active_q) ||
    (tensor_wsld_wld_launch && !tensor_wsld_transpose_q) ||
    (tensor_circular_wld_launch && !tensor_cmd_wld_trans_req);
  assign tensor_unit_cmd_wld_trans_req =
    (tensor_cmd_wld_trans_req && !tensor_wsld_active_q) ||
    (tensor_wsld_wld_launch && tensor_wsld_transpose_q);
  assign tensor_unit_cmd_wld_reuse = tensor_cmd_wld_reuse &&
                                     !tensor_wsld_active_q;
  assign tensor_unit_cmd_sld_ptr = tensor_sld_circular_launch ?
                                    tensor_circular_consumer_addr :
                                    tensor_wsld_sld_launch ?
                                    tensor_wsld_group_addr_q :
                                    tensor_cmd_sld_ptr;
  assign tensor_unit_cmd_sld_req = tensor_sld_circular_launch ||
                                   tensor_wsld_sld_launch ||
                                   (tensor_cmd_sld_req && !tensor_wsld_active_q &&
                                    !tensor_sld_circular_active_q);
  assign tensor_unit_cmd_sld_reuse = tensor_wsld_active_q ?
                                      (tensor_wsld_sld_issued_q[2:0] != 3'd0) :
                                      tensor_cmd_sld_reuse;
  assign tensor_unit_cmd_sld_stream = tensor_sld_circular_launch;

  assign scalar_dma_start_ready = !edge_dma_busy && !edge_dma_start_req &&
                                  !tensor_dma_start_req &&
                                  !tensor_circular_dma_launch &&
                                  !tensor_strided_dma_launch;
  assign scalar_dma_sync_ready = !edge_dma_busy && !edge_dma_start_req &&
                                 !edge_dma_active_q &&
                                 !tensor_dma_start_req &&
                                 !tensor_circular_busy &&
                                 !tensor_strided_dma_busy;
  assign dtcm_dma_start_req = edge_dma_start_req || tensor_dma_direct_start_req ||
                              tensor_strided_dma_launch ||
                              scalar_dma_start_valid;
  assign dtcm_dma_start_addr_src = edge_dma_start_req ?
    edge_dma_start_addr_src[PC_WIDTH-1:0] :
    (tensor_dma_direct_start_req ? tensor_dma_start_src[PC_WIDTH-1:0] :
      (tensor_strided_dma_launch ? tensor_strided_dma_src_q[PC_WIDTH-1:0] :
                                  scalar_dma_start_src[PC_WIDTH-1:0]));
  assign dtcm_dma_start_addr_dst = edge_dma_start_req ?
    edge_dma_start_addr_dst[PC_WIDTH-1:0] :
    (tensor_dma_direct_start_req ? tensor_dma_start_dst[PC_WIDTH-1:0] :
      (tensor_strided_dma_launch ? tensor_strided_dma_dst_q[PC_WIDTH-1:0] :
                                  scalar_dma_start_dst[PC_WIDTH-1:0]));
  assign dtcm_dma_start_len = edge_dma_start_req ?
    edge_dma_start_len[31:0] :
    (tensor_dma_direct_start_req ? tensor_dma_start_len[31:0] :
      (tensor_strided_dma_launch ? tensor_strided_dma_len_q[31:0] :
                                  scalar_dma_start_len[31:0]));

  assign dcache_clean_wb_ready = !clean_wb_buf_valid_q;
  assign dcache_clean_wb_complete =
    clean_wb_buf_valid_q && clean_wb_last_q &&
    biu_core_bvalid && biu_core_bready;
  assign biu_core_awvalid =
    clean_wb_buf_valid_q && !clean_wb_aw_sent_q ?
      1'b1 : bringup_core_awvalid;
  assign biu_core_awaddr[PC_WIDTH-1:0] =
    clean_wb_buf_valid_q && !clean_wb_aw_sent_q ?
      clean_wb_addr_q[PC_WIDTH-1:0] : bringup_core_awaddr[PC_WIDTH-1:0];
  assign biu_core_awburst[1:0] =
    clean_wb_buf_valid_q && !clean_wb_aw_sent_q ? 2'b01 : bringup_core_awburst[1:0];
  assign biu_core_awcache[3:0] =
    clean_wb_buf_valid_q && !clean_wb_aw_sent_q ? 4'h0 : bringup_core_awcache[3:0];
  assign biu_core_awid[AXI_ID_WIDTH-1:0] =
    clean_wb_buf_valid_q && !clean_wb_aw_sent_q ?
      8'hc1 : bringup_core_awid[AXI_ID_WIDTH-1:0];
  assign biu_core_awlen[AXI_LEN_WIDTH-1:0] =
    clean_wb_buf_valid_q && !clean_wb_aw_sent_q ?
      {AXI_LEN_WIDTH{1'b0}} : bringup_core_awlen[AXI_LEN_WIDTH-1:0];
  assign biu_core_awlock =
    clean_wb_buf_valid_q && !clean_wb_aw_sent_q ? 1'b0 : bringup_core_awlock;
  assign biu_core_awprot[2:0] =
    clean_wb_buf_valid_q && !clean_wb_aw_sent_q ? 3'b000 : bringup_core_awprot[2:0];
  assign biu_core_awsize[2:0] =
    clean_wb_buf_valid_q && !clean_wb_aw_sent_q ? 3'b100 : bringup_core_awsize[2:0];
  assign bringup_core_awready =
    clean_wb_buf_valid_q ? 1'b0 : biu_core_awready;

  assign biu_core_wvalid =
    clean_wb_buf_valid_q && clean_wb_aw_sent_q && !clean_wb_w_sent_q ?
      1'b1 : bringup_core_wvalid;
  assign biu_core_wdata[AXI_DATA_WIDTH-1:0] =
    clean_wb_buf_valid_q && clean_wb_aw_sent_q && !clean_wb_w_sent_q ?
      clean_wb_data_q[AXI_DATA_WIDTH-1:0] : bringup_core_wdata[AXI_DATA_WIDTH-1:0];
  assign biu_core_wlast =
    clean_wb_buf_valid_q && clean_wb_aw_sent_q && !clean_wb_w_sent_q ?
      1'b1 : bringup_core_wlast;
  assign biu_core_wstrb[(AXI_DATA_WIDTH/8)-1:0] =
    clean_wb_buf_valid_q && clean_wb_aw_sent_q && !clean_wb_w_sent_q ?
      {(AXI_DATA_WIDTH/8){1'b1}} : bringup_core_wstrb[(AXI_DATA_WIDTH/8)-1:0];
  assign bringup_core_wready =
    clean_wb_buf_valid_q ? 1'b0 : biu_core_wready;

  assign biu_core_bready =
    clean_wb_buf_valid_q && clean_wb_w_sent_q ? 1'b1 : bringup_core_bready;
  assign bringup_core_bid[AXI_ID_WIDTH-1:0] = biu_core_bid[AXI_ID_WIDTH-1:0];
  assign bringup_core_bresp[1:0] = biu_core_bresp[1:0];
  assign bringup_core_bvalid = clean_wb_buf_valid_q ? 1'b0 : biu_core_bvalid;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      clean_wb_buf_valid_q <= 1'b0;
      clean_wb_aw_sent_q <= 1'b0;
      clean_wb_w_sent_q <= 1'b0;
      clean_wb_addr_q <= {PC_WIDTH{1'b0}};
      clean_wb_data_q <= {AXI_DATA_WIDTH{1'b0}};
      clean_wb_last_q <= 1'b0;
    end else begin
      if (dcache_clean_wb_valid && dcache_clean_wb_ready) begin
        clean_wb_buf_valid_q <= 1'b1;
        clean_wb_aw_sent_q <= 1'b0;
        clean_wb_w_sent_q <= 1'b0;
        clean_wb_addr_q <= dcache_clean_wb_addr[PC_WIDTH-1:0];
        clean_wb_data_q <= dcache_clean_wb_data[AXI_DATA_WIDTH-1:0];
        clean_wb_last_q <= dcache_clean_wb_last;
      end

      if (clean_wb_buf_valid_q && !clean_wb_aw_sent_q &&
          biu_core_awready) begin
        clean_wb_aw_sent_q <= 1'b1;
      end

      if (clean_wb_buf_valid_q && clean_wb_aw_sent_q &&
          !clean_wb_w_sent_q && biu_core_wready) begin
        clean_wb_w_sent_q <= 1'b1;
      end

      if (clean_wb_buf_valid_q && clean_wb_w_sent_q &&
          biu_core_bvalid && biu_core_bready) begin
        clean_wb_buf_valid_q <= 1'b0;
        clean_wb_aw_sent_q <= 1'b0;
        clean_wb_w_sent_q <= 1'b0;
      end
    end
  end

  edge_pc_redirect_ctrl #(
    .PC_WIDTH(PC_WIDTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH)
  ) redirect_ctrl (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .scalar_control_valid(control_placeholder_valid),
    .scalar_control_taken(control_placeholder_taken),
    .scalar_control_target(control_placeholder_target),
    .scalar_control_seq_id(control_placeholder_seq_id),
    .scalar_control_epoch(control_placeholder_epoch),
    .retire_redirect_valid(1'b0),
    .retire_redirect_pc({PC_WIDTH{1'b0}}),
    .retire_redirect_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .retire_redirect_epoch({EPOCH_WIDTH{1'b0}}),
    .loop_predict_valid(1'b0),
    .loop_predict_target({PC_WIDTH{1'b0}}),
    .loop_predict_fallthrough({PC_WIDTH{1'b0}}),
    .loop_predict_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .loop_predict_epoch({EPOCH_WIDTH{1'b0}}),
    .ifu_redirect_valid(ifu_redirect_valid),
    .ifu_redirect_pc(ifu_redirect_pc),
    .ifu_redirect_epoch(ifu_redirect_epoch),
    .redirect_flush_valid(redirect_flush_valid),
    .redirect_predict_valid(),
    .redirect_kill_seq_id(redirect_kill_seq_id),
    .redirect_kill_epoch(redirect_kill_epoch),
    .redirect_new_epoch(redirect_new_epoch),
    .current_epoch()
  );

  // Frontend recovery starts from the resolved issue result immediately.
  // Scalar dependency/retire cleanup follows one cycle later so the
  // redirecting instruction can reserve and complete its own backend state.
  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      backend_redirect_kill_valid_q <= 1'b0;
      backend_redirect_kill_seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
      backend_redirect_kill_epoch_q <= {EPOCH_WIDTH{1'b0}};
    end else begin
      backend_redirect_kill_valid_q <= redirect_flush_valid;
      if (redirect_flush_valid) begin
        backend_redirect_kill_seq_id_q <= redirect_kill_seq_id;
        backend_redirect_kill_epoch_q <= redirect_kill_epoch;
      end
    end
  end

  edge_ifu_fetch #(
    .PC_WIDTH(PC_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH)
  ) ifu_fetch (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .boot_pc(boot_pc),
    .fetch_start(core_start),
    .fetch_stop(core_force_stop),
    .redirect_valid(ifu_redirect_valid),
    .redirect_pc(ifu_redirect_pc),
    .redirect_epoch(ifu_redirect_epoch),
    .imem_req_valid(ifu_cache_req_valid),
    .imem_req_ready(ifu_cache_req_ready),
    .imem_req_addr(ifu_cache_req_addr),
    .imem_resp_valid(ifu_cache_resp_valid),
    .imem_resp_ready(ifu_cache_resp_ready),
    .imem_resp_bits(ifu_cache_resp_bits),
    .fetch_valid(ifu_fetch_valid),
    .fetch_ready(ifu_fetch_ready),
    .fetch_block_pc(ifu_fetch_block_pc),
    .fetch_start_word(ifu_fetch_start_word),
    .fetch_bits(ifu_fetch_bits),
    .fetch_epoch(ifu_fetch_epoch)
  );

  edge_fetch_packet_fifo #(
    .PC_WIDTH(PC_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .DEPTH(4),
    .PTR_WIDTH(2),
    .COUNT_WIDTH(3)
  ) fetch_packet_fifo (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .flush_valid(redirect_flush_valid),
    .in_valid(ifu_fetch_valid),
    .in_ready(ifu_fetch_ready),
    .in_block_pc(ifu_fetch_block_pc),
    .in_start_word(ifu_fetch_start_word),
    .in_bits(ifu_fetch_bits),
    .in_epoch(ifu_fetch_epoch),
    .out_valid(fetch_valid),
    .out_ready(fetch_ready),
    .out_block_pc(fetch_block_pc),
    .out_first_word(fetch_first_word),
    .out_bits(fetch_bits),
    .out_epoch(fetch_epoch),
    .debug_count()
  );

  edge_ifu_icache #(
    .PC_WIDTH(PC_WIDTH),
    .ICACHE_BYTES(ICACHE_BYTES)
  ) ifu_icache (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .fetch_req_valid(ifu_cache_req_valid),
    .fetch_req_ready(ifu_cache_req_ready),
    .fetch_req_addr(ifu_cache_req_addr),
    .invalidate_valid(1'b0),
    .invalidate_ready(),
    .fetch_resp_valid(ifu_cache_resp_valid),
    .fetch_resp_ready(ifu_cache_resp_ready),
    .fetch_resp_bits(ifu_cache_resp_bits),
    .imem_req_valid(icache_refill_req_valid),
    .imem_req_ready(icache_refill_req_ready),
    .imem_req_addr(icache_refill_req_addr),
    .imem_resp_valid(icache_refill_resp_valid),
    .imem_resp_ready(icache_refill_resp_ready),
    .imem_resp_bits(icache_refill_resp_bits),
`ifdef EDGE_DEBUG
    .debug_icache_bytes(debug_icache_bytes),
`else
    .debug_icache_bytes(),
`endif
    .debug_hit(ifu_cache_debug_hit),
    .debug_miss_pending(ifu_cache_debug_miss_pending),
    .debug_invalidate_busy()
  );

  edge_reverse_snapshot #(
    .DEPTH(2),
    .ID_WIDTH(1),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH)
  ) reverse_snapshot (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .alloc_valid(reverse_snapshot_alloc_valid),
    .alloc_ready(reverse_snapshot_alloc_ready),
    .alloc_id(reverse_snapshot_alloc_id),
    .alloc_seq_id(reverse_snapshot_alloc_seq_id),
    .alloc_epoch(reverse_snapshot_alloc_epoch),
    .write_valid(reverse_snapshot_write_valid),
    .write_ready(reverse_snapshot_write_ready),
    .write_id(reverse_snapshot_write_id),
    .write_value(reverse_snapshot_write_value),
    .read_id(reverse_snapshot_read_id),
    .read_ready(reverse_snapshot_read_ready),
    .read_value(reverse_snapshot_read_value),
    .consume_valid(reverse_snapshot_consume_valid),
    .consume_id(reverse_snapshot_consume_id),
    .redirect_kill_valid(backend_redirect_kill_valid_q),
    .redirect_kill_seq_id(backend_redirect_kill_seq_id_q),
    .redirect_kill_epoch(backend_redirect_kill_epoch_q),
    .debug_owned(),
    .debug_value_valid()
  );

  edge_ifu_predecode_frontend #(
    .PC_WIDTH(PC_WIDTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .CAPTURE_SLOTS(CAPTURE_SLOTS),
    .CAPTURE_ID_WIDTH(CAPTURE_ID_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .PRODUCER_TAG_WIDTH(PRODUCER_TAG_WIDTH),
    .REF_COUNT_WIDTH(REF_COUNT_WIDTH)
  ) ifu_predecode_frontend (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .fetch_valid(fetch_valid),
    .fetch_ready(fetch_ready),
    .fetch_block_pc(fetch_block_pc),
    .fetch_first_word(fetch_first_word),
    .fetch_bits(fetch_bits),
    .fetch_epoch(fetch_epoch),
    .redirect_flush_valid(redirect_flush_valid),
    .redirect_new_epoch(redirect_new_epoch),
    .scalar0_ready(scalar_ready),
    .scalar0_valid(frontend_scalar_valid),
    .scalar0_pc(pre_scalar_pc),
    .scalar0_inst(pre_scalar_inst),
    .scalar0_seq_id(pre_scalar_seq_id),
    .scalar0_epoch(pre_scalar_epoch),
    .scalar0_is_pseudo(pre_scalar_is_pseudo),
    .scalar0_pseudo_kind(pre_scalar_pseudo_kind),
    .scalar0_def_valid(pre_scalar_def_valid),
    .scalar0_def_domain(pre_scalar_def_domain),
    .scalar0_def_dst_reg(pre_scalar_def_dst_reg),
    .scalar0_def_bank(pre_scalar_def_bank),
    .scalar1_ready(pipe_issue1_ready),
    .scalar1_valid(frontend_scalar1_valid),
    .scalar1_pc(pre_scalar1_pc),
    .scalar1_inst(pre_scalar1_inst),
    .scalar1_seq_id(pre_scalar1_seq_id),
    .scalar1_epoch(pre_scalar1_epoch),
    .scalar1_is_pseudo(pre_scalar1_is_pseudo),
    .scalar1_pseudo_kind(pre_scalar1_pseudo_kind),
    .scalar1_def_valid(frontend_scalar1_def_valid),
    .scalar1_def_dst_reg(frontend_scalar1_def_dst_reg),
    .scalar1_def_bank(frontend_scalar1_def_bank),
    .accel_command_ready(tensor_cmd_queue_cmd_ready),
    .reverse_snapshot_alloc_ready(reverse_snapshot_alloc_ready),
    .reverse_snapshot_alloc_id(reverse_snapshot_alloc_id),
    .reverse_snapshot_alloc_valid(reverse_snapshot_alloc_valid),
    .reverse_snapshot_alloc_seq_id(reverse_snapshot_alloc_seq_id),
    .reverse_snapshot_alloc_epoch(reverse_snapshot_alloc_epoch),
    .debug_token0_valid(token0_valid),
    .debug_token0_kind(token0_kind),
    .debug_token0_inst32(token0_inst32),
    .accel_command_valid(tensor_command_valid),
    .accel_command_is_tensor(tensor_command_is_tensor),
    .accel_command_inst64(tensor_command_inst64),
    .accel_command_seq_id(tensor_command_seq_id),
    .accel_command_epoch(tensor_command_epoch),
    .accel_command_capture_count(tensor_command_capture_count),
    .accel_command_n_capture_valid(tensor_command_n_capture_valid),
    .accel_command_n_capture_id(tensor_command_n_capture_id),
    .accel_command_n_capture_bank(tensor_command_n_capture_bank),
    .accel_command_n_producer_tag(tensor_command_n_producer_tag),
    .accel_command_n_src_gpr(tensor_command_n_src_gpr),
    .accel_command_base_capture_valid(tensor_command_base_capture_valid),
    .accel_command_base_capture_id(tensor_command_base_capture_id),
    .accel_command_base_capture_bank(tensor_command_base_capture_bank),
    .accel_command_base_producer_tag(tensor_command_base_producer_tag),
    .accel_command_base_src_gpr(tensor_command_base_src_gpr)
  );

  edge_accel_cmd_queue #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .QUEUE_DEPTH(8),
    .QUEUE_PTR_WIDTH(3),
    .SNAPSHOT_DEPTH(8),
    .SNAPSHOT_PTR_WIDTH(3)
  ) tensor_cmd_queue (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .cmd_valid(tensor_command_queue_valid),
    .cmd_ready(tensor_cmd_queue_cmd_ready),
    .cmd_inst64(tensor_command_inst64),
    .cmd_seq_id(tensor_command_seq_id),
    .cmd_epoch(tensor_command_epoch),
    .cmd_n_capture_valid(tensor_command_n_capture_valid),
    .snapshot_valid(tensor_gpr_snapshot_valid),
    .snapshot_seq_id(tensor_gpr_snapshot_seq_id),
    .snapshot_epoch(tensor_gpr_snapshot_epoch),
    .snapshot_target(tensor_gpr_snapshot_target),
    .snapshot_n_valid(tensor_gpr_snapshot_operand_valid),
    .snapshot_n_value(tensor_gpr_snapshot_operand_value),
    .issue_valid(tensor_issue_valid),
    .issue_ready(tensor_cmd_queue_issue_ready),
    .issue_opcode8(tensor_issue_opcode8),
    .issue_imm8(tensor_issue_imm8),
    .issue_inst64(tensor_issue_inst64),
    .issue_seq_id(tensor_issue_seq_id),
    .issue_epoch(tensor_issue_epoch),
    .issue_n_valid(tensor_issue_n_valid),
    .issue_n_value(tensor_issue_n_value),
    .redirect_kill_valid(backend_redirect_kill_valid_q),
    .redirect_kill_seq_id(backend_redirect_kill_seq_id_q),
    .redirect_kill_epoch(backend_redirect_kill_epoch_q),
    .debug_entry_valid(),
    .debug_count(tensor_cmd_queue_count),
    .debug_head(),
    .debug_tail()
  );

  edge_accel_pipe #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .ADDR_WIDTH(16),
    .COMPACT_CMD_INPUT(1)
  ) accel_pipe (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .mem_region_base(mem_region_base_q),
    .mem_region_mask(mem_region_mask_q),
    .mem_region_enable(mem_region_enable_q),
    .cmd_valid(accel_pipe_cmd_valid),
    .cmd_opcode8(tensor_issue_opcode8),
    .cmd_imm8(tensor_issue_imm8),
    .cmd_inst64(64'b0),
    .cmd_seq_id(tensor_issue_seq_id),
    .cmd_epoch(tensor_issue_epoch),
    .cmd_capture_valid(tensor_issue_n_valid),
    .cmd_capture_value(tensor_issue_n_value),
    .dma_start_ready(!edge_dma_busy && !edge_dma_start_req &&
                     !tensor_circular_dma_inflight_q &&
                     !tensor_strided_dma_busy &&
                     !tensor_circular_dma_launch &&
                     !tensor_strided_dma_launch),
    .dma_start_circular_ready(!edge_dma_busy && !edge_dma_start_req &&
                              !tensor_circular_dma_active_q &&
                              !tensor_circular_dma_inflight_q &&
                              !tensor_strided_dma_busy),
    .dma_sync_done(!edge_dma_busy && !edge_dma_start_req &&
                   !edge_dma_active_q &&
                   !tensor_circular_dma_inflight_q &&
                   !tensor_circular_dma_launch &&
                   !tensor_strided_dma_busy),
    .tensor_cmd_ready(tensor_cmd_ready),
    .tensor_start_ready(tensor_start_ready),
    .tensor_wld_cmd_ready(tensor_wld_cmd_ready),
    .tensor_sld_cmd_ready(tensor_sld_cmd_ready),
    .tensor_wld_circular_ready(tensor_wld_circular_ready),
    .tensor_wsld_circular_ready(tensor_wsld_circular_ready),
    .tensor_sld_circular_ready(tensor_sld_circular_ready),
    .tensor_sync_stall(tensor_sync_stall),
    .actu_cmd_ready(actu_cmd_ready),
    .actu_start_ready(actu_start_ready),
    .actu_sync_stall(actu_sync_stall),
    .cmpu_cmd_ready(cmpu_cmd_ready),
    .cmpu_start_ready(cmpu_start_ready),
    .cmpu_sync_stall(cmpu_sync_stall),
    .actu_last_sum_bits(actu_last_sum_bits),
    .cmpu_max_value(cmpu_max_value),
    .cmpu_argmax_idx(cmpu_argmax_idx),
    .cmpu_min_value(cmpu_min_value),
    .cmpu_argmin_idx(cmpu_argmin_idx),
    .reverse_snapshot_write_ready(reverse_snapshot_write_ready),
    .cmd_ready(tensor_issue_ready),
    .decode_illegal(),
    .capture_consume_valid(),
    .tensor_done_valid(accel_pipe_done_valid),
    .tensor_done_seq_id(accel_pipe_done_seq_id),
    .tensor_done_epoch(accel_pipe_done_epoch),
    .dma_start_req(tensor_dma_start_req),
    .dma_start_circular_req(tensor_dma_start_circular_req),
    .dma_start_src(tensor_dma_start_src),
    .dma_start_dst(tensor_dma_start_dst),
    .dma_start_len(tensor_dma_start_len),
    .dma_start_entry_bytes(tensor_dma_start_entry_bytes),
    .dma_start_circular_tiles(tensor_dma_start_circular_tiles),
    .dma_start_use_xy(tensor_dma_start_use_xy),
    .dma_start_circular(tensor_dma_start_circular),
    .dma_start_x(tensor_dma_start_x),
    .dma_start_y(tensor_dma_start_y),
    .dma_sync_req(tensor_dma_sync_req),
    .cmd_setcsr_dtype(tensor_cmd_setcsr_dtype),
    .cmd_setcsr_req(tensor_cmd_setcsr_req),
    .cmd_setcsr_wtype(tensor_cmd_setcsr_wtype),
    .cmd_setin_ptr(tensor_cmd_setin_ptr),
    .cmd_setin_req(tensor_cmd_setin_req),
    .cmd_setn_req(tensor_cmd_setn_req),
    .cmd_setn_value(tensor_cmd_setn_value),
    .cmd_setout_ptr(tensor_cmd_setout_ptr),
    .cmd_setout_req(tensor_cmd_setout_req),
    .cmd_setpsum_ptr(tensor_cmd_setpsum_ptr),
    .cmd_setpsum_req(tensor_cmd_setpsum_req),
    .cmd_start_req(tensor_cmd_start_req),
    .cmd_start_tile_req(tensor_cmd_start_tile_req),
    .cmd_start_mode(tensor_cmd_start_mode),
    .cmd_sync_req(tensor_cmd_sync_req),
    .cmd_wld_ptr(tensor_cmd_wld_ptr),
    .cmd_wld_req(tensor_cmd_wld_req),
    .cmd_wld_circular_req(tensor_cmd_wld_circular_req),
    .cmd_wld_trans_req(tensor_cmd_wld_trans_req),
    .cmd_wld_reuse(tensor_cmd_wld_reuse),
    .cmd_sld_ptr(tensor_cmd_sld_ptr),
    .cmd_sld_req(tensor_cmd_sld_req),
    .cmd_sld_reuse(tensor_cmd_sld_reuse),
    .cmd_sld_stream_ptr(tensor_cmd_sld_stream_ptr),
    .cmd_sld_stream_req(tensor_cmd_sld_stream_req),
    .cmd_wsld_circular_req(tensor_cmd_wsld_circular_req),
    .cmd_wsld_circular_transpose(tensor_cmd_wsld_circular_transpose),
    .cmd_sld_circular_req(tensor_cmd_sld_circular_req),
    .actu_cmd_setcsr_dtype(actu_cmd_setcsr_dtype),
    .actu_cmd_setcsr_mode(actu_cmd_setcsr_mode),
    .actu_cmd_setcsr_req(actu_cmd_setcsr_req),
    .actu_cmd_setin_ptr(actu_cmd_setin_ptr),
    .actu_cmd_setin_req(actu_cmd_setin_req),
    .actu_cmd_setn_req(actu_cmd_setn_req),
    .actu_cmd_setn_value(actu_cmd_setn_value),
    .actu_cmd_setout_ptr(actu_cmd_setout_ptr),
    .actu_cmd_setout_req(actu_cmd_setout_req),
    .actu_cmd_setscalar_req(actu_cmd_setscalar_req),
    .actu_cmd_setscalar_value(actu_cmd_setscalar_value),
    .actu_cmd_start_req(actu_cmd_start_req),
    .actu_cmd_sync_req(actu_cmd_sync_req),
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
    .cmpu_cmd_start_req(cmpu_cmd_start_req),
    .cmpu_cmd_sync_req(cmpu_cmd_sync_req),
    .reverse_snapshot_write_valid(reverse_snapshot_write_valid),
    .reverse_snapshot_write_id(reverse_snapshot_write_id),
    .reverse_snapshot_write_value(reverse_snapshot_write_value)
  );

  edge_scalar_idu_shim #(
    .PC_WIDTH(PC_WIDTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .PSEUDO_WIDTH(PSEUDO_WIDTH)
  ) scalar_idu_shim (
    .scalar_valid(frontend_scalar_valid),
    .scalar_ready(scalar_ready),
    .scalar_pc(pre_scalar_pc),
    .scalar_inst(pre_scalar_inst),
    .scalar_len(1'b0),
    .scalar_is_pseudo(pre_scalar_is_pseudo),
    .scalar_pseudo_kind(pre_scalar_pseudo_kind),
    .scalar_seq_id(pre_scalar_seq_id),
    .scalar_epoch(pre_scalar_epoch),
    .downstream_ready(scalar_downstream_ready),
    .issue_valid(shim_issue_valid),
    .issue_pc(shim_issue_pc),
    .issue_inst(shim_issue_inst),
    .issue_len(shim_issue_len),
    .issue_is_pseudo(shim_issue_is_pseudo),
    .issue_pseudo_kind(shim_issue_pseudo_kind),
    .issue_seq_id(shim_issue_seq_id),
    .issue_epoch(shim_issue_epoch),
    .scalar_def_valid(shim_scalar_def_valid),
    .scalar_def_domain(shim_scalar_def_domain),
    .scalar_def_dst_reg(shim_scalar_def_dst_reg),
    .scalar_def_seq_id(shim_scalar_def_seq_id),
    .scalar_def_epoch(shim_scalar_def_epoch),
    .scalar_control_valid(),
    .scalar_control_seq_id(),
    .scalar_control_epoch(),
    .decode_illegal(shim_decode_illegal)
  );

  edge_scalar_pipe #(
    .PC_WIDTH(PC_WIDTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .PRODUCER_TAG_WIDTH(PRODUCER_TAG_WIDTH),
    .PSEUDO_WIDTH(PSEUDO_WIDTH),
    .ENABLE_EARLY_LOAD_RETIRE(ENABLE_EARLY_LOAD_RETIRE),
    .ENABLE_COMMITTED_STORE_DRAIN(1)
  ) scalar_pipe (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .mem_region_enable(mem_region_enable_q),
    .mem_region_base({{(VALUE_WIDTH-PC_WIDTH){1'b0}},
                     mem_region_base_q}),
    .mem_region_mask({{(VALUE_WIDTH-PC_WIDTH){1'b0}},
                     mem_region_mask_q}),
    .lsu_dtcm_store_query_seq_id(tensor_issue_seq_id),
    .lsu_dtcm_store_query_epoch(tensor_issue_epoch),
    .issue_valid(shim_issue_valid),
    .issue_ready(pipe_issue_ready),
    .issue1_valid(frontend_scalar1_valid && shim_issue_valid),
    .issue1_ready(pipe_issue1_ready),
    .retire_alloc_ready(retire_alloc_ready),
    .ordered_retire0_valid(retire0_valid &&
                           (retire0_kind == TOKEN_KIND_SCALAR)),
    .ordered_retire0_seq_id(retire0_seq_id),
    .ordered_retire0_epoch(retire0_epoch),
    .ordered_retire1_valid(retire1_valid &&
                           (retire1_kind == TOKEN_KIND_SCALAR)),
    .ordered_retire1_seq_id(retire1_seq_id),
    .ordered_retire1_epoch(retire1_epoch),
    .issue_pc(shim_issue_pc),
    .issue_inst(shim_issue_inst),
    .issue_len(shim_issue_len),
    .issue_is_pseudo(shim_issue_is_pseudo),
    .issue_pseudo_kind(shim_issue_pseudo_kind),
    .issue_seq_id(shim_issue_seq_id),
    .issue_epoch(shim_issue_epoch),
    .issue1_pc(pre_scalar1_pc),
    .issue1_inst(pre_scalar1_inst),
    .issue1_is_pseudo(pre_scalar1_is_pseudo),
    .issue1_pseudo_kind(pre_scalar1_pseudo_kind),
    .issue1_seq_id(pre_scalar1_seq_id),
    .issue1_epoch(pre_scalar1_epoch),
    .scalar_def_valid(shim_scalar_def_valid),
    .scalar_def_domain(shim_scalar_def_domain),
    .scalar_def_dst_reg(shim_scalar_def_dst_reg),
    .scalar_def_bank(1'b0),
    .scalar_def_seq_id(shim_scalar_def_seq_id),
    .scalar_def_epoch(shim_scalar_def_epoch),
    .scalar1_def_valid(frontend_scalar1_def_valid),
    .scalar1_def_dst_reg(frontend_scalar1_def_dst_reg),
    .scalar1_def_bank(frontend_scalar1_def_bank),
    .scalar1_def_seq_id(pre_scalar1_seq_id),
    .scalar1_def_epoch(pre_scalar1_epoch),
    .gpr_placeholder_complete_valid(tensor_sync_done_valid),
    .gpr_placeholder_complete_seq_id(accel_pipe_done_seq_id),
    .gpr_placeholder_complete_epoch(accel_pipe_done_epoch),
    .gpr_placeholder_complete_reg({REG_INDEX_WIDTH{1'b0}}),
    .gpr_placeholder_complete_bank(1'b0),
    .gpr_placeholder_complete_value({VALUE_WIDTH{1'b0}}),
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
    .fpr_placeholder_complete_valid(1'b0),
    .fpr_placeholder_complete_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .fpr_placeholder_complete_epoch({EPOCH_WIDTH{1'b0}}),
    .fpr_placeholder_complete_reg({REG_INDEX_WIDTH{1'b0}}),
    .fpr_placeholder_complete_bank(1'b0),
    .fpr_placeholder_complete_value(32'b0),
    .redirect_kill_valid(backend_redirect_kill_valid_q),
    .redirect_kill_seq_id(backend_redirect_kill_seq_id_q),
    .redirect_kill_epoch(backend_redirect_kill_epoch_q),
    .producer_valid(scalar_producer_valid),
    .producer_domain(scalar_producer_domain),
    .producer_reg(scalar_producer_reg),
    .producer_bank(scalar_producer_bank),
    .producer_tag(scalar_producer_tag),
    .producer_value(scalar_producer_value),
    .producer_epoch(scalar_producer_epoch),
    .retire_valid(),
    .retire_seq_id(),
    .retire_epoch(),
    .retire_is_pseudo(),
    .retire_alloc_valid(retire_alloc_valid),
    .retire_alloc_seq_id(retire_alloc_seq_id),
    .retire_alloc_epoch(retire_alloc_epoch),
    .retire_alloc_kind(retire_alloc_kind),
    .retire_alloc_serializing(retire_alloc_serializing),
    .retire_alloc1_valid(scalar_retire_alloc1_valid),
    .retire_alloc1_seq_id(scalar_retire_alloc1_seq_id),
    .retire_alloc1_epoch(scalar_retire_alloc1_epoch),
    .retire_alloc1_kind(scalar_retire_alloc1_kind),
    .retire_alloc1_serializing(scalar_retire_alloc1_serializing),
    .retire_complete0_valid(retire_complete0_valid),
    .retire_complete0_seq_id(retire_complete0_seq_id),
    .retire_complete0_epoch(retire_complete0_epoch),
    .retire_complete1_valid(retire_complete1_valid),
    .retire_complete1_seq_id(retire_complete1_seq_id),
    .retire_complete1_epoch(retire_complete1_epoch),
    .retire_complete2_valid(retire_complete2_valid),
    .retire_complete2_seq_id(retire_complete2_seq_id),
    .retire_complete2_epoch(retire_complete2_epoch),
    .retire_complete3_valid(retire_complete3_valid),
    .retire_complete3_seq_id(retire_complete3_seq_id),
    .retire_complete3_epoch(retire_complete3_epoch),
    .retire_complete4_valid(scalar_retire_complete4_valid),
    .retire_complete4_seq_id(scalar_retire_complete4_seq_id),
    .retire_complete4_epoch(scalar_retire_complete4_epoch),
    .retire_complete5_valid(scalar_retire_complete5_valid),
    .retire_complete5_seq_id(scalar_retire_complete5_seq_id),
    .retire_complete5_epoch(scalar_retire_complete5_epoch),
    .mem_placeholder_valid(),
    .mem_placeholder_is_store(),
    .mem_placeholder_size(),
    .mem_placeholder_load_signed(),
    .mem_placeholder_addr(),
    .mem_placeholder_store_data(),
    .mem_placeholder_seq_id(),
    .mem_placeholder_epoch(),
    .mem_placeholder1_valid(),
    .mem_placeholder1_is_store(),
    .mem_placeholder1_size(),
    .mem_placeholder1_load_signed(),
    .mem_placeholder1_addr(),
    .mem_placeholder1_store_data(),
    .mem_placeholder1_seq_id(),
    .mem_placeholder1_epoch(),
    .system_placeholder_valid(scalar_system_placeholder_valid),
    .system_placeholder_funct3(scalar_system_placeholder_funct3),
    .system_placeholder_csr(scalar_system_placeholder_csr),
    .system_placeholder_rd(scalar_system_placeholder_rd),
    .system_placeholder_rs1(scalar_system_placeholder_rs1),
    .system_placeholder_rs1_value(scalar_system_placeholder_rs1_value),
    .system_placeholder_seq_id(scalar_system_placeholder_seq_id),
    .system_placeholder_epoch(scalar_system_placeholder_epoch),
    .cache_op_valid(scalar_cache_op_valid),
    .cache_op_ready(scalar_cache_op_ready),
    .cache_op_is_va(scalar_cache_op_is_va),
    .cache_op_kind(scalar_cache_op_kind),
    .cache_op_addr(scalar_cache_op_addr),
    .cache_op_seq_id(scalar_cache_op_seq_id),
    .cache_op_epoch(scalar_cache_op_epoch),
    .cache_op_complete_valid(scalar_cache_op_complete_valid),
    .cache_op_complete_seq_id(scalar_cache_op_complete_seq_id),
    .cache_op_complete_epoch(scalar_cache_op_complete_epoch),
    .dma_start_valid(scalar_dma_start_valid),
    .dma_start_ready(scalar_dma_start_ready),
    .dma_start_src(scalar_dma_start_src),
    .dma_start_dst(scalar_dma_start_dst),
    .dma_start_len(scalar_dma_start_len),
    .dma_start_seq_id(),
    .dma_start_epoch(),
    .dma_sync_valid(scalar_dma_sync_valid),
    .dma_sync_ready(scalar_dma_sync_ready),
    .dma_sync_seq_id(),
    .dma_sync_epoch(),
    .fence_placeholder_valid(),
    .fence_placeholder_i(),
    .fence_placeholder_seq_id(),
    .fence_placeholder_epoch(),
    .fatal_report_valid(scalar_fatal_valid),
    .fatal_report_code(scalar_fatal_code),
    .fatal_report_inst(scalar_fatal_inst),
    .fatal_report_seq_id(scalar_fatal_seq_id),
    .fatal_report_epoch(scalar_fatal_epoch),
    .ebreak_report_valid(scalar_ebreak_valid),
    .ebreak_report_seq_id(scalar_ebreak_seq_id),
    .ebreak_report_epoch(scalar_ebreak_epoch),
    .control_placeholder_valid(control_placeholder_valid),
    .control_placeholder_taken(control_placeholder_taken),
    .control_placeholder_target(control_placeholder_target),
    .control_placeholder_seq_id(control_placeholder_seq_id),
    .control_placeholder_epoch(control_placeholder_epoch),
    .tensor_gpr_snapshot_valid(tensor_gpr_snapshot_valid),
    .tensor_gpr_snapshot_seq_id(tensor_gpr_snapshot_seq_id),
    .tensor_gpr_snapshot_epoch(tensor_gpr_snapshot_epoch),
    .tensor_gpr_snapshot_target(tensor_gpr_snapshot_target),
    .tensor_gpr_snapshot_operand_valid(tensor_gpr_snapshot_operand_valid),
    .tensor_gpr_snapshot_operand_value(tensor_gpr_snapshot_operand_value),
    .reverse_snapshot_read_ready(reverse_snapshot_read_ready),
    .reverse_snapshot_read_value(reverse_snapshot_read_value),
    .reverse_snapshot_read_id(reverse_snapshot_read_id),
    .reverse_snapshot_consume_valid(reverse_snapshot_consume_valid),
    .reverse_snapshot_consume_id(reverse_snapshot_consume_id),
    .lsu_dtcm_store_pending(scalar_lsu_dtcm_store_pending),
    .gpr_busy_status(gpr_busy_status)
`ifdef EDGE_DEBUG
    ,
    .debug_gpr_read_reg({REG_INDEX_WIDTH{1'b0}}),
    .debug_gpr_read_data(),
    .debug_fpr_read_reg({REG_INDEX_WIDTH{1'b0}}),
    .debug_fpr_read_data(),
    .debug_fpr_busy(debug_fpr_busy),
    .debug_redirect_block(),
    .debug_retire_alloc_ready(),
    .debug_producer_queue_ready(),
    .debug_producer_queue_count(),
    .debug_gpr_issue_ready(),
    .debug_fpr_issue_ready(),
    .debug_alu_issue_ready(),
    .debug_lsu_issue_ready(),
    .debug_sys_issue_ready(),
    .debug_issue_gpr_check_candidate(),
    .debug_issue_fpr_dst_candidate(),
    .debug_is_alu_or_branch(),
    .debug_is_lsu_op(),
    .debug_is_sys_or_fence()
`endif
  );

`ifdef EDGE_DEBUG
  assign debug_gpr_busy = gpr_busy_status;
`endif

  edge_lsu_mem_io #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .ADDR_WIDTH(PC_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH)
  ) lsu_mem_selector (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .redirect_kill_valid(redirect_flush_valid),
    .redirect_kill_seq_id(redirect_kill_seq_id),
    .redirect_kill_epoch(redirect_kill_epoch),
    .mem_region_enable(mem_region_enable_q),
    .mem_region_base(mem_region_base_q),
    .mem_region_mask(mem_region_mask_q),
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
    .lsu_store_req_addr(lsu_store_req_addr),
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
    .lsu_load_resp_valid(lsu_load_resp_valid),
    .lsu_load_resp_seq_id(lsu_load_resp_seq_id),
    .lsu_load_resp_epoch(lsu_load_resp_epoch),
    .lsu_load_resp_error(lsu_load_resp_error),
    .lsu_load_resp_value(lsu_load_resp_value),
    .dcache_load_req_valid(dcache_load_req_valid),
    .dcache_load_req_ready(dcache_load_req_ready),
    .dcache_load_req1_valid(dcache_load_req1_valid),
    .dcache_load_req1_ready(dcache_load_req1_ready),
    .dcache_load_resp_valid(dcache_load_resp_valid),
    .dcache_load_resp_seq_id(dcache_load_resp_seq_id),
    .dcache_load_resp_epoch(dcache_load_resp_epoch),
    .dcache_load_resp_error(dcache_load_resp_error),
    .dcache_load_resp_value(dcache_load_resp_value),
    .dcache_store_req_valid(dcache_store_req_valid),
    .dcache_store_req_ready(dcache_store_req_ready),
    .dcache_store_req1_valid(dcache_store_req1_valid),
    .dcache_store_req1_ready(dcache_store_req1_ready),
    .dcache_store_predict_phase(dcache_store_predict_phase),
    .dcache_store_predict_mem_active(dcache_store_predict_mem_active),
    .dcache_store_predict_backend_blocked(dcache_store_predict_backend_blocked),
    .dcache_debug_load_pending(debug_dcache_load_pending),
    .mem_io_req(mem_io_req),
    .mem_io_we(mem_io_we),
    .mem_io_addr(mem_io_addr),
    .mem_io_wdata(mem_io_wdata),
    .mem_io_wstrb(mem_io_wstrb),
    .mem_io_rdata(mem_io_rdata),
    .mem_io_ready(mem_io_ready),
    .mem_io_rvalid(mem_io_rvalid),
    .mem_store_block(mem_store_block),
    .debug_load_mem_hit(),
    .debug_store_mem_hit(),
    .debug_mem_load_pending()
  );

  edge_lsu_dtcm_adapter #(
    .ADDR_WIDTH(PC_WIDTH),
    .DTCM_ADDR_WIDTH(16),
    .DATA_WIDTH(64)
  ) lsu_dtcm_adapter (
    .mem_addr(mem_io_addr),
    .mem_req(mem_io_req),
    .mem_we(mem_io_we),
    .mem_wdata(mem_io_wdata),
    .mem_wstrb(mem_io_wstrb),
    .mem_rdata(mem_io_rdata),
    .mem_ready(mem_io_ready),
    .mem_rvalid(mem_io_rvalid),
    .mem_store_block(mem_store_block),
    .dtcm_base(mem_region_base_q),
    .dtcm_addr(dtcm_lsu_addr),
    .dtcm_req(dtcm_lsu_req),
    .dtcm_we(dtcm_lsu_we),
    .dtcm_wdata(dtcm_lsu_wdata),
    .dtcm_wstrb(dtcm_lsu_wstrb),
    .dtcm_rdata(dtcm_lsu_rdata),
    .dtcm_ready(dtcm_lsu_ready),
    .dtcm_rvalid(dtcm_lsu_rvalid),
    .asic_store_block(asic_store_block)
  );

  edge_dcache #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .ICACHE_BYTES(ICACHE_BYTES),
    .DCACHE_BYTES(DCACHE_BYTES)
  ) dcache (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .redirect_kill_valid(redirect_flush_valid),
    .redirect_kill_seq_id(redirect_kill_seq_id),
    .redirect_kill_epoch(redirect_kill_epoch),
    .backend_load_pause(dcache_backend_load_pause),
    .backend_store_pause(dcache_backend_store_pause),
    .lsu_load_req_valid(dcache_load_req_valid),
    .lsu_load_req_ready(dcache_load_req_ready),
    .lsu_load_req_seq_id(lsu_load_req_seq_id),
    .lsu_load_req_epoch(lsu_load_req_epoch),
    .lsu_load_req_addr(lsu_load_req_addr),
    .lsu_load_req_size(lsu_load_req_size),
    .lsu_load_req_signed(lsu_load_req_signed),
    .lsu_load_req1_valid(dcache_load_req1_valid),
    .lsu_load_req1_ready(dcache_load_req1_ready),
    .lsu_load_req1_seq_id(lsu_load_req1_seq_id),
    .lsu_load_req1_epoch(lsu_load_req1_epoch),
    .lsu_load_req1_addr(lsu_load_req1_addr),
    .lsu_load_req1_size(lsu_load_req1_size),
    .lsu_load_req1_signed(lsu_load_req1_signed),
    .lsu_load_resp_valid(dcache_load_resp_valid),
    .lsu_load_resp_seq_id(dcache_load_resp_seq_id),
    .lsu_load_resp_epoch(dcache_load_resp_epoch),
    .lsu_load_resp_error(dcache_load_resp_error),
    .lsu_load_resp_value(dcache_load_resp_value),
    .lsu_store_req_valid(dcache_store_req_valid),
    .lsu_store_req_ready(dcache_store_req_ready),
    .lsu_store_req_seq_id(lsu_store_req_seq_id),
    .lsu_store_req_epoch(lsu_store_req_epoch),
    .lsu_store_req_addr(lsu_store_req_addr),
    .lsu_store_req_size(lsu_store_req_size),
    .lsu_store_req_data(lsu_store_req_data),
    .lsu_store_req_wstrb(lsu_store_req_wstrb),
    .lsu_store_req1_valid(dcache_store_req1_valid),
    .lsu_store_req1_ready(dcache_store_req1_ready),
    .lsu_store_req1_seq_id(lsu_store_req1_seq_id),
    .lsu_store_req1_epoch(lsu_store_req1_epoch),
    .lsu_store_req1_addr(lsu_store_req1_addr),
    .lsu_store_req1_size(lsu_store_req1_size),
    .lsu_store_req1_data(lsu_store_req1_data),
    .lsu_store_req1_wstrb(lsu_store_req1_wstrb),
    .cache_op_valid(scalar_cache_op_valid),
    .cache_op_ready(scalar_cache_op_ready),
    .cache_op_is_va(scalar_cache_op_is_va),
    .cache_op_kind(scalar_cache_op_kind),
    .cache_op_addr(scalar_cache_op_addr),
    .cache_op_seq_id(scalar_cache_op_seq_id),
    .cache_op_epoch(scalar_cache_op_epoch),
    .cache_op_complete_valid(scalar_cache_op_complete_valid),
    .cache_op_complete_seq_id(scalar_cache_op_complete_seq_id),
    .cache_op_complete_epoch(scalar_cache_op_complete_epoch),
    .clean_wb_valid(dcache_clean_wb_valid),
    .clean_wb_ready(dcache_clean_wb_ready),
    .clean_wb_addr(dcache_clean_wb_addr),
    .clean_wb_data(dcache_clean_wb_data),
    .clean_wb_last(dcache_clean_wb_last),
    .clean_wb_complete(dcache_clean_wb_complete),
    .refill_req_valid(dcache_refill_req_valid),
    .refill_req_ready(dcache_refill_req_ready),
    .refill_req_addr(dcache_refill_req_addr),
    .refill_resp_valid(dcache_refill_resp_valid),
    .refill_resp_ready(dcache_refill_resp_ready),
    .refill_resp_data(dcache_refill_resp_data),
    .refill_resp_last(dcache_refill_resp_last),
    .refill_resp_error(dcache_refill_resp_error),
    .debug_icache_bytes(dcache_debug_icache_bytes_unused),
`ifdef EDGE_DEBUG
    .debug_dcache_bytes(debug_dcache_bytes),
`else
    .debug_dcache_bytes(),
`endif
    .debug_load_pending(debug_dcache_load_pending),
    .debug_load_miss_pending(),
`ifdef EDGE_DEBUG
    .debug_store_fire(debug_dcache_store_fire),
`else
    .debug_store_fire(),
`endif
    .store_predict_phase(dcache_store_predict_phase),
    .store_predict_mem_active(dcache_store_predict_mem_active),
    .store_predict_backend_blocked(dcache_store_predict_backend_blocked),
`ifdef EDGE_DEBUG
    .debug_cache_op_fire(debug_dcache_cache_op_fire),
    .debug_cache_op_kind(debug_dcache_cache_op_kind),
    .debug_cache_op_is_va(debug_dcache_cache_op_is_va)
`else
    .debug_cache_op_fire(),
    .debug_cache_op_kind(),
    .debug_cache_op_is_va()
`endif
  );

  edge_retire_sync #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH)
  ) retire_sync (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .alloc0_valid(retire_sync_alloc0_valid),
    .alloc0_seq_id(retire_sync_alloc0_seq_id),
    .alloc0_epoch(retire_sync_alloc0_epoch),
    .alloc0_kind(retire_sync_alloc0_kind),
    .alloc0_serializing(retire_sync_alloc0_serializing),
    .alloc1_valid(retire_sync_alloc1_valid),
    .alloc1_seq_id(retire_sync_alloc1_seq_id),
    .alloc1_epoch(retire_sync_alloc1_epoch),
    .alloc1_kind(retire_sync_alloc1_kind),
    .alloc1_serializing(retire_sync_alloc1_serializing),
    .alloc_ready(retire_alloc_ready),
    .complete0_valid(retire_complete0_valid),
    .complete0_seq_id(retire_complete0_seq_id),
    .complete0_epoch(retire_complete0_epoch),
    .complete1_valid(retire_complete1_valid),
    .complete1_seq_id(retire_complete1_seq_id),
    .complete1_epoch(retire_complete1_epoch),
    .complete2_valid(retire_complete2_valid),
    .complete2_seq_id(retire_complete2_seq_id),
    .complete2_epoch(retire_complete2_epoch),
    .complete3_valid(retire_complete3_valid),
    .complete3_seq_id(retire_complete3_seq_id),
    .complete3_epoch(retire_complete3_epoch),
    .complete4_valid(retire_complete4_valid),
    .complete4_seq_id(retire_complete4_seq_id),
    .complete4_epoch(retire_complete4_epoch),
    .complete5_valid(scalar_retire_complete5_valid),
    .complete5_seq_id(scalar_retire_complete5_seq_id),
    .complete5_epoch(scalar_retire_complete5_epoch),
    .complete6_valid(1'b0),
    .complete6_seq_id({SEQ_ID_WIDTH{1'b0}}),
    .complete6_epoch({EPOCH_WIDTH{1'b0}}),
    .redirect_kill_valid(backend_redirect_kill_valid_q),
    .redirect_kill_seq_id(backend_redirect_kill_seq_id_q),
    .redirect_kill_epoch(backend_redirect_kill_epoch_q),
    .retire0_valid(retire0_valid),
    .retire0_seq_id(retire0_seq_id),
    .retire0_epoch(retire0_epoch),
    .retire0_kind(retire0_kind),
    .retire1_valid(retire1_valid),
    .retire1_seq_id(retire1_seq_id),
    .retire1_epoch(retire1_epoch),
    .retire1_kind(retire1_kind)
`ifdef EDGE_DEBUG
    ,
    .debug_valid(),
    .debug_done(),
    .debug_count(debug_retire_count)
`endif
  );

  edge_dtcm_subsys #(
    .AXI_ADDR_WIDTH(PC_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),
    .AXI_LEN_WIDTH(AXI_LEN_WIDTH),
    .DTCM_ADDR_WIDTH(14),
    .LSU_DATA_WIDTH(64)
  ) dtcm_subsys (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .mem_region_base(mem_region_base_q),
    .mem_region_mask(mem_region_mask_q),
    .mem_region_enable(mem_region_enable_q),
    .scalar_lsu_addr(dtcm_lsu_addr),
    .scalar_lsu_req(dtcm_lsu_req),
    .scalar_lsu_we(dtcm_lsu_we),
    .scalar_lsu_wdata(dtcm_lsu_wdata),
    .scalar_lsu_wstrb(dtcm_lsu_wstrb),
    .scalar_lsu_rdata(dtcm_lsu_rdata),
    .scalar_lsu_ready(dtcm_lsu_ready),
    .scalar_lsu_rvalid(dtcm_lsu_rvalid),
    .scalar_lsu_store_block(asic_store_block),
    .tensor_cmd_setcsr_dtype(tensor_cmd_setcsr_dtype[3:0]),
    .tensor_cmd_setcsr_req(tensor_cmd_setcsr_req),
    .tensor_cmd_setcsr_wtype(tensor_cmd_setcsr_wtype[3:0]),
    .tensor_cmd_setin_ptr(tensor_cmd_setin_ptr[15:0]),
    .tensor_cmd_setin_req(tensor_cmd_setin_req),
    .tensor_cmd_setn_req(tensor_cmd_setn_req),
    .tensor_cmd_setn_value(tensor_cmd_setn_value[15:0]),
    .tensor_cmd_setout_ptr(tensor_cmd_setout_ptr[15:0]),
    .tensor_cmd_setout_req(tensor_cmd_setout_req),
    .tensor_cmd_setpsum_ptr(tensor_cmd_setpsum_ptr[15:0]),
    .tensor_cmd_setpsum_req(tensor_cmd_setpsum_req),
    .tensor_cmd_start_req(tensor_cmd_start_req),
    .tensor_cmd_start_tile_req(tensor_cmd_start_tile_req),
    .tensor_cmd_start_mode(tensor_cmd_start_mode),
    .tensor_cmd_start_seq_id(tensor_issue_seq_id),
    .tensor_cmd_start_epoch(tensor_issue_epoch),
    .tensor_cmd_sync_req(tensor_cmd_sync_req),
    .tensor_cmd_wld_ptr(tensor_unit_cmd_wld_ptr[15:0]),
    .tensor_cmd_wld_req(tensor_unit_cmd_wld_req),
    .tensor_cmd_wld_trans_req(tensor_unit_cmd_wld_trans_req),
    .tensor_cmd_wld_reuse(tensor_unit_cmd_wld_reuse),
    .tensor_cmd_sld_ptr(tensor_unit_cmd_sld_ptr[15:0]),
    .tensor_cmd_sld_req(tensor_unit_cmd_sld_req),
    .tensor_cmd_sld_reuse(tensor_unit_cmd_sld_reuse),
    .tensor_cmd_sld_stream(tensor_unit_cmd_sld_stream),
    .tensor_cmd_sld_stream_setup_ptr(tensor_cmd_sld_stream_ptr),
    .tensor_cmd_sld_stream_setup_req(tensor_cmd_sld_stream_req),
    .tensor_busy(tensor_busy),
    .tensor_cmd_ready(tensor_cmd_ready),
    .tensor_start_ready(tensor_start_ready),
    .tensor_sync_stall(tensor_unit_sync_stall),
    .tensor_start_retire_valid(tensor_start_retire_valid),
    .tensor_start_retire_seq_id(tensor_start_retire_seq_id),
    .tensor_start_retire_epoch(tensor_start_retire_epoch),
    .tensor_wld_cmd_ready(tensor_wld_unit_cmd_ready),
    .tensor_sld_cmd_ready(tensor_sld_unit_cmd_ready),
    .tensor_sld_fill_done(tensor_sld_fill_done),
    .tensor_wld_fill_done(tensor_wld_fill_done),
    .tensor_wld_tile_words(tensor_wld_tile_words[4:0]),
    .actu_cmd_setcsr_dtype(actu_cmd_setcsr_dtype[3:0]),
    .actu_cmd_setcsr_mode(actu_cmd_setcsr_mode[3:0]),
    .actu_cmd_setcsr_req(actu_cmd_setcsr_req),
    .actu_cmd_setin_ptr(actu_cmd_setin_ptr[15:0]),
    .actu_cmd_setin_req(actu_cmd_setin_req),
    .actu_cmd_setn_req(actu_cmd_setn_req),
    .actu_cmd_setn_value(actu_cmd_setn_value[15:0]),
    .actu_cmd_setout_ptr(actu_cmd_setout_ptr[15:0]),
    .actu_cmd_setout_req(actu_cmd_setout_req),
    .actu_cmd_setscalar_req(actu_cmd_setscalar_req),
    .actu_cmd_setscalar_value(actu_cmd_setscalar_value[63:0]),
    .actu_cmd_start_req(actu_cmd_start_req),
    .actu_cmd_sync_req(actu_cmd_sync_req),
    .actu_cmd_ready(actu_cmd_ready),
    .actu_start_ready(actu_start_ready),
    .actu_sync_stall(actu_sync_stall),
    .actu_busy(actu_busy),
    .actu_last_sum_bits(actu_last_sum_bits),
    .cmpu_cmd_setcsr_mode(cmpu_cmd_setcsr_mode[3:0]),
    .cmpu_cmd_setcsr_req(cmpu_cmd_setcsr_req),
    .cmpu_cmd_setlhs_ptr(cmpu_cmd_setlhs_ptr[15:0]),
    .cmpu_cmd_setlhs_req(cmpu_cmd_setlhs_req),
    .cmpu_cmd_setrhs_ptr(cmpu_cmd_setrhs_ptr[15:0]),
    .cmpu_cmd_setrhs_req(cmpu_cmd_setrhs_req),
    .cmpu_cmd_setmask_ptr(cmpu_cmd_setmask_ptr[15:0]),
    .cmpu_cmd_setmask_req(cmpu_cmd_setmask_req),
    .cmpu_cmd_setout_ptr(cmpu_cmd_setout_ptr[15:0]),
    .cmpu_cmd_setout_req(cmpu_cmd_setout_req),
    .cmpu_cmd_setn_req(cmpu_cmd_setn_req),
    .cmpu_cmd_setn_value(cmpu_cmd_setn_value[15:0]),
    .cmpu_cmd_start_req(cmpu_cmd_start_req),
    .cmpu_cmd_sync_req(cmpu_cmd_sync_req),
    .cmpu_cmd_ready(cmpu_cmd_ready),
    .cmpu_start_ready(cmpu_start_ready),
    .cmpu_sync_stall(cmpu_sync_stall),
    .cmpu_busy(cmpu_busy),
    .cmpu_result_update(cmpu_result_update),
    .cmpu_max_value(cmpu_max_value[15:0]),
    .cmpu_argmax_idx(cmpu_argmax_idx[15:0]),
    .cmpu_min_value(cmpu_min_value[15:0]),
    .cmpu_argmin_idx(cmpu_argmin_idx[15:0]),
    .dma_start_addr_src(dtcm_dma_start_addr_src[PC_WIDTH-1:0]),
    .dma_start_addr_dst(dtcm_dma_start_addr_dst[PC_WIDTH-1:0]),
    .dma_start_len(dtcm_dma_start_len[31:0]),
    .dma_start_req(dtcm_dma_start_req),
    .dma_busy(edge_dma_busy),
    .dma_stream_cmd_valid(tensor_circular_dma_cmd_valid),
    .dma_stream_cmd_ready(dma_stream_cmd_ready),
    .dma_stream_cmd_axi_addr(tensor_circular_dma_src_addr[PC_WIDTH-1:0]),
    .dma_stream_cmd_dtcm_addr(
      tensor_circular_dma_dst_addr[18:3]),
    .dma_stream_beat_done(dma_stream_beat_done),
    .dma_stream_busy(dma_stream_busy),
    .tensor_io_lease_channel_mask(tensor_io_lease_channel_mask[7:0]),
    .tensor_io_lease_cycles(tensor_io_lease_cycles[8:0]),
    .tensor_io_lease_delay(tensor_io_lease_delay[3:0]),
    .tensor_io_lease1_channel_mask(tensor_io_lease1_channel_mask[7:0]),
    .tensor_io_lease1_cycles(tensor_io_lease1_cycles[8:0]),
    .tensor_io_lease1_delay(tensor_io_lease1_delay[3:0]),
    .tensor_io_lease1_valid(tensor_io_lease1_valid),
    .tensor_io_lease2_channel_mask(tensor_io_lease2_channel_mask[7:0]),
    .tensor_io_lease2_cycles(tensor_io_lease2_cycles[8:0]),
    .tensor_io_lease2_delay(tensor_io_lease2_delay[3:0]),
    .tensor_io_lease2_valid(tensor_io_lease2_valid),
    .tensor_io_lease_valid(tensor_io_lease_valid),
    .tensor_wld_lease_channel_mask(tensor_wld_lease_channel_mask[7:0]),
    .tensor_wld_lease_cycles(tensor_wld_lease_cycles[8:0]),
    .tensor_wld_lease_delay(tensor_wld_lease_delay[3:0]),
    .tensor_wld_lease_valid(tensor_wld_lease_valid),
    .dma_axi_araddr(dtcm_dma_araddr[PC_WIDTH-1:0]),
    .dma_axi_arburst(dtcm_dma_arburst[1:0]),
    .dma_axi_arcache(dtcm_dma_arcache[3:0]),
    .dma_axi_arid(dtcm_dma_arid[AXI_ID_WIDTH-1:0]),
    .dma_axi_arlen(dtcm_dma_arlen[AXI_LEN_WIDTH-1:0]),
    .dma_axi_arlock(dtcm_dma_arlock),
    .dma_axi_arprot(dtcm_dma_arprot[2:0]),
    .dma_axi_arsize(dtcm_dma_arsize[2:0]),
    .dma_axi_arvalid(dtcm_dma_arvalid),
    .dma_axi_arready(dtcm_dma_arready),
    .dma_axi_rdata(dtcm_dma_rdata[AXI_DATA_WIDTH-1:0]),
    .dma_axi_rlast(dtcm_dma_rlast),
    .dma_axi_rready(dtcm_dma_rready),
    .dma_axi_rvalid(dtcm_dma_rvalid),
    .dma_axi_awaddr(dtcm_dma_awaddr[PC_WIDTH-1:0]),
    .dma_axi_awburst(dtcm_dma_awburst[1:0]),
    .dma_axi_awcache(dtcm_dma_awcache[3:0]),
    .dma_axi_awid(dtcm_dma_awid[AXI_ID_WIDTH-1:0]),
    .dma_axi_awlen(dtcm_dma_awlen[AXI_LEN_WIDTH-1:0]),
    .dma_axi_awlock(dtcm_dma_awlock),
    .dma_axi_awprot(dtcm_dma_awprot[2:0]),
    .dma_axi_awsize(dtcm_dma_awsize[2:0]),
    .dma_axi_awvalid(dtcm_dma_awvalid),
    .dma_axi_awready(dtcm_dma_awready),
    .dma_axi_bvalid(dtcm_dma_bvalid),
    .dma_axi_bready(dtcm_dma_bready),
    .dma_axi_wdata(dtcm_dma_wdata[AXI_DATA_WIDTH-1:0]),
    .dma_axi_wlast(dtcm_dma_wlast),
    .dma_axi_wready(dtcm_dma_wready),
    .dma_axi_wstrb(dtcm_dma_wstrb[(AXI_DATA_WIDTH/8)-1:0]),
    .dma_axi_wvalid(dtcm_dma_wvalid)
  );

  edge_biu_top #(
    .ADDR_WIDTH(PC_WIDTH),
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_ID_WIDTH),
    .LEN_WIDTH(AXI_LEN_WIDTH)
  ) biu_top (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .core_araddr(biu_core_araddr),
    .core_arburst(biu_core_arburst),
    .core_arcache(biu_core_arcache),
    .core_arid(biu_core_arid),
    .core_arlen(biu_core_arlen),
    .core_arlock(biu_core_arlock),
    .core_arprot(biu_core_arprot),
    .core_arsize(biu_core_arsize),
    .core_arvalid(biu_core_arvalid),
    .core_arready(biu_core_arready),
    .core_rdata(biu_core_rdata),
    .core_rid(biu_core_rid),
    .core_rlast(biu_core_rlast),
    .core_rready(biu_core_rready),
    .core_rresp(biu_core_rresp),
    .core_rvalid(biu_core_rvalid),
    .core_awaddr(biu_core_awaddr),
    .core_awburst(biu_core_awburst),
    .core_awcache(biu_core_awcache),
    .core_awid(biu_core_awid),
    .core_awlen(biu_core_awlen),
    .core_awlock(biu_core_awlock),
    .core_awprot(biu_core_awprot),
    .core_awsize(biu_core_awsize),
    .core_awvalid(biu_core_awvalid),
    .core_awready(biu_core_awready),
    .core_bid(biu_core_bid),
    .core_bready(biu_core_bready),
    .core_bresp(biu_core_bresp),
    .core_bvalid(biu_core_bvalid),
    .core_wdata(biu_core_wdata),
    .core_wlast(biu_core_wlast),
    .core_wready(biu_core_wready),
    .core_wstrb(biu_core_wstrb),
    .core_wvalid(biu_core_wvalid),
    .dma_araddr(biu_dma_araddr),
    .dma_arburst(biu_dma_arburst),
    .dma_arcache(biu_dma_arcache),
    .dma_arid(biu_dma_arid),
    .dma_arlen(biu_dma_arlen),
    .dma_arlock(biu_dma_arlock),
    .dma_arprot(biu_dma_arprot),
    .dma_arsize(biu_dma_arsize),
    .dma_arvalid(biu_dma_arvalid),
    .dma_arready(biu_dma_arready),
    .dma_rdata(biu_dma_rdata),
    .dma_rid(biu_dma_rid),
    .dma_rlast(biu_dma_rlast),
    .dma_rready(biu_dma_rready),
    .dma_rresp(biu_dma_rresp),
    .dma_rvalid(biu_dma_rvalid),
    .dma_awaddr(biu_dma_awaddr),
    .dma_awburst(biu_dma_awburst),
    .dma_awcache(biu_dma_awcache),
    .dma_awid(biu_dma_awid),
    .dma_awlen(biu_dma_awlen),
    .dma_awlock(biu_dma_awlock),
    .dma_awprot(biu_dma_awprot),
    .dma_awsize(biu_dma_awsize),
    .dma_awvalid(biu_dma_awvalid),
    .dma_awready(biu_dma_awready),
    .dma_bid(biu_dma_bid),
    .dma_bready(biu_dma_bready),
    .dma_bresp(biu_dma_bresp),
    .dma_bvalid(biu_dma_bvalid),
    .dma_wdata(biu_dma_wdata),
    .dma_wlast(biu_dma_wlast),
    .dma_wready(biu_dma_wready),
    .dma_wstrb(biu_dma_wstrb),
    .dma_wvalid(biu_dma_wvalid),
    .pad_araddr(biu_pad_araddr),
    .pad_arburst(biu_pad_arburst),
    .pad_arcache(biu_pad_arcache),
    .pad_arid(biu_pad_arid),
    .pad_arlen(biu_pad_arlen),
    .pad_arlock(biu_pad_arlock),
    .pad_arprot(biu_pad_arprot),
    .pad_arready(pad_biu_arready),
    .pad_arsize(biu_pad_arsize),
    .pad_arvalid(biu_pad_arvalid),
    .pad_rdata(pad_biu_rdata),
    .pad_rid(pad_biu_rid),
    .pad_rlast(pad_biu_rlast),
    .pad_rready(biu_pad_rready),
    .pad_rresp(pad_biu_rresp),
    .pad_rvalid(pad_biu_rvalid),
    .pad_awaddr(biu_pad_awaddr),
    .pad_awburst(biu_pad_awburst),
    .pad_awcache(biu_pad_awcache),
    .pad_awid(biu_pad_awid),
    .pad_awlen(biu_pad_awlen),
    .pad_awlock(biu_pad_awlock),
    .pad_awprot(biu_pad_awprot),
    .pad_awready(pad_biu_awready),
    .pad_awsize(biu_pad_awsize),
    .pad_awvalid(biu_pad_awvalid),
    .pad_bid(pad_biu_bid),
    .pad_bready(biu_pad_bready),
    .pad_bresp(pad_biu_bresp),
    .pad_bvalid(pad_biu_bvalid),
    .pad_wdata(biu_pad_wdata),
    .pad_wlast(biu_pad_wlast),
    .pad_wready(pad_biu_wready),
    .pad_wstrb(biu_pad_wstrb),
    .pad_wvalid(biu_pad_wvalid),
`ifdef EDGE_DEBUG
    .debug_read_owner_valid(debug_biu_read_owner_valid),
    .debug_read_owner_dma(debug_biu_read_owner_dma),
    .debug_write_owner_valid(debug_biu_write_owner_valid),
    .debug_write_owner_dma(debug_biu_write_owner_dma)
`else
    .debug_read_owner_valid(),
    .debug_read_owner_dma(),
    .debug_write_owner_valid(),
    .debug_write_owner_dma()
`endif
  );

  assign scalar_csr_break_valid =
    scalar_system_placeholder_valid &&
    (scalar_system_placeholder_funct3 == 3'b001) &&
    (scalar_system_placeholder_csr == EDGE_CSR_BREAK_ID) &&
    (scalar_system_placeholder_rd == {REG_INDEX_WIDTH{1'b0}}) &&
    (scalar_system_placeholder_rs1 != {REG_INDEX_WIDTH{1'b0}});
  assign scalar_csr_break_code = scalar_system_placeholder_rs1_value;
  assign scalar_csr_break_seq_id = scalar_system_placeholder_seq_id;
  assign scalar_csr_break_epoch = scalar_system_placeholder_epoch;
  assign scalar_csr_putchar_valid =
    scalar_system_placeholder_valid &&
    (scalar_system_placeholder_funct3 == 3'b001) &&
    (scalar_system_placeholder_csr == EDGE_CSR_PUTCHAR_ID) &&
    (scalar_system_placeholder_rd == {REG_INDEX_WIDTH{1'b0}}) &&
    (scalar_system_placeholder_rs1 != {REG_INDEX_WIDTH{1'b0}});
  assign scalar_csr_putchar_char = scalar_system_placeholder_rs1_value[7:0];

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      mem_region_base_q <= mem_region_base;
      mem_region_mask_q <= mem_region_mask;
      mem_region_enable_q <= mem_region_enable;
    end else if (scalar_system_placeholder_valid &&
                 (scalar_system_placeholder_funct3 == 3'b001)) begin
      case (scalar_system_placeholder_csr)
        EDGE_CSR_DTCM_BASE_ID:
          mem_region_base_q <= scalar_system_placeholder_rs1_value[PC_WIDTH-1:0];
        EDGE_CSR_DTCM_MASK_ID:
          mem_region_mask_q <= scalar_system_placeholder_rs1_value[PC_WIDTH-1:0];
        EDGE_CSR_DTCM_CTRL_ID:
          mem_region_enable_q <= scalar_system_placeholder_rs1_value[0];
        default: begin end
      endcase
    end
  end

  wire unused_token1 = shim_decode_illegal;

endmodule
