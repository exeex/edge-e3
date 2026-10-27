// One 64-bit, 32-bit-in/32-bit-out circular lane with six routing modes.
module edge_weight_circular_lane_mux6(
  clk, rst_b, mode_i,
  load_valid_i, load_ready_o, load_data_i,
  drain_valid_o, drain_ready_i, drain_data_o
);

input clk, rst_b;
input [2:0] mode_i;
input load_valid_i;
output load_ready_o;
input [31:0] load_data_i;
output drain_valid_o;
input drain_ready_i;
output [31:0] drain_data_o;

localparam MODE_N16 = 3'd0;
localparam MODE_T16 = 3'd1;
localparam MODE_N8  = 3'd2;
localparam MODE_T8  = 3'd3;
localparam MODE_N4  = 3'd4;
localparam MODE_T4  = 3'd5;
localparam ST_EMPTY = 2'd0;
localparam ST_HALF  = 2'd1;
localparam ST_OUT0  = 2'd2;
localparam ST_OUT1  = 2'd3;

reg [1:0] state_q;
reg [31:0] first_q;
reg [31:0] out0_q, out1_q;
reg [31:0] next_first_q;
reg next_first_valid_q;
wire load_accept = load_valid_i && load_ready_o;
wire drain_accept = drain_valid_o && drain_ready_i;

function [63:0] route_pair;
  input [2:0] mode;
  input [31:0] word0;
  input [31:0] word1;
  reg [31:0] routed0, routed1;
  integer i;
  begin
    routed0 = word0;
    routed1 = word1;
    case (mode)
      MODE_T16: begin
        routed0 = {word1[15:0], word0[15:0]};
        routed1 = {word1[31:16], word0[31:16]};
      end
      MODE_T8: begin
        for (i=0; i<2; i=i+1) begin
          routed0[i*16 +: 8] = word0[i*8 +: 8];
          routed0[i*16+8 +: 8] = word1[i*8 +: 8];
          routed1[i*16 +: 8] = word0[(i+2)*8 +: 8];
          routed1[i*16+8 +: 8] = word1[(i+2)*8 +: 8];
        end
      end
      MODE_T4: begin
        for (i=0; i<4; i=i+1) begin
          routed0[i*8 +: 4] = word0[i*4 +: 4];
          routed0[i*8+4 +: 4] = word1[i*4 +: 4];
          routed1[i*8 +: 4] = word0[(i+4)*4 +: 4];
          routed1[i*8+4 +: 4] = word1[(i+4)*4 +: 4];
        end
      end
      default: begin end
    endcase
    route_pair = {routed1, routed0};
  end
endfunction

wire [63:0] direct_pair = route_pair(mode_i, first_q, load_data_i);
wire [63:0] rolling_pair = route_pair(mode_i, next_first_q, load_data_i);

assign drain_valid_o = state_q == ST_OUT0 || state_q == ST_OUT1;
assign drain_data_o = state_q == ST_OUT0 ? out0_q : out1_q;
assign load_ready_o = state_q == ST_EMPTY || state_q == ST_HALF
                    || (state_q == ST_OUT0 && drain_ready_i)
                    || (state_q == ST_OUT1
                        && (!next_first_valid_q || drain_ready_i));

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    state_q <= ST_EMPTY;
    first_q <= 0;
    out0_q <= 0;
    out1_q <= 0;
    next_first_q <= 0;
    next_first_valid_q <= 1'b0;
  end else begin
    case (state_q)
      ST_EMPTY: if (load_accept) begin
        first_q <= load_data_i;
        state_q <= ST_HALF;
      end
      ST_HALF: if (load_accept) begin
        out0_q <= direct_pair[31:0];
        out1_q <= direct_pair[63:32];
        state_q <= ST_OUT0;
      end
      ST_OUT0: if (drain_accept) begin
        if (load_accept) begin
          next_first_q <= load_data_i;
          next_first_valid_q <= 1'b1;
        end
        state_q <= ST_OUT1;
      end
      ST_OUT1: begin
        if (!next_first_valid_q) begin
          if (drain_accept && load_accept) begin
            first_q <= load_data_i;
            state_q <= ST_HALF;
          end else if (drain_accept) begin
            state_q <= ST_EMPTY;
          end else if (load_accept) begin
            next_first_q <= load_data_i;
            next_first_valid_q <= 1'b1;
          end
        end else if (drain_accept) begin
          if (load_accept) begin
            out0_q <= rolling_pair[31:0];
            out1_q <= rolling_pair[63:32];
            next_first_valid_q <= 1'b0;
            state_q <= ST_OUT0;
          end else begin
            first_q <= next_first_q;
            next_first_valid_q <= 1'b0;
            state_q <= ST_HALF;
          end
        end
      end
      default: state_q <= ST_EMPTY;
    endcase
  end
end

endmodule
