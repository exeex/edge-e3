`timescale 1ns/1ps

module edge_actu_io #(
  parameter ADDR_WIDTH = 16,
  parameter LANES = 1,
  parameter FIFO_DEPTH = 16,
  parameter FIFO_INDEX_WIDTH = 4,
  parameter BEAT_BITS = 128
) (
  input  wire                         clk,
  input  wire                         cpurst_b,

  input  wire                         start_valid,
  output wire                         start_ready,
  input  wire [ADDR_WIDTH-1:0]        in_base_addr,
  input  wire [ADDR_WIDTH-1:0]        out_base_addr,
  input  wire [15:0]                  n_elements,

  output wire                         busy,
  output wire                         done_valid,

  output wire                         dtcm_rd_req,
  input  wire                         dtcm_rd_ready,
  output wire [ADDR_WIDTH-1:0]        dtcm_rd_addr,
  input  wire                         dtcm_rd_rvalid,
  input  wire [BEAT_BITS-1:0]         dtcm_rd_rdata,

  output wire                         dtcm_wr_req,
  input  wire                         dtcm_wr_ready,
  output wire [ADDR_WIDTH-1:0]        dtcm_wr_addr,
  output wire [BEAT_BITS-1:0]         dtcm_wr_wdata,
  output wire [(BEAT_BITS/8)-1:0]     dtcm_wr_wstrb,

  output wire [LANES-1:0]             core_in_valid,
  input  wire [LANES-1:0]             core_in_ready,
  output wire [LANES*32-1:0]          core_in_data,

  input  wire [LANES-1:0]             core_out_valid,
  output wire [LANES-1:0]             core_out_ready,
  input  wire [LANES*32-1:0]          core_out_data
);

localparam BEAT_BYTES = BEAT_BITS / 8;
localparam MAX_ELEMS_PER_BEAT = BEAT_BYTES / 2;
localparam FIFO_COUNT_WIDTH = FIFO_INDEX_WIDTH + 1;
localparam [FIFO_COUNT_WIDTH-1:0] FIFO_DEPTH_COUNT = FIFO_DEPTH;

reg                         active_q;
reg [ADDR_WIDTH-1:0]        in_base_addr_q;
reg [ADDR_WIDTH-1:0]        out_base_addr_q;
reg [15:0]                  n_elements_q;
reg [15:0]                  rd_issued_elems_q;
reg [15:0]                  rd_returned_elems_q;
reg [15:0]                  in_streamed_elems_q;
reg [15:0]                  out_accepted_elems_q;
reg [15:0]                  wr_committed_elems_q;
reg                         rd_inflight_q;
reg [3:0]                   rd_inflight_elems_q;
reg [ADDR_WIDTH-1:0]        rd_next_addr_q;
reg [ADDR_WIDTH-1:0]        wr_next_addr_q;
reg [31:0]                  in_fifo [0:FIFO_DEPTH-1];
reg [FIFO_INDEX_WIDTH-1:0]  in_fifo_head_q;
reg [FIFO_INDEX_WIDTH-1:0]  in_fifo_tail_q;
reg [FIFO_COUNT_WIDTH-1:0]  in_fifo_count_q;
reg [BEAT_BITS-1:0]         wr_pack_data_q;
reg [3:0]                   wr_pack_count_q;
reg                         wr_pending_q;
reg [BEAT_BITS-1:0]         wr_pending_data_q;
reg [(BEAT_BITS/8)-1:0]     wr_pending_wstrb_q;
reg [3:0]                   wr_pending_elems_q;
reg                         done_valid_q;

wire                        start_fire;
wire [3:0]                  elems_per_beat;
wire [3:0]                  elem_bytes;
wire [3:0]                  rd_issue_elems;
wire                        rd_can_issue;
wire                        rd_fire;
wire                        rd_push;
wire [3:0]                  in_pop_count;
wire [3:0]                  out_accept_count;
wire                        wr_fire;
wire                        wr_make_pending;
wire [3:0]                  wr_pack_count_after_accept;
wire [15:0]                 out_accepted_after_accept;
wire                        wr_tail_after_accept;
wire [BEAT_BITS-1:0]        wr_pack_data_after_accept;
wire [(BEAT_BITS/8)-1:0]    wr_wstrb_after_accept;
wire [3:0]                  wr_pending_elems_next;

integer lane_i;
integer pop_i;
integer push_i;
integer pack_i;
integer byte_i;

assign start_ready = !active_q;
assign start_fire = start_valid && start_ready;
assign busy = active_q;
assign done_valid = done_valid_q;
assign elems_per_beat = 4'd8;
assign elem_bytes = 4'd2;

function [3:0] min4_u16;
  input [15:0] a;
  input [3:0]  b;
  begin
    min4_u16 = (a < {12'b0, b}) ? a[3:0] : b;
  end
endfunction

function [31:0] fifo_elem_at;
  input [FIFO_INDEX_WIDTH-1:0] head;
  input integer                offset;
  reg [FIFO_INDEX_WIDTH-1:0]   idx;
  begin
    idx = head + offset[FIFO_INDEX_WIDTH-1:0];
    fifo_elem_at = in_fifo[idx];
  end
endfunction

function [3:0] prefix_pop_count;
  input [LANES-1:0] valid_mask;
  input [LANES-1:0] ready_mask;
  integer           i;
  reg               keep_counting;
  begin
    prefix_pop_count = 4'd0;
    keep_counting = 1'b1;
    for (i = 0; i < LANES; i = i + 1) begin
      if (keep_counting && valid_mask[i] && ready_mask[i])
        prefix_pop_count = prefix_pop_count + 4'd1;
      else if (valid_mask[i])
        keep_counting = 1'b0;
    end
  end
endfunction

function [BEAT_BITS-1:0] insert_elem;
  input [BEAT_BITS-1:0] beat;
  input [3:0]           slot;
  input [31:0]          elem;
  reg [BEAT_BITS-1:0]   next_beat;
  begin
    next_beat = beat;
    next_beat[slot*16 +: 16] = elem[15:0];
    insert_elem = next_beat;
  end
endfunction

function [31:0] extract_elem;
  input [BEAT_BITS-1:0] beat;
  input [3:0]           slot;
  begin
    extract_elem = {16'b0, beat[slot*16 +: 16]};
  end
endfunction

assign rd_issue_elems = min4_u16(n_elements_q - rd_issued_elems_q,
                                 elems_per_beat);
assign rd_can_issue = active_q &&
                      !rd_inflight_q &&
                      (rd_issued_elems_q < n_elements_q) &&
                      (in_fifo_count_q <=
                       (FIFO_DEPTH_COUNT -
                        {{(FIFO_COUNT_WIDTH-4){1'b0}}, elems_per_beat}));
assign rd_fire = rd_can_issue && dtcm_rd_ready;
assign dtcm_rd_req = rd_can_issue;
assign dtcm_rd_addr = rd_next_addr_q;
assign rd_push = dtcm_rd_rvalid && rd_inflight_q;

genvar valid_gen_i;
generate
  for (valid_gen_i = 0; valid_gen_i < LANES; valid_gen_i = valid_gen_i + 1) begin: CORE_IN_GEN
    assign core_in_valid[valid_gen_i] =
      active_q &&
      (in_fifo_count_q > valid_gen_i[FIFO_COUNT_WIDTH-1:0]) &&
      ((in_streamed_elems_q + valid_gen_i[15:0]) < n_elements_q);
    assign core_in_data[valid_gen_i*32 +: 32] =
      fifo_elem_at(in_fifo_head_q, valid_gen_i);
  end
endgenerate

assign in_pop_count = prefix_pop_count(core_in_valid, core_in_ready);

genvar ready_gen_i;
generate
  for (ready_gen_i = 0; ready_gen_i < LANES; ready_gen_i = ready_gen_i + 1) begin: CORE_OUT_GEN
    assign core_out_ready[ready_gen_i] =
      active_q &&
      !wr_pending_q &&
      (wr_pack_count_q + ready_gen_i[3:0] < elems_per_beat) &&
      ((out_accepted_elems_q + ready_gen_i[15:0]) < n_elements_q);
  end
endgenerate

assign out_accept_count = prefix_pop_count(core_out_valid, core_out_ready);
assign out_accepted_after_accept =
       out_accepted_elems_q + {12'b0, out_accept_count};
assign wr_pack_count_after_accept =
       wr_pack_count_q + out_accept_count;
assign wr_tail_after_accept =
       (out_accept_count != 4'd0) &&
       (out_accepted_after_accept == n_elements_q);
assign wr_make_pending =
       (out_accept_count != 4'd0) &&
       ((wr_pack_count_after_accept == elems_per_beat) ||
        wr_tail_after_accept);
assign wr_pending_elems_next = wr_pack_count_after_accept;

reg [BEAT_BITS-1:0] wr_pack_data_comb;
always @* begin
  wr_pack_data_comb = wr_pack_data_q;
  for (pack_i = 0; pack_i < LANES; pack_i = pack_i + 1) begin
    if (pack_i < out_accept_count)
      wr_pack_data_comb = insert_elem(
        wr_pack_data_comb,
        wr_pack_count_q + pack_i[3:0],
        core_out_data[pack_i*32 +: 32]
      );
  end
end
assign wr_pack_data_after_accept = wr_pack_data_comb;

reg [(BEAT_BITS/8)-1:0] wr_wstrb_comb;
always @* begin
  wr_wstrb_comb = {(BEAT_BITS/8){1'b0}};
  for (byte_i = 0; byte_i < BEAT_BYTES; byte_i = byte_i + 1) begin
    if (byte_i < (wr_pending_elems_next * elem_bytes))
      wr_wstrb_comb[byte_i] = 1'b1;
  end
end
assign wr_wstrb_after_accept = wr_wstrb_comb;

assign dtcm_wr_req = wr_pending_q;
assign dtcm_wr_addr = wr_next_addr_q;
assign dtcm_wr_wdata = wr_pending_data_q;
assign dtcm_wr_wstrb = wr_pending_wstrb_q;
assign wr_fire = wr_pending_q && dtcm_wr_ready;

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    active_q <= 1'b0;
    in_base_addr_q <= {ADDR_WIDTH{1'b0}};
    out_base_addr_q <= {ADDR_WIDTH{1'b0}};
    n_elements_q <= 16'b0;
    rd_issued_elems_q <= 16'b0;
    rd_returned_elems_q <= 16'b0;
    in_streamed_elems_q <= 16'b0;
    out_accepted_elems_q <= 16'b0;
    wr_committed_elems_q <= 16'b0;
    rd_inflight_q <= 1'b0;
    rd_inflight_elems_q <= 4'b0;
    rd_next_addr_q <= {ADDR_WIDTH{1'b0}};
    wr_next_addr_q <= {ADDR_WIDTH{1'b0}};
    in_fifo_head_q <= {FIFO_INDEX_WIDTH{1'b0}};
    in_fifo_tail_q <= {FIFO_INDEX_WIDTH{1'b0}};
    in_fifo_count_q <= {FIFO_COUNT_WIDTH{1'b0}};
    wr_pack_data_q <= {BEAT_BITS{1'b0}};
    wr_pack_count_q <= 4'b0;
    wr_pending_q <= 1'b0;
    wr_pending_data_q <= {BEAT_BITS{1'b0}};
    wr_pending_wstrb_q <= {(BEAT_BITS/8){1'b0}};
    wr_pending_elems_q <= 4'b0;
    done_valid_q <= 1'b0;
  end else begin
    done_valid_q <= 1'b0;

    if (start_fire) begin
      active_q <= (n_elements != 16'b0);
      in_base_addr_q <= in_base_addr;
      out_base_addr_q <= out_base_addr;
      n_elements_q <= n_elements;
      rd_issued_elems_q <= 16'b0;
      rd_returned_elems_q <= 16'b0;
      in_streamed_elems_q <= 16'b0;
      out_accepted_elems_q <= 16'b0;
      wr_committed_elems_q <= 16'b0;
      rd_inflight_q <= 1'b0;
      rd_inflight_elems_q <= 4'b0;
      rd_next_addr_q <= {in_base_addr[ADDR_WIDTH-1:1], 1'b0};
      wr_next_addr_q <= {out_base_addr[ADDR_WIDTH-1:1], 1'b0};
      in_fifo_head_q <= {FIFO_INDEX_WIDTH{1'b0}};
      in_fifo_tail_q <= {FIFO_INDEX_WIDTH{1'b0}};
      in_fifo_count_q <= {FIFO_COUNT_WIDTH{1'b0}};
      wr_pack_data_q <= {BEAT_BITS{1'b0}};
      wr_pack_count_q <= 4'b0;
      wr_pending_q <= 1'b0;
      wr_pending_data_q <= {BEAT_BITS{1'b0}};
      wr_pending_wstrb_q <= {(BEAT_BITS/8){1'b0}};
      wr_pending_elems_q <= 4'b0;
      if (n_elements == 16'b0)
        done_valid_q <= 1'b1;
    end else begin
      if (rd_fire) begin
        rd_inflight_q <= 1'b1;
        rd_inflight_elems_q <= rd_issue_elems;
        rd_issued_elems_q <= rd_issued_elems_q + {12'b0, rd_issue_elems};
        rd_next_addr_q <= rd_next_addr_q + {{ADDR_WIDTH-2{1'b0}}, 2'd2};
      end

      if (rd_push) begin
        for (push_i = 0; push_i < MAX_ELEMS_PER_BEAT; push_i = push_i + 1) begin
          if (push_i < rd_inflight_elems_q) begin
            in_fifo[in_fifo_tail_q + push_i[FIFO_INDEX_WIDTH-1:0]] <=
              extract_elem(dtcm_rd_rdata, push_i[3:0]);
          end
        end
        rd_inflight_q <= 1'b0;
        rd_inflight_elems_q <= 4'b0;
        rd_returned_elems_q <= rd_returned_elems_q
                               + {12'b0, rd_inflight_elems_q};
      end

      if (in_pop_count != 4'd0) begin
        in_fifo_head_q <= in_fifo_head_q
                          + {{(FIFO_INDEX_WIDTH-4){1'b0}}, in_pop_count};
        in_streamed_elems_q <= in_streamed_elems_q
                               + {12'b0, in_pop_count};
      end

      case ({rd_push, (in_pop_count != 4'd0)})
        2'b10: begin
          in_fifo_tail_q <= in_fifo_tail_q
                            + {{(FIFO_INDEX_WIDTH-4){1'b0}},
                               rd_inflight_elems_q};
          in_fifo_count_q <= in_fifo_count_q
                             + {1'b0, rd_inflight_elems_q};
        end
        2'b01: begin
          in_fifo_count_q <= in_fifo_count_q
                             - {1'b0, in_pop_count};
        end
        2'b11: begin
          in_fifo_tail_q <= in_fifo_tail_q
                            + {{(FIFO_INDEX_WIDTH-4){1'b0}},
                               rd_inflight_elems_q};
          in_fifo_count_q <= in_fifo_count_q
                             + {1'b0, rd_inflight_elems_q}
                             - {1'b0, in_pop_count};
        end
        default: begin
        end
      endcase

      if (out_accept_count != 4'd0) begin
        out_accepted_elems_q <= out_accepted_after_accept;
        if (wr_make_pending) begin
          wr_pending_q <= 1'b1;
          wr_pending_data_q <= wr_pack_data_after_accept;
          wr_pending_wstrb_q <= wr_wstrb_after_accept;
          wr_pending_elems_q <= wr_pending_elems_next;
          wr_pack_data_q <= {BEAT_BITS{1'b0}};
          wr_pack_count_q <= 4'b0;
        end else begin
          wr_pack_data_q <= wr_pack_data_after_accept;
          wr_pack_count_q <= wr_pack_count_after_accept;
        end
      end

      if (wr_fire) begin
        wr_pending_q <= 1'b0;
        wr_committed_elems_q <= wr_committed_elems_q
                                + {12'b0, wr_pending_elems_q};
        wr_pending_elems_q <= 4'b0;
        wr_next_addr_q <= wr_next_addr_q + {{ADDR_WIDTH-2{1'b0}}, 2'd2};
      end

      if (active_q &&
          !rd_inflight_q &&
          (rd_issued_elems_q == n_elements_q) &&
          (rd_returned_elems_q == n_elements_q) &&
          (in_streamed_elems_q == n_elements_q) &&
          (out_accepted_elems_q == n_elements_q) &&
          !wr_pending_q &&
          (wr_committed_elems_q == n_elements_q)) begin
        active_q <= 1'b0;
        done_valid_q <= 1'b1;
      end
    end
  end
end

endmodule
