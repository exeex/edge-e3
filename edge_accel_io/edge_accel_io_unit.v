`timescale 1ns/1ps

module edge_accel_io_unit #(
  parameter ADDR_WIDTH = 16,
  parameter ACTU_LATENCY = 9
) (
  input wire clk, input wire cpurst_b,
  input wire start_valid, output wire start_ready,
  input wire start_owner, input wire [3:0] start_mode,
  input wire src0_enable, input wire src0_is_byte, input wire [ADDR_WIDTH-1:0] src0_addr,
  input wire src1_enable, input wire src1_is_byte, input wire [ADDR_WIDTH-1:0] src1_addr,
  input wire src2_enable, input wire src2_is_byte, input wire [ADDR_WIDTH-1:0] src2_addr,
  input wire dst_enable, input wire dst_is_byte, input wire [ADDR_WIDTH-1:0] dst_addr,
  input wire [15:0] n_elements,
  output wire busy, output wire done_valid,
  output wire dtcm_rd_req, input wire dtcm_rd_ready,
  output wire [ADDR_WIDTH-1:0] dtcm_rd_addr,
  input wire dtcm_rd_rvalid, input wire [127:0] dtcm_rd_rdata,
  output wire dtcm_wr_req, input wire dtcm_wr_ready,
  output wire [ADDR_WIDTH-1:0] dtcm_wr_addr,
  output wire [127:0] dtcm_wr_wdata, output wire [15:0] dtcm_wr_wstrb,
  input wire [31:0] actu_scalar_bits,
  output wire [31:0] actu_last_sum_bits,
  output reg cmpu_result_update,
  output reg [15:0] cmpu_max_value,
  output reg [15:0] cmpu_argmax_idx,
  output reg [15:0] cmpu_min_value,
  output reg [15:0] cmpu_argmin_idx
);

wire core_start_valid, core_start_ready, core_owner;
wire [3:0] core_mode;
wire core_in_valid, core_in_ready, core_last;
wire [15:0] core_src0, core_src1, core_src2, core_index;
wire core_out_valid, core_out_ready, core_out_last;
wire [15:0] core_out_data;
wire core_result_valid, core_result_ready;
wire [15:0] result_max, result_argmax, result_min, result_argmin;
wire cmpu_start_valid, cmpu_start_ready;
wire [3:0] cmpu_start_mode;
wire cmpu_in_valid, cmpu_in_ready, cmpu_in_last;
wire [15:0] cmpu_lhs, cmpu_rhs, cmpu_index;
wire [7:0] cmpu_mask;
wire cmpu_out_valid, cmpu_out_last, cmpu_out_is_mask;
wire [15:0] cmpu_out_value;
wire cmpu_result_valid_i, cmpu_result_ready_i;
wire [15:0] cmpu_result_max, cmpu_result_argmax;
wire [15:0] cmpu_result_min, cmpu_result_argmin;
wire actu_in_valid_i, actu_in_ready_i, actu_out_valid_i;
wire [2:0] actu_in_mode_i, actu_out_mode_i;
wire [15:0] actu_in_bf16_i, actu_out_bf16_i;
wire actu_sum_valid_i;
wire [31:0] actu_sum_bits_i;
reg [31:0] last_actu_sum_q;
reg [31:0] active_actu_scalar_q;
wire actu_job_start = core_start_valid && core_start_ready && !core_owner;
wire [31:0] selected_actu_scalar = (core_mode == 4'd7) ?
                                           last_actu_sum_q : active_actu_scalar_q;
assign actu_last_sum_bits = last_actu_sum_q;

edge_accel_io #(.ADDR_WIDTH(ADDR_WIDTH)) io (
 .clk(clk),.cpurst_b(cpurst_b),.start_valid(start_valid),.start_ready(start_ready),
 .start_owner(start_owner),.start_mode(start_mode),
 .src0_enable(src0_enable),.src0_is_byte(src0_is_byte),.src0_addr(src0_addr),
 .src1_enable(src1_enable),.src1_is_byte(src1_is_byte),.src1_addr(src1_addr),
 .src2_enable(src2_enable),.src2_is_byte(src2_is_byte),.src2_addr(src2_addr),
 .dst_enable(dst_enable),.dst_is_byte(dst_is_byte),.dst_addr(dst_addr),
 .n_elements(n_elements),.busy(busy),.done_valid(done_valid),
 .dtcm_rd_req(dtcm_rd_req),.dtcm_rd_ready(dtcm_rd_ready),.dtcm_rd_addr(dtcm_rd_addr),
 .dtcm_rd_rvalid(dtcm_rd_rvalid),.dtcm_rd_rdata(dtcm_rd_rdata),
 .dtcm_wr_req(dtcm_wr_req),.dtcm_wr_ready(dtcm_wr_ready),.dtcm_wr_addr(dtcm_wr_addr),
 .dtcm_wr_wdata(dtcm_wr_wdata),.dtcm_wr_wstrb(dtcm_wr_wstrb),
 .core_start_valid(core_start_valid),.core_start_ready(core_start_ready),
 .core_owner(core_owner),.core_mode(core_mode),.core_in_valid(core_in_valid),
 .core_in_ready(core_in_ready),.core_src0(core_src0),.core_src1(core_src1),
 .core_src2(core_src2),.core_index(core_index),.core_last(core_last),
 .core_out_valid(core_out_valid),.core_out_ready(core_out_ready),
 .core_out_data(core_out_data),.core_out_last(core_out_last),
 .core_result_valid(core_result_valid),.core_result_ready(core_result_ready));

edge_accel_core_mux #(.ACTU_LATENCY(ACTU_LATENCY)) mux (
 .clk(clk),.cpurst_b(cpurst_b),.io_start_valid(core_start_valid),
 .io_start_ready(core_start_ready),.io_owner(core_owner),.io_mode(core_mode),
 .io_in_valid(core_in_valid),.io_in_ready(core_in_ready),.io_src0(core_src0),
 .io_src1(core_src1),.io_src2(core_src2),.io_index(core_index),.io_last(core_last),
 .io_out_valid(core_out_valid),.io_out_data(core_out_data),.io_out_last(core_out_last),
 .io_result_valid(core_result_valid),.io_result_ready(core_result_ready),
 .io_result_max_value(result_max),.io_result_argmax_idx(result_argmax),
 .io_result_min_value(result_min),.io_result_argmin_idx(result_argmin),
 .actu_in_valid(actu_in_valid_i),.actu_in_ready(actu_in_ready_i),
 .actu_in_mode(actu_in_mode_i),.actu_in_bf16(actu_in_bf16_i),
 .actu_out_valid(actu_out_valid_i),.actu_out_bf16(actu_out_bf16_i),
 .cmpu_start_valid(cmpu_start_valid),.cmpu_start_ready(cmpu_start_ready),
 .cmpu_start_mode(cmpu_start_mode),.cmpu_in_valid(cmpu_in_valid),
 .cmpu_in_ready(cmpu_in_ready),.cmpu_in_lhs(cmpu_lhs),.cmpu_in_rhs(cmpu_rhs),
 .cmpu_in_mask(cmpu_mask),.cmpu_in_index(cmpu_index),.cmpu_in_last(cmpu_in_last),
 .cmpu_out_valid(cmpu_out_valid),.cmpu_out_value(cmpu_out_value),
 .cmpu_out_last(cmpu_out_last),.cmpu_result_valid(cmpu_result_valid_i),
 .cmpu_result_ready(cmpu_result_ready_i),.cmpu_result_max_value(cmpu_result_max),
 .cmpu_result_argmax_idx(cmpu_result_argmax),.cmpu_result_min_value(cmpu_result_min),
 .cmpu_result_argmin_idx(cmpu_result_argmin));

edge_cmpu cmpu (
 .clk(clk),.cpurst_b(cpurst_b),.start_valid(cmpu_start_valid),
 .start_ready(cmpu_start_ready),.start_mode(cmpu_start_mode),
 .in_valid(cmpu_in_valid),.in_ready(cmpu_in_ready),.in_lhs(cmpu_lhs),
 .in_rhs(cmpu_rhs),.in_mask(cmpu_mask),.in_index(cmpu_index),.in_last(cmpu_in_last),
 .out_valid(cmpu_out_valid),.out_value(cmpu_out_value),
 .out_is_mask(cmpu_out_is_mask),.out_last(cmpu_out_last),
 .result_valid(cmpu_result_valid_i),.result_ready(cmpu_result_ready_i),
 .result_max_value(cmpu_result_max),.result_argmax_idx(cmpu_result_argmax),
 .result_min_value(cmpu_result_min),.result_argmin_idx(cmpu_result_argmin));

edge_actu_bf16_stream #(.PIPE_STAGES(ACTU_LATENCY)) actu (
 .clk(clk),.cpurst_b(cpurst_b),.in_valid(actu_in_valid_i),
 .in_ready(actu_in_ready_i),.in_mode(actu_in_mode_i),.in_bf16(actu_in_bf16_i),
 .in_scalar_bits(selected_actu_scalar),
 .softmax_sum_clear(actu_job_start && (core_mode == 4'd5)),
 .out_valid(actu_out_valid_i),.out_mode(actu_out_mode_i),
 .out_bf16(actu_out_bf16_i),.softmax_sum_valid(actu_sum_valid_i),
 .softmax_sum_bits(actu_sum_bits_i));

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    cmpu_result_update <= 1'b0;
    cmpu_max_value <= 16'b0; cmpu_argmax_idx <= 16'b0;
    cmpu_min_value <= 16'b0; cmpu_argmin_idx <= 16'b0;
    last_actu_sum_q <= 32'b0;
    active_actu_scalar_q <= 32'b0;
  end else begin
    cmpu_result_update <= core_result_valid && core_result_ready;
    if (core_result_valid && core_result_ready) begin
      cmpu_max_value <= result_max; cmpu_argmax_idx <= result_argmax;
      cmpu_min_value <= result_min; cmpu_argmin_idx <= result_argmin;
    end
    if (actu_sum_valid_i)
      last_actu_sum_q <= actu_sum_bits_i;
    if (actu_job_start)
      active_actu_scalar_q <= actu_scalar_bits;
  end
end

wire unused_core_out_ready = core_out_ready;
wire unused_cmpu_out_is_mask = cmpu_out_is_mask;
wire [2:0] unused_actu_out_mode = actu_out_mode_i;
endmodule
