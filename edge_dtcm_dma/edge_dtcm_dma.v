module edge_dtcm_dma(
  axi_araddr,
  axi_arlen,
  axi_arready,
  axi_arvalid,
  axi_awaddr,
  axi_awlen,
  axi_awready,
  axi_awvalid,
  axi_bready,
  axi_bvalid,
  axi_rdata,
  axi_rready,
  axi_rlast,
  axi_rvalid,
  axi_wdata,
  axi_wlast,
  axi_wready,
  axi_wstrb,
  axi_wvalid,
  clk,
  cpurst_b,
  dma_busy,
  dma_done,
  dma_dtcm_addr,
  dma_dtcm_rdata,
  dma_dtcm_ready,
  dma_dtcm_req,
  dma_dtcm_rvalid,
  dma_dtcm_we,
  dma_dtcm_wdata,
  dma_dtcm_wstrb,
  dma_lease_channel,
  dma_lease_cycles,
  dma_lease_delay,
  dma_lease_valid,
  start,
  start_axi_addr,
  start_dir,
  start_dtcm_addr,
  start_len
);

parameter AXI_ADDR_WIDTH  = 40;
parameter DTCM_ADDR_WIDTH = 10;
parameter DATA_WIDTH      = 128;
parameter BYTE_WIDTH      = DATA_WIDTH / 8;
parameter BEAT_SHIFT      = DATA_WIDTH == 128 ? 4 : 3;
parameter DTCM_ADDR_INCR  = DATA_WIDTH / 64;
parameter BURST_MAX_BEATS = 4;
parameter FIFO_DEPTH      = 4;
parameter FIFO_PTR_WIDTH  = 2;
parameter [3:0] DMA_LEASE_DELAY = 4'd3;

localparam [31:0] BEAT_BYTES = BYTE_WIDTH;

input                       axi_arready;
input                       axi_awready;
input                       axi_bvalid;
input  [DATA_WIDTH-1:0]     axi_rdata;
input                       axi_rlast;
input                       axi_rvalid;
input                       axi_wready;
input                       clk;
input                       cpurst_b;
input  [DATA_WIDTH-1:0]     dma_dtcm_rdata;
input                       dma_dtcm_ready;
input                       dma_dtcm_rvalid;
input                       start;
input  [AXI_ADDR_WIDTH-1:0] start_axi_addr;
input                       start_dir;
input  [DTCM_ADDR_WIDTH-1:0] start_dtcm_addr;
input  [31:0]               start_len;

output [AXI_ADDR_WIDTH-1:0] axi_araddr;
output [7:0]                axi_arlen;
output                      axi_arvalid;
output [AXI_ADDR_WIDTH-1:0] axi_awaddr;
output [7:0]                axi_awlen;
output                      axi_awvalid;
output                      axi_bready;
output                      axi_rready;
output [DATA_WIDTH-1:0]     axi_wdata;
output                      axi_wlast;
output [BYTE_WIDTH-1:0]     axi_wstrb;
output                      axi_wvalid;
output                      dma_busy;
output                      dma_done;
output [DTCM_ADDR_WIDTH-1:0] dma_dtcm_addr;
output                      dma_dtcm_req;
output                      dma_dtcm_we;
output [DATA_WIDTH-1:0]     dma_dtcm_wdata;
output [BYTE_WIDTH-1:0]     dma_dtcm_wstrb;
output [2:0]                dma_lease_channel;
output [8:0]                dma_lease_cycles;
output [3:0]                dma_lease_delay;
output                      dma_lease_valid;

