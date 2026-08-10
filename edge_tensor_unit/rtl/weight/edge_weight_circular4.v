// Four format-agnostic 64-bit circular lanes for an 8x8 packed weight tile.
module edge_weight_circular4(
  clk, rst_b,
  start, start_ready, start_weight_format, start_transpose,
  busy, done,
  load_valid, load_ready, load_data,
  drain_valid, drain_ready, drain_data, drain_lane_valid,
  drain_weight_format, drain_target_dot, drain_fill_slot
);

input          clk;
input          rst_b;
input          start;
output         start_ready;
input  [1:0]   start_weight_format;
input          start_transpose;
output         busy;
output         done;
input          load_valid;
output         load_ready;
input  [127:0] load_data;
output         drain_valid;
input          drain_ready;
output [127:0] drain_data;
output [3:0]   drain_lane_valid;
output [1:0]   drain_weight_format;
output [11:0]  drain_target_dot;
output [1:0]   drain_fill_slot;

localparam WEIGHT_BF16 = 2'd0;
localparam WEIGHT_I8   = 2'd1;
localparam STATE_IDLE  = 2'd0;
localparam STATE_LOAD  = 2'd1;
localparam STATE_DRAIN = 2'd2;

reg [1:0] state_q;
reg [1:0] format_q;
reg       transpose_q;
reg       load_phase_q;
reg [1:0] drain_phase_q;
reg [2:0] group_q;
reg       done_q;
reg [3:0] lane_write_enable [0:3];
reg [63:0] lane_write_data [0:3];
wire [63:0] lane_read_data [0:3];
reg [127:0] drain_data_comb;
reg [3:0] drain_lane_valid_comb;
reg [11:0] drain_target_comb;
reg [1:0] drain_fill_slot_comb;
integer lane_i;

wire load_accept = load_valid && load_ready;
wire drain_accept = drain_valid && drain_ready;

assign start_ready = (state_q == STATE_IDLE);
assign busy = (state_q != STATE_IDLE);
assign done = done_q;
assign load_ready = (state_q == STATE_LOAD);
assign drain_valid = (state_q == STATE_DRAIN);
assign drain_data = drain_data_comb;
assign drain_lane_valid = drain_lane_valid_comb;
assign drain_weight_format = format_q;
assign drain_target_dot = drain_target_comb;
assign drain_fill_slot = drain_fill_slot_comb;

generate
  genvar lane_g;
  for (lane_g = 0; lane_g < 4; lane_g = lane_g + 1) begin : GEN_LANE
    edge_weight_circular_lane x_lane (
      .clk(clk), .rst_b(rst_b),
      .write_valid_i(load_accept),
      .write_enable_i(lane_write_enable[lane_g]),
      .write_data_i(lane_write_data[lane_g]),
      .read_data_o(lane_read_data[lane_g])
    );
  end
endgenerate

always @(*) begin
  for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
    lane_write_enable[lane_i] = 4'b0;
    lane_write_data[lane_i] = 64'b0;
    if (format_q == WEIGHT_BF16) begin
      // Transpose interleaves two rows by column; normal needs one row only.
      if (!transpose_q) begin
        lane_write_enable[lane_i] = 4'b0011;
        lane_write_data[lane_i][31:0] = load_data[lane_i*32 +: 32];
      end else begin
        lane_write_enable[lane_i] = load_phase_q ? 4'b1010 : 4'b0101;
        lane_write_data[lane_i][load_phase_q*16 +: 16] =
            load_data[(lane_i*2)*16 +: 16];
        lane_write_data[lane_i][32+load_phase_q*16 +: 16] =
            load_data[(lane_i*2+1)*16 +: 16];
      end
    end else if (format_q == WEIGHT_I8) begin
      if (!transpose_q) begin
        // Two packed rows arrive per beat; two beats fill four lanes.
        if (lane_i[1] == load_phase_q) begin
          lane_write_enable[lane_i] = 4'b1111;
          lane_write_data[lane_i] = load_data[lane_i[0]*64 +: 64];
        end
      end else begin
        // A lane owns a column pair.  Low/high halves hold even/odd columns.
        lane_write_enable[lane_i] = load_phase_q ? 4'b1010 : 4'b0101;
        lane_write_data[lane_i][load_phase_q*16 +: 8] =
            load_data[(lane_i*2)*8 +: 8];
        lane_write_data[lane_i][load_phase_q*16+8 +: 8] =
            load_data[(8+lane_i*2)*8 +: 8];
        lane_write_data[lane_i][32+load_phase_q*16 +: 8] =
            load_data[(lane_i*2+1)*8 +: 8];
        lane_write_data[lane_i][40+load_phase_q*16 +: 8] =
            load_data[(8+lane_i*2+1)*8 +: 8];
      end
    end
  end
