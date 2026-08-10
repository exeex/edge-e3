`timescale 1ns/1ps

module edge_accel_io #(
  parameter ADDR_WIDTH = 16,
  parameter FIFO_DEPTH = 32,
  parameter FIFO_INDEX_WIDTH = 5,
  parameter BEAT_BITS = 128
) (
  input wire clk,
  input wire cpurst_b,
  input wire start_valid,
  output wire start_ready,
  input wire start_owner,
  input wire [3:0] start_mode,
  input wire src0_enable,
  input wire src0_is_byte,
  input wire [ADDR_WIDTH-1:0] src0_addr,
  input wire src1_enable,
  input wire src1_is_byte,
  input wire [ADDR_WIDTH-1:0] src1_addr,
  input wire src2_enable,
  input wire src2_is_byte,
  input wire [ADDR_WIDTH-1:0] src2_addr,
  input wire dst_enable,
  input wire dst_is_byte,
  input wire [ADDR_WIDTH-1:0] dst_addr,
  input wire [15:0] n_elements,
  output wire busy,
  output wire done_valid,

  output wire dtcm_rd_req,
  input wire dtcm_rd_ready,
  output wire [ADDR_WIDTH-1:0] dtcm_rd_addr,
  input wire dtcm_rd_rvalid,
  input wire [BEAT_BITS-1:0] dtcm_rd_rdata,
  output wire dtcm_wr_req,
  input wire dtcm_wr_ready,
  output wire [ADDR_WIDTH-1:0] dtcm_wr_addr,
  output wire [BEAT_BITS-1:0] dtcm_wr_wdata,
  output wire [(BEAT_BITS/8)-1:0] dtcm_wr_wstrb,

  output wire core_start_valid,
  input wire core_start_ready,
  output wire core_owner,
  output wire [3:0] core_mode,
  output wire core_in_valid,
  input wire core_in_ready,
  output wire [15:0] core_src0,
  output wire [15:0] core_src1,
  output wire [15:0] core_src2,
  output wire [15:0] core_index,
  output wire core_last,
  input wire core_out_valid,
  output wire core_out_ready,
  input wire [15:0] core_out_data,
  input wire core_out_last,
  input wire core_result_valid,
  output wire core_result_ready
);

localparam STATE_IDLE = 2'd0;
localparam STATE_START = 2'd1;
localparam STATE_ACTIVE = 2'd2;
localparam BEAT_BYTES = BEAT_BITS / 8;
localparam WR_FIFO_DEPTH = 2;

reg [1:0] state_q;
reg owner_q;
reg [3:0] mode_q;
reg [2:0] src_enable_q;
reg [2:0] src_is_byte_q;
reg dst_enable_q;
reg dst_is_byte_q;
reg [ADDR_WIDTH-1:0] src_next_addr_q [0:2];
reg [ADDR_WIDTH-1:0] dst_next_addr_q;
reg [15:0] n_q;
reg [15:0] src_issued_q [0:2];
reg [15:0] streamed_q;
reg [15:0] out_accepted_q;
reg [15:0] wr_committed_q;

// Each source owns one 128-bit reservoir and one current-element head.
// beat_count_q counts future elements in beat_q; head_q is a copy and is not
// additional logical stream capacity.
reg [BEAT_BITS-1:0] src_beat_q [0:2];
reg [15:0] src_head_q [0:2];
reg src_head_valid_q [0:2];
reg [4:0] src_beat_count_q [0:2];
reg [3:0] src_next_lane_q [0:2];

reg rd_inflight_q;
reg [1:0] rd_tag_q;
reg [4:0] rd_elems_q;
reg [1:0] rr_q;

// Results pack directly into a beat. Two completed beats absorb DTCM stalls.
reg [BEAT_BITS-1:0] wr_pack_q;
reg [4:0] wr_pack_count_q;
reg [BEAT_BITS-1:0] wr_fifo_data_q [0:WR_FIFO_DEPTH-1];
reg [BEAT_BYTES-1:0] wr_fifo_strb_q [0:WR_FIFO_DEPTH-1];
reg [4:0] wr_fifo_elems_q [0:WR_FIFO_DEPTH-1];
reg wr_fifo_head_q;
reg wr_fifo_tail_q;
reg [1:0] wr_fifo_count_q;
reg done_q;

wire start_fire = start_valid && start_ready;
wire core_start_fire = core_start_valid && core_start_ready;
wire stream_fire = core_in_valid && core_in_ready;
wire output_push = core_out_valid && core_out_ready;
wire write_fire = dtcm_wr_req && dtcm_wr_ready;
wire read_return = dtcm_rd_rvalid && rd_inflight_q;
wire [4:0] dst_beat_elems = dst_is_byte_q ? 5'd16 : 5'd8;
wire [4:0] pack_after = wr_pack_count_q + 5'd1;
wire pack_would_complete = (pack_after == dst_beat_elems) || core_out_last;
wire make_pending = output_push && pack_would_complete;
wire wr_fifo_can_push = (wr_fifo_count_q < WR_FIFO_DEPTH) || write_fire;
wire [15:0] next_streamed = streamed_q + 16'd1;
wire [16:0] reserved_outputs = {1'b0, streamed_q} -
                               {1'b0, wr_committed_q};
// Keep one completed-beat slot available for the next fixed-latency result.
// The usable credit is one queued beat plus one not-yet-complete pack.
wire [16:0] output_capacity = dst_is_byte_q ? 17'd31 : 17'd15;
wire output_capacity_available = !dst_enable_q ||
                                 (reserved_outputs < output_capacity);

reg [2:0] rd_eligible;
reg [1:0] rd_select;
reg [4:0] rd_select_elems;
reg [ADDR_WIDTH-1:0] rd_select_addr;
reg [BEAT_BITS-1:0] pack_after_data;
reg [BEAT_BYTES-1:0] pack_after_strb;
integer s;
integer b;

function [4:0] min_beat;
  input [15:0] remaining;
  input is_byte;
  reg [4:0] capacity;
  begin
    capacity = is_byte ? 5'd16 : 5'd8;
    min_beat = (remaining < {11'b0, capacity}) ? remaining[4:0] : capacity;
  end
endfunction

function [15:0] beat_element;
  input [BEAT_BITS-1:0] beat;
  input is_byte;
  input [3:0] lane;
  begin
    if (is_byte) begin
      case (lane)
        4'd0: beat_element = {8'b0, beat[7:0]};
        4'd1: beat_element = {8'b0, beat[15:8]};
        4'd2: beat_element = {8'b0, beat[23:16]};
        4'd3: beat_element = {8'b0, beat[31:24]};
        4'd4: beat_element = {8'b0, beat[39:32]};
        4'd5: beat_element = {8'b0, beat[47:40]};
        4'd6: beat_element = {8'b0, beat[55:48]};
        4'd7: beat_element = {8'b0, beat[63:56]};
        4'd8: beat_element = {8'b0, beat[71:64]};
        4'd9: beat_element = {8'b0, beat[79:72]};
        4'd10: beat_element = {8'b0, beat[87:80]};
        4'd11: beat_element = {8'b0, beat[95:88]};
        4'd12: beat_element = {8'b0, beat[103:96]};
        4'd13: beat_element = {8'b0, beat[111:104]};
        4'd14: beat_element = {8'b0, beat[119:112]};
        default: beat_element = {8'b0, beat[127:120]};
      endcase
    end else begin
      case (lane[2:0])
        3'd0: beat_element = beat[15:0];
        3'd1: beat_element = beat[31:16];
        3'd2: beat_element = beat[47:32];
        3'd3: beat_element = beat[63:48];
        3'd4: beat_element = beat[79:64];
        3'd5: beat_element = beat[95:80];
        3'd6: beat_element = beat[111:96];
        default: beat_element = beat[127:112];
      endcase
    end
  end
endfunction

assign start_ready = (state_q == STATE_IDLE);
assign busy = (state_q != STATE_IDLE);
assign done_valid = done_q;
assign core_start_valid = (state_q == STATE_START);
assign core_owner = owner_q;
assign core_mode = mode_q;
assign core_in_valid = (state_q == STATE_ACTIVE) &&
                       (!src_enable_q[0] || src_head_valid_q[0]) &&
                       (!src_enable_q[1] || src_head_valid_q[1]) &&
                       (!src_enable_q[2] || src_head_valid_q[2]) &&
                       (streamed_q < n_q) && output_capacity_available;
assign core_src0 = src_head_q[0];
assign core_src1 = src_head_q[1];
assign core_src2 = src_head_q[2];
assign core_index = streamed_q;
assign core_last = (streamed_q == (n_q - 16'd1));

always @* begin
  for (s = 0; s < 3; s = s + 1) begin
    rd_eligible[s] = (state_q == STATE_ACTIVE) && src_enable_q[s] &&
                     (src_issued_q[s] < n_q) &&
                     !(rd_inflight_q && (rd_tag_q == s[1:0])) &&
                     (!src_head_valid_q[s] ||
                      (src_beat_count_q[s] == 0) ||
                      ((src_beat_count_q[s] == 1) && stream_fire));
  end
  rd_select = rr_q;
  case (rr_q)
    2'd0: begin
      if (rd_eligible[0]) rd_select = 2'd0;
      else if (rd_eligible[1]) rd_select = 2'd1;
      else rd_select = 2'd2;
    end
    2'd1: begin
      if (rd_eligible[1]) rd_select = 2'd1;
      else if (rd_eligible[2]) rd_select = 2'd2;
      else rd_select = 2'd0;
    end
    default: begin
      if (rd_eligible[2]) rd_select = 2'd2;
      else if (rd_eligible[0]) rd_select = 2'd0;
      else rd_select = 2'd1;
    end
  endcase
  rd_select_elems = min_beat(n_q - src_issued_q[rd_select],
                             src_is_byte_q[rd_select]);
  rd_select_addr = src_next_addr_q[rd_select];
end

wire any_rd_eligible = |rd_eligible;
// A returning response releases the single tag soon enough to issue another
// request in the same cycle.
assign dtcm_rd_req = any_rd_eligible && (!rd_inflight_q || read_return);
assign dtcm_rd_addr = rd_select_addr;

always @* begin
  pack_after_data = wr_pack_q;
  if (dst_is_byte_q)
    pack_after_data[wr_pack_count_q*8 +: 8] = core_out_data[7:0];
  else
    pack_after_data[wr_pack_count_q*16 +: 16] = core_out_data;
  pack_after_strb = {BEAT_BYTES{1'b0}};
  for (b = 0; b < BEAT_BYTES; b = b + 1) begin
    if (dst_is_byte_q ? (b < pack_after) : (b < pack_after * 2))
      pack_after_strb[b] = 1'b1;
  end
end

assign core_out_ready = (state_q == STATE_ACTIVE) && dst_enable_q &&
                        (!pack_would_complete || wr_fifo_can_push);
assign core_result_ready = (state_q == STATE_ACTIVE) && !dst_enable_q &&
                           (streamed_q == n_q);
assign dtcm_wr_req = (wr_fifo_count_q != 2'd0);
assign dtcm_wr_addr = dst_next_addr_q;
assign dtcm_wr_wdata = wr_fifo_data_q[wr_fifo_head_q];
assign dtcm_wr_wstrb = wr_fifo_strb_q[wr_fifo_head_q];

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    state_q <= STATE_IDLE;
    owner_q <= 1'b0;
    mode_q <= 4'b0;
    src_enable_q <= 3'b0;
    src_is_byte_q <= 3'b0;
    dst_enable_q <= 1'b0;
    dst_is_byte_q <= 1'b0;
    dst_next_addr_q <= {ADDR_WIDTH{1'b0}};
    n_q <= 16'b0;
    streamed_q <= 16'b0;
    out_accepted_q <= 16'b0;
    wr_committed_q <= 16'b0;
    rd_inflight_q <= 1'b0;
    rd_tag_q <= 2'b0;
    rd_elems_q <= 5'b0;
    rr_q <= 2'b0;
    wr_pack_q <= {BEAT_BITS{1'b0}};
    wr_pack_count_q <= 5'b0;
    wr_fifo_head_q <= 1'b0;
    wr_fifo_tail_q <= 1'b0;
    wr_fifo_count_q <= 2'b0;
    done_q <= 1'b0;
    for (s = 0; s < 3; s = s + 1) begin
      src_next_addr_q[s] <= {ADDR_WIDTH{1'b0}};
      src_issued_q[s] <= 16'b0;
      src_beat_q[s] <= {BEAT_BITS{1'b0}};
      src_head_q[s] <= 16'b0;
      src_head_valid_q[s] <= 1'b0;
      src_beat_count_q[s] <= 5'b0;
      src_next_lane_q[s] <= 4'b0;
    end
  end else begin
    done_q <= 1'b0;
    if (start_fire) begin
      owner_q <= start_owner;
      mode_q <= start_mode;
      src_enable_q <= {src2_enable, src1_enable, src0_enable};
      src_is_byte_q <= {src2_is_byte, src1_is_byte, src0_is_byte};
      dst_enable_q <= dst_enable;
      dst_is_byte_q <= dst_is_byte;
      src_next_addr_q[0] <= {src0_addr[ADDR_WIDTH-1:1], 1'b0};
      src_next_addr_q[1] <= {src1_addr[ADDR_WIDTH-1:1], 1'b0};
      src_next_addr_q[2] <= {src2_addr[ADDR_WIDTH-1:1], 1'b0};
      dst_next_addr_q <= {dst_addr[ADDR_WIDTH-1:1], 1'b0};
      n_q <= n_elements;
      streamed_q <= 16'b0;
      out_accepted_q <= 16'b0;
      wr_committed_q <= 16'b0;
      rd_inflight_q <= 1'b0;
      rr_q <= 2'b0;
      wr_pack_q <= {BEAT_BITS{1'b0}};
      wr_pack_count_q <= 5'b0;
      wr_fifo_head_q <= 1'b0;
      wr_fifo_tail_q <= 1'b0;
      wr_fifo_count_q <= 2'b0;
      for (s = 0; s < 3; s = s + 1) begin
        src_issued_q[s] <= 16'b0;
        src_beat_q[s] <= {BEAT_BITS{1'b0}};
        src_head_q[s] <= 16'b0;
        src_head_valid_q[s] <= 1'b0;
        src_beat_count_q[s] <= 5'b0;
        src_next_lane_q[s] <= 4'b0;
      end
      if (n_elements == 0) begin
        state_q <= STATE_IDLE;
        done_q <= 1'b1;
      end else begin
        state_q <= STATE_START;
      end
    end else begin
      if (core_start_fire)
        state_q <= STATE_ACTIVE;

      // Consume all enabled source heads in lockstep.
      if (stream_fire) begin
        streamed_q <= next_streamed;
        for (s = 0; s < 3; s = s + 1) begin
          if (src_enable_q[s]) begin
            if (src_beat_count_q[s] != 0) begin
              src_head_q[s] <= beat_element(src_beat_q[s],
                                               src_is_byte_q[s],
                                               src_next_lane_q[s]);
              src_next_lane_q[s] <= src_next_lane_q[s] + 1'b1;
              src_beat_count_q[s] <= src_beat_count_q[s] - 1'b1;
            end else begin
              src_head_valid_q[s] <= 1'b0;
            end
          end
        end
      end

      if (dtcm_rd_req && dtcm_rd_ready) begin
        rd_inflight_q <= 1'b1;
        rd_tag_q <= rd_select;
        rd_elems_q <= rd_select_elems;
        src_issued_q[rd_select] <= src_issued_q[rd_select] +
                                   {11'b0, rd_select_elems};
        src_next_addr_q[rd_select] <= src_next_addr_q[rd_select] +
                                      {{ADDR_WIDTH-2{1'b0}}, 2'd2};
        rr_q <= (rd_select == 2'd2) ? 2'd0 : rd_select + 2'd1;
      end else if (read_return) begin
        rd_inflight_q <= 1'b0;
      end

      if (read_return) begin
        src_beat_q[rd_tag_q] <= dtcm_rd_rdata;
        // If the old head survives this edge, keep it and put every returned
        // element behind it. Otherwise install lane zero directly as head.
        if (src_head_valid_q[rd_tag_q] &&
            !(stream_fire && src_enable_q[rd_tag_q] &&
              (src_beat_count_q[rd_tag_q] == 0))) begin
          src_beat_count_q[rd_tag_q] <= rd_elems_q;
          src_next_lane_q[rd_tag_q] <= 4'd0;
        end else begin
          src_head_q[rd_tag_q] <= beat_element(dtcm_rd_rdata,
                                                src_is_byte_q[rd_tag_q], 4'd0);
          src_head_valid_q[rd_tag_q] <= 1'b1;
          src_beat_count_q[rd_tag_q] <= rd_elems_q - 1'b1;
          src_next_lane_q[rd_tag_q] <= 4'd1;
        end
      end

      if (output_push) begin
        out_accepted_q <= out_accepted_q + 16'd1;
        if (make_pending) begin
          wr_fifo_data_q[wr_fifo_tail_q] <= pack_after_data;
          wr_fifo_strb_q[wr_fifo_tail_q] <= pack_after_strb;
          wr_fifo_elems_q[wr_fifo_tail_q] <= pack_after;
          wr_fifo_tail_q <= wr_fifo_tail_q + 1'b1;
          wr_pack_q <= {BEAT_BITS{1'b0}};
          wr_pack_count_q <= 5'b0;
        end else begin
          wr_pack_q <= pack_after_data;
          wr_pack_count_q <= pack_after;
        end
      end
      if (write_fire) begin
        wr_committed_q <= wr_committed_q +
                          {11'b0, wr_fifo_elems_q[wr_fifo_head_q]};
        wr_fifo_head_q <= wr_fifo_head_q + 1'b1;
        dst_next_addr_q <= dst_next_addr_q + {{ADDR_WIDTH-2{1'b0}}, 2'd2};
      end
      case ({make_pending, write_fire})
        2'b10: wr_fifo_count_q <= wr_fifo_count_q + 2'd1;
        2'b01: wr_fifo_count_q <= wr_fifo_count_q - 2'd1;
        default: wr_fifo_count_q <= wr_fifo_count_q;
      endcase

      if (!dst_enable_q && core_result_valid && core_result_ready) begin
        state_q <= STATE_IDLE;
        done_q <= 1'b1;
      end else if (dst_enable_q && (streamed_q == n_q) &&
                   (out_accepted_q == n_q) &&
                   (wr_committed_q == n_q) &&
                   (wr_fifo_count_q == 2'd0) &&
                   (wr_pack_count_q == 0)) begin
        state_q <= STATE_IDLE;
        done_q <= 1'b1;
      end
    end
  end
end

wire unused_fifo_parameters = (FIFO_DEPTH == 0) || (FIFO_INDEX_WIDTH == 0);

endmodule
