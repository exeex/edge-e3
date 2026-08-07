`timescale 1ns/1ps

module edge_biu_top #(
  parameter ADDR_WIDTH = 40,
  parameter DATA_WIDTH = 128,
  parameter ID_WIDTH = 8,
  parameter LEN_WIDTH = 8
) (
  input                         forever_cpuclk,
  input                         cpurst_b,

  input  [ADDR_WIDTH-1:0]       core_araddr,
  input  [1:0]                  core_arburst,
  input  [3:0]                  core_arcache,
  input  [ID_WIDTH-1:0]         core_arid,
  input  [LEN_WIDTH-1:0]        core_arlen,
  input                         core_arlock,
  input  [2:0]                  core_arprot,
  input  [2:0]                  core_arsize,
  input                         core_arvalid,
  output                        core_arready,
  output [DATA_WIDTH-1:0]       core_rdata,
  output [ID_WIDTH-1:0]         core_rid,
  output                        core_rlast,
  input                         core_rready,
  output [1:0]                  core_rresp,
  output                        core_rvalid,

  input  [ADDR_WIDTH-1:0]       core_awaddr,
  input  [1:0]                  core_awburst,
  input  [3:0]                  core_awcache,
  input  [ID_WIDTH-1:0]         core_awid,
  input  [LEN_WIDTH-1:0]        core_awlen,
  input                         core_awlock,
  input  [2:0]                  core_awprot,
  input  [2:0]                  core_awsize,
  input                         core_awvalid,
  output                        core_awready,
  output [ID_WIDTH-1:0]         core_bid,
  input                         core_bready,
  output [1:0]                  core_bresp,
  output                        core_bvalid,
  input  [DATA_WIDTH-1:0]       core_wdata,
  input                         core_wlast,
  output                        core_wready,
  input  [(DATA_WIDTH/8)-1:0]   core_wstrb,
  input                         core_wvalid,

  input  [ADDR_WIDTH-1:0]       dma_araddr,
  input  [1:0]                  dma_arburst,
  input  [3:0]                  dma_arcache,
  input  [ID_WIDTH-1:0]         dma_arid,
  input  [LEN_WIDTH-1:0]        dma_arlen,
  input                         dma_arlock,
  input  [2:0]                  dma_arprot,
  input  [2:0]                  dma_arsize,
  input                         dma_arvalid,
  output                        dma_arready,
  output [DATA_WIDTH-1:0]       dma_rdata,
  output [ID_WIDTH-1:0]         dma_rid,
  output                        dma_rlast,
  input                         dma_rready,
  output [1:0]                  dma_rresp,
  output                        dma_rvalid,

  input  [ADDR_WIDTH-1:0]       dma_awaddr,
  input  [1:0]                  dma_awburst,
  input  [3:0]                  dma_awcache,
  input  [ID_WIDTH-1:0]         dma_awid,
  input  [LEN_WIDTH-1:0]        dma_awlen,
  input                         dma_awlock,
  input  [2:0]                  dma_awprot,
  input  [2:0]                  dma_awsize,
  input                         dma_awvalid,
  output                        dma_awready,
  output [ID_WIDTH-1:0]         dma_bid,
  input                         dma_bready,
  output [1:0]                  dma_bresp,
  output                        dma_bvalid,
  input  [DATA_WIDTH-1:0]       dma_wdata,
  input                         dma_wlast,
  output                        dma_wready,
  input  [(DATA_WIDTH/8)-1:0]   dma_wstrb,
  input                         dma_wvalid,

  output [ADDR_WIDTH-1:0]       pad_araddr,
  output [1:0]                  pad_arburst,
  output [3:0]                  pad_arcache,
  output [ID_WIDTH-1:0]         pad_arid,
  output [LEN_WIDTH-1:0]        pad_arlen,
  output                        pad_arlock,
  output [2:0]                  pad_arprot,
  input                         pad_arready,
  output [2:0]                  pad_arsize,
  output                        pad_arvalid,
  input  [DATA_WIDTH-1:0]       pad_rdata,
  input  [ID_WIDTH-1:0]         pad_rid,
  input                         pad_rlast,
  output                        pad_rready,
  input  [1:0]                  pad_rresp,
  input                         pad_rvalid,

  output [ADDR_WIDTH-1:0]       pad_awaddr,
  output [1:0]                  pad_awburst,
  output [3:0]                  pad_awcache,
  output [ID_WIDTH-1:0]         pad_awid,
  output [LEN_WIDTH-1:0]        pad_awlen,
  output                        pad_awlock,
  output [2:0]                  pad_awprot,
  input                         pad_awready,
  output [2:0]                  pad_awsize,
  output                        pad_awvalid,
  input  [ID_WIDTH-1:0]         pad_bid,
  output                        pad_bready,
  input  [1:0]                  pad_bresp,
  input                         pad_bvalid,
  output [DATA_WIDTH-1:0]       pad_wdata,
  output                        pad_wlast,
  input                         pad_wready,
  output [(DATA_WIDTH/8)-1:0]   pad_wstrb,
  output                        pad_wvalid,

  output                        debug_read_owner_valid,
  output                        debug_read_owner_dma,
  output                        debug_write_owner_valid,
  output                        debug_write_owner_dma
);

  localparam STRB_WIDTH = DATA_WIDTH / 8;

  reg read_owner_valid_q;
  reg read_owner_dma_q;
  reg write_owner_valid_q;
  reg write_owner_dma_q;

  wire select_dma_read;
  wire select_core_read;
  wire select_dma_write;
  wire select_core_write;
  wire ar_fire;
  wire aw_fire;
  wire r_fire;
  wire b_fire;

  assign select_dma_read =
       !read_owner_valid_q
    && dma_arvalid;
  assign select_core_read =
       !read_owner_valid_q
    && !select_dma_read
    && core_arvalid;

  assign pad_arvalid = select_dma_read || select_core_read;
  assign pad_araddr[ADDR_WIDTH-1:0] = select_dma_read
                                    ? dma_araddr[ADDR_WIDTH-1:0]
                                    : core_araddr[ADDR_WIDTH-1:0];
  assign pad_arburst[1:0] = select_dma_read ? dma_arburst[1:0] : core_arburst[1:0];
  assign pad_arcache[3:0] = select_dma_read ? dma_arcache[3:0] : core_arcache[3:0];
  assign pad_arid[ID_WIDTH-1:0] = select_dma_read
                                ? dma_arid[ID_WIDTH-1:0]
                                : core_arid[ID_WIDTH-1:0];
  assign pad_arlen[LEN_WIDTH-1:0] = select_dma_read
                                  ? dma_arlen[LEN_WIDTH-1:0]
                                  : core_arlen[LEN_WIDTH-1:0];
  assign pad_arlock = select_dma_read ? dma_arlock : core_arlock;
  assign pad_arprot[2:0] = select_dma_read ? dma_arprot[2:0] : core_arprot[2:0];
  assign pad_arsize[2:0] = select_dma_read ? dma_arsize[2:0] : core_arsize[2:0];
  assign dma_arready = select_dma_read && pad_arready;
  assign core_arready = select_core_read && pad_arready;
  assign ar_fire = pad_arvalid && pad_arready;

  assign pad_rready = read_owner_valid_q
                    && (read_owner_dma_q ? dma_rready : core_rready);
  assign dma_rvalid = read_owner_valid_q && read_owner_dma_q && pad_rvalid;
  assign core_rvalid = read_owner_valid_q && !read_owner_dma_q && pad_rvalid;
  assign dma_rdata[DATA_WIDTH-1:0] = pad_rdata[DATA_WIDTH-1:0];
  assign core_rdata[DATA_WIDTH-1:0] = pad_rdata[DATA_WIDTH-1:0];
  assign dma_rid[ID_WIDTH-1:0] = pad_rid[ID_WIDTH-1:0];
  assign core_rid[ID_WIDTH-1:0] = pad_rid[ID_WIDTH-1:0];
  assign dma_rlast = dma_rvalid && pad_rlast;
  assign core_rlast = core_rvalid && pad_rlast;
  assign dma_rresp[1:0] = pad_rresp[1:0];
  assign core_rresp[1:0] = pad_rresp[1:0];
  assign r_fire = pad_rvalid && pad_rready && pad_rlast;

  assign select_dma_write =
       !write_owner_valid_q
    && dma_awvalid;
  assign select_core_write =
       !write_owner_valid_q
    && !select_dma_write
    && core_awvalid;

  assign pad_awvalid = select_dma_write || select_core_write;
  assign pad_awaddr[ADDR_WIDTH-1:0] = select_dma_write
                                    ? dma_awaddr[ADDR_WIDTH-1:0]
                                    : core_awaddr[ADDR_WIDTH-1:0];
  assign pad_awburst[1:0] = select_dma_write ? dma_awburst[1:0] : core_awburst[1:0];
  assign pad_awcache[3:0] = select_dma_write ? dma_awcache[3:0] : core_awcache[3:0];
  assign pad_awid[ID_WIDTH-1:0] = select_dma_write
                                ? dma_awid[ID_WIDTH-1:0]
                                : core_awid[ID_WIDTH-1:0];
  assign pad_awlen[LEN_WIDTH-1:0] = select_dma_write
                                  ? dma_awlen[LEN_WIDTH-1:0]
                                  : core_awlen[LEN_WIDTH-1:0];
  assign pad_awlock = select_dma_write ? dma_awlock : core_awlock;
  assign pad_awprot[2:0] = select_dma_write ? dma_awprot[2:0] : core_awprot[2:0];
  assign pad_awsize[2:0] = select_dma_write ? dma_awsize[2:0] : core_awsize[2:0];
  assign dma_awready = select_dma_write && pad_awready;
  assign core_awready = select_core_write && pad_awready;
  assign aw_fire = pad_awvalid && pad_awready;

  assign pad_wvalid = write_owner_valid_q
                    && (write_owner_dma_q ? dma_wvalid : core_wvalid);
  assign pad_wdata[DATA_WIDTH-1:0] = write_owner_dma_q
                                   ? dma_wdata[DATA_WIDTH-1:0]
                                   : core_wdata[DATA_WIDTH-1:0];
  assign pad_wstrb[STRB_WIDTH-1:0] = write_owner_dma_q
                                   ? dma_wstrb[STRB_WIDTH-1:0]
                                   : core_wstrb[STRB_WIDTH-1:0];
  assign pad_wlast = write_owner_dma_q ? dma_wlast : core_wlast;
  assign dma_wready = write_owner_valid_q && write_owner_dma_q && pad_wready;
  assign core_wready = write_owner_valid_q && !write_owner_dma_q && pad_wready;

  assign pad_bready = write_owner_valid_q
                    && (write_owner_dma_q ? dma_bready : core_bready);
  assign dma_bvalid = write_owner_valid_q && write_owner_dma_q && pad_bvalid;
  assign core_bvalid = write_owner_valid_q && !write_owner_dma_q && pad_bvalid;
  assign dma_bid[ID_WIDTH-1:0] = pad_bid[ID_WIDTH-1:0];
  assign core_bid[ID_WIDTH-1:0] = pad_bid[ID_WIDTH-1:0];
  assign dma_bresp[1:0] = pad_bresp[1:0];
  assign core_bresp[1:0] = pad_bresp[1:0];
  assign b_fire = pad_bvalid && pad_bready;

  assign debug_read_owner_valid = read_owner_valid_q;
  assign debug_read_owner_dma = read_owner_dma_q;
  assign debug_write_owner_valid = write_owner_valid_q;
  assign debug_write_owner_dma = write_owner_dma_q;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      read_owner_valid_q <= 1'b0;
      read_owner_dma_q <= 1'b0;
    end else if (ar_fire) begin
      read_owner_valid_q <= 1'b1;
      read_owner_dma_q <= select_dma_read;
    end else if (r_fire) begin
      read_owner_valid_q <= 1'b0;
      read_owner_dma_q <= 1'b0;
    end
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      write_owner_valid_q <= 1'b0;
      write_owner_dma_q <= 1'b0;
    end else if (aw_fire) begin
      write_owner_valid_q <= 1'b1;
      write_owner_dma_q <= select_dma_write;
    end else if (b_fire) begin
      write_owner_valid_q <= 1'b0;
      write_owner_dma_q <= 1'b0;
    end
  end

`ifdef IVERILOG_SIM
  initial begin
    if (DATA_WIDTH % 8 != 0) begin
      $display("EDGE_BIU CONFIG FAIL: DATA_WIDTH must be byte aligned");
      $finish;
    end
  end
`endif

endmodule
