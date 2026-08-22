module edge_core_edge32_top #(
  parameter ADDR_WIDTH=40,parameter DATA_WIDTH=128,
  parameter ID_WIDTH=8,parameter LEN_WIDTH=8,
  parameter ICACHE_BYTES=16384,parameter DCACHE_BYTES=16384,
  parameter DTCM_ADDR_WIDTH=14,parameter DTCM_SRAM_ADDR_WIDTH=10,
  parameter DTCM_SEGMENT_NUM=1,
  parameter [46:0] EDGE_ASIC_ID={15'd3,4'd3,4'd3,8'h03,8'h01,8'h01}
)(
  input wire forever_cpuclk,input wire cpurst_b,
  input wire core_start,input wire core_force_stop,
  input wire [ADDR_WIDTH-1:0] boot_pc,
  input wire [ADDR_WIDTH-1:0] mem_region_base,input wire [ADDR_WIDTH-1:0] mem_region_mask,
  input wire mem_region_enable,
  output wire [ADDR_WIDTH-1:0] dma_araddr,output wire [1:0] dma_arburst,
  output wire [3:0] dma_arcache,output wire [ID_WIDTH-1:0] dma_arid,
  output wire [LEN_WIDTH-1:0] dma_arlen,output wire dma_arlock,
  output wire [2:0] dma_arprot,output wire [2:0] dma_arsize,output wire dma_arvalid,
  input wire dma_arready,input wire [DATA_WIDTH-1:0] dma_rdata,
  input wire [ID_WIDTH-1:0] dma_rid,input wire dma_rlast,output wire dma_rready,
  input wire [1:0] dma_rresp,input wire dma_rvalid,
  output wire [ADDR_WIDTH-1:0] dma_awaddr,output wire [1:0] dma_awburst,
  output wire [3:0] dma_awcache,output wire [ID_WIDTH-1:0] dma_awid,
  output wire [LEN_WIDTH-1:0] dma_awlen,output wire dma_awlock,
  output wire [2:0] dma_awprot,output wire [2:0] dma_awsize,output wire dma_awvalid,
  input wire dma_awready,input wire [ID_WIDTH-1:0] dma_bid,output wire dma_bready,
  input wire [1:0] dma_bresp,input wire dma_bvalid,
  output wire [DATA_WIDTH-1:0] dma_wdata,output wire dma_wlast,
  input wire dma_wready,output wire [(DATA_WIDTH/8)-1:0] dma_wstrb,output wire dma_wvalid,
  output wire halted,output wire illegal,output wire [63:0] debug_x31,
  output wire [63:0] cycle_count,output wire [63:0] instret_count,
  output wire asic_power_enable,input wire asic_power_ready,output wire asic_ready,
  output wire tensor_busy,output wire actu_busy,output wire cmpu_busy,output wire accel_dma_busy
);
  wire bringup_arready,bringup_rready,bringup_awready,bringup_bready,bringup_wready;
  wire [ADDR_WIDTH-1:0] bringup_araddr,bringup_awaddr;
  wire [1:0] bringup_arburst,bringup_awburst;
  wire [3:0] bringup_arcache,bringup_awcache;
  wire [ID_WIDTH-1:0] bringup_arid,bringup_awid,bringup_rid,bringup_bid;
  wire [LEN_WIDTH-1:0] bringup_arlen,bringup_awlen;
  wire bringup_arlock,bringup_awlock,bringup_arvalid,bringup_rvalid;
  wire [2:0] bringup_arprot,bringup_arsize,bringup_awprot,bringup_awsize;
  wire [DATA_WIDTH-1:0] bringup_rdata,bringup_wdata;
  wire bringup_rlast; wire [1:0] bringup_rresp,bringup_bresp;
  wire bringup_awvalid,bringup_bvalid,bringup_wlast,bringup_wvalid;
  wire [(DATA_WIDTH/8)-1:0] bringup_wstrb;
  wire dtcm_arready,dtcm_rready,dtcm_awready,dtcm_bready,dtcm_wready;
  wire [ADDR_WIDTH-1:0] dtcm_araddr,dtcm_awaddr;
  wire [1:0] dtcm_arburst,dtcm_awburst; wire [3:0] dtcm_arcache,dtcm_awcache;
  wire [ID_WIDTH-1:0] dtcm_arid,dtcm_awid; wire [LEN_WIDTH-1:0] dtcm_arlen,dtcm_awlen;
  wire dtcm_arlock,dtcm_awlock,dtcm_arvalid,dtcm_rvalid,dtcm_rlast;
  wire [2:0] dtcm_arprot,dtcm_arsize,dtcm_awprot,dtcm_awsize;
  wire [DATA_WIDTH-1:0] dtcm_rdata,dtcm_wdata; wire dtcm_awvalid,dtcm_bvalid;
  wire dtcm_wlast,dtcm_wvalid; wire [(DATA_WIDTH/8)-1:0] dtcm_wstrb;
  wire accel_req_valid,accel_req_ready,platform_req_ready,accel_resp_valid,accel_resp_error;
  wire [31:0] accel_req_inst;
  wire [31:0] scalar_accel_req_inst;
  localparam SCALAR_PC_WIDTH=32;
  wire [63:0] accel_req_src0,accel_req_src1,accel_resp_value;
  wire dtcm_lsu_req,dtcm_lsu_ready,dtcm_lsu_we,dtcm_lsu_rvalid;
  wire [DTCM_ADDR_WIDTH-1:0] dtcm_lsu_addr;
  wire [63:0] dtcm_lsu_wdata,dtcm_lsu_rdata;
  wire [7:0] dtcm_lsu_wstrb;

  edge32_axi_core #(.PC_WIDTH(SCALAR_PC_WIDTH),.AXI_ADDR_WIDTH(ADDR_WIDTH),
    .AXI_DATA_WIDTH(DATA_WIDTH),
    .AXI_ID_WIDTH(ID_WIDTH),.AXI_LEN_WIDTH(LEN_WIDTH),.ICACHE_BYTES(ICACHE_BYTES),
    .DCACHE_BYTES(DCACHE_BYTES),.DTCM_ADDR_WIDTH(DTCM_ADDR_WIDTH),
    .ENABLE_DTCM_PORT(1),.EDGE_ASIC_ID(EDGE_ASIC_ID)) core(
    .forever_cpuclk(forever_cpuclk),.cpurst_b(cpurst_b),
    .core_start(core_start),.core_force_stop(core_force_stop),
    .boot_pc(boot_pc[SCALAR_PC_WIDTH-1:0]),
    .biu_pad_araddr(bringup_araddr),.biu_pad_arburst(bringup_arburst),
    .biu_pad_arcache(bringup_arcache),.biu_pad_arid(bringup_arid),
    .biu_pad_arlen(bringup_arlen),.biu_pad_arlock(bringup_arlock),
    .biu_pad_arprot(bringup_arprot),.biu_pad_arsize(bringup_arsize),
    .biu_pad_arvalid(bringup_arvalid),.pad_biu_arready(bringup_arready),
    .pad_biu_rdata(bringup_rdata),.pad_biu_rid(bringup_rid),
    .pad_biu_rlast(bringup_rlast),.pad_biu_rresp(bringup_rresp),
    .pad_biu_rvalid(bringup_rvalid),.biu_pad_rready(bringup_rready),
    .biu_pad_awaddr(bringup_awaddr),.biu_pad_awburst(bringup_awburst),
    .biu_pad_awcache(bringup_awcache),.biu_pad_awid(bringup_awid),
    .biu_pad_awlen(bringup_awlen),.biu_pad_awlock(bringup_awlock),
    .biu_pad_awprot(bringup_awprot),.biu_pad_awsize(bringup_awsize),
    .biu_pad_awvalid(bringup_awvalid),.pad_biu_awready(bringup_awready),
    .pad_biu_bid(bringup_bid),.pad_biu_bresp(bringup_bresp),
    .pad_biu_bvalid(bringup_bvalid),.biu_pad_bready(bringup_bready),
    .biu_pad_wdata(bringup_wdata),.biu_pad_wlast(bringup_wlast),
    .biu_pad_wstrb(bringup_wstrb),.biu_pad_wvalid(bringup_wvalid),
    .pad_biu_wready(bringup_wready),.dtcm_base({{(64-ADDR_WIDTH){1'b0}},mem_region_base}),
    .dtcm_mask({{(64-ADDR_WIDTH){1'b0}},mem_region_mask}),.dtcm_enable(mem_region_enable),
    .dtcm_lsu_req(dtcm_lsu_req),.dtcm_lsu_ready(dtcm_lsu_ready),
    .dtcm_lsu_we(dtcm_lsu_we),.dtcm_lsu_addr(dtcm_lsu_addr),
    .dtcm_lsu_wdata(dtcm_lsu_wdata),.dtcm_lsu_wstrb(dtcm_lsu_wstrb),
    .dtcm_lsu_rvalid(dtcm_lsu_rvalid),.dtcm_lsu_rdata(dtcm_lsu_rdata),
    .accel_req_valid(accel_req_valid),.accel_req_ready(accel_req_ready),
    .accel_req_inst(scalar_accel_req_inst),.accel_req_src0(accel_req_src0),
    .accel_req_src1(accel_req_src1),.accel_resp_valid(accel_resp_valid),
    .accel_resp_error(accel_resp_error),.accel_resp_value(accel_resp_value),
    .halted(halted),.illegal(illegal),.debug_x31(debug_x31),
    .cycle_count(cycle_count),.instret_count(instret_count));

  assign accel_req_inst=scalar_accel_req_inst;

  edge_lite_accel_platform #(.AXI_ADDR_WIDTH(ADDR_WIDTH),.AXI_DATA_WIDTH(DATA_WIDTH),
    .AXI_ID_WIDTH(ID_WIDTH),.AXI_LEN_WIDTH(LEN_WIDTH),
    .DTCM_ADDR_WIDTH(DTCM_ADDR_WIDTH),.DTCM_SRAM_ADDR_WIDTH(DTCM_SRAM_ADDR_WIDTH),
    .DTCM_SEGMENT_NUM(DTCM_SEGMENT_NUM)) platform(
    .forever_cpuclk(forever_cpuclk),.cpurst_b(cpurst_b),.mem_region_base(mem_region_base),
    .mem_region_mask(mem_region_mask),.mem_region_enable(mem_region_enable),
    .req_valid(accel_req_valid),.req_ready(platform_req_ready),.req_inst(accel_req_inst),
    .req_capture_value(accel_req_src1),.resp_valid(accel_resp_valid),
    .resp_error(accel_resp_error),.resp_value(accel_resp_value),
    .scalar_lsu_addr(dtcm_lsu_addr),.scalar_lsu_req(dtcm_lsu_req),
    .scalar_lsu_we(dtcm_lsu_we),.scalar_lsu_wdata(dtcm_lsu_wdata),
    .scalar_lsu_wstrb(dtcm_lsu_wstrb),.scalar_lsu_rdata(dtcm_lsu_rdata),
    .scalar_lsu_ready(dtcm_lsu_ready),.scalar_lsu_rvalid(dtcm_lsu_rvalid),
    .dma_axi_araddr(dtcm_araddr),.dma_axi_arburst(dtcm_arburst),
    .dma_axi_arcache(dtcm_arcache),.dma_axi_arid(dtcm_arid),.dma_axi_arlen(dtcm_arlen),
    .dma_axi_arlock(dtcm_arlock),.dma_axi_arprot(dtcm_arprot),.dma_axi_arsize(dtcm_arsize),
    .dma_axi_arvalid(dtcm_arvalid),.dma_axi_arready(dtcm_arready),.dma_axi_rdata(dtcm_rdata),
    .dma_axi_rlast(dtcm_rlast),.dma_axi_rready(dtcm_rready),.dma_axi_rvalid(dtcm_rvalid),
    .dma_axi_awaddr(dtcm_awaddr),.dma_axi_awburst(dtcm_awburst),.dma_axi_awcache(dtcm_awcache),
    .dma_axi_awid(dtcm_awid),.dma_axi_awlen(dtcm_awlen),.dma_axi_awlock(dtcm_awlock),
    .dma_axi_awprot(dtcm_awprot),.dma_axi_awsize(dtcm_awsize),.dma_axi_awvalid(dtcm_awvalid),
    .dma_axi_awready(dtcm_awready),.dma_axi_bvalid(dtcm_bvalid),.dma_axi_bready(dtcm_bready),
    .dma_axi_wdata(dtcm_wdata),.dma_axi_wlast(dtcm_wlast),.dma_axi_wready(dtcm_wready),
    .dma_axi_wstrb(dtcm_wstrb),.dma_axi_wvalid(dtcm_wvalid),.tensor_busy(tensor_busy),
    .actu_busy(actu_busy),.cmpu_busy(cmpu_busy),.dma_busy(accel_dma_busy),
    .asic_power_enable_o(asic_power_enable),.asic_power_ready_i(asic_power_ready),
    .asic_ready_o(asic_ready));

  assign accel_req_ready=platform_req_ready;

  edge_core_dma_axi_mux #(.ADDR_WIDTH(ADDR_WIDTH),.DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH(ID_WIDTH),.LEN_WIDTH(LEN_WIDTH)) axi_mux(
      .forever_cpuclk(forever_cpuclk),.cpurst_b(cpurst_b),
      .dtcm_write_select_enable(1'b1),.dtcm_read_is_stream(1'b0),
      .dtcm_stream_busy(1'b0),.*);
endmodule
