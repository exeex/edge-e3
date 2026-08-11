module edge_lite_accel_platform #(
  parameter AXI_ADDR_WIDTH=40,parameter AXI_DATA_WIDTH=128,
  parameter AXI_ID_WIDTH=8,parameter AXI_LEN_WIDTH=8
)(
  input wire forever_cpuclk,input wire cpurst_b,
  input wire [AXI_ADDR_WIDTH-1:0] mem_region_base,input wire [AXI_ADDR_WIDTH-1:0] mem_region_mask,
  input wire mem_region_enable,input wire req_valid,output wire req_ready,
  input wire [63:0] req_inst,input wire [63:0] req_capture_value,
  output wire resp_valid,output wire resp_error,output wire [63:0] resp_value,
  input wire [13:0] scalar_lsu_addr,input wire scalar_lsu_req,input wire scalar_lsu_we,
  input wire [63:0] scalar_lsu_wdata,input wire [7:0] scalar_lsu_wstrb,
  output wire [63:0] scalar_lsu_rdata,output wire scalar_lsu_ready,output wire scalar_lsu_rvalid,
  output wire [AXI_ADDR_WIDTH-1:0] dma_axi_araddr,output wire [1:0] dma_axi_arburst,
  output wire [3:0] dma_axi_arcache,output wire [AXI_ID_WIDTH-1:0] dma_axi_arid,
  output wire [AXI_LEN_WIDTH-1:0] dma_axi_arlen,output wire dma_axi_arlock,
  output wire [2:0] dma_axi_arprot,output wire [2:0] dma_axi_arsize,
  output wire dma_axi_arvalid,input wire dma_axi_arready,
  input wire [AXI_DATA_WIDTH-1:0] dma_axi_rdata,input wire dma_axi_rlast,
  output wire dma_axi_rready,input wire dma_axi_rvalid,
  output wire [AXI_ADDR_WIDTH-1:0] dma_axi_awaddr,output wire [1:0] dma_axi_awburst,
  output wire [3:0] dma_axi_awcache,output wire [AXI_ID_WIDTH-1:0] dma_axi_awid,
  output wire [AXI_LEN_WIDTH-1:0] dma_axi_awlen,output wire dma_axi_awlock,
  output wire [2:0] dma_axi_awprot,output wire [2:0] dma_axi_awsize,
  output wire dma_axi_awvalid,input wire dma_axi_awready,input wire dma_axi_bvalid,
  output wire dma_axi_bready,output wire [AXI_DATA_WIDTH-1:0] dma_axi_wdata,
  output wire dma_axi_wlast,input wire dma_axi_wready,
  output wire [(AXI_DATA_WIDTH/8)-1:0] dma_axi_wstrb,output wire dma_axi_wvalid,
  output wire tensor_busy,output wire actu_busy,output wire cmpu_busy,output wire dma_busy
);
  wire [3:0] tensor_cmd_setcsr_dtype,tensor_cmd_setcsr_wtype;
  wire tensor_cmd_setcsr_req,tensor_cmd_setin_req,tensor_cmd_setn_req;
  wire tensor_cmd_setout_req,tensor_cmd_setpsum_req,tensor_cmd_start_req;
  wire tensor_cmd_start_tile_req,tensor_cmd_sync_req,tensor_cmd_wld_req;
  wire tensor_cmd_wld_trans_req,tensor_cmd_wld_reuse,tensor_cmd_sld_req;
  wire tensor_cmd_sld_reuse,tensor_cmd_sld_stream_setup_req;
  wire [15:0] tensor_cmd_setin_ptr,tensor_cmd_setn_value,tensor_cmd_setout_ptr;
  wire [15:0] tensor_cmd_setpsum_ptr,tensor_cmd_wld_ptr,tensor_cmd_sld_ptr;
  wire [15:0] tensor_cmd_sld_stream_setup_ptr; wire [7:0] tensor_cmd_start_mode;
  wire tensor_cmd_ready,tensor_start_ready,tensor_sync_stall;
  wire tensor_wld_cmd_ready,tensor_sld_cmd_ready;
  wire [3:0] actu_cmd_setcsr_dtype,actu_cmd_setcsr_mode;
  wire actu_cmd_setcsr_req,actu_cmd_setin_req,actu_cmd_setn_req;
  wire actu_cmd_setout_req,actu_cmd_setscalar_req,actu_cmd_start_req,actu_cmd_sync_req;
  wire [15:0] actu_cmd_setin_ptr,actu_cmd_setn_value,actu_cmd_setout_ptr;
  wire [63:0] actu_cmd_setscalar_value; wire actu_cmd_ready,actu_start_ready,actu_sync_stall;
  wire [31:0] actu_last_sum_bits;
  wire [3:0] cmpu_cmd_setcsr_mode; wire cmpu_cmd_setcsr_req,cmpu_cmd_setlhs_req;
  wire cmpu_cmd_setrhs_req,cmpu_cmd_setmask_req,cmpu_cmd_setout_req;
  wire cmpu_cmd_setn_req,cmpu_cmd_start_req,cmpu_cmd_sync_req;
  wire [15:0] cmpu_cmd_setlhs_ptr,cmpu_cmd_setrhs_ptr,cmpu_cmd_setmask_ptr;
  wire [15:0] cmpu_cmd_setout_ptr,cmpu_cmd_setn_value;
  wire cmpu_cmd_ready,cmpu_start_ready,cmpu_sync_stall;
  wire [15:0] cmpu_max_value,cmpu_argmax_idx,cmpu_min_value,cmpu_argmin_idx;
  wire dma_start_req,dma_sync_req; wire [63:0] dma_start_src,dma_start_dst;
  wire [31:0] dma_start_len;
  wire [AXI_ADDR_WIDTH-1:0] dma_start_addr_src=dma_start_src[AXI_ADDR_WIDTH-1:0];
  wire [AXI_ADDR_WIDTH-1:0] dma_start_addr_dst=dma_start_dst[AXI_ADDR_WIDTH-1:0];
  wire scalar_lsu_store_block=1'b0;
  wire [7:0] tensor_cmd_start_seq_id=8'b0; wire [3:0] tensor_cmd_start_epoch=4'b0;
  wire tensor_cmd_sld_stream=1'b0;
  wire dma_stream_cmd_valid=1'b0; wire [AXI_ADDR_WIDTH-1:0] dma_stream_cmd_axi_addr={AXI_ADDR_WIDTH{1'b0}};
  wire [13:0] dma_stream_cmd_dtcm_addr=14'b0;
  wire tensor_start_retire_valid,tensor_sld_fill_done,tensor_wld_fill_done;
  wire [7:0] tensor_start_retire_seq_id; wire [3:0] tensor_start_retire_epoch;
  wire [4:0] tensor_wld_tile_words; wire cmpu_result_update;
  wire dma_stream_cmd_ready,dma_stream_beat_done,dma_stream_busy;
  wire [7:0] tensor_io_lease_channel_mask,tensor_io_lease1_channel_mask;
  wire [7:0] tensor_io_lease2_channel_mask,tensor_wld_lease_channel_mask;
  wire [8:0] tensor_io_lease_cycles,tensor_io_lease1_cycles;
  wire [8:0] tensor_io_lease2_cycles,tensor_wld_lease_cycles;
  wire [3:0] tensor_io_lease_delay,tensor_io_lease1_delay;
  wire [3:0] tensor_io_lease2_delay,tensor_wld_lease_delay;
  wire tensor_io_lease1_valid,tensor_io_lease2_valid,tensor_io_lease_valid;
  wire tensor_wld_lease_valid;
  reg tensor_start_ready_q,actu_start_ready_q,cmpu_start_ready_q;
  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if(!cpurst_b) begin
      tensor_start_ready_q<=1'b0; actu_start_ready_q<=1'b0; cmpu_start_ready_q<=1'b0;
    end else begin
      tensor_start_ready_q<=tensor_start_ready;
      actu_start_ready_q<=actu_start_ready;
      cmpu_start_ready_q<=cmpu_start_ready;
    end
  end

  edge_lite_accel_dispatch dispatch(
    .clk(forever_cpuclk),.reset_n(cpurst_b),.mem_region_base(mem_region_base),
    .mem_region_mask(mem_region_mask),.mem_region_enable(mem_region_enable),
    .req_valid(req_valid),.req_ready(req_ready),.req_inst(req_inst),
    .req_capture_value(req_capture_value),.resp_valid(resp_valid),
    .resp_error(resp_error),.resp_value(resp_value),.dma_start_ready(!dma_busy),
    .dma_sync_done(!dma_busy),.tensor_cmd_ready(tensor_cmd_ready),
    .tensor_start_ready(tensor_start_ready_q),.tensor_wld_cmd_ready(tensor_wld_cmd_ready),
    .tensor_sld_cmd_ready(tensor_sld_cmd_ready),.tensor_sync_stall(tensor_sync_stall),
    .actu_cmd_ready(actu_cmd_ready),.actu_start_ready(actu_start_ready_q),
    .actu_sync_stall(actu_sync_stall),.cmpu_cmd_ready(cmpu_cmd_ready),
    .cmpu_start_ready(cmpu_start_ready_q),.cmpu_sync_stall(cmpu_sync_stall),
    .actu_last_sum_bits(actu_last_sum_bits),.cmpu_max_value(cmpu_max_value),
    .cmpu_argmax_idx(cmpu_argmax_idx),.cmpu_min_value(cmpu_min_value),
    .cmpu_argmin_idx(cmpu_argmin_idx),.dma_start_req(dma_start_req),
    .dma_start_src(dma_start_src),.dma_start_dst(dma_start_dst),
    .dma_start_len(dma_start_len),.dma_sync_req(dma_sync_req),
    .cmd_setcsr_dtype(tensor_cmd_setcsr_dtype),.cmd_setcsr_req(tensor_cmd_setcsr_req),
    .cmd_setcsr_wtype(tensor_cmd_setcsr_wtype),.cmd_setin_ptr(tensor_cmd_setin_ptr),
    .cmd_setin_req(tensor_cmd_setin_req),.cmd_setn_req(tensor_cmd_setn_req),
    .cmd_setn_value(tensor_cmd_setn_value),.cmd_setout_ptr(tensor_cmd_setout_ptr),
    .cmd_setout_req(tensor_cmd_setout_req),.cmd_setpsum_ptr(tensor_cmd_setpsum_ptr),
    .cmd_setpsum_req(tensor_cmd_setpsum_req),.cmd_start_req(tensor_cmd_start_req),
    .cmd_start_tile_req(tensor_cmd_start_tile_req),.cmd_start_mode(tensor_cmd_start_mode),
    .cmd_sync_req(tensor_cmd_sync_req),.cmd_wld_ptr(tensor_cmd_wld_ptr),
    .cmd_wld_req(tensor_cmd_wld_req),.cmd_wld_trans_req(tensor_cmd_wld_trans_req),
    .cmd_wld_reuse(tensor_cmd_wld_reuse),.cmd_sld_ptr(tensor_cmd_sld_ptr),
    .cmd_sld_req(tensor_cmd_sld_req),.cmd_sld_reuse(tensor_cmd_sld_reuse),
    .cmd_sld_stream_ptr(tensor_cmd_sld_stream_setup_ptr),
    .cmd_sld_stream_req(tensor_cmd_sld_stream_setup_req),
    .actu_cmd_setcsr_dtype(actu_cmd_setcsr_dtype),.actu_cmd_setcsr_mode(actu_cmd_setcsr_mode),
    .actu_cmd_setcsr_req(actu_cmd_setcsr_req),.actu_cmd_setin_ptr(actu_cmd_setin_ptr),
    .actu_cmd_setin_req(actu_cmd_setin_req),.actu_cmd_setn_req(actu_cmd_setn_req),
    .actu_cmd_setn_value(actu_cmd_setn_value),.actu_cmd_setout_ptr(actu_cmd_setout_ptr),
    .actu_cmd_setout_req(actu_cmd_setout_req),.actu_cmd_setscalar_req(actu_cmd_setscalar_req),
    .actu_cmd_setscalar_value(actu_cmd_setscalar_value),.actu_cmd_start_req(actu_cmd_start_req),
    .actu_cmd_sync_req(actu_cmd_sync_req),.cmpu_cmd_setcsr_mode(cmpu_cmd_setcsr_mode),
    .cmpu_cmd_setcsr_req(cmpu_cmd_setcsr_req),.cmpu_cmd_setlhs_ptr(cmpu_cmd_setlhs_ptr),
    .cmpu_cmd_setlhs_req(cmpu_cmd_setlhs_req),.cmpu_cmd_setrhs_ptr(cmpu_cmd_setrhs_ptr),
    .cmpu_cmd_setrhs_req(cmpu_cmd_setrhs_req),.cmpu_cmd_setmask_ptr(cmpu_cmd_setmask_ptr),
    .cmpu_cmd_setmask_req(cmpu_cmd_setmask_req),.cmpu_cmd_setout_ptr(cmpu_cmd_setout_ptr),
    .cmpu_cmd_setout_req(cmpu_cmd_setout_req),.cmpu_cmd_setn_req(cmpu_cmd_setn_req),
    .cmpu_cmd_setn_value(cmpu_cmd_setn_value),.cmpu_cmd_start_req(cmpu_cmd_start_req),
    .cmpu_cmd_sync_req(cmpu_cmd_sync_req));

  /* verilator lint_off PINMISSING */
  edge_dtcm_subsys #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),.AXI_LEN_WIDTH(AXI_LEN_WIDTH)) dtcm(.*);
  /* verilator lint_on PINMISSING */
endmodule
