module edge_fpu_cvt #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter VALUE_WIDTH = 64
) (
  input wire forever_cpuclk, input wire cpurst_b,
  input wire cvt_issue_valid, output wire cvt_issue_ready,
  input wire [SEQ_ID_WIDTH-1:0] cvt_issue_seq_id,
  input wire [EPOCH_WIDTH-1:0] cvt_issue_epoch,
  input wire [1:0] cvt_issue_op,
  input wire [1:0] cvt_issue_int_type,
  input wire [2:0] cvt_issue_rm,
  input wire [REG_INDEX_WIDTH-1:0] cvt_issue_rd,
  input wire cvt_issue_rd_bank,
  input wire [31:0] cvt_issue_fsrc,
  input wire [VALUE_WIDTH-1:0] cvt_issue_gsrc,
  output reg cvt_complete_valid,
  output reg [SEQ_ID_WIDTH-1:0] cvt_complete_seq_id,
  output reg [EPOCH_WIDTH-1:0] cvt_complete_epoch,
  output reg [REG_INDEX_WIDTH-1:0] cvt_complete_rd,
  output reg cvt_complete_rd_bank,
  output reg cvt_complete_domain,
  output reg [VALUE_WIDTH-1:0] cvt_complete_value,
  output reg [4:0] cvt_complete_fflags
);
  localparam [1:0] OP_F2F = 2'd0, OP_F2I = 2'd1, OP_I2F = 2'd2;
  localparam [1:0] TYPE_W = 2'd0, TYPE_WU = 2'd1,
                   TYPE_L = 2'd2, TYPE_LU = 2'd3;

  reg domain_d;
  reg [63:0] value_d;
  reg [4:0] flags_d;
  reg sign;
  reg is_unsigned;
  reg is_word;
  reg is_nan;
  reg is_inf;
  reg invalid;
  reg inexact;
  reg increment;
  reg [7:0] exp_field;
  reg [22:0] frac;
  reg [23:0] sig;
  reg [63:0] magnitude;
  reg [63:0] integer_mag;
  reg [63:0] remainder;
  reg [63:0] half;
  reg [63:0] rounded_mag;
  reg [63:0] signed_limit;
  reg [63:0] unsigned_limit;
  reg [63:0] int_value;
  reg [63:0] int_magnitude;
  reg [23:0] fp_sig;
  reg [24:0] fp_rounded;
  reg [7:0] fp_exp;
  integer unbiased;
  integer rshift;
  integer msb;
  integer i;
  reg found;

  assign cvt_issue_ready = 1'b1;

  always @* begin
    domain_d = 1'b1;
    value_d = 64'b0;
    flags_d = 5'b0;
    sign = cvt_issue_fsrc[31];
    exp_field = cvt_issue_fsrc[30:23];
    frac = cvt_issue_fsrc[22:0];
    sig = exp_field == 0 ? {1'b0, frac} : {1'b1, frac};
    is_nan = (exp_field == 8'hff) && (frac != 0);
    is_inf = (exp_field == 8'hff) && (frac == 0);
    is_unsigned = (cvt_issue_int_type == TYPE_WU) ||
                  (cvt_issue_int_type == TYPE_LU);
    is_word = (cvt_issue_int_type == TYPE_W) ||
              (cvt_issue_int_type == TYPE_WU);
    invalid = 1'b0;
    inexact = 1'b0;
    increment = 1'b0;
    magnitude = 0;
    integer_mag = 0;
    remainder = 0;
    half = 0;
    rounded_mag = 0;
    signed_limit = is_word ? 64'h0000000080000000 : 64'h8000000000000000;
    unsigned_limit = is_word ? 64'h00000000ffffffff : 64'hffffffffffffffff;
    int_value = cvt_issue_gsrc;
    int_magnitude = 0;
    fp_sig = 0;
    fp_rounded = 0;
    fp_exp = 0;
    unbiased = 0;
    rshift = 0;
    msb = 0;
    found = 0;

    case (cvt_issue_op)
      OP_F2F: begin
        // D/S/H are aliases of the same physical FP32 FPR payload.
        domain_d = 1'b1;
        value_d = {32'b0, cvt_issue_fsrc};
      end
      OP_F2I: begin
        domain_d = 1'b0;
        unbiased = (exp_field == 0) ? -126 : exp_field - 127;
        if (is_nan || is_inf) invalid = 1'b1;
        else if (unbiased > 63) invalid = 1'b1;
        else begin
          if (unbiased >= 23) integer_mag = {40'b0, sig} << (unbiased - 23);
          else if (unbiased >= -1) begin
            rshift = 23 - unbiased;
            integer_mag = sig >> rshift;
            remainder = sig & ((64'h1 << rshift) - 1'b1);
            half = 64'h1 << (rshift - 1);
          end else begin
            integer_mag = 0;
            remainder = sig;
            // |value| < 0.5, so nearest modes never increment. Directed
            // modes still use the nonzero remainder through `inexact`.
            half = 64'hffffffffffffffff;
          end
          inexact = remainder != 0;
          case (cvt_issue_rm)
            3'd0: increment = inexact &&
                              ((remainder > half) ||
                               ((remainder == half) && integer_mag[0]));
            3'd1: increment = 1'b0;
            3'd2: increment = sign && inexact;
            3'd3: increment = !sign && inexact;
            3'd4: increment = inexact && (remainder >= half);
            default: increment = inexact &&
                                 ((remainder > half) ||
                                  ((remainder == half) && integer_mag[0]));
          endcase
          rounded_mag = integer_mag + increment;
          if (is_unsigned) begin
            if (sign && (rounded_mag != 0)) invalid = 1'b1;
            else if (rounded_mag > unsigned_limit) invalid = 1'b1;
          end else if ((!sign && rounded_mag >= signed_limit) ||
                       (sign && rounded_mag > signed_limit)) invalid = 1'b1;
        end
        if (invalid) begin
          flags_d[4] = 1'b1;
          if (is_unsigned)
            value_d = (sign && !is_nan) ? 64'b0 : unsigned_limit;
          else
            value_d = (sign && !is_nan) ? signed_limit : (signed_limit - 1'b1);
        end else begin
          flags_d[0] = inexact;
          value_d = sign ? (~rounded_mag + 1'b1) : rounded_mag;
        end
        if (is_word) value_d = {{32{value_d[31]}}, value_d[31:0]};
      end
      OP_I2F: begin
        domain_d = 1'b1;
        if (is_word)
          int_value = is_unsigned ? {32'b0, cvt_issue_gsrc[31:0]}
                                  : {{32{cvt_issue_gsrc[31]}}, cvt_issue_gsrc[31:0]};
        sign = !is_unsigned && int_value[63];
        int_magnitude = sign ? (~int_value + 1'b1) : int_value;
        if (int_magnitude == 0) value_d = 0;
        else begin
          for (i = 63; i >= 0; i = i - 1)
            if (!found && int_magnitude[i]) begin msb = i; found = 1; end
          fp_exp = msb + 127;
          if (msb <= 23) fp_sig = int_magnitude << (23-msb);
          else begin
            rshift = msb - 23;
            fp_sig = int_magnitude >> rshift;
            remainder = int_magnitude & ((64'h1 << rshift) - 1'b1);
            half = 64'h1 << (rshift-1);
            inexact = remainder != 0;
            case (cvt_issue_rm)
              3'd0: increment = inexact &&
                                ((remainder > half) ||
                                 ((remainder == half) && fp_sig[0]));
              3'd1: increment = 1'b0;
              3'd2: increment = sign && inexact;
              3'd3: increment = !sign && inexact;
              3'd4: increment = inexact && (remainder >= half);
              default: increment = inexact &&
                                   ((remainder > half) ||
                                    ((remainder == half) && fp_sig[0]));
            endcase
          end
          fp_rounded = {1'b0, fp_sig} + increment;
          if (fp_rounded[24]) begin
            fp_exp = fp_exp + 1'b1;
            fp_sig = fp_rounded[24:1];
          end else fp_sig = fp_rounded[23:0];
          value_d = {32'b0, sign, fp_exp, fp_sig[22:0]};
          flags_d[0] = inexact;
        end
      end
      default: begin end
    endcase
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      cvt_complete_valid <= 0; cvt_complete_seq_id <= 0;
      cvt_complete_epoch <= 0; cvt_complete_rd <= 0;
      cvt_complete_rd_bank <= 0; cvt_complete_domain <= 0;
      cvt_complete_value <= 0; cvt_complete_fflags <= 0;
    end else begin
      cvt_complete_valid <= cvt_issue_valid && cvt_issue_ready;
      if (cvt_issue_valid && cvt_issue_ready) begin
        cvt_complete_seq_id <= cvt_issue_seq_id;
        cvt_complete_epoch <= cvt_issue_epoch;
        cvt_complete_rd <= cvt_issue_rd;
        cvt_complete_rd_bank <= cvt_issue_rd_bank;
        cvt_complete_domain <= domain_d;
        cvt_complete_value <= value_d;
        cvt_complete_fflags <= flags_d;
      end
    end
  end
endmodule
