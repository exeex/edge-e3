`timescale 1ns/1ps
module edge_core_write_axi_mux #(
  parameter ADDR_WIDTH = 40,
  parameter DATA_WIDTH = 128,
  parameter ID_WIDTH = 8,
  parameter LEN_WIDTH = 8
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,

  input  wire                       clean_valid,
  output wire                       clean_ready,
  input  wire [ADDR_WIDTH-1:0]      clean_addr,
  input  wire [DATA_WIDTH-1:0]      clean_data,
  input  wire                       clean_last,
  output wire                       clean_complete,

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

  output wire [ADDR_WIDTH-1:0]      core_awaddr,
  output wire [1:0]                 core_awburst,
  output wire [3:0]                 core_awcache,
  output wire [ID_WIDTH-1:0]        core_awid,
  output wire [LEN_WIDTH-1:0]       core_awlen,
  output wire                       core_awlock,
  output wire [2:0]                 core_awprot,
  output wire [2:0]                 core_awsize,
  output wire                       core_awvalid,
  input  wire                       core_awready,
  input  wire [ID_WIDTH-1:0]        core_bid,
  output wire                       core_bready,
  input  wire [1:0]                 core_bresp,
  input  wire                       core_bvalid,
  output wire [DATA_WIDTH-1:0]      core_wdata,
  output wire                       core_wlast,
  input  wire                       core_wready,
  output wire [(DATA_WIDTH/8)-1:0]  core_wstrb,
  output wire                       core_wvalid
);

  localparam [2:0] STATE_IDLE = 3'd0;
  localparam [2:0] STATE_CLEAN_AW = 3'd1;
  localparam [2:0] STATE_CLEAN_W = 3'd2;
  localparam [2:0] STATE_CLEAN_B = 3'd3;
  localparam [2:0] STATE_BRINGUP_W = 3'd4;
  localparam [2:0] STATE_BRINGUP_B = 3'd5;
  localparam [ID_WIDTH-1:0] CLEAN_ID = 8'hc1;

  reg [2:0] state_q;
  reg [ADDR_WIDTH-1:0] clean_addr_q;
  reg [DATA_WIDTH-1:0] clean_data_q;
  reg clean_last_q;

  wire clean_fire = clean_valid && clean_ready;
  wire bringup_aw_fire = bringup_awvalid && bringup_awready;
  wire core_aw_fire = core_awvalid && core_awready;
  wire core_w_fire = core_wvalid && core_wready;
  wire core_b_fire = core_bvalid && core_bready;

  // Bring-up AW wins an idle-cycle tie. A clean beat is accepted only when no
  // external address request is being presented, so ownership cannot change
  // between a bring-up AW handshake and its W/B phases.
  assign clean_ready = (state_q == STATE_IDLE) && !bringup_awvalid;
  assign bringup_awready = (state_q == STATE_IDLE) && core_awready;

  assign core_awvalid = (state_q == STATE_CLEAN_AW) ? 1'b1 :
                        (state_q == STATE_IDLE) ? bringup_awvalid : 1'b0;
  assign core_awaddr = (state_q == STATE_CLEAN_AW) ? clean_addr_q :
                       bringup_awaddr;
  assign core_awburst = (state_q == STATE_CLEAN_AW) ? 2'b01 :
                         bringup_awburst;
  assign core_awcache = (state_q == STATE_CLEAN_AW) ? 4'h0 :
                         bringup_awcache;
  assign core_awid = (state_q == STATE_CLEAN_AW) ? CLEAN_ID : bringup_awid;
  assign core_awlen = (state_q == STATE_CLEAN_AW) ? {LEN_WIDTH{1'b0}} :
                      bringup_awlen;
  assign core_awlock = (state_q == STATE_CLEAN_AW) ? 1'b0 : bringup_awlock;
  assign core_awprot = (state_q == STATE_CLEAN_AW) ? 3'b000 : bringup_awprot;
  assign core_awsize = (state_q == STATE_CLEAN_AW) ? 3'b100 : bringup_awsize;

  assign core_wvalid = (state_q == STATE_CLEAN_W) ? 1'b1 :
                       (state_q == STATE_BRINGUP_W) ? bringup_wvalid : 1'b0;
  assign core_wdata = (state_q == STATE_CLEAN_W) ? clean_data_q :
                      bringup_wdata;
  assign core_wlast = (state_q == STATE_CLEAN_W) ? 1'b1 : bringup_wlast;
  assign core_wstrb = (state_q == STATE_CLEAN_W) ?
                      {(DATA_WIDTH/8){1'b1}} : bringup_wstrb;
  assign bringup_wready = (state_q == STATE_BRINGUP_W) && core_wready;

  assign core_bready = (state_q == STATE_CLEAN_B) ? 1'b1 :
                       (state_q == STATE_BRINGUP_B) ? bringup_bready : 1'b0;
  assign bringup_bid = core_bid;
  assign bringup_bresp = core_bresp;
  assign bringup_bvalid = (state_q == STATE_BRINGUP_B) && core_bvalid;
  assign clean_complete = (state_q == STATE_CLEAN_B) && clean_last_q &&
                          core_bvalid && core_bready;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      state_q <= STATE_IDLE;
      clean_addr_q <= {ADDR_WIDTH{1'b0}};
      clean_data_q <= {DATA_WIDTH{1'b0}};
      clean_last_q <= 1'b0;
    end else begin
      case (state_q)
        STATE_IDLE: begin
          if (bringup_aw_fire)
            state_q <= STATE_BRINGUP_W;
          else if (clean_fire) begin
            state_q <= STATE_CLEAN_AW;
            clean_addr_q <= clean_addr;
            clean_data_q <= clean_data;
            clean_last_q <= clean_last;
          end
        end
        STATE_CLEAN_AW: begin
          if (core_aw_fire)
            state_q <= STATE_CLEAN_W;
        end
        STATE_CLEAN_W: begin
          if (core_w_fire)
            state_q <= STATE_CLEAN_B;
        end
        STATE_CLEAN_B: begin
          if (core_b_fire)
            state_q <= STATE_IDLE;
        end
        STATE_BRINGUP_W: begin
          if (core_w_fire)
            state_q <= STATE_BRINGUP_B;
        end
        STATE_BRINGUP_B: begin
          if (core_b_fire)
            state_q <= STATE_IDLE;
        end
        default: state_q <= STATE_IDLE;
      endcase
    end
  end

endmodule
