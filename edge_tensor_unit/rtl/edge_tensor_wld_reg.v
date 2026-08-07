module edge_tensor_wld_reg(
  clk,
  clear,
  drain_busy,
  drain_col_pair,
  drain_data,
  drain_done,
  drain_start,
  drain_bf16_mode,
  drain_transpose,
  drain_valid,
  load_data,
  load_done,
  load_idx,
  load_bf16_mode,
  load_valid,
  rst_b
);

input          clk;
input          clear;
input          drain_start;
input          drain_bf16_mode;
input          drain_transpose;
input  [127:0] load_data;
input  [2:0]   load_idx;
input          load_bf16_mode;
input          load_valid;
input          rst_b;
output         drain_busy;
output [1:0]   drain_col_pair;
output [127:0] drain_data;
output         drain_done;
output         drain_valid;
output         load_done;

reg [15:0]  wld_reg [0:7][0:7];
reg [7:0]   load_done_mask;
reg         drain_busy_q;
reg [2:0]   drain_idx_q;
reg [1:0]   drain_col_pair_out_q;
reg         drain_bf16_mode_q;
reg         drain_transpose_q;
reg [127:0] drain_data_q;
reg [127:0] drain_data_next;
reg         drain_done_q;
reg         drain_beat_ready;
reg         drain_valid_q;

integer row_i;
integer col_i;
integer lane_i;
integer beat_i;
integer byte_idx;
integer load_row;
integer load_col;

assign drain_busy = drain_busy_q;
assign drain_col_pair[1:0] = drain_col_pair_out_q[1:0];
assign drain_data[127:0] = drain_data_q[127:0];
assign drain_done = drain_done_q;
assign drain_valid = drain_valid_q;
assign load_done = load_bf16_mode ? (load_done_mask[7:0] == 8'hff)
                                  : (load_done_mask[3:0] == 4'hf);

always @(*) begin
  if (drain_transpose_q) begin
    if (drain_bf16_mode_q)
      drain_beat_ready = load_done_mask[drain_idx_q];
    else
      drain_beat_ready = load_done_mask[{1'b0, drain_idx_q[1:0]}];
  end
  else
    drain_beat_ready = drain_bf16_mode_q
                     ? (load_done_mask[7:0] == 8'hff)
                     : (load_done_mask[3:0] == 4'hf);
end

always @(*) begin
  drain_data_next[127:0] = 128'b0;
  for (lane_i = 0; lane_i < 8; lane_i = lane_i + 1) begin
    if (drain_bf16_mode_q) begin
      if (drain_transpose_q)
        drain_data_next[lane_i*16 +: 16] = wld_reg[drain_idx_q][lane_i];
      else
        drain_data_next[lane_i*16 +: 16] = wld_reg[lane_i][drain_idx_q];
    end else if (drain_transpose_q) begin
      drain_data_next[lane_i*16 +: 8] =
        wld_reg[{drain_idx_q[1:0], 1'b0}][lane_i][7:0];
      drain_data_next[lane_i*16 + 8 +: 8] =
        wld_reg[{drain_idx_q[1:0], 1'b0} + 3'd1][lane_i][7:0];
    end else begin
      drain_data_next[lane_i*16 +: 8] =
        wld_reg[lane_i][{drain_idx_q[1:0], 1'b0}][7:0];
      drain_data_next[lane_i*16 + 8 +: 8] =
        wld_reg[lane_i][{drain_idx_q[1:0], 1'b0} + 3'd1][7:0];
    end
  end
end

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    load_done_mask[7:0] <= 8'b0;
    drain_busy_q <= 1'b0;
    drain_idx_q[2:0] <= 3'b0;
    drain_col_pair_out_q[1:0] <= 2'b0;
    drain_bf16_mode_q <= 1'b0;
    drain_transpose_q <= 1'b0;
    drain_data_q[127:0] <= 128'b0;
    drain_done_q <= 1'b0;
    drain_valid_q <= 1'b0;
    for (row_i = 0; row_i < 8; row_i = row_i + 1) begin
      for (col_i = 0; col_i < 8; col_i = col_i + 1) begin
        wld_reg[row_i][col_i] <= 16'b0;
      end
    end
  end else begin
    drain_done_q <= 1'b0;
    drain_valid_q <= 1'b0;

    if (clear) begin
      load_done_mask[7:0] <= 8'b0;
      drain_busy_q <= 1'b0;
      drain_idx_q[2:0] <= 3'b0;
      drain_col_pair_out_q[1:0] <= 2'b0;
      drain_bf16_mode_q <= drain_bf16_mode;
      drain_transpose_q <= 1'b0;
    end else begin
      if (load_valid) begin
        if (load_bf16_mode) begin
          for (beat_i = 0; beat_i < 8; beat_i = beat_i + 1)
            wld_reg[load_idx][beat_i] <= load_data[beat_i*16 +: 16];
        end else begin
          for (beat_i = 0; beat_i < 16; beat_i = beat_i + 1) begin
            byte_idx = (load_idx[1:0] * 16) + beat_i;
            load_row = byte_idx >> 3;
            load_col = byte_idx & 7;
            wld_reg[load_row][load_col] <=
                {8'b0, load_data[beat_i*8 +: 8]};
          end
        end
        load_done_mask[load_idx] <= 1'b1;
      end

      if (drain_start) begin
        drain_busy_q <= 1'b1;
        drain_idx_q[2:0] <= 3'b0;
        drain_bf16_mode_q <= drain_bf16_mode;
        drain_transpose_q <= drain_transpose;
      end else if (drain_busy_q && drain_beat_ready) begin
        drain_col_pair_out_q[1:0] <= drain_idx_q[1:0];
        drain_data_q[127:0] <= drain_data_next[127:0];
        drain_valid_q <= 1'b1;
        if (drain_idx_q[2:0] == (drain_bf16_mode_q ? 3'd7 : 3'd3)) begin
          drain_busy_q <= 1'b0;
          drain_done_q <= 1'b1;
        end else begin
          drain_idx_q[2:0] <= drain_idx_q[2:0] + 3'd1;
        end
      end
    end
  end
end

endmodule