reg [AXI_ADDR_WIDTH-1:0]    axi_addr;
reg [DTCM_ADDR_WIDTH-1:0]   dtcm_addr;
reg [DATA_WIDTH-1:0]        fifo_data [0:FIFO_DEPTH-1];
reg [BYTE_WIDTH-1:0]        fifo_wstrb [0:FIFO_DEPTH-1];
reg [31:0]                  beats_left;
reg [31:0]                  bytes_left;
reg [31:0]                  recv_bytes_left;
reg [31:0]                  read_req_beats_left;
reg [31:0]                  read_resp_beats_left;
reg [31:0]                  write_chunk_beats_left;
reg [31:0]                  burst_beats;
reg [31:0]                  d2a_reads_issued;
reg [31:0]                  d2a_reads_received;
reg [3:0]                   state;
reg [BYTE_WIDTH-1:0]        partial_wstrb;
reg [BYTE_WIDTH-1:0]        recv_partial_wstrb;
reg [FIFO_PTR_WIDTH-1:0]    fifo_rd_ptr;
reg [FIFO_PTR_WIDTH-1:0]    fifo_wr_ptr;
reg [FIFO_PTR_WIDTH:0]      fifo_count;
reg [2:0]                   lease_phase;

wire [31:0]                 start_beats;
wire [2:0]                  start_pair;
wire [2:0]                  lease_issue_phase;
wire [31:0]                 next_burst_beats;
wire [AXI_ADDR_WIDTH-1:0]   next_burst_beats_ext;
wire [BYTE_WIDTH-1:0]       active_wstrb;
wire [BYTE_WIDTH-1:0]       recv_wstrb;
wire                        a2d_active;
wire                        a2d_ar_fire;
wire                        a2d_done;
wire                        a2d_fifo_empty;
wire                        a2d_fifo_full;
wire                        a2d_fifo_pop;
wire                        a2d_fifo_push;
wire                        d2a_aw_fire;
wire                        d2a_w_fire;
wire                        d2a_read_response;
integer                     wstrb_i;
integer                     fifo_i;

localparam IDLE      = 4'd0;
localparam A2D_AR    = 4'd1;
localparam A2D_RUN   = 4'd2;
localparam D2A_DR    = 4'd4;
localparam D2A_DWAIT = 4'd5;
localparam D2A_AW    = 4'd6;
localparam D2A_W     = 4'd7;
localparam D2A_B     = 4'd8;
localparam DONE      = 4'd9;

