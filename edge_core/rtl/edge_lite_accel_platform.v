module edge_lite_accel_platform #(
  parameter AXI_ADDR_WIDTH=40,parameter AXI_DATA_WIDTH=128,
  parameter AXI_ID_WIDTH=8,parameter AXI_LEN_WIDTH=8,
  parameter DTCM_ADDR_WIDTH=14,parameter DTCM_SRAM_ADDR_WIDTH=10,
  parameter DTCM_SEGMENT_NUM=1
)(
  input wire forever_cpuclk,input wire cpurst_b,
  input wire [AXI_ADDR_WIDTH-1:0] mem_region_base,input wire [AXI_ADDR_WIDTH-1:0] mem_region_mask,
  input wire mem_region_enable,input wire req_valid,output wire req_ready,
  input wire [63:0] req_inst,input wire [63:0] req_capture_value,
  output wire resp_valid,output wire resp_error,output wire [63:0] resp_value,
  input wire [DTCM_ADDR_WIDTH-1:0] scalar_lsu_addr,
  input wire scalar_lsu_req,input wire scalar_lsu_we,
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
  output wire tensor_busy,output wire actu_busy,output wire cmpu_busy,output wire dma_busy,
  output wire asic_ready_o
);
  localparam [6:0] ASIC_POWER=7'h09;
  wire [6:0] req_subop=req_inst[38:32];
  wire req_is_power=req_inst[39]&&(req_subop==ASIC_POWER);
  wire req_power_on=req_inst[56];
  wire dispatch_req_ready,dispatch_resp_valid,dispatch_resp_error;
  wire [63:0] dispatch_resp_value;
  reg asic_ready_q,power_resp_q,power_off_pending_q;
  wire all_accel_idle=!tensor_busy&&!actu_busy&&!cmpu_busy&&!dma_busy;
  assign asic_ready_o=asic_ready_q;
  assign req_ready=req_is_power?!power_off_pending_q:
                   (asic_ready_q&&dispatch_req_ready);
  assign resp_valid=power_resp_q||dispatch_resp_valid;
  assign resp_error=power_resp_q?1'b0:dispatch_resp_error;
  assign resp_value=power_resp_q?64'b0:dispatch_resp_value;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if(!cpurst_b) begin
      asic_ready_q<=1'b0; power_resp_q<=1'b0; power_off_pending_q<=1'b0;
    end else begin
      power_resp_q<=1'b0;
      if(req_valid&&req_ready&&req_is_power) begin
        if(req_power_on) begin
          asic_ready_q<=1'b1; power_resp_q<=1'b1;
        end else if(!asic_ready_q) power_resp_q<=1'b1;
        else if(all_accel_idle) begin
          asic_ready_q<=1'b0; power_resp_q<=1'b1;
        end else power_off_pending_q<=1'b1;
      end
      if(power_off_pending_q&&all_accel_idle) begin
        asic_ready_q<=1'b0; power_off_pending_q<=1'b0; power_resp_q<=1'b1;
      end
    end
  end
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
  wire tensor_unit_sync_stall,tensor_wld_unit_cmd_ready,tensor_sld_unit_cmd_ready;
  wire tensor_wld_cmd_ready,tensor_sld_cmd_ready;
  wire tensor_wld_circular_ready,tensor_wsld_circular_ready;
  wire tensor_sld_circular_ready;
  wire tensor_cmd_wld_circular_req,tensor_cmd_wsld_circular_req;
  wire tensor_cmd_wsld_circular_transpose,tensor_cmd_sld_circular_req;
  wire [15:0] tensor_unit_cmd_wld_ptr,tensor_unit_cmd_sld_ptr;
  wire tensor_unit_cmd_wld_req,tensor_unit_cmd_wld_trans_req;
  wire tensor_unit_cmd_wld_reuse,tensor_unit_cmd_sld_req;
  wire tensor_unit_cmd_sld_reuse,tensor_unit_cmd_sld_stream;
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
  wire dma_start_req,dma_start_circular_req,dma_sync_req;
  wire [63:0] dma_start_src,dma_start_dst,dma_start_x,dma_start_y;
  wire [31:0] dma_start_len,dma_start_entry_bytes;
  wire [15:0] dma_start_circular_tiles;
  wire dma_start_use_xy,dma_start_circular;
  wire dma_start_ready,dma_start_circular_ready,dma_sync_done;
  wire [AXI_ADDR_WIDTH-1:0] dma_start_addr_src,dma_start_addr_dst;
  wire [31:0] dtcm_dma_start_len;
  wire dtcm_dma_start_req,accel_dma_active;
  wire scalar_lsu_store_block=1'b0;
  wire [7:0] tensor_cmd_start_seq_id=8'b0; wire [3:0] tensor_cmd_start_epoch=4'b0;
  wire tensor_cmd_sld_stream;
  wire dma_stream_cmd_valid; wire [AXI_ADDR_WIDTH-1:0] dma_stream_cmd_axi_addr;
  wire [15:0] dma_stream_cmd_dtcm_addr;
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
    .req_valid(req_valid&&!req_is_power&&asic_ready_q),
    .req_ready(dispatch_req_ready),.req_inst(req_inst),
    .req_capture_value(req_capture_value),.resp_valid(dispatch_resp_valid),
    .resp_error(dispatch_resp_error),.resp_value(dispatch_resp_value),.dma_start_ready(dma_start_ready),
    .dma_start_circular_ready(dma_start_circular_ready),
    .dma_sync_done(dma_sync_done),.tensor_cmd_ready(tensor_cmd_ready),
    .tensor_start_ready(tensor_start_ready_q),.tensor_wld_cmd_ready(tensor_wld_cmd_ready),
    .tensor_sld_cmd_ready(tensor_sld_cmd_ready),
    .tensor_wld_circular_ready(tensor_wld_circular_ready),
    .tensor_wsld_circular_ready(tensor_wsld_circular_ready),
    .tensor_sld_circular_ready(tensor_sld_circular_ready),
    .tensor_sync_stall(tensor_sync_stall),
    .actu_cmd_ready(actu_cmd_ready),.actu_start_ready(actu_start_ready_q),
    .actu_sync_stall(actu_sync_stall),.cmpu_cmd_ready(cmpu_cmd_ready),
    .cmpu_start_ready(cmpu_start_ready_q),.cmpu_sync_stall(cmpu_sync_stall),
    .actu_last_sum_bits(actu_last_sum_bits),.cmpu_max_value(cmpu_max_value),
    .cmpu_argmax_idx(cmpu_argmax_idx),.cmpu_min_value(cmpu_min_value),
    .cmpu_argmin_idx(cmpu_argmin_idx),.dma_start_req(dma_start_req),
    .dma_start_src(dma_start_src),.dma_start_dst(dma_start_dst),
    .dma_start_len(dma_start_len),.dma_sync_req(dma_sync_req),
    .dma_start_circular_req(dma_start_circular_req),
    .dma_start_entry_bytes(dma_start_entry_bytes),
    .dma_start_circular_tiles(dma_start_circular_tiles),
    .dma_start_use_xy(dma_start_use_xy),.dma_start_circular(dma_start_circular),
    .dma_start_x(dma_start_x),.dma_start_y(dma_start_y),
    .cmd_setcsr_dtype(tensor_cmd_setcsr_dtype),.cmd_setcsr_req(tensor_cmd_setcsr_req),
    .cmd_setcsr_wtype(tensor_cmd_setcsr_wtype),.cmd_setin_ptr(tensor_cmd_setin_ptr),
    .cmd_setin_req(tensor_cmd_setin_req),.cmd_setn_req(tensor_cmd_setn_req),
    .cmd_setn_value(tensor_cmd_setn_value),.cmd_setout_ptr(tensor_cmd_setout_ptr),
    .cmd_setout_req(tensor_cmd_setout_req),.cmd_setpsum_ptr(tensor_cmd_setpsum_ptr),
    .cmd_setpsum_req(tensor_cmd_setpsum_req),.cmd_start_req(tensor_cmd_start_req),
    .cmd_start_tile_req(tensor_cmd_start_tile_req),.cmd_start_mode(tensor_cmd_start_mode),
    .cmd_sync_req(tensor_cmd_sync_req),.cmd_wld_ptr(tensor_cmd_wld_ptr),
    .cmd_wld_req(tensor_cmd_wld_req),.cmd_wld_trans_req(tensor_cmd_wld_trans_req),
    .cmd_wld_reuse(tensor_cmd_wld_reuse),
    .cmd_wld_circular_req(tensor_cmd_wld_circular_req),
    .cmd_sld_ptr(tensor_cmd_sld_ptr),
    .cmd_sld_req(tensor_cmd_sld_req),.cmd_sld_reuse(tensor_cmd_sld_reuse),
    .cmd_sld_stream_ptr(tensor_cmd_sld_stream_setup_ptr),
    .cmd_sld_stream_req(tensor_cmd_sld_stream_setup_req),
    .cmd_wsld_circular_req(tensor_cmd_wsld_circular_req),
    .cmd_wsld_circular_transpose(tensor_cmd_wsld_circular_transpose),
    .cmd_sld_circular_req(tensor_cmd_sld_circular_req),
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

  edge_accel_data_ctrl #(.ADDR_WIDTH(AXI_ADDR_WIDTH),.VALUE_WIDTH(64)) data_ctrl(
    .forever_cpuclk(forever_cpuclk),.cpurst_b(cpurst_b),
    .mem_region_base(mem_region_base),
    .edge_start_req(1'b0),.edge_start_src({AXI_ADDR_WIDTH{1'b0}}),
    .edge_start_dst({AXI_ADDR_WIDTH{1'b0}}),.edge_start_len(32'b0),
    .scalar_start_valid(1'b0),.scalar_start_src(64'b0),
    .scalar_start_dst(64'b0),.scalar_start_len(64'b0),
    .tensor_dma_start_req(dma_start_req),
    .tensor_dma_start_circular_req(dma_start_circular_req),
    .tensor_dma_start_src(dma_start_src),.tensor_dma_start_dst(dma_start_dst),
    .tensor_dma_start_len(dma_start_len),
    .tensor_dma_start_entry_bytes(dma_start_entry_bytes),
    .tensor_dma_start_circular_tiles(dma_start_circular_tiles),
    .tensor_dma_start_use_xy(dma_start_use_xy),
    .tensor_dma_start_circular(dma_start_circular),
    .tensor_dma_start_x(dma_start_x),.tensor_dma_start_y(dma_start_y),
    .edge_dma_busy(dma_busy),.dma_stream_cmd_ready(dma_stream_cmd_ready),
    .dma_stream_beat_done(dma_stream_beat_done),.dma_stream_busy(dma_stream_busy),
    .tensor_cmd_wld_req(tensor_cmd_wld_req),
    .tensor_cmd_wld_circular_req(tensor_cmd_wld_circular_req),
    .tensor_cmd_wld_trans_req(tensor_cmd_wld_trans_req),
    .tensor_cmd_wld_reuse(tensor_cmd_wld_reuse),.tensor_cmd_wld_ptr(tensor_cmd_wld_ptr),
    .tensor_cmd_wsld_circular_req(tensor_cmd_wsld_circular_req),
    .tensor_cmd_wsld_circular_transpose(tensor_cmd_wsld_circular_transpose),
    .tensor_cmd_sld_req(tensor_cmd_sld_req),
    .tensor_cmd_sld_circular_req(tensor_cmd_sld_circular_req),
    .tensor_cmd_sld_reuse(tensor_cmd_sld_reuse),.tensor_cmd_sld_ptr(tensor_cmd_sld_ptr),
    .tensor_unit_sync_stall(tensor_unit_sync_stall),
    .tensor_wld_unit_cmd_ready(tensor_wld_unit_cmd_ready),
    .tensor_sld_unit_cmd_ready(tensor_sld_unit_cmd_ready),
    .tensor_wld_fill_done(tensor_wld_fill_done),
    .tensor_sld_fill_done(tensor_sld_fill_done),
    .tensor_wld_tile_words(tensor_wld_tile_words),
    .tensor_start_retire_valid(tensor_start_retire_valid),
    .dma_start_ready(dma_start_ready),
    .dma_start_circular_ready(dma_start_circular_ready),
    .dma_sync_done(dma_sync_done),.dma_active(accel_dma_active),
    .scalar_start_ready(),.scalar_sync_ready(),
    .dtcm_dma_start_req(dtcm_dma_start_req),
    .dtcm_dma_start_src(dma_start_addr_src),
    .dtcm_dma_start_dst(dma_start_addr_dst),
    .dtcm_dma_start_len(dtcm_dma_start_len),
    .dma_stream_cmd_valid(dma_stream_cmd_valid),
    .dma_stream_cmd_axi_addr(dma_stream_cmd_axi_addr),
    .dma_stream_cmd_dtcm_addr(dma_stream_cmd_dtcm_addr),
    .tensor_wld_cmd_ready(tensor_wld_cmd_ready),
    .tensor_sld_cmd_ready(tensor_sld_cmd_ready),
    .tensor_wld_circular_ready(tensor_wld_circular_ready),
    .tensor_wsld_circular_ready(tensor_wsld_circular_ready),
    .tensor_sld_circular_ready(tensor_sld_circular_ready),
    .tensor_sync_stall(tensor_sync_stall),
    .tensor_unit_cmd_wld_ptr(tensor_unit_cmd_wld_ptr),
    .tensor_unit_cmd_wld_req(tensor_unit_cmd_wld_req),
    .tensor_unit_cmd_wld_trans_req(tensor_unit_cmd_wld_trans_req),
    .tensor_unit_cmd_wld_reuse(tensor_unit_cmd_wld_reuse),
    .tensor_unit_cmd_sld_ptr(tensor_unit_cmd_sld_ptr),
    .tensor_unit_cmd_sld_req(tensor_unit_cmd_sld_req),
    .tensor_unit_cmd_sld_reuse(tensor_unit_cmd_sld_reuse),
    .tensor_unit_cmd_sld_stream(tensor_unit_cmd_sld_stream));

  /* verilator lint_off PINMISSING */
  edge_dtcm_subsys #(.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),.AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH),.AXI_LEN_WIDTH(AXI_LEN_WIDTH),
    .DTCM_ADDR_WIDTH(DTCM_ADDR_WIDTH),.SRAM_ADDR_WIDTH(DTCM_SRAM_ADDR_WIDTH),
    .SEGMENT_NUM(DTCM_SEGMENT_NUM)) dtcm(
    .tensor_cmd_wld_ptr(tensor_unit_cmd_wld_ptr),
    .tensor_cmd_wld_req(tensor_unit_cmd_wld_req),
    .tensor_cmd_wld_trans_req(tensor_unit_cmd_wld_trans_req),
    .tensor_cmd_wld_reuse(tensor_unit_cmd_wld_reuse),
    .tensor_cmd_sld_ptr(tensor_unit_cmd_sld_ptr),
    .tensor_cmd_sld_req(tensor_unit_cmd_sld_req),
    .tensor_cmd_sld_reuse(tensor_unit_cmd_sld_reuse),
    .tensor_cmd_sld_stream(tensor_unit_cmd_sld_stream),
    .tensor_sync_stall(tensor_unit_sync_stall),
    .tensor_wld_cmd_ready(tensor_wld_unit_cmd_ready),
    .tensor_sld_cmd_ready(tensor_sld_unit_cmd_ready),
    .dma_start_addr_src(dma_start_addr_src),
    .dma_start_addr_dst(dma_start_addr_dst),
    .dma_start_len(dtcm_dma_start_len),.dma_start_req(dtcm_dma_start_req),
    .dma_stream_cmd_valid(dma_stream_cmd_valid),
    .dma_stream_cmd_axi_addr(dma_stream_cmd_axi_addr),
    .dma_stream_cmd_dtcm_addr(
      dma_stream_cmd_dtcm_addr[DTCM_ADDR_WIDTH-1:0]),.*);
  /* verilator lint_on PINMISSING */
endmodule
