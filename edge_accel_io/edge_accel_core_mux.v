`timescale 1ns/1ps

module edge_accel_core_mux #(
  parameter ACTU_LATENCY = 9
) (
  input wire clk,
  input wire cpurst_b,
  input wire io_start_valid,
  output wire io_start_ready,
  input wire io_owner,
  input wire [3:0] io_mode,
  input wire io_in_valid,
  output wire io_in_ready,
  input wire [15:0] io_src0,
  input wire [15:0] io_src1,
  input wire [15:0] io_src2,
  input wire [15:0] io_index,
  input wire io_last,
  output wire io_out_valid,
  output wire [15:0] io_out_data,
  output wire io_out_last,
  output wire io_result_valid,
  input wire io_result_ready,
  output wire [15:0] io_result_max_value,
  output wire [15:0] io_result_argmax_idx,
  output wire [15:0] io_result_min_value,
  output wire [15:0] io_result_argmin_idx,

  output wire actu_in_valid,
  input wire actu_in_ready,
  output wire [2:0] actu_in_mode,
  output wire [15:0] actu_in_bf16,
  input wire actu_out_valid,
  input wire [15:0] actu_out_bf16,

  output wire cmpu_start_valid,
  input wire cmpu_start_ready,
  output wire [3:0] cmpu_start_mode,
  output wire cmpu_in_valid,
  input wire cmpu_in_ready,
  output wire [15:0] cmpu_in_lhs,
  output wire [15:0] cmpu_in_rhs,
  output wire [7:0] cmpu_in_mask,
  output wire [15:0] cmpu_in_index,
  output wire cmpu_in_last,
  input wire cmpu_out_valid,
  input wire [15:0] cmpu_out_value,
  input wire cmpu_out_last,
  input wire cmpu_result_valid,
  output wire cmpu_result_ready,
  input wire [15:0] cmpu_result_max_value,
  input wire [15:0] cmpu_result_argmax_idx,
  input wire [15:0] cmpu_result_min_value,
  input wire [15:0] cmpu_result_argmin_idx
);

localparam OWNER_ACTU = 1'b0;
localparam OWNER_CMPU = 1'b1;
reg [ACTU_LATENCY-1:0] actu_last_pipe_q;
integer stage_i;

assign io_start_ready = (io_owner == OWNER_CMPU) ? cmpu_start_ready : 1'b1;
assign io_in_ready = (io_owner == OWNER_CMPU) ? cmpu_in_ready : actu_in_ready;

assign actu_in_valid = io_in_valid && (io_owner == OWNER_ACTU);
assign actu_in_mode = io_mode[2:0];
assign actu_in_bf16 = io_src0;

assign cmpu_start_valid = io_start_valid && (io_owner == OWNER_CMPU);
assign cmpu_start_mode = io_mode;
assign cmpu_in_valid = io_in_valid && (io_owner == OWNER_CMPU);
assign cmpu_in_lhs = io_src0;
assign cmpu_in_rhs = io_src1;
assign cmpu_in_mask = io_src2[7:0];
assign cmpu_in_index = io_index;
assign cmpu_in_last = io_last;

assign io_out_valid = (io_owner == OWNER_CMPU) ? cmpu_out_valid : actu_out_valid;
assign io_out_data = (io_owner == OWNER_CMPU) ? cmpu_out_value : actu_out_bf16;
assign io_out_last = (io_owner == OWNER_CMPU) ? cmpu_out_last :
                                                    actu_last_pipe_q[ACTU_LATENCY-1];
assign io_result_valid = (io_owner == OWNER_CMPU) && cmpu_result_valid;
assign cmpu_result_ready = (io_owner == OWNER_CMPU) && io_result_ready;
assign io_result_max_value = cmpu_result_max_value;
assign io_result_argmax_idx = cmpu_result_argmax_idx;
assign io_result_min_value = cmpu_result_min_value;
assign io_result_argmin_idx = cmpu_result_argmin_idx;

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    actu_last_pipe_q <= {ACTU_LATENCY{1'b0}};
  end else begin
    actu_last_pipe_q[0] <= actu_in_valid && actu_in_ready && io_last;
    for (stage_i = 1; stage_i < ACTU_LATENCY; stage_i = stage_i + 1)
      actu_last_pipe_q[stage_i] <= actu_last_pipe_q[stage_i-1];
  end
end

endmodule
