module edge_tensor_iopsum_remux(
  clk,
  clear_i_psum,
  clear_o,
  lane0_data,
  lane0_hi,
  lane0_role,
  lane0_valid,
  lane1_data,
  lane1_hi,
  lane1_pair_data,
  lane1_pair_role,
  lane1_pair_valid,
  lane1_role,
  lane1_valid,
  lane2_data,
  lane2_hi,
  lane2_role,
  lane2_valid,
  output_push_data,
  output_push_valid,
  rst_b,
  input_vec,
  input_vec_ready,
  output_vec,
  output_vec_ready,
  psum_vec,
  psum_vec_ready
);

input          clk;
input          clear_i_psum;
input          clear_o;
input  [63:0]  lane0_data;
input          lane0_hi;
input  [1:0]   lane0_role;
input          lane0_valid;
input  [63:0]  lane1_data;
input          lane1_hi;
input  [127:0] lane1_pair_data;
input  [1:0]   lane1_pair_role;
input          lane1_pair_valid;
input  [1:0]   lane1_role;
input          lane1_valid;
input  [63:0]  lane2_data;
input          lane2_hi;
input  [1:0]   lane2_role;
input          lane2_valid;
input  [127:0] output_push_data;
input          output_push_valid;
input          rst_b;
output [127:0] input_vec;
output         input_vec_ready;
output [127:0] output_vec;
output         output_vec_ready;
output [127:0] psum_vec;
output         psum_vec_ready;

reg [127:0] input_vec_q;
reg [127:0] output_vec_q;
reg [127:0] psum_vec_q;
reg [1:0]   input_valid_q;
reg [1:0]   output_valid_q;
reg [1:0]   psum_valid_q;

localparam [1:0] ROLE_NONE = 2'd0;
localparam [1:0] ROLE_I    = 2'd1;
localparam [1:0] ROLE_PSUM = 2'd2;
localparam [1:0] ROLE_O    = 2'd3;

assign input_vec[127:0] = input_vec_q[127:0];
assign psum_vec[127:0] = psum_vec_q[127:0];
assign output_vec[127:0] = output_vec_q[127:0];
assign input_vec_ready = input_valid_q[1:0] == 2'b11;
assign psum_vec_ready = psum_valid_q[1:0] == 2'b11;
assign output_vec_ready = output_valid_q[1:0] == 2'b11;

task remux_lane;
  input [1:0]  role;
  input        hi;
  input [63:0] data;
begin
  case (role[1:0])
    ROLE_I: begin
      if (hi) begin
        input_vec_q[127:64] <= data[63:0];
        input_valid_q[1] <= 1'b1;
      end else begin
        input_vec_q[63:0] <= data[63:0];
        input_valid_q[0] <= 1'b1;
      end
    end
    ROLE_PSUM: begin
      if (hi) begin
        psum_vec_q[127:64] <= data[63:0];
        psum_valid_q[1] <= 1'b1;
      end else begin
        psum_vec_q[63:0] <= data[63:0];
        psum_valid_q[0] <= 1'b1;
      end
    end
    ROLE_O: begin
      if (hi) begin
        output_vec_q[127:64] <= data[63:0];
        output_valid_q[1] <= 1'b1;
      end else begin
        output_vec_q[63:0] <= data[63:0];
        output_valid_q[0] <= 1'b1;
      end
    end
    default: begin
    end
  endcase
end
endtask

task remux_pair;
  input [1:0]   role;
  input [127:0] data;
begin
  case (role[1:0])
    ROLE_I: begin
      input_vec_q[127:0] <= data[127:0];
      input_valid_q[1:0] <= 2'b11;
    end
    ROLE_PSUM: begin
      psum_vec_q[127:0] <= data[127:0];
      psum_valid_q[1:0] <= 2'b11;
    end
    ROLE_O: begin
      output_vec_q[127:0] <= data[127:0];
      output_valid_q[1:0] <= 2'b11;
    end
    default: begin
    end
  endcase
end
endtask

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    input_vec_q[127:0] <= 128'b0;
    psum_vec_q[127:0] <= 128'b0;
    output_vec_q[127:0] <= 128'b0;
    input_valid_q[1:0] <= 2'b0;
    psum_valid_q[1:0] <= 2'b0;
    output_valid_q[1:0] <= 2'b0;
  end else begin
    if (clear_i_psum) begin
      input_valid_q[1:0] <= 2'b0;
      psum_valid_q[1:0] <= 2'b0;
    end

    if (clear_o)
      output_valid_q[1:0] <= 2'b0;

    if (output_push_valid) begin
      output_vec_q[127:0] <= output_push_data[127:0];
      output_valid_q[1:0] <= 2'b11;
    end

    if (lane0_valid)
      remux_lane(lane0_role[1:0], lane0_hi, lane0_data[63:0]);
    if (lane1_valid)
      remux_lane(lane1_role[1:0], lane1_hi, lane1_data[63:0]);
    if (lane1_pair_valid)
      remux_pair(lane1_pair_role[1:0], lane1_pair_data[127:0]);
    if (lane2_valid)
      remux_lane(lane2_role[1:0], lane2_hi, lane2_data[63:0]);
  end
end

endmodule
