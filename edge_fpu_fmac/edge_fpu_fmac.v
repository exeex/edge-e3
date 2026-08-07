module edge_fpu_fmac(
  cpurst_b,
  forever_cpuclk,
  fmac_cancel,
  fmac_inst_vld,
  fmac_func,
  fmac_rm,
  fmac_src0,
  fmac_src1,
  fmac_src2,
  fmac_dst_reg,
  fmac_dst_vld,
  fmac_stall,
  fmac_wb_data,
  fmac_wb_fflags,
  fmac_wb_reg,
  fmac_wb_vld
);

input           cpurst_b;
input           forever_cpuclk;
input           fmac_cancel;
input           fmac_inst_vld;
input   [19:0]  fmac_func;
input   [2 :0]  fmac_rm;
input   [31:0]  fmac_src0;
input   [31:0]  fmac_src1;
input   [31:0]  fmac_src2;
input   [4 :0]  fmac_dst_reg;
input           fmac_dst_vld;
output          fmac_stall;
output  [31:0]  fmac_wb_data;
output  [4 :0]  fmac_wb_fflags;
output  [4 :0]  fmac_wb_reg;
output          fmac_wb_vld;

wire            cpurst_b;
wire            forever_cpuclk;
wire            fmac_cancel;
wire            fmac_inst_vld;
wire    [19:0]  fmac_func;
wire    [2 :0]  fmac_rm;
wire    [31:0]  fmac_src0;
wire    [31:0]  fmac_src1;
wire    [31:0]  fmac_src2;
wire    [4 :0]  fmac_dst_reg;
wire            fmac_dst_vld;
reg     [31:0]  fmac_wb_data;
reg     [4 :0]  fmac_wb_fflags;
reg     [4 :0]  fmac_wb_reg;
reg             fmac_wb_vld;
reg             fmac_inst_vld_q;
reg     [19:0]  fmac_func_q;
reg     [2 :0]  fmac_rm_q;
reg     [31:0]  fmac_src0_q;
reg     [31:0]  fmac_src1_q;
reg     [31:0]  fmac_src2_q;
reg     [4 :0]  fmac_dst_reg_q;
reg             fmac_dst_vld_q;
reg             fmac_pipe_vld_d0;
reg             fmac_pipe_vld_d1;
reg     [4 :0]  fmac_dst_reg_d0;
reg     [4 :0]  fmac_dst_reg_d1;

wire            fmac_fadd;
wire            fmac_fmadd;
wire            fmac_fmul;
wire            fmac_fsub;
wire            fmac_narrow_fmadd;
wire    [4 :0]  narrow_fmadd_fflags;
wire    [31:0]  narrow_fmadd_result;
wire    [31:0]  fmac_wb_data_pre;
wire    [4 :0]  fmac_wb_fflags_pre;
wire            fmac_wb_vld_pre;
wire    [31:0]  fmac_mac_a;
wire    [31:0]  fmac_mac_b;
wire    [31:0]  fmac_mac_c;
wire            fmac_neg_product;
wire            fmac_neg_addend;
wire    [31:0]  fmac_fp32_result;

always @(posedge forever_cpuclk or negedge cpurst_b)
begin
  if(!cpurst_b) begin
    fmac_inst_vld_q <= 1'b0;
    fmac_func_q[19:0] <= 20'b0;
    fmac_rm_q[2:0] <= 3'b0;
    fmac_src0_q <= 32'b0;
    fmac_src1_q <= 32'b0;
    fmac_src2_q <= 32'b0;
    fmac_dst_reg_q[4:0] <= 5'b0;
    fmac_dst_vld_q <= 1'b0;
  end
  else if(fmac_cancel) begin
    fmac_inst_vld_q <= 1'b0;
    fmac_func_q[19:0] <= 20'b0;
    fmac_rm_q[2:0] <= 3'b0;
    fmac_src0_q <= 32'b0;
    fmac_src1_q <= 32'b0;
    fmac_src2_q <= 32'b0;
    fmac_dst_reg_q[4:0] <= 5'b0;
    fmac_dst_vld_q <= 1'b0;
  end
  else begin
    fmac_inst_vld_q <= fmac_inst_vld;
    fmac_func_q[19:0] <= fmac_func[19:0];
    fmac_rm_q[2:0] <= fmac_rm[2:0];
    fmac_src0_q <= fmac_src0;
    fmac_src1_q <= fmac_src1;
    fmac_src2_q <= fmac_src2;
    fmac_dst_reg_q[4:0] <= fmac_dst_reg[4:0];
    fmac_dst_vld_q <= fmac_dst_vld;
  end
end

edge_fpu_fmac_prep  x_edge_fpu_fmac_prep (
  .fmac_func    (fmac_func_q ),
  .fmac_src0    (fmac_src0_q ),
  .fmac_src1    (fmac_src1_q ),
  .fmac_src2    (fmac_src2_q ),
  .fmac_fadd    (fmac_fadd   ),
  .fmac_fsub    (fmac_fsub   ),
  .fmac_fmul    (fmac_fmul   ),
  .fmac_fmadd   (fmac_fmadd  ),
  .fmac_mac_a   (fmac_mac_a  ),
  .fmac_mac_b   (fmac_mac_b  ),
  .fmac_mac_c   (fmac_mac_c  )
);

assign fmac_narrow_fmadd = fmac_fadd || fmac_fsub || fmac_fmul || fmac_fmadd;

