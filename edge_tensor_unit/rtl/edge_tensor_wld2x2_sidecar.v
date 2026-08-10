// Experimental BF16-only 8x8 transpose sidecar built from four 2x2 buffers.
module edge_tensor_wld2x2_sidecar(
  clk,
  rst_b,
  start,
  start_ready,
  busy,
  done,
  load_valid,
  load_ready,
  load_data,
  drain_valid,
  drain_ready,
  drain_data,
  drain_target_dot,
  drain_quarter
);

input          clk;
input          rst_b;
input          start;
output         start_ready;
output         busy;
output         done;
input          load_valid;
output         load_ready;
input  [127:0] load_data;
output         drain_valid;
input          drain_ready;
output [127:0] drain_data;
output [11:0]  drain_target_dot;
output [1:0]   drain_quarter;

localparam STATE_IDLE  = 2'd0;
localparam STATE_LOAD  = 2'd1;
localparam STATE_DRAIN = 2'd2;

reg [1:0] state_q;
reg       load_phase_q;
reg       drain_phase_q;
reg [1:0] row_pair_q;
reg [15:0] entry_q [0:3][0:3];
reg         done_q;

integer channel_i;

assign start_ready = (state_q == STATE_IDLE);
assign busy = (state_q != STATE_IDLE);
assign done = done_q;
assign load_ready = (state_q == STATE_LOAD);
assign drain_valid = (state_q == STATE_DRAIN);
assign drain_quarter = row_pair_q;

generate
  genvar channel;
  for (channel = 0; channel < 4; channel = channel + 1) begin : GEN_DRAIN
    assign drain_data[channel*32 +: 32] = drain_phase_q
        ? {entry_q[channel][3], entry_q[channel][2]}
        : {entry_q[channel][1], entry_q[channel][0]};
    assign drain_target_dot[channel*3 +: 3] =
        {channel[1:0], drain_phase_q};
  end
endgenerate

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    state_q <= STATE_IDLE;
    load_phase_q <= 1'b0;
    drain_phase_q <= 1'b0;
    row_pair_q <= 2'b0;
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
        end
      end
      STATE_LOAD: begin
        if (load_valid) begin
          for (channel_i = 0; channel_i < 4; channel_i = channel_i + 1) begin
            if (!load_phase_q) begin
              entry_q[channel_i][0] <= load_data[(channel_i*2)*16 +: 16];
              entry_q[channel_i][2] <= load_data[(channel_i*2+1)*16 +: 16];
            end else begin
              entry_q[channel_i][1] <= load_data[(channel_i*2)*16 +: 16];
              entry_q[channel_i][3] <= load_data[(channel_i*2+1)*16 +: 16];
            end
          end
          if (load_phase_q) begin
            state_q <= STATE_DRAIN;
            drain_phase_q <= 1'b0;
          end
          load_phase_q <= !load_phase_q;
        end
      end
      STATE_DRAIN: begin
        if (drain_ready) begin
          if (drain_phase_q) begin
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
