module edge_fpu_slow #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter DIV_LATENCY = 16,
  parameter SQRT_LATENCY = 24
) (
  input wire forever_cpuclk, input wire cpurst_b, input wire slow_cancel,
  input wire slow_issue_valid, output wire slow_issue_ready,
  input wire [SEQ_ID_WIDTH-1:0] slow_issue_seq_id,
  input wire [EPOCH_WIDTH-1:0] slow_issue_epoch,
  input wire slow_issue_sqrt, input wire [2:0] slow_issue_rm,
  input wire [REG_INDEX_WIDTH-1:0] slow_issue_rd,
  input wire slow_issue_rd_bank,
  input wire [31:0] slow_issue_src0, input wire [31:0] slow_issue_src1,
  output reg slow_complete_valid,
  output reg [SEQ_ID_WIDTH-1:0] slow_complete_seq_id,
  output reg [EPOCH_WIDTH-1:0] slow_complete_epoch,
  output reg [REG_INDEX_WIDTH-1:0] slow_complete_rd,
  output reg slow_complete_rd_bank,
  output reg [31:0] slow_complete_value,
  output reg [4:0] slow_complete_fflags
);
  // DIV_LATENCY and SQRT_LATENCY remain compatibility parameters. Arithmetic
  // latency is now determined by normalization, iteration, and rounding.
  localparam ST_IDLE   = 3'd0;
  localparam ST_NORM_A = 3'd1;
  localparam ST_NORM_B = 3'd2;
  localparam ST_PREP   = 3'd3;
  localparam ST_DIV    = 3'd4;
  localparam ST_SQRT   = 3'd5;
  localparam ST_DENORM = 3'd6;
  localparam ST_ROUND  = 3'd7;

  reg [2:0] state_r;
  reg busy_r;
  reg sqrt_r;
  reg sign_r;
  reg [2:0] rm_r;
  reg [23:0] sig_a_r, sig_b_r;
  reg signed [10:0] exp_a_r, exp_b_r, exp_z_r;

  reg [24:0] div_rem_r;
  reg [31:0] div_quot_r;
  reg [5:0] iter_r;

  reg [63:0] sqrt_rad_r;
  reg [65:0] sqrt_rem_r;
  reg [31:0] sqrt_root_r;

  reg [31:0] round_sig_r;
  reg signed [10:0] round_exp_r;
  reg tiny_r;
  reg [36:0] result_flags;

  wire div_take = div_rem_r >= {1'b0, sig_b_r};
  wire [24:0] div_rem_sub = div_take
                           ? div_rem_r - {1'b0, sig_b_r} : div_rem_r;
  wire [24:0] div_rem_next = div_rem_sub << 1;
  wire [31:0] div_quot_next = {div_quot_r[30:0], div_take};

  wire [65:0] sqrt_rem_shift = (sqrt_rem_r << 2) |
                                {64'b0, sqrt_rad_r[63:62]};
  wire [65:0] sqrt_trial = ({34'b0, sqrt_root_r} << 2) | 66'b1;
  wire sqrt_take = sqrt_rem_shift >= sqrt_trial;
  wire [65:0] sqrt_rem_next = sqrt_take
                            ? sqrt_rem_shift - sqrt_trial : sqrt_rem_shift;
  wire [31:0] sqrt_root_next = {sqrt_root_r[30:0], sqrt_take};

  assign slow_issue_ready = !busy_r;

  function [7:0] round_increment;
    input sign;
    input [2:0] rm;
    begin
      round_increment = 8'h40;
      if ((rm != 0) && (rm != 4)) begin
        if ((rm == 2 && sign) || (rm == 3 && !sign))
          round_increment = 8'h7f;
        else
          round_increment = 0;
      end
    end
  endfunction

  function result_is_tiny;
    input sign;
    input signed [10:0] exp;
    input [31:0] sig;
    input [2:0] rm;
    reg [7:0] increment;
    begin
      increment = round_increment(sign, rm);
      result_is_tiny = (exp < -1) ||
                       ((exp == -1) &&
                        (({1'b0, sig} + {25'b0, increment}) <
                         33'h080000000));
    end
  endfunction

  // Input exponent is nonnegative. Subnormal right shifting is performed by
  // ST_DENORM one bit per cycle before entering this final round stage.
  function [36:0] round_pack;
    input sign;
    input signed [10:0] exp_in;
    input [31:0] sig_in;
    input [2:0] rm;
    reg [7:0] increment;
    reg [6:0] round_bits;
    reg [24:0] rounded;
    reg [32:0] rounded_full;
    reg [4:0] flags;
    begin
      flags = 0;
      increment = round_increment(sign, rm);
      round_bits = sig_in[6:0];
      if ((exp_in > 253) ||
          ((exp_in == 253) &&
           (({1'b0, sig_in} + {25'b0, increment}) >=
            33'h080000000))) begin
        flags[2] = 1'b1;
        flags[0] = 1'b1;
        round_pack = {flags,
                      ({sign, 8'hff, 23'b0} -
                       {31'b0, (increment == 0)})};
      end else begin
        rounded_full = {1'b0, sig_in} + {25'b0, increment};
        rounded = rounded_full[31:7];
        if (round_bits != 0)
          flags[0] = 1'b1;
        if ((rm == 0) && (round_bits == 7'h40))
          rounded[0] = 1'b0;
        round_pack = {flags,
                      ({sign, exp_in[7:0], 23'b0} +
                       {7'b0, rounded[24:0]})};
      end
    end
  endfunction

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      state_r <= ST_IDLE;
      busy_r <= 1'b0;
      sqrt_r <= 1'b0;
      sign_r <= 1'b0;
      rm_r <= 3'b0;
      sig_a_r <= 24'b0;
      sig_b_r <= 24'b0;
      exp_a_r <= 11'sd0;
      exp_b_r <= 11'sd0;
      exp_z_r <= 11'sd0;
      div_rem_r <= 25'b0;
      div_quot_r <= 32'b0;
      iter_r <= 6'b0;
      sqrt_rad_r <= 64'b0;
      sqrt_rem_r <= 66'b0;
      sqrt_root_r <= 32'b0;
      round_sig_r <= 32'b0;
      round_exp_r <= 11'sd0;
      tiny_r <= 1'b0;
      slow_complete_valid <= 1'b0;
      slow_complete_seq_id <= {SEQ_ID_WIDTH{1'b0}};
      slow_complete_epoch <= {EPOCH_WIDTH{1'b0}};
      slow_complete_rd <= {REG_INDEX_WIDTH{1'b0}};
      slow_complete_rd_bank <= 1'b0;
      slow_complete_value <= 32'b0;
      slow_complete_fflags <= 5'b0;
    end else if (slow_cancel) begin
      state_r <= ST_IDLE;
      busy_r <= 1'b0;
      slow_complete_valid <= 1'b0;
    end else begin
      slow_complete_valid <= 1'b0;
      case (state_r)
        ST_IDLE: begin
          if (slow_issue_valid) begin
            busy_r <= 1'b1;
            sqrt_r <= slow_issue_sqrt;
            sign_r <= slow_issue_sqrt ? 1'b0
                                      : slow_issue_src0[31] ^ slow_issue_src1[31];
            rm_r <= slow_issue_rm;
            slow_complete_seq_id <= slow_issue_seq_id;
            slow_complete_epoch <= slow_issue_epoch;
            slow_complete_rd <= slow_issue_rd;
            slow_complete_rd_bank <= slow_issue_rd_bank;
            slow_complete_fflags <= 5'b0;

            if (slow_issue_sqrt) begin
              if (slow_issue_src0[30:23] == 8'hff &&
                  slow_issue_src0[22:0] != 0) begin
                slow_complete_value <= 32'h7fc00000;
                slow_complete_fflags <= {!slow_issue_src0[22], 4'b0};
                state_r <= ST_ROUND;
                round_exp_r <= 11'sd1023;
              end else if (slow_issue_src0[31] &&
                           slow_issue_src0[30:0] != 0) begin
                slow_complete_value <= 32'h7fc00000;
                slow_complete_fflags <= 5'b10000;
                state_r <= ST_ROUND;
                round_exp_r <= 11'sd1023;
              end else if (slow_issue_src0[30:23] == 8'hff ||
                           slow_issue_src0[30:0] == 0) begin
                slow_complete_value <= slow_issue_src0;
                state_r <= ST_ROUND;
                round_exp_r <= 11'sd1023;
              end else begin
                sig_a_r <= {1'b0, slow_issue_src0[22:0]};
                exp_a_r <= slow_issue_src0[30:23] == 0
                         ? 11'sd1 : {3'b0, slow_issue_src0[30:23]};
                if (slow_issue_src0[30:23] != 0)
                  sig_a_r[23] <= 1'b1;
                state_r <= ST_NORM_A;
              end
            end else if ((slow_issue_src0[30:23] == 8'hff &&
                          slow_issue_src0[22:0] != 0) ||
                         (slow_issue_src1[30:23] == 8'hff &&
                          slow_issue_src1[22:0] != 0)) begin
              slow_complete_value <= 32'h7fc00000;
              slow_complete_fflags <=
                {((slow_issue_src0[30:23] == 8'hff &&
                   slow_issue_src0[22:0] != 0 && !slow_issue_src0[22]) ||
                  (slow_issue_src1[30:23] == 8'hff &&
                   slow_issue_src1[22:0] != 0 && !slow_issue_src1[22])), 4'b0};
              state_r <= ST_ROUND;
              round_exp_r <= 11'sd1023;
            end else if ((slow_issue_src0[30:23] == 8'hff &&
                          slow_issue_src1[30:23] == 8'hff) ||
                         (slow_issue_src0[30:0] == 0 &&
                          slow_issue_src1[30:0] == 0)) begin
              slow_complete_value <= 32'h7fc00000;
              slow_complete_fflags <= 5'b10000;
              state_r <= ST_ROUND;
              round_exp_r <= 11'sd1023;
            end else if (slow_issue_src0[30:23] == 8'hff) begin
              slow_complete_value <= {slow_issue_src0[31] ^
                                      slow_issue_src1[31], 8'hff, 23'b0};
              state_r <= ST_ROUND;
              round_exp_r <= 11'sd1023;
            end else if (slow_issue_src1[30:23] == 8'hff) begin
              slow_complete_value <= {slow_issue_src0[31] ^
                                      slow_issue_src1[31], 31'b0};
              state_r <= ST_ROUND;
              round_exp_r <= 11'sd1023;
            end else if (slow_issue_src1[30:0] == 0) begin
              slow_complete_value <= {slow_issue_src0[31] ^
                                      slow_issue_src1[31], 8'hff, 23'b0};
              slow_complete_fflags <= 5'b01000;
              state_r <= ST_ROUND;
              round_exp_r <= 11'sd1023;
            end else if (slow_issue_src0[30:0] == 0) begin
              slow_complete_value <= {slow_issue_src0[31] ^
                                      slow_issue_src1[31], 31'b0};
              state_r <= ST_ROUND;
              round_exp_r <= 11'sd1023;
            end else begin
              sig_a_r <= {1'b0, slow_issue_src0[22:0]};
              sig_b_r <= {1'b0, slow_issue_src1[22:0]};
              exp_a_r <= slow_issue_src0[30:23] == 0
                       ? 11'sd1 : {3'b0, slow_issue_src0[30:23]};
              exp_b_r <= slow_issue_src1[30:23] == 0
                       ? 11'sd1 : {3'b0, slow_issue_src1[30:23]};
              if (slow_issue_src0[30:23] != 0)
                sig_a_r[23] <= 1'b1;
              if (slow_issue_src1[30:23] != 0)
                sig_b_r[23] <= 1'b1;
              state_r <= ST_NORM_A;
            end
          end
        end

        ST_NORM_A: begin
          if (!sig_a_r[23]) begin
            sig_a_r <= sig_a_r << 1;
            exp_a_r <= exp_a_r - 1'b1;
          end else if (sqrt_r) begin
            state_r <= ST_PREP;
          end else begin
            state_r <= ST_NORM_B;
          end
        end

        ST_NORM_B: begin
          if (!sig_b_r[23]) begin
            sig_b_r <= sig_b_r << 1;
            exp_b_r <= exp_b_r - 1'b1;
          end else begin
            state_r <= ST_PREP;
          end
        end

        ST_PREP: begin
          if (sqrt_r) begin
            exp_z_r <= ((exp_a_r - 11'sd127) >>> 1) + 11'sd126;
            sqrt_rad_r <= {40'b0, sig_a_r} <<
                          (!exp_a_r[0] ? 38 : 37);
            sqrt_rem_r <= 66'b0;
            sqrt_root_r <= 32'b0;
            iter_r <= 6'd32;
            state_r <= ST_SQRT;
          end else begin
            exp_z_r <= exp_a_r - exp_b_r + 11'sd126 -
                       {10'b0, (sig_a_r < sig_b_r)};
            div_rem_r <= {1'b0, sig_a_r};
            div_quot_r <= 32'b0;
            iter_r <= sig_a_r < sig_b_r ? 6'd32 : 6'd31;
            state_r <= ST_DIV;
          end
        end

        ST_DIV: begin
          div_rem_r <= div_rem_next;
          div_quot_r <= div_quot_next;
          iter_r <= iter_r - 1'b1;
          if (iter_r == 1) begin
            round_sig_r <= (div_rem_sub != 0)
                         ? {div_quot_next[31:1], 1'b1} : div_quot_next;
            round_exp_r <= exp_z_r;
            tiny_r <= result_is_tiny(sign_r, exp_z_r,
                         (div_rem_sub != 0)
                           ? {div_quot_next[31:1], 1'b1} : div_quot_next,
                         rm_r);
            state_r <= exp_z_r < 0 ? ST_DENORM : ST_ROUND;
          end
        end

        ST_SQRT: begin
          sqrt_rad_r <= sqrt_rad_r << 2;
          sqrt_rem_r <= sqrt_rem_next;
          sqrt_root_r <= sqrt_root_next;
          iter_r <= iter_r - 1'b1;
          if (iter_r == 1) begin
            round_sig_r <= (sqrt_rem_next != 0)
                         ? {sqrt_root_next[31:1], 1'b1} : sqrt_root_next;
            round_exp_r <= exp_z_r;
            tiny_r <= 1'b0;
            state_r <= ST_ROUND;
          end
        end

        ST_DENORM: begin
          round_sig_r <= {1'b0, round_sig_r[31:2],
                          round_sig_r[1] | round_sig_r[0]};
          round_exp_r <= round_exp_r + 1'b1;
          if (round_exp_r == -1)
            state_r <= ST_ROUND;
        end

        ST_ROUND: begin
          if (round_exp_r == 11'sd1023) begin
            // Special-case result was already captured at issue.
            busy_r <= 1'b0;
            state_r <= ST_IDLE;
            slow_complete_valid <= 1'b1;
          end else begin
            result_flags = round_pack(sign_r, round_exp_r,
                                      round_sig_r, rm_r);
            slow_complete_value <= result_flags[31:0];
            slow_complete_fflags <= result_flags[36:32] |
                                    {3'b0,
                                     tiny_r && result_flags[32], 1'b0};
            busy_r <= 1'b0;
            state_r <= ST_IDLE;
            slow_complete_valid <= 1'b1;
          end
        end

        default: begin
          state_r <= ST_IDLE;
          busy_r <= 1'b0;
        end
      endcase
    end
  end
endmodule
