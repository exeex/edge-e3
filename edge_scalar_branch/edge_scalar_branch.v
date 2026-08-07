`ifndef EDGE_SCALAR_BRANCH_V
`define EDGE_SCALAR_BRANCH_V

// Combinational scalar branch/jump fact calculation.
(* keep_hierarchy = "yes" *)
module edge_scalar_branch #(
  parameter PC_WIDTH    = 40,
  parameter VALUE_WIDTH = 64,
  parameter OP_WIDTH    = 4
) (
  input  wire [OP_WIDTH-1:0]      branch_issue_op,
  input  wire [PC_WIDTH-1:0]      branch_issue_pc,
  input  wire [VALUE_WIDTH-1:0]   branch_issue_src0_value,
  input  wire [VALUE_WIDTH-1:0]   branch_issue_src1_value,
  input  wire [VALUE_WIDTH-1:0]   branch_issue_imm,
  input  wire [VALUE_WIDTH-1:0]   branch_issue_branch_imm,
  input  wire [VALUE_WIDTH-1:0]   branch_issue_jal_imm,
  input  wire [2:0]               branch_issue_funct3,

  output reg                      branch_taken,
  output reg  [PC_WIDTH-1:0]      branch_target
);

  localparam [OP_WIDTH-1:0] ALU_OP_JAL    = 4'd6;
  localparam [OP_WIDTH-1:0] ALU_OP_JALR   = 4'd7;

  reg [VALUE_WIDTH-1:0] control_target;
  wire signed [VALUE_WIDTH-1:0] src0_signed;
  wire signed [VALUE_WIDTH-1:0] src1_signed;

  assign src0_signed = branch_issue_src0_value;
  assign src1_signed = branch_issue_src1_value;

  always @* begin
    case (branch_issue_funct3)
      3'b000: branch_taken = (branch_issue_src0_value ==
                              branch_issue_src1_value);
      3'b001: branch_taken = (branch_issue_src0_value !=
                              branch_issue_src1_value);
      3'b100: branch_taken = (src0_signed < src1_signed);
      3'b101: branch_taken = (src0_signed >= src1_signed);
      3'b110: branch_taken = (branch_issue_src0_value <
                              branch_issue_src1_value);
      3'b111: branch_taken = (branch_issue_src0_value >=
                              branch_issue_src1_value);
      default: branch_taken = 1'b0;
    endcase

    if (branch_issue_op == ALU_OP_JAL) begin
      control_target = {{(VALUE_WIDTH-PC_WIDTH){1'b0}}, branch_issue_pc} +
                       branch_issue_jal_imm;
      branch_taken = 1'b1;
    end else if (branch_issue_op == ALU_OP_JALR) begin
      control_target = (branch_issue_src0_value + branch_issue_imm) &
                       ~{{(VALUE_WIDTH-1){1'b0}}, 1'b1};
      branch_taken = 1'b1;
    end else begin
      control_target = {{(VALUE_WIDTH-PC_WIDTH){1'b0}}, branch_issue_pc} +
                       branch_issue_branch_imm;
    end
    branch_target = control_target[PC_WIDTH-1:0];
  end

endmodule

`endif