assign fmac_neg_product = fmac_fmadd && fmac_func_q[2];
assign fmac_neg_addend = fmac_fmadd
                       ? (fmac_func_q[2] ^ fmac_func_q[1])
                       : fmac_fsub;

edge_fpu_fmac_narrow_fmadd  x_edge_fpu_fmac_narrow_fmadd (
  .cpurst_b           (cpurst_b                ),
  .forever_cpuclk     (forever_cpuclk          ),
  .fmadd_cancel       (fmac_cancel             ),
  .fmadd_mul_only     (fmac_fmul              ),
  .fmadd_neg_product (fmac_neg_product       ),
  .fmadd_neg_addend  (fmac_neg_addend        ),
  .fmadd_rm          (fmac_rm_q              ),
  .fmadd_src0        (fmac_mac_a             ),
  .fmadd_src1        (fmac_mac_b             ),
  .fmadd_src2        (fmac_mac_c             ),
  .fmadd_result      (narrow_fmadd_result    ),
  .fmadd_fflags      (narrow_fmadd_fflags    )
);

assign fmac_stall = 1'b0;
assign fmac_fp32_result = narrow_fmadd_result;
assign fmac_wb_data_pre = fmac_fp32_result;
assign fmac_wb_fflags_pre[4:0] = narrow_fmadd_fflags[4:0];
assign fmac_wb_vld_pre = fmac_pipe_vld_d1
                       && !fmac_cancel;

always @(posedge forever_cpuclk or negedge cpurst_b)
begin
  if(!cpurst_b) begin
    fmac_pipe_vld_d0 <= 1'b0;
    fmac_pipe_vld_d1 <= 1'b0;
    fmac_dst_reg_d0 <= 5'b0;
    fmac_dst_reg_d1 <= 5'b0;
    fmac_wb_vld <= 1'b0;
    fmac_wb_reg[4:0] <= 5'b0;
    fmac_wb_data <= 32'b0;
    fmac_wb_fflags[4:0] <= 5'b0;
  end
  else if(fmac_cancel) begin
    fmac_pipe_vld_d0 <= 1'b0;
    fmac_pipe_vld_d1 <= 1'b0;
    fmac_dst_reg_d0 <= 5'b0;
    fmac_dst_reg_d1 <= 5'b0;
    fmac_wb_vld <= 1'b0;
    fmac_wb_reg[4:0] <= 5'b0;
    fmac_wb_data <= 32'b0;
    fmac_wb_fflags[4:0] <= 5'b0;
  end
  else begin
    fmac_pipe_vld_d0 <= fmac_inst_vld_q && fmac_dst_vld_q
                     && fmac_narrow_fmadd;
    fmac_pipe_vld_d1 <= fmac_pipe_vld_d0;
    fmac_dst_reg_d0 <= fmac_dst_reg_q;
    fmac_dst_reg_d1 <= fmac_dst_reg_d0;
    fmac_wb_vld <= fmac_wb_vld_pre;
    fmac_wb_reg[4:0] <= fmac_dst_reg_d1[4:0];
    fmac_wb_data <= fmac_wb_data_pre;
    fmac_wb_fflags[4:0] <= fmac_wb_fflags_pre[4:0];
  end
end

endmodule

module edge_fpu_fmac_prep(
  fmac_func,
  fmac_src0,
  fmac_src1,
  fmac_src2,
  fmac_fadd,
  fmac_fsub,
  fmac_fmul,
  fmac_fmadd,
  fmac_mac_a,
  fmac_mac_b,
  fmac_mac_c
);

input   [19:0]  fmac_func;
input   [31:0]  fmac_src0;
input   [31:0]  fmac_src1;
input   [31:0]  fmac_src2;
output          fmac_fadd;
output          fmac_fsub;
output          fmac_fmul;
output          fmac_fmadd;
output  [31:0]  fmac_mac_a;
output  [31:0]  fmac_mac_b;
output  [31:0]  fmac_mac_c;

wire            fmac_fadd;
wire            fmac_fmadd;
wire            fmac_fmul;
wire            fmac_fsub;
wire    [19:0]  fmac_func;
wire    [31:0]  fmac_one;
wire    [31:0]  fmac_src0;
wire    [31:0]  fmac_src1;
wire    [31:0]  fmac_src2;
wire    [31:0]  fmac_zero;

assign fmac_fadd = {2'b00, fmac_func[17:0]} == 20'b0000_0010_0000_1001_0000;
assign fmac_fsub = {2'b00, fmac_func[17:0]} == 20'b0000_0010_0000_1000_1000;
assign fmac_fmul = {2'b00, fmac_func[17:0]} == 20'b0000_0000_0000_0010_0000;
assign fmac_fmadd = {2'b00, fmac_func[17:0]} == 20'b0000_0000_0000_0010_0001
                 || {2'b00, fmac_func[17:0]} == 20'b0000_0000_0000_0010_0011
                 || {2'b00, fmac_func[17:0]} == 20'b0000_0000_0000_0010_0101
                 || {2'b00, fmac_func[17:0]} == 20'b0000_0000_0000_0010_0111;

assign fmac_one = 32'h3f80_0000;
assign fmac_zero = 32'h0;

assign fmac_mac_a = fmac_src0;
assign fmac_mac_b = (fmac_fadd || fmac_fsub)
                          ? fmac_one : fmac_src1;
assign fmac_mac_c = fmac_fmul
                          ? fmac_zero
                          : (fmac_fadd || fmac_fsub)
                            ? fmac_src1 : fmac_src2;

endmodule
