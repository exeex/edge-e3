`timescale 1ns/1ps
module edge_core_read_axi_mux #(
  parameter ADDR_WIDTH = 40,
  parameter DATA_WIDTH = 128,
  parameter ID_WIDTH = 8,
  parameter LEN_WIDTH = 8,
  parameter ENABLE_ICACHE_REFILL = 1,
  parameter [3:0] ICACHE_STARVE_THRESHOLD = 4'd4,
  parameter [3:0] DCACHE_STARVE_THRESHOLD = 4'd8
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,

  input  wire                       icache_req_valid,
  output wire                       icache_req_ready,
  input  wire [ADDR_WIDTH-1:0]      icache_req_addr,
  output wire                       icache_resp_valid,
  input  wire                       icache_resp_ready,
  output wire [127:0]               icache_resp_bits,
  input  wire                       icache_miss_pending,

  input  wire                       dcache_req_valid,
  output wire                       dcache_req_ready,
  input  wire [ADDR_WIDTH-1:0]      dcache_req_addr,
  output wire                       dcache_resp_valid,
  input  wire                       dcache_resp_ready,
  output wire [DATA_WIDTH-1:0]      dcache_resp_data,
  output wire                       dcache_resp_last,
  output wire                       dcache_resp_error,

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

  output wire [ADDR_WIDTH-1:0]      core_araddr,
  output wire [1:0]                 core_arburst,
  output wire [3:0]                 core_arcache,
  output wire [ID_WIDTH-1:0]        core_arid,
  output wire [LEN_WIDTH-1:0]       core_arlen,
  output wire                       core_arlock,
  output wire [2:0]                 core_arprot,
  output wire [2:0]                 core_arsize,
  output wire                       core_arvalid,
  input  wire                       core_arready,
  input  wire [DATA_WIDTH-1:0]      core_rdata,
  input  wire [ID_WIDTH-1:0]        core_rid,
  input  wire                       core_rlast,
  output wire                       core_rready,
  input  wire [1:0]                 core_rresp,
  input  wire                       core_rvalid
);

  localparam [1:0] OWNER_NONE = 2'd0;
  localparam [1:0] OWNER_ICACHE = 2'd1;
  localparam [1:0] OWNER_DCACHE = 2'd2;
  localparam [1:0] OWNER_BRINGUP = 2'd3;
  localparam [ID_WIDTH-1:0] ICACHE_ID = 8'hf1;
  localparam [ID_WIDTH-1:0] DCACHE_ID = 8'hd1;
  localparam [LEN_WIDTH-1:0] ICACHE_LEN = {LEN_WIDTH{1'b0}};
  localparam [LEN_WIDTH-1:0] DCACHE_LEN = 3;

  reg [1:0] ar_owner_q;
  reg [1:0] r_owner_q;
  reg       icache_buf_valid_q;
  reg [ADDR_WIDTH-1:0] icache_buf_addr_q;
  reg [3:0] icache_starve_q;
  reg [3:0] dcache_starve_q;

  wire request_idle = (ar_owner_q == OWNER_NONE) &&
                      (r_owner_q == OWNER_NONE);
  wire icache_pending = ENABLE_ICACHE_REFILL && icache_buf_valid_q;
  wire dcache_pending = dcache_req_valid;
  wire grant_icache = request_idle && icache_pending &&
                      (!dcache_pending ||
                       (icache_starve_q >= ICACHE_STARVE_THRESHOLD) ||
                       (icache_starve_q >= dcache_starve_q));
  wire grant_dcache = request_idle && dcache_pending && !grant_icache &&
                      (!icache_pending ||
                       (dcache_starve_q >= DCACHE_STARVE_THRESHOLD));
  wire grant_bringup = request_idle && !grant_icache && !grant_dcache &&
                       bringup_arvalid;
  wire [1:0] grant_owner = grant_icache ? OWNER_ICACHE :
                           grant_dcache ? OWNER_DCACHE :
                           grant_bringup ? OWNER_BRINGUP : OWNER_NONE;
  wire [1:0] selected_owner = (ar_owner_q != OWNER_NONE) ? ar_owner_q :
                              grant_owner;
  wire ar_fire = core_arvalid && core_arready;
  wire r_done = (r_owner_q != OWNER_NONE) && core_rvalid && core_rready &&
                core_rlast;
  wire icache_req_fire = icache_req_valid && icache_req_ready;
  wire icache_accepted = ar_fire && (selected_owner == OWNER_ICACHE);
  wire dcache_accepted = ar_fire && (selected_owner == OWNER_DCACHE);

  assign icache_req_ready = ENABLE_ICACHE_REFILL && !icache_buf_valid_q;
  assign dcache_req_ready = dcache_accepted;
  assign bringup_arready = ar_fire && (selected_owner == OWNER_BRINGUP);

  assign core_arvalid = selected_owner != OWNER_NONE;
  assign core_araddr = (selected_owner == OWNER_ICACHE) ? icache_buf_addr_q :
                       (selected_owner == OWNER_DCACHE) ? dcache_req_addr :
                       bringup_araddr;
  assign core_arburst = (selected_owner == OWNER_BRINGUP) ?
                        bringup_arburst : 2'b01;
  assign core_arcache = (selected_owner == OWNER_BRINGUP) ?
                        bringup_arcache : 4'h0;
  assign core_arid = (selected_owner == OWNER_ICACHE) ? ICACHE_ID :
                     (selected_owner == OWNER_DCACHE) ? DCACHE_ID :
                     bringup_arid;
  assign core_arlen = (selected_owner == OWNER_ICACHE) ? ICACHE_LEN :
                      (selected_owner == OWNER_DCACHE) ? DCACHE_LEN :
                      bringup_arlen;
  assign core_arlock = (selected_owner == OWNER_BRINGUP) ?
                       bringup_arlock : 1'b0;
  assign core_arprot = (selected_owner == OWNER_BRINGUP) ?
                       bringup_arprot : 3'b000;
  assign core_arsize = (selected_owner == OWNER_BRINGUP) ?
                       bringup_arsize : 3'b100;

  assign core_rready = (r_owner_q == OWNER_ICACHE) ?
                       (icache_resp_ready || !icache_miss_pending) :
                       (r_owner_q == OWNER_DCACHE) ? dcache_resp_ready :
                       bringup_rready;
  assign icache_resp_valid = (r_owner_q == OWNER_ICACHE) && core_rvalid;
  assign icache_resp_bits = core_rdata[127:0];
  assign dcache_resp_valid = (r_owner_q == OWNER_DCACHE) && core_rvalid;
  assign dcache_resp_data = core_rdata;
  assign dcache_resp_last = (r_owner_q == OWNER_DCACHE) && core_rlast;
  assign dcache_resp_error = |core_rresp;
  assign bringup_rdata = core_rdata;
  assign bringup_rid = core_rid;
  assign bringup_rlast = (r_owner_q == OWNER_BRINGUP) && core_rvalid &&
                         core_rlast;
  assign bringup_rresp = core_rresp;
  assign bringup_rvalid = (r_owner_q == OWNER_BRINGUP) && core_rvalid;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      ar_owner_q <= OWNER_NONE;
      r_owner_q <= OWNER_NONE;
    end else begin
      if ((ar_owner_q == OWNER_NONE) && (grant_owner != OWNER_NONE) &&
          !core_arready)
        ar_owner_q <= grant_owner;
      else if (ar_fire)
        ar_owner_q <= OWNER_NONE;

      if (ar_fire)
        r_owner_q <= selected_owner;
      else if (r_done)
        r_owner_q <= OWNER_NONE;
    end
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      icache_buf_valid_q <= 1'b0;
      icache_buf_addr_q <= {ADDR_WIDTH{1'b0}};
    end else if (icache_req_fire) begin
      icache_buf_valid_q <= 1'b1;
      icache_buf_addr_q <= icache_req_addr;
    end else if (icache_accepted) begin
      icache_buf_valid_q <= 1'b0;
    end
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      icache_starve_q <= 4'd0;
      dcache_starve_q <= 4'd0;
    end else begin
      if (icache_accepted)
        icache_starve_q <= 4'd0;
      else if (icache_pending && (selected_owner != OWNER_ICACHE) &&
               (icache_starve_q <= 4'd13))
        icache_starve_q <= icache_starve_q + 4'd2;
      else if (!icache_pending)
        icache_starve_q <= 4'd0;

      if (dcache_accepted)
        dcache_starve_q <= 4'd0;
      else if (dcache_pending && (selected_owner != OWNER_DCACHE) &&
               (dcache_starve_q != 4'hf))
        dcache_starve_q <= dcache_starve_q + 4'd1;
      else if (!dcache_pending)
        dcache_starve_q <= 4'd0;
    end
  end

endmodule
