// Experimental BF16-only 8x8 transpose sidecar built from four 2x2 buffers.
module edge_tensor_wld2x2_sidecar(
  clk,
  rst_b,
  start,
  start_transpose,
  start_ready,
  busy,
  done,
  load_valid,
  load_ready,
  load_data,
  drain_valid,
  drain_ready,
  drain_data,
  drain_lane_valid,
  drain_transpose,
  drain_target_dot,
  drain_quarter
);

input          clk;
input          rst_b;
input          start;
input          start_transpose;
output         start_ready;
output         busy;
output         done;
input          load_valid;
output         load_ready;
input  [127:0] load_data;
output         drain_valid;
input          drain_ready;
output [127:0] drain_data;
output [3:0]   drain_lane_valid;
output         drain_transpose;
output [11:0]  drain_target_dot;
output [1:0]   drain_quarter;

localparam STATE_IDLE  = 2'd0;
localparam STATE_LOAD  = 2'd1;
localparam STATE_DRAIN = 2'd2;

reg [1:0] state_q;
reg       load_phase_q;
reg       drain_phase_q;
reg [1:0] row_pair_q;
reg [2:0] row_q;
reg [1:0] quarter_q;
reg       transpose_q;
reg [15:0] entry_q [0:3][0:3];
reg         done_q;
reg [127:0] drain_data_comb;
reg [11:0]  drain_target_comb;

integer channel_i;

assign start_ready = (state_q == STATE_IDLE);
assign busy = (state_q != STATE_IDLE);
assign done = done_q;
assign load_ready = (state_q == STATE_LOAD);
assign drain_valid = (state_q == STATE_DRAIN);
assign drain_data = drain_data_comb;
assign drain_target_dot = drain_target_comb;
assign drain_lane_valid = transpose_q ? 4'b1111 : 4'b0001;
assign drain_transpose = transpose_q;
assign drain_quarter = transpose_q ? row_pair_q : quarter_q;

always @(*) begin
  drain_data_comb = 128'b0;
  drain_target_comb = 12'b0;
  if (transpose_q) begin
    for (channel_i = 0; channel_i < 4; channel_i = channel_i + 1) begin
      drain_data_comb[channel_i*32 +: 32] = drain_phase_q
          ? {entry_q[channel_i][3], entry_q[channel_i][2]}
          : {entry_q[channel_i][1], entry_q[channel_i][0]};
      drain_target_comb[channel_i*3 +: 3] =
          {channel_i[1:0], drain_phase_q};
    end
  end else begin
    drain_data_comb[31:0] =
        {entry_q[quarter_q][1], entry_q[quarter_q][0]};
    drain_target_comb[2:0] = row_q;
  end
end

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    state_q <= STATE_IDLE;
    load_phase_q <= 1'b0;
    drain_phase_q <= 1'b0;
    row_pair_q <= 2'b0;
    row_q <= 3'b0;
    quarter_q <= 2'b0;
    transpose_q <= 1'b0;
    done_q <= 1'b0;
    for (channel_i = 0; channel_i < 4; channel_i = channel_i + 1) begin
      entry_q[channel_i][0] <= 16'b0;
      entry_q[channel_i][1] <= 16'b0;
      entry_q[channel_i][2] <= 16'b0;
      entry_q[channel_i][3] <= 16'b0;
    end
  end else begin
    done_q <= 1'b0;
    case (state_q)
      STATE_IDLE: begin
        if (start) begin
          state_q <= STATE_LOAD;
          load_phase_q <= 1'b0;
          drain_phase_q <= 1'b0;
          row_pair_q <= 2'b0;
          row_q <= 3'b0;
          quarter_q <= 2'b0;
          transpose_q <= start_transpose;
        end
      end
      STATE_LOAD: begin
        if (load_valid) begin
          for (channel_i = 0; channel_i < 4; channel_i = channel_i + 1) begin
            if (transpose_q) begin
              if (!load_phase_q) begin
                entry_q[channel_i][0] <= load_data[(channel_i*2)*16 +: 16];
                entry_q[channel_i][2] <= load_data[(channel_i*2+1)*16 +: 16];
              end else begin
                entry_q[channel_i][1] <= load_data[(channel_i*2)*16 +: 16];
                entry_q[channel_i][3] <= load_data[(channel_i*2+1)*16 +: 16];
              end
            end else begin
              entry_q[channel_i][0] <= load_data[channel_i*32 +: 16];
              entry_q[channel_i][1] <= load_data[channel_i*32+16 +: 16];
            end
          end
          if (!transpose_q || load_phase_q) begin
            state_q <= STATE_DRAIN;
            drain_phase_q <= 1'b0;
            quarter_q <= 2'b0;
          end
          if (transpose_q)
            load_phase_q <= !load_phase_q;
        end
      end
      STATE_DRAIN: begin
        if (drain_ready) begin
          if (!transpose_q) begin
            if (quarter_q == 2'd3) begin
              if (row_q == 3'd7) begin
                state_q <= STATE_IDLE;
                done_q <= 1'b1;
              end else begin
                row_q <= row_q + 3'd1;
                state_q <= STATE_LOAD;
              end
            end else begin
              quarter_q <= quarter_q + 2'd1;
            end
          end else if (drain_phase_q) begin
            if (row_pair_q == 2'd3) begin
              state_q <= STATE_IDLE;
              done_q <= 1'b1;
            end else begin
              row_pair_q <= row_pair_q + 2'd1;
              load_phase_q <= 1'b0;
              state_q <= STATE_LOAD;
            end
          end
          drain_phase_q <= !drain_phase_q;
        end
      end
      default: state_q <= STATE_IDLE;
    endcase
  end
end

endmodule