assign start_beats[31:0] = start_len[31:BEAT_SHIFT]
                         + {{31{1'b0}}, |start_len[BEAT_SHIFT-1:0]};
assign start_pair[2:0] = start_dtcm_addr[3:1];
assign lease_issue_phase[2:0] =
       lease_phase[2:0] + DMA_LEASE_DELAY[2:0];
assign next_burst_beats[31:0] =
       read_req_beats_left[31:0] > BURST_MAX_BEATS[31:0]
       ? BURST_MAX_BEATS[31:0]
       : read_req_beats_left[31:0];
assign next_burst_beats_ext[AXI_ADDR_WIDTH-1:0] =
       {{AXI_ADDR_WIDTH-32{1'b0}}, next_burst_beats[31:0]};
assign active_wstrb[BYTE_WIDTH-1:0] =
       bytes_left[31:0] >= BEAT_BYTES[31:0]
       ? {BYTE_WIDTH{1'b1}}
       : partial_wstrb[BYTE_WIDTH-1:0];
assign recv_wstrb[BYTE_WIDTH-1:0] =
       recv_bytes_left[31:0] >= BEAT_BYTES[31:0]
       ? {BYTE_WIDTH{1'b1}}
       : recv_partial_wstrb[BYTE_WIDTH-1:0];
assign a2d_active = state == A2D_AR || state == A2D_RUN;
assign a2d_fifo_empty = fifo_count == {FIFO_PTR_WIDTH+1{1'b0}};
assign a2d_fifo_full = fifo_count == FIFO_DEPTH[FIFO_PTR_WIDTH:0];
assign a2d_ar_fire = axi_arvalid && axi_arready;
assign a2d_fifo_push = a2d_active && axi_rvalid && axi_rready;
assign a2d_fifo_pop = a2d_active && !a2d_fifo_empty && dma_dtcm_ready;
assign a2d_done = state == A2D_RUN
               && read_req_beats_left[31:0] == 32'b0
               && read_resp_beats_left[31:0] == 32'b0
               && a2d_fifo_empty;
assign d2a_aw_fire = axi_awvalid && axi_awready;
assign d2a_w_fire = axi_wvalid && axi_wready;
assign d2a_read_response = (state == D2A_DR || state == D2A_DWAIT) &&
                           dma_dtcm_rvalid;

always @(*) begin
  partial_wstrb[BYTE_WIDTH-1:0] = {BYTE_WIDTH{1'b0}};
  recv_partial_wstrb[BYTE_WIDTH-1:0] = {BYTE_WIDTH{1'b0}};
  for (wstrb_i = 0; wstrb_i < BYTE_WIDTH; wstrb_i = wstrb_i + 1)
    partial_wstrb[wstrb_i] = wstrb_i[31:0] < bytes_left[31:0];
  for (wstrb_i = 0; wstrb_i < BYTE_WIDTH; wstrb_i = wstrb_i + 1)
    recv_partial_wstrb[wstrb_i] =
      wstrb_i[31:0] < recv_bytes_left[31:0];
end

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    state      <= IDLE;
    axi_addr   <= {AXI_ADDR_WIDTH{1'b0}};
    dtcm_addr  <= {DTCM_ADDR_WIDTH{1'b0}};
    beats_left <= 32'b0;
    bytes_left <= 32'b0;
    recv_bytes_left <= 32'b0;
    read_req_beats_left <= 32'b0;
    read_resp_beats_left <= 32'b0;
    write_chunk_beats_left <= 32'b0;
    burst_beats <= 32'b0;
    d2a_reads_issued <= 32'b0;
    d2a_reads_received <= 32'b0;
    fifo_rd_ptr <= {FIFO_PTR_WIDTH{1'b0}};
    fifo_wr_ptr <= {FIFO_PTR_WIDTH{1'b0}};
    fifo_count <= {FIFO_PTR_WIDTH+1{1'b0}};
    lease_phase <= 3'b0;
    for (fifo_i = 0; fifo_i < FIFO_DEPTH; fifo_i = fifo_i + 1) begin
      fifo_data[fifo_i] <= {DATA_WIDTH{1'b0}};
      fifo_wstrb[fifo_i] <= {BYTE_WIDTH{1'b0}};
    end
  end else begin
    lease_phase <= lease_phase[2:0] + 3'b1;

    if (a2d_fifo_push) begin
      fifo_data[fifo_wr_ptr] <= axi_rdata[DATA_WIDTH-1:0];
      fifo_wstrb[fifo_wr_ptr] <= recv_wstrb[BYTE_WIDTH-1:0];
      fifo_wr_ptr <= fifo_wr_ptr == FIFO_DEPTH[FIFO_PTR_WIDTH-1:0] - 1'b1
                     ? {FIFO_PTR_WIDTH{1'b0}}
                     : fifo_wr_ptr + {{FIFO_PTR_WIDTH-1{1'b0}}, 1'b1};
      recv_bytes_left <= recv_bytes_left > BEAT_BYTES[31:0]
                         ? recv_bytes_left - BEAT_BYTES[31:0]
                         : 32'b0;
      if (read_resp_beats_left[31:0] != 32'b0)
        read_resp_beats_left <= read_resp_beats_left - 1'b1;
    end

    if (a2d_fifo_pop) begin
      dtcm_addr <= dtcm_addr + DTCM_ADDR_INCR[DTCM_ADDR_WIDTH-1:0];
      fifo_rd_ptr <= fifo_rd_ptr == FIFO_DEPTH[FIFO_PTR_WIDTH-1:0] - 1'b1
                     ? {FIFO_PTR_WIDTH{1'b0}}
                     : fifo_rd_ptr + {{FIFO_PTR_WIDTH-1{1'b0}}, 1'b1};
    end

    if (a2d_fifo_push && !a2d_fifo_pop)
      fifo_count <= fifo_count + {{FIFO_PTR_WIDTH{1'b0}}, 1'b1};
    else if (!a2d_fifo_push && a2d_fifo_pop)
      fifo_count <= fifo_count - {{FIFO_PTR_WIDTH{1'b0}}, 1'b1};

    if (d2a_read_response) begin
      fifo_data[fifo_wr_ptr] <= dma_dtcm_rdata[DATA_WIDTH-1:0];
      fifo_wstrb[fifo_wr_ptr] <= active_wstrb[BYTE_WIDTH-1:0];
      fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
      fifo_count <= fifo_count + 1'b1;
      d2a_reads_received <= d2a_reads_received + 1'b1;
      bytes_left <= bytes_left > BEAT_BYTES[31:0]
                    ? bytes_left - BEAT_BYTES[31:0] : 32'b0;
    end

    case (state)
      IDLE: begin
        if (start) begin
          axi_addr   <= start_axi_addr[AXI_ADDR_WIDTH-1:0];
          dtcm_addr  <= start_dtcm_addr[DTCM_ADDR_WIDTH-1:0];
          beats_left <= start_beats[31:0];
          bytes_left <= start_len[31:0];
          recv_bytes_left <= start_len[31:0];
          read_req_beats_left <= start_dir ? 32'b0 : start_beats[31:0];
          read_resp_beats_left <= 32'b0;
          write_chunk_beats_left <= 32'b0;
          burst_beats <= 32'b0;
          d2a_reads_issued <= 32'b0;
          d2a_reads_received <= 32'b0;
          fifo_rd_ptr <= {FIFO_PTR_WIDTH{1'b0}};
          fifo_wr_ptr <= {FIFO_PTR_WIDTH{1'b0}};
          fifo_count <= {FIFO_PTR_WIDTH+1{1'b0}};
          if (start_dir) begin
            burst_beats <= start_beats[31:0] > BURST_MAX_BEATS[31:0]
                           ? BURST_MAX_BEATS[31:0] : start_beats[31:0];
            write_chunk_beats_left <=
              start_beats[31:0] > BURST_MAX_BEATS[31:0]
              ? BURST_MAX_BEATS[31:0] : start_beats[31:0];
          end
          state      <= start_beats[31:0] == 32'b0
                        ? DONE
                        : (start_dir ? D2A_DR : A2D_AR);
        end
      end
      A2D_AR: begin
        if (a2d_ar_fire) begin
          burst_beats[31:0] <= next_burst_beats[31:0];
          read_req_beats_left[31:0] <=
            read_req_beats_left[31:0] - next_burst_beats[31:0];
          read_resp_beats_left[31:0] <= next_burst_beats[31:0];
          axi_addr[AXI_ADDR_WIDTH-1:0] <=
            axi_addr[AXI_ADDR_WIDTH-1:0]
            + (next_burst_beats_ext[AXI_ADDR_WIDTH-1:0] << BEAT_SHIFT);
          state <= A2D_RUN;
        end
      end
      A2D_RUN: begin
        if (a2d_fifo_pop)
          beats_left <= beats_left - 1'b1;
        if (a2d_done)
          state <= DONE;
        else if (read_req_beats_left[31:0] != 32'b0
                 && read_resp_beats_left[31:0] == 32'b0)
          state <= A2D_AR;
      end
      D2A_DR: begin
        if (dma_dtcm_ready) begin
          dtcm_addr <= dtcm_addr + DTCM_ADDR_INCR[DTCM_ADDR_WIDTH-1:0];
          d2a_reads_issued <= d2a_reads_issued + 1'b1;
          if ((d2a_reads_issued + 1'b1) >= burst_beats)
            state <= D2A_DWAIT;
        end
      end
      D2A_DWAIT: begin
        if (d2a_read_response &&
            (d2a_reads_received + 1'b1) >= burst_beats)
          state <= D2A_AW;
      end
      D2A_AW: begin
        if (d2a_aw_fire) begin
          state <= D2A_W;
        end
      end
      D2A_W: begin
        if (d2a_w_fire) begin
          fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
          fifo_count <= fifo_count - 1'b1;
          write_chunk_beats_left <= write_chunk_beats_left - 1'b1;
          if (write_chunk_beats_left == 32'd1)
            state <= D2A_B;
        end
      end
      D2A_B: begin
        if (axi_bvalid) begin
          axi_addr <= axi_addr +
            ({{(AXI_ADDR_WIDTH-32){1'b0}}, burst_beats} << BEAT_SHIFT);
          beats_left <= beats_left - burst_beats;
          fifo_rd_ptr <= {FIFO_PTR_WIDTH{1'b0}};
          fifo_wr_ptr <= {FIFO_PTR_WIDTH{1'b0}};
          fifo_count <= {(FIFO_PTR_WIDTH+1){1'b0}};
          d2a_reads_issued <= 32'b0;
          d2a_reads_received <= 32'b0;
          if (beats_left == burst_beats) begin
            state <= DONE;
          end else begin
            burst_beats <= (beats_left - burst_beats) > BURST_MAX_BEATS[31:0]
                           ? BURST_MAX_BEATS[31:0]
                           : (beats_left - burst_beats);
            write_chunk_beats_left <=
              (beats_left - burst_beats) > BURST_MAX_BEATS[31:0]
              ? BURST_MAX_BEATS[31:0] : (beats_left - burst_beats);
            state <= D2A_DR;
          end
        end
      end
      DONE: begin
        state <= IDLE;
      end
      default: begin
        state <= IDLE;
      end
    endcase
  end
end

assign dma_busy = state != IDLE && state != DONE;
assign dma_done = state == DONE;

assign axi_arvalid = state == A2D_AR;
assign axi_araddr[AXI_ADDR_WIDTH-1:0] = axi_addr[AXI_ADDR_WIDTH-1:0];
assign axi_arlen[7:0] = next_burst_beats[7:0] - 8'b1;
assign axi_rready = state == A2D_RUN && !a2d_fifo_full;

assign axi_awvalid = state == D2A_AW;
assign axi_awaddr[AXI_ADDR_WIDTH-1:0] = axi_addr[AXI_ADDR_WIDTH-1:0];
assign axi_awlen[7:0] = burst_beats[7:0] - 8'b1;
assign axi_wvalid = state == D2A_W;
assign axi_wdata[DATA_WIDTH-1:0] = fifo_data[fifo_rd_ptr];
assign axi_wlast = state == D2A_W && write_chunk_beats_left == 32'd1;
assign axi_wstrb[BYTE_WIDTH-1:0] = fifo_wstrb[fifo_rd_ptr];
assign axi_bready = state == D2A_B;

assign dma_dtcm_req = (state == A2D_RUN && !a2d_fifo_empty)
                   || state == D2A_DR;
assign dma_dtcm_we  = state == A2D_RUN;
assign dma_dtcm_addr[DTCM_ADDR_WIDTH-1:0] = dtcm_addr[DTCM_ADDR_WIDTH-1:0];
assign dma_dtcm_wdata[DATA_WIDTH-1:0] =
       fifo_data[fifo_rd_ptr][DATA_WIDTH-1:0];
assign dma_dtcm_wstrb[BYTE_WIDTH-1:0] =
       fifo_wstrb[fifo_rd_ptr][BYTE_WIDTH-1:0];

assign dma_lease_valid = start && start_beats[31:0] != 32'b0;
assign dma_lease_channel[2:0] =
       start_pair[2:0] - lease_issue_phase[2:0];
assign dma_lease_cycles[8:0] =
       start_beats[31:0] > 32'd256 ? 9'd256 : start_beats[8:0];
assign dma_lease_delay[3:0] = DMA_LEASE_DELAY[3:0];

endmodule
