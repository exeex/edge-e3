`timescale 1ns/1ps

module edge_accel_unit #(
  parameter ADDR_WIDTH = 16,
  parameter ACTU_PIPE_STAGES = 9
) (
  input  wire                  clk,
  input  wire                  cpurst_b,

  input  wire [3:0]            actu_cmd_setcsr_dtype,
  input  wire [3:0]            actu_cmd_setcsr_mode,
  input  wire                  actu_cmd_setcsr_req,
  input  wire [ADDR_WIDTH-1:0] actu_cmd_setin_ptr,
  input  wire                  actu_cmd_setin_req,
  input  wire [ADDR_WIDTH-1:0] actu_cmd_setout_ptr,
  input  wire                  actu_cmd_setout_req,
  input  wire                  actu_cmd_setn_req,
  input  wire [15:0]           actu_cmd_setn_value,
  input  wire                  actu_cmd_setscalar_req,
  input  wire [63:0]           actu_cmd_setscalar_value,
  input  wire                  actu_cmd_start_req,
  input  wire                  actu_cmd_sync_req,
  output wire                  actu_cmd_ready,
  output wire                  actu_start_ready,
  output wire                  actu_sync_stall,
  output wire                  actu_busy,
  output wire                  actu_done_valid,

  input  wire [3:0]            cmpu_cmd_setcsr_mode,
  input  wire                  cmpu_cmd_setcsr_req,
  input  wire [ADDR_WIDTH-1:0] cmpu_cmd_setlhs_ptr,
  input  wire                  cmpu_cmd_setlhs_req,
  input  wire [ADDR_WIDTH-1:0] cmpu_cmd_setrhs_ptr,
  input  wire                  cmpu_cmd_setrhs_req,
  input  wire [ADDR_WIDTH-1:0] cmpu_cmd_setmask_ptr,
  input  wire                  cmpu_cmd_setmask_req,
  input  wire [ADDR_WIDTH-1:0] cmpu_cmd_setout_ptr,
  input  wire                  cmpu_cmd_setout_req,
  input  wire                  cmpu_cmd_setn_req,
  input  wire [15:0]           cmpu_cmd_setn_value,
  input  wire                  cmpu_cmd_start_req,
  input  wire                  cmpu_cmd_sync_req,
  output wire                  cmpu_cmd_ready,
  output wire                  cmpu_start_ready,
  output wire                  cmpu_sync_stall,
  output wire                  cmpu_busy,
  output wire                  cmpu_done_valid,
  output wire                  cmpu_result_update,
  output wire [15:0]           cmpu_max_value,
  output wire [15:0]           cmpu_argmax_idx,
  output wire [15:0]           cmpu_min_value,
  output wire [15:0]           cmpu_argmin_idx,

  output wire                  dtcm_rd_req,
  input  wire                  dtcm_rd_ready,
  output wire [ADDR_WIDTH-1:0] dtcm_rd_addr,
  input  wire                  dtcm_rd_rvalid,
  input  wire [127:0]          dtcm_rd_rdata,
  output wire                  dtcm_wr_req,
  input  wire                  dtcm_wr_ready,
  output wire [ADDR_WIDTH-1:0] dtcm_wr_addr,
  output wire [127:0]          dtcm_wr_wdata,
  output wire [15:0]           dtcm_wr_wstrb,
  output wire [31:0]           actu_last_sum_bits
);

localparam [3:0] CMPU_REDUCE = 4'd0;
localparam [3:0] CMPU_SELECT = 4'd3;
localparam [3:0] CMPU_CMP_GT = 4'd4;

reg [3:0] actu_mode_q;
reg [ADDR_WIDTH-1:0] actu_in_ptr_q;
reg [ADDR_WIDTH-1:0] actu_out_ptr_q;
reg [15:0] actu_n_q;
reg [31:0] actu_scalar_q;
reg [3:0] cmpu_mode_q;
reg [ADDR_WIDTH-1:0] cmpu_lhs_ptr_q;
reg [ADDR_WIDTH-1:0] cmpu_rhs_ptr_q;
reg [ADDR_WIDTH-1:0] cmpu_mask_ptr_q;
reg [ADDR_WIDTH-1:0] cmpu_out_ptr_q;
reg [15:0] cmpu_n_q;
reg active_owner_q;

wire start_valid = actu_cmd_start_req || cmpu_cmd_start_req;
wire start_owner = cmpu_cmd_start_req;
wire start_ready;
wire shared_busy;
wire shared_done_valid;
wire start_fire = start_valid && start_ready;
wire cmpu_is_reduce = (cmpu_mode_q == CMPU_REDUCE);
wire cmpu_is_select = (cmpu_mode_q == CMPU_SELECT);
wire cmpu_is_compare = (cmpu_mode_q >= CMPU_CMP_GT);

assign actu_cmd_ready = 1'b1;
assign cmpu_cmd_ready = 1'b1;
assign actu_start_ready = start_ready && !cmpu_cmd_start_req;
assign cmpu_start_ready = start_ready;
assign actu_sync_stall = shared_busy;
assign cmpu_sync_stall = shared_busy;
assign actu_busy = shared_busy;
assign cmpu_busy = shared_busy;
assign actu_done_valid = shared_done_valid && !active_owner_q;
assign cmpu_done_valid = shared_done_valid && active_owner_q;

edge_accel_io_unit #(
  .ADDR_WIDTH(ADDR_WIDTH),
  .ACTU_LATENCY(ACTU_PIPE_STAGES)
) shared_unit (
  .clk(clk),
  .cpurst_b(cpurst_b),
  .start_valid(start_valid),
  .start_ready(start_ready),
  .start_owner(start_owner),
  .start_mode(start_owner ? cmpu_mode_q : actu_mode_q),
  .src0_enable(1'b1),
  .src0_is_byte(1'b0),
  .src0_addr(start_owner ? cmpu_lhs_ptr_q : actu_in_ptr_q),
  .src1_enable(start_owner && !cmpu_is_reduce),
  .src1_is_byte(1'b0),
  .src1_addr(cmpu_rhs_ptr_q),
  .src2_enable(start_owner && cmpu_is_select),
  .src2_is_byte(1'b1),
  .src2_addr(cmpu_mask_ptr_q),
  .dst_enable(start_owner ? !cmpu_is_reduce : 1'b1),
  .dst_is_byte(start_owner && cmpu_is_compare),
  .dst_addr(start_owner ? cmpu_out_ptr_q : actu_out_ptr_q),
  .n_elements(start_owner ? cmpu_n_q : actu_n_q),
  .busy(shared_busy),
  .done_valid(shared_done_valid),
  .dtcm_rd_req(dtcm_rd_req),
  .dtcm_rd_ready(dtcm_rd_ready),
  .dtcm_rd_addr(dtcm_rd_addr),
  .dtcm_rd_rvalid(dtcm_rd_rvalid),
  .dtcm_rd_rdata(dtcm_rd_rdata),
  .dtcm_wr_req(dtcm_wr_req),
  .dtcm_wr_ready(dtcm_wr_ready),
  .dtcm_wr_addr(dtcm_wr_addr),
  .dtcm_wr_wdata(dtcm_wr_wdata),
  .dtcm_wr_wstrb(dtcm_wr_wstrb),
  .actu_scalar_bits(actu_scalar_q),
  .actu_last_sum_bits(actu_last_sum_bits),
  .cmpu_result_update(cmpu_result_update),
  .cmpu_max_value(cmpu_max_value),
  .cmpu_argmax_idx(cmpu_argmax_idx),
  .cmpu_min_value(cmpu_min_value),
  .cmpu_argmin_idx(cmpu_argmin_idx)
);

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    actu_mode_q <= 4'b0;
    actu_in_ptr_q <= {ADDR_WIDTH{1'b0}};
    actu_out_ptr_q <= {ADDR_WIDTH{1'b0}};
    actu_n_q <= 16'b0;
    actu_scalar_q <= 32'b0;
    cmpu_mode_q <= 4'b0;
    cmpu_lhs_ptr_q <= {ADDR_WIDTH{1'b0}};
    cmpu_rhs_ptr_q <= {ADDR_WIDTH{1'b0}};
    cmpu_mask_ptr_q <= {ADDR_WIDTH{1'b0}};
    cmpu_out_ptr_q <= {ADDR_WIDTH{1'b0}};
    cmpu_n_q <= 16'b0;
    active_owner_q <= 1'b0;
  end else begin
    if (actu_cmd_setcsr_req)
      actu_mode_q <= actu_cmd_setcsr_mode;
    if (actu_cmd_setin_req)
      actu_in_ptr_q <= actu_cmd_setin_ptr;
    if (actu_cmd_setout_req)
      actu_out_ptr_q <= actu_cmd_setout_ptr;
    if (actu_cmd_setn_req)
      actu_n_q <= actu_cmd_setn_value;
    if (actu_cmd_setscalar_req)
      actu_scalar_q <= actu_cmd_setscalar_value[31:0];
    if (cmpu_cmd_setcsr_req)
      cmpu_mode_q <= cmpu_cmd_setcsr_mode;
    if (cmpu_cmd_setlhs_req)
      cmpu_lhs_ptr_q <= cmpu_cmd_setlhs_ptr;
    if (cmpu_cmd_setrhs_req)
      cmpu_rhs_ptr_q <= cmpu_cmd_setrhs_ptr;
    if (cmpu_cmd_setmask_req)
      cmpu_mask_ptr_q <= cmpu_cmd_setmask_ptr;
    if (cmpu_cmd_setout_req)
      cmpu_out_ptr_q <= cmpu_cmd_setout_ptr;
    if (cmpu_cmd_setn_req)
      cmpu_n_q <= cmpu_cmd_setn_value;
    if (start_fire)
      active_owner_q <= start_owner;
  end
end

wire unused_actu_dtype = |actu_cmd_setcsr_dtype;
wire unused_actu_sync = actu_cmd_sync_req;
wire unused_cmpu_sync = cmpu_cmd_sync_req;

endmodule
