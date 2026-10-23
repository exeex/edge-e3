`timescale 1ns/1ps
module edge_core_dma_axi_mux #(
  parameter ADDR_WIDTH = 40,
  parameter DATA_WIDTH = 128,
  parameter ID_WIDTH = 8,
  parameter LEN_WIDTH = 8
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,
  input  wire                       dtcm_write_select_enable,
  input  wire                       dtcm_read_is_stream,
  input  wire                       dtcm_stream_busy,

  input  wire [ADDR_WIDTH-1:0]      dtcm_araddr,
  input  wire [1:0]                 dtcm_arburst,
  input  wire [3:0]                 dtcm_arcache,
  input  wire [ID_WIDTH-1:0]        dtcm_arid,
  input  wire [LEN_WIDTH-1:0]       dtcm_arlen,
  input  wire                       dtcm_arlock,
  input  wire [2:0]                 dtcm_arprot,
  input  wire [2:0]                 dtcm_arsize,
  input  wire                       dtcm_arvalid,
  output wire                       dtcm_arready,
  output wire [DATA_WIDTH-1:0]      dtcm_rdata,
  output wire                       dtcm_rlast,
  input  wire                       dtcm_rready,
  output wire                       dtcm_rvalid,
  input  wire [ADDR_WIDTH-1:0]      dtcm_awaddr,
  input  wire [1:0]                 dtcm_awburst,
  input  wire [3:0]                 dtcm_awcache,
  input  wire [ID_WIDTH-1:0]        dtcm_awid,
  input  wire [LEN_WIDTH-1:0]       dtcm_awlen,
  input  wire                       dtcm_awlock,
  input  wire [2:0]                 dtcm_awprot,
  input  wire [2:0]                 dtcm_awsize,
  input  wire                       dtcm_awvalid,
  output wire                       dtcm_awready,
  output wire                       dtcm_bvalid,
  input  wire                       dtcm_bready,
  input  wire [DATA_WIDTH-1:0]      dtcm_wdata,
  input  wire                       dtcm_wlast,
  output wire                       dtcm_wready,
  input  wire [(DATA_WIDTH/8)-1:0]  dtcm_wstrb,
  input  wire                       dtcm_wvalid,

  input  wire [ADDR_WIDTH-1:0]      bringup_araddr,
  input  wire [1:0]                 bringup_arburst,
  input  wire [3:0]                 bringup_arcache,
  input  wire [ID_WIDTH-1:0]        bringup_arid,
  input  wire [LEN_WIDTH-1:0]       bringup_arlen,
  input  wire                       bringup_arlock,
  input  wire [2:0]                 bringup_arprot,
  input  wire [2:0]                 bringup_arsize,
  input  wire                       bringup_arvalid,
  output wire                       bringup_arready,
  output wire [DATA_WIDTH-1:0]      bringup_rdata,
  output wire [ID_WIDTH-1:0]        bringup_rid,
  output wire                       bringup_rlast,
  input  wire                       bringup_rready,
  output wire [1:0]                 bringup_rresp,
  output wire                       bringup_rvalid,
  input  wire [ADDR_WIDTH-1:0]      bringup_awaddr,
  input  wire [1:0]                 bringup_awburst,
  input  wire [3:0]                 bringup_awcache,
  input  wire [ID_WIDTH-1:0]        bringup_awid,
  input  wire [LEN_WIDTH-1:0]       bringup_awlen,
  input  wire                       bringup_awlock,
  input  wire [2:0]                 bringup_awprot,
  input  wire [2:0]                 bringup_awsize,
  input  wire                       bringup_awvalid,
  output wire                       bringup_awready,
  output wire [ID_WIDTH-1:0]        bringup_bid,
  input  wire                       bringup_bready,
  output wire [1:0]                 bringup_bresp,
  output wire                       bringup_bvalid,
  input  wire [DATA_WIDTH-1:0]      bringup_wdata,
  input  wire                       bringup_wlast,
  output wire                       bringup_wready,
  input  wire [(DATA_WIDTH/8)-1:0]  bringup_wstrb,
  input  wire                       bringup_wvalid,

  output wire [ADDR_WIDTH-1:0]      dma_araddr,
  output wire [1:0]                 dma_arburst,
  output wire [3:0]                 dma_arcache,
  output wire [ID_WIDTH-1:0]        dma_arid,
  output wire [LEN_WIDTH-1:0]       dma_arlen,
  output wire                       dma_arlock,
  output wire [2:0]                 dma_arprot,
  output wire [2:0]                 dma_arsize,
  output wire                       dma_arvalid,
  input  wire                       dma_arready,
  input  wire [DATA_WIDTH-1:0]      dma_rdata,
  input  wire [ID_WIDTH-1:0]        dma_rid,
  input  wire                       dma_rlast,
  output wire                       dma_rready,
  input  wire [1:0]                 dma_rresp,
  input  wire                       dma_rvalid,
  output wire [ADDR_WIDTH-1:0]      dma_awaddr,
  output wire [1:0]                 dma_awburst,
  output wire [3:0]                 dma_awcache,
  output wire [ID_WIDTH-1:0]        dma_awid,
  output wire [LEN_WIDTH-1:0]       dma_awlen,
  output wire                       dma_awlock,
  output wire [2:0]                 dma_awprot,
  output wire [2:0]                 dma_awsize,
  output wire                       dma_awvalid,
  input  wire                       dma_awready,
  input  wire [ID_WIDTH-1:0]        dma_bid,
  output wire                       dma_bready,
  input  wire [1:0]                 dma_bresp,
  input  wire                       dma_bvalid,
  output wire [DATA_WIDTH-1:0]      dma_wdata,
  output wire                       dma_wlast,
  input  wire                       dma_wready,
  output wire [(DATA_WIDTH/8)-1:0]  dma_wstrb,
  output wire                       dma_wvalid
);

  reg read_owner_dtcm_q;
  reg read_owner_stream_q;
  reg stream_yield_q;
  reg read_inflight_q;
  reg ar_locked_q, ar_owner_dtcm_q;
  reg write_owner_dtcm_q;
  wire stream_defer_to_core = dtcm_read_is_stream && stream_yield_q
                            && bringup_arvalid;
  wire select_dtcm_read = ar_locked_q ? ar_owner_dtcm_q :
                          dtcm_arvalid && !stream_defer_to_core;
  wire select_dtcm_write = dtcm_write_select_enable && dtcm_awvalid;
  wire ar_fire = dma_arvalid && dma_arready;
  wire r_done = dma_rvalid && dma_rready && dma_rlast;
  wire aw_fire = dma_awvalid && dma_awready;
  wire b_fire = dma_bvalid && dma_bready;
  wire read_owner_dtcm = read_owner_dtcm_q;

  assign dma_araddr = select_dtcm_read ? dtcm_araddr : bringup_araddr;
  assign dma_arburst = select_dtcm_read ? dtcm_arburst : bringup_arburst;
  assign dma_arcache = select_dtcm_read ? dtcm_arcache : bringup_arcache;
  assign dma_arid = select_dtcm_read ? dtcm_arid : bringup_arid;
  assign dma_arlen = select_dtcm_read ? dtcm_arlen : bringup_arlen;
  assign dma_arlock = select_dtcm_read ? dtcm_arlock : bringup_arlock;
  assign dma_arprot = select_dtcm_read ? dtcm_arprot : bringup_arprot;
  assign dma_arsize = select_dtcm_read ? dtcm_arsize : bringup_arsize;
  assign dma_arvalid = !read_inflight_q
                     && (select_dtcm_read || bringup_arvalid);
  assign dtcm_arready = !read_inflight_q && select_dtcm_read && dma_arready;
  assign bringup_arready = !read_inflight_q && !select_dtcm_read
                         && dma_arready;

  assign dma_rready = read_owner_dtcm ? dtcm_rready : bringup_rready;
  assign dtcm_rdata = dma_rdata;
  assign dtcm_rlast = dma_rlast;
  assign dtcm_rvalid = read_owner_dtcm && dma_rvalid;
  assign bringup_rdata = dma_rdata;
  assign bringup_rid = dma_rid;
  assign bringup_rlast = !read_owner_dtcm && dma_rvalid && dma_rlast;
  assign bringup_rresp = dma_rresp;
  assign bringup_rvalid = !read_owner_dtcm && dma_rvalid;

  assign dma_awaddr = select_dtcm_write ? dtcm_awaddr : bringup_awaddr;
  assign dma_awburst = select_dtcm_write ? dtcm_awburst : bringup_awburst;
  assign dma_awcache = select_dtcm_write ? dtcm_awcache : bringup_awcache;
  assign dma_awid = select_dtcm_write ? dtcm_awid : bringup_awid;
  assign dma_awlen = select_dtcm_write ? dtcm_awlen : bringup_awlen;
  assign dma_awlock = select_dtcm_write ? dtcm_awlock : bringup_awlock;
  assign dma_awprot = select_dtcm_write ? dtcm_awprot : bringup_awprot;
  assign dma_awsize = select_dtcm_write ? dtcm_awsize : bringup_awsize;
  assign dma_awvalid = select_dtcm_write || bringup_awvalid;
  assign dtcm_awready = select_dtcm_write && dma_awready;
  assign bringup_awready = !select_dtcm_write && dma_awready;

  assign dma_wdata = write_owner_dtcm_q ? dtcm_wdata : bringup_wdata;
  assign dma_wlast = write_owner_dtcm_q ? dtcm_wlast : bringup_wlast;
  assign dma_wstrb = write_owner_dtcm_q ? dtcm_wstrb : bringup_wstrb;
  assign dma_wvalid = write_owner_dtcm_q ? dtcm_wvalid : bringup_wvalid;
  assign dtcm_wready = write_owner_dtcm_q && dma_wready;
  assign bringup_wready = !write_owner_dtcm_q && dma_wready;

  assign dma_bready = write_owner_dtcm_q ? dtcm_bready : bringup_bready;
  assign dtcm_bvalid = write_owner_dtcm_q && dma_bvalid;
  assign bringup_bid = dma_bid;
  assign bringup_bresp = dma_bresp;
  assign bringup_bvalid = !write_owner_dtcm_q && dma_bvalid;

  // Hold the selected requester while AR is backpressured. A newly arriving
  // DMA request must not replace a CPU address already visible on AXI.
  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin ar_locked_q <= 0; ar_owner_dtcm_q <= 0; end
    else if (ar_fire) ar_locked_q <= 0;
    else if (dma_arvalid && !dma_arready && !ar_locked_q) begin
      ar_locked_q <= 1; ar_owner_dtcm_q <= select_dtcm_read;
    end
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      read_owner_dtcm_q <= 1'b0;
      read_owner_stream_q <= 1'b0;
      stream_yield_q <= 1'b0;
      read_inflight_q <= 1'b0;
    end else if (ar_fire) begin
      read_inflight_q <= 1'b1;
      read_owner_dtcm_q <= select_dtcm_read;
      read_owner_stream_q <= select_dtcm_read && dtcm_read_is_stream;
      if(!select_dtcm_read)stream_yield_q<=1'b0;
    end else if (r_done) begin
      read_inflight_q <= 1'b0;
      read_owner_dtcm_q <= 1'b0;
      if(read_owner_dtcm_q&&read_owner_stream_q)stream_yield_q<=1'b1;
    end
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b)
      write_owner_dtcm_q <= 1'b0;
    else if (aw_fire)
      write_owner_dtcm_q <= select_dtcm_write;
    else if (b_fire)
      write_owner_dtcm_q <= 1'b0;
  end

endmodule
