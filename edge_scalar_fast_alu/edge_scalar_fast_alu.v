`ifndef EDGE_SCALAR_FAST_ALU_V
`define EDGE_SCALAR_FAST_ALU_V

// Combinational fast integer ALU datapath for the Edge scalar pipe.
(* keep_hierarchy = "yes" *)
module edge_scalar_fast_alu #(
  parameter PC_WIDTH    = 40,
  parameter VALUE_WIDTH = 64,
  parameter OP_WIDTH    = 4
) (
  input  wire [OP_WIDTH-1:0]      fast_issue_op,
  input  wire [PC_WIDTH-1:0]      fast_issue_pc,
  input  wire [VALUE_WIDTH-1:0]   fast_issue_src0_value,
  input  wire [VALUE_WIDTH-1:0]   fast_issue_src1_value,
  input  wire [VALUE_WIDTH-1:0]   fast_issue_imm,
  input  wire [2:0]               fast_issue_funct3,
  input  wire                     fast_issue_funct7_bit5,
  input  wire                     fast_issue_funct7_is_m,
  input  wire [5:0]               fast_issue_shamt,
  input  wire [4:0]               fast_issue_shamt32,

  output reg  [VALUE_WIDTH-1:0]   fast_result
);

  localparam [OP_WIDTH-1:0] ALU_OP_OP_IMM   = 4'd0;
  localparam [OP_WIDTH-1:0] ALU_OP_OP       = 4'd1;
  localparam [OP_WIDTH-1:0] ALU_OP_OP_IMM32 = 4'd2;
  localparam [OP_WIDTH-1:0] ALU_OP_OP32     = 4'd3;
  localparam [OP_WIDTH-1:0] ALU_OP_LUI      = 4'd4;
  localparam [OP_WIDTH-1:0] ALU_OP_AUIPC    = 4'd5;
  localparam [OP_WIDTH-1:0] ALU_OP_JAL      = 4'd6;
  localparam [OP_WIDTH-1:0] ALU_OP_JALR     = 4'd7;
  localparam [OP_WIDTH-1:0] ALU_OP_ZBA      = 4'd9;
  localparam [OP_WIDTH-1:0] ALU_OP_ZBA_UW   = 4'd10;

  wire signed [VALUE_WIDTH-1:0] src0_signed;
  wire signed [VALUE_WIDTH-1:0] src1_signed;
  wire [31:0] src0_word;
  wire [31:0] src1_word;
  wire [VALUE_WIDTH-1:0] src0_word_zext;
  reg [31:0] word_result;

  assign src0_signed = fast_issue_src0_value;
  assign src1_signed = fast_issue_src1_value;
  assign src0_word = fast_issue_src0_value[31:0];
  assign src1_word = fast_issue_src1_value[31:0];
  assign src0_word_zext = {{(VALUE_WIDTH-32){1'b0}}, src0_word};

  function [VALUE_WIDTH-1:0] sll64_stage8;
    input [VALUE_WIDTH-1:0] value;
    input [5:0] amount;
    reg [VALUE_WIDTH-1:0] coarse;
    begin
      case (amount[5:3])
        3'd0: coarse = value;
        3'd1: coarse = {value[55:0], 8'b0};
        3'd2: coarse = {value[47:0], 16'b0};
        3'd3: coarse = {value[39:0], 24'b0};
        3'd4: coarse = {value[31:0], 32'b0};
        3'd5: coarse = {value[23:0], 40'b0};
        3'd6: coarse = {value[15:0], 48'b0};
        default: coarse = {value[7:0], 56'b0};
      endcase
      case (amount[2:0])
        3'd0: sll64_stage8 = coarse;
        3'd1: sll64_stage8 = {coarse[62:0], 1'b0};
        3'd2: sll64_stage8 = {coarse[61:0], 2'b0};
        3'd3: sll64_stage8 = {coarse[60:0], 3'b0};
        3'd4: sll64_stage8 = {coarse[59:0], 4'b0};
        3'd5: sll64_stage8 = {coarse[58:0], 5'b0};
        3'd6: sll64_stage8 = {coarse[57:0], 6'b0};
        default: sll64_stage8 = {coarse[56:0], 7'b0};
      endcase
    end
  endfunction

  function [VALUE_WIDTH-1:0] srl64_stage8;
    input [VALUE_WIDTH-1:0] value;
    input [5:0] amount;
    reg [VALUE_WIDTH-1:0] coarse;
    begin
      case (amount[5:3])
        3'd0: coarse = value;
        3'd1: coarse = {8'b0, value[63:8]};
        3'd2: coarse = {16'b0, value[63:16]};
        3'd3: coarse = {24'b0, value[63:24]};
        3'd4: coarse = {32'b0, value[63:32]};
        3'd5: coarse = {40'b0, value[63:40]};
        3'd6: coarse = {48'b0, value[63:48]};
        default: coarse = {56'b0, value[63:56]};
      endcase
      case (amount[2:0])
        3'd0: srl64_stage8 = coarse;
        3'd1: srl64_stage8 = {1'b0, coarse[63:1]};
        3'd2: srl64_stage8 = {2'b0, coarse[63:2]};
        3'd3: srl64_stage8 = {3'b0, coarse[63:3]};
        3'd4: srl64_stage8 = {4'b0, coarse[63:4]};
        3'd5: srl64_stage8 = {5'b0, coarse[63:5]};
        3'd6: srl64_stage8 = {6'b0, coarse[63:6]};
        default: srl64_stage8 = {7'b0, coarse[63:7]};
      endcase
    end
  endfunction

  function [VALUE_WIDTH-1:0] sra64_stage8;
    input [VALUE_WIDTH-1:0] value;
    input [5:0] amount;
    reg [VALUE_WIDTH-1:0] coarse;
    begin
      case (amount[5:3])
        3'd0: coarse = value;
        3'd1: coarse = {{8{value[VALUE_WIDTH-1]}}, value[63:8]};
        3'd2: coarse = {{16{value[VALUE_WIDTH-1]}}, value[63:16]};
        3'd3: coarse = {{24{value[VALUE_WIDTH-1]}}, value[63:24]};
        3'd4: coarse = {{32{value[VALUE_WIDTH-1]}}, value[63:32]};
        3'd5: coarse = {{40{value[VALUE_WIDTH-1]}}, value[63:40]};
        3'd6: coarse = {{48{value[VALUE_WIDTH-1]}}, value[63:48]};
        default: coarse = {{56{value[VALUE_WIDTH-1]}}, value[63:56]};
      endcase
      case (amount[2:0])
        3'd0: sra64_stage8 = coarse;
        3'd1: sra64_stage8 = {coarse[VALUE_WIDTH-1], coarse[63:1]};
        3'd2: sra64_stage8 = {{2{coarse[VALUE_WIDTH-1]}}, coarse[63:2]};
        3'd3: sra64_stage8 = {{3{coarse[VALUE_WIDTH-1]}}, coarse[63:3]};
        3'd4: sra64_stage8 = {{4{coarse[VALUE_WIDTH-1]}}, coarse[63:4]};
        3'd5: sra64_stage8 = {{5{coarse[VALUE_WIDTH-1]}}, coarse[63:5]};
        3'd6: sra64_stage8 = {{6{coarse[VALUE_WIDTH-1]}}, coarse[63:6]};
        default: sra64_stage8 = {{7{coarse[VALUE_WIDTH-1]}}, coarse[63:7]};
      endcase
    end
  endfunction

  function [31:0] sll32_stage8;
    input [31:0] value;
    input [4:0] amount;
    reg [31:0] coarse;
    begin
      case (amount[4:3])
        2'd0: coarse = value;
        2'd1: coarse = {value[23:0], 8'b0};
        2'd2: coarse = {value[15:0], 16'b0};
        default: coarse = {value[7:0], 24'b0};
      endcase
      case (amount[2:0])
        3'd0: sll32_stage8 = coarse;
        3'd1: sll32_stage8 = {coarse[30:0], 1'b0};
        3'd2: sll32_stage8 = {coarse[29:0], 2'b0};
        3'd3: sll32_stage8 = {coarse[28:0], 3'b0};
        3'd4: sll32_stage8 = {coarse[27:0], 4'b0};
        3'd5: sll32_stage8 = {coarse[26:0], 5'b0};
        3'd6: sll32_stage8 = {coarse[25:0], 6'b0};
        default: sll32_stage8 = {coarse[24:0], 7'b0};
      endcase
    end
  endfunction

  function [31:0] srl32_stage8;
    input [31:0] value;
    input [4:0] amount;
    reg [31:0] coarse;
    begin
      case (amount[4:3])
        2'd0: coarse = value;
        2'd1: coarse = {8'b0, value[31:8]};
        2'd2: coarse = {16'b0, value[31:16]};
        default: coarse = {24'b0, value[31:24]};
      endcase
      case (amount[2:0])
        3'd0: srl32_stage8 = coarse;
        3'd1: srl32_stage8 = {1'b0, coarse[31:1]};
        3'd2: srl32_stage8 = {2'b0, coarse[31:2]};
        3'd3: srl32_stage8 = {3'b0, coarse[31:3]};
        3'd4: srl32_stage8 = {4'b0, coarse[31:4]};
        3'd5: srl32_stage8 = {5'b0, coarse[31:5]};
        3'd6: srl32_stage8 = {6'b0, coarse[31:6]};
        default: srl32_stage8 = {7'b0, coarse[31:7]};
      endcase
    end
  endfunction

  function [31:0] sra32_stage8;
    input [31:0] value;
    input [4:0] amount;
    reg [31:0] coarse;
    begin
      case (amount[4:3])
        2'd0: coarse = value;
        2'd1: coarse = {{8{value[31]}}, value[31:8]};
        2'd2: coarse = {{16{value[31]}}, value[31:16]};
        default: coarse = {{24{value[31]}}, value[31:24]};
      endcase
      case (amount[2:0])
        3'd0: sra32_stage8 = coarse;
        3'd1: sra32_stage8 = {coarse[31], coarse[31:1]};
        3'd2: sra32_stage8 = {{2{coarse[31]}}, coarse[31:2]};
        3'd3: sra32_stage8 = {{3{coarse[31]}}, coarse[31:3]};
        3'd4: sra32_stage8 = {{4{coarse[31]}}, coarse[31:4]};
        3'd5: sra32_stage8 = {{5{coarse[31]}}, coarse[31:5]};
        3'd6: sra32_stage8 = {{6{coarse[31]}}, coarse[31:6]};
        default: sra32_stage8 = {{7{coarse[31]}}, coarse[31:7]};
      endcase
    end
  endfunction

  always @* begin
    fast_result = {VALUE_WIDTH{1'b0}};
    word_result = 32'd0;

    case (fast_issue_op)
      ALU_OP_LUI: begin
        fast_result = fast_issue_imm;
      end
      ALU_OP_AUIPC: begin
        fast_result = {{(VALUE_WIDTH-PC_WIDTH){1'b0}}, fast_issue_pc} +
                      fast_issue_imm;
      end
      ALU_OP_JAL,
      ALU_OP_JALR: begin
        fast_result = {{(VALUE_WIDTH-PC_WIDTH){1'b0}}, fast_issue_pc} +
                      {{(VALUE_WIDTH-3){1'b0}}, 3'd4};
      end
      ALU_OP_OP_IMM: begin
        case (fast_issue_funct3)
          3'b000: fast_result = fast_issue_src0_value + fast_issue_imm;
          3'b010: fast_result = (src0_signed < $signed(fast_issue_imm)) ?
                                 {{(VALUE_WIDTH-1){1'b0}}, 1'b1} :
                                 {VALUE_WIDTH{1'b0}};
          3'b011: fast_result = (fast_issue_src0_value < fast_issue_imm) ?
                                 {{(VALUE_WIDTH-1){1'b0}}, 1'b1} :
                                 {VALUE_WIDTH{1'b0}};
          3'b100: fast_result = fast_issue_src0_value ^ fast_issue_imm;
          3'b110: fast_result = fast_issue_src0_value | fast_issue_imm;
          3'b111: fast_result = fast_issue_src0_value & fast_issue_imm;
          3'b001: fast_result = sll64_stage8(fast_issue_src0_value,
                                              fast_issue_shamt);
          3'b101: fast_result = fast_issue_funct7_bit5 ?
                                 sra64_stage8(fast_issue_src0_value,
                                              fast_issue_shamt) :
                                 srl64_stage8(fast_issue_src0_value,
                                              fast_issue_shamt);
          default: fast_result = {VALUE_WIDTH{1'b0}};
        endcase
      end
      ALU_OP_OP: begin
        if (!fast_issue_funct7_is_m) begin
          case (fast_issue_funct3)
            3'b000: fast_result = fast_issue_funct7_bit5 ?
                                   (fast_issue_src0_value -
                                    fast_issue_src1_value) :
                                   (fast_issue_src0_value +
                                    fast_issue_src1_value);
            3'b001: fast_result = sll64_stage8(
                                     fast_issue_src0_value,
                                     fast_issue_src1_value[5:0]);
            3'b010: fast_result = (src0_signed < src1_signed) ?
                                   {{(VALUE_WIDTH-1){1'b0}}, 1'b1} :
                                   {VALUE_WIDTH{1'b0}};
            3'b011: fast_result = (fast_issue_src0_value <
                                   fast_issue_src1_value) ?
                                   {{(VALUE_WIDTH-1){1'b0}}, 1'b1} :
                                   {VALUE_WIDTH{1'b0}};
            3'b100: fast_result = fast_issue_src0_value ^
                                   fast_issue_src1_value;
            3'b101: fast_result = fast_issue_funct7_bit5 ?
                                   sra64_stage8(
                                     fast_issue_src0_value,
                                     fast_issue_src1_value[5:0]) :
                                   srl64_stage8(
                                     fast_issue_src0_value,
                                     fast_issue_src1_value[5:0]);
            3'b110: fast_result = fast_issue_src0_value |
                                   fast_issue_src1_value;
            3'b111: fast_result = fast_issue_src0_value &
                                   fast_issue_src1_value;
            default: fast_result = {VALUE_WIDTH{1'b0}};
          endcase
        end
      end
      ALU_OP_OP_IMM32: begin
        case (fast_issue_funct3)
          3'b000: word_result = src0_word + fast_issue_imm[31:0];
          3'b001: word_result = sll32_stage8(src0_word,
                                             fast_issue_shamt32);
          3'b101: word_result = fast_issue_funct7_bit5 ?
                                 sra32_stage8(src0_word,
                                              fast_issue_shamt32) :
                                 srl32_stage8(src0_word,
                                              fast_issue_shamt32);
          default: word_result = 32'd0;
        endcase
        fast_result = {{32{word_result[31]}}, word_result};
      end
      ALU_OP_OP32: begin
        if (!fast_issue_funct7_is_m) begin
          case (fast_issue_funct3)
            3'b000: word_result = fast_issue_funct7_bit5 ?
                                   (src0_word - src1_word) :
                                   (src0_word + src1_word);
            3'b001: word_result = sll32_stage8(
                                     src0_word,
                                     fast_issue_src1_value[4:0]);
            3'b101: word_result = fast_issue_funct7_bit5 ?
                                   sra32_stage8(
                                     src0_word,
                                     fast_issue_src1_value[4:0]) :
                                   srl32_stage8(
                                     src0_word,
                                     fast_issue_src1_value[4:0]);
            default: word_result = 32'd0;
          endcase
        end
        fast_result = {{32{word_result[31]}}, word_result};
      end
      ALU_OP_ZBA: begin
        case (fast_issue_funct3)
          3'b010: fast_result = fast_issue_src1_value +
                                 (fast_issue_src0_value << 1);
          3'b100: fast_result = fast_issue_src1_value +
                                 (fast_issue_src0_value << 2);
          3'b110: fast_result = fast_issue_src1_value +
                                 (fast_issue_src0_value << 3);
          default: fast_result = {VALUE_WIDTH{1'b0}};
        endcase
      end
      ALU_OP_ZBA_UW: begin
        case (fast_issue_funct3)
          3'b000: fast_result = fast_issue_src1_value + src0_word_zext;
          3'b001: fast_result = sll64_stage8(src0_word_zext,
                                             fast_issue_shamt);
          3'b010: fast_result = fast_issue_src1_value +
                                 (src0_word_zext << 1);
          3'b100: fast_result = fast_issue_src1_value +
                                 (src0_word_zext << 2);
          3'b110: fast_result = fast_issue_src1_value +
                                 (src0_word_zext << 3);
          default: fast_result = {VALUE_WIDTH{1'b0}};
        endcase
      end
      default: begin
        fast_result = {VALUE_WIDTH{1'b0}};
      end
    endcase
  end

endmodule

`endif