end

always @(*) begin
  drain_data_comb = 128'b0;
  drain_lane_valid_comb = 4'b0;
  drain_target_comb = 12'b0;
  drain_fill_slot_comb = 2'b0;

  if (format_q == WEIGHT_BF16) begin
    drain_fill_slot_comb = transpose_q ? group_q[1:0] : drain_phase_q;
    if (transpose_q) begin
      drain_lane_valid_comb = 4'b1111;
      for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
        drain_data_comb[lane_i*32 +: 32] =
            drain_phase_q[0] ? lane_read_data[lane_i][63:32]
                             : lane_read_data[lane_i][31:0];
        drain_target_comb[lane_i*3 +: 3] = {lane_i[1:0], drain_phase_q[0]};
      end
    end else begin
      drain_lane_valid_comb = 4'b0001;
      drain_data_comb[31:0] = lane_read_data[drain_phase_q][31:0];
      drain_target_comb[2:0] = group_q;
    end
  end else if (format_q == WEIGHT_I8) begin
    // Normal phase chooses the low/high half of a target row.  Under
    // transpose, phase chooses a target column and group chooses whether the
    // packed data contains source rows 0..3 or 4..7.
    drain_fill_slot_comb = {1'b0, transpose_q ? group_q[0]
                                               : drain_phase_q[0]};
    drain_lane_valid_comb = 4'b1111;
    for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
      drain_data_comb[lane_i*32 +: 32] =
          drain_phase_q[0] ? lane_read_data[lane_i][63:32]
                           : lane_read_data[lane_i][31:0];
      if (transpose_q)
        drain_target_comb[lane_i*3 +: 3] = {lane_i[1:0], drain_phase_q[0]};
      else
        drain_target_comb[lane_i*3 +: 3] = {group_q[0], lane_i[1:0]};
    end
  end
end

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    state_q <= STATE_IDLE;
    format_q <= WEIGHT_BF16;
    transpose_q <= 1'b0;
    load_phase_q <= 1'b0;
    drain_phase_q <= 2'b0;
    group_q <= 3'b0;
    done_q <= 1'b0;
  end else begin
    done_q <= 1'b0;
    case (state_q)
      STATE_IDLE: if (start) begin
        if (start_weight_format == WEIGHT_BF16
            || start_weight_format == WEIGHT_I8) begin
          state_q <= STATE_LOAD;
          format_q <= start_weight_format;
          transpose_q <= start_transpose;
          load_phase_q <= 1'b0;
          drain_phase_q <= 2'b0;
          group_q <= 3'b0;
        end else begin
          // Reserved formats complete as a no-op until their unpackers exist.
          done_q <= 1'b1;
        end
      end
      STATE_LOAD: if (load_accept) begin
        if ((format_q == WEIGHT_BF16 && !transpose_q) || load_phase_q) begin
          state_q <= STATE_DRAIN;
          drain_phase_q <= 2'b0;
          load_phase_q <= 1'b0;
        end else begin
          load_phase_q <= 1'b1;
        end
      end
      STATE_DRAIN: if (drain_accept) begin
        if (format_q == WEIGHT_BF16 && !transpose_q) begin
          if (drain_phase_q == 2'd3) begin
            if (group_q == 3'd7) begin
              state_q <= STATE_IDLE;
              done_q <= 1'b1;
            end else begin
              group_q <= group_q + 3'd1;
              state_q <= STATE_LOAD;
            end
          end else begin
            drain_phase_q <= drain_phase_q + 2'd1;
          end
        end else if (drain_phase_q[0]) begin
          if ((format_q == WEIGHT_BF16 && group_q == 3'd3)
              || (format_q == WEIGHT_I8 && group_q == 3'd1)) begin
            state_q <= STATE_IDLE;
            done_q <= 1'b1;
          end else begin
            group_q <= group_q + 3'd1;
            state_q <= STATE_LOAD;
          end
          drain_phase_q <= 2'b0;
        end else begin
          drain_phase_q <= 2'd1;
        end
      end
      default: state_q <= STATE_IDLE;
    endcase
  end
end

endmodule
