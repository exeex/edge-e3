// One-entry descriptor queue that binds and launches an explicit weight token.
module edge_tensor_packed_start_queue_sidecar(
  clk, rst_b,
  weight_start_i, weight_start_ready_o,
  weight_format_i, weight_transpose_i,
  weight_load_valid_i, weight_load_ready_o, weight_load_data_i,
  weight_drain_ready_i, weight_done_o,
  weight_reuse_i, weight_reuse_ready_o,
  weight_token_valid_o, weight_token_reuse_o, weight_active_valid_o,
  desc_valid_i, desc_ready_o, desc_tag_i, desc_mode_i,
  desc_vector_count_i, desc_input_addr_i, desc_psum_addr_i,
  desc_output_addr_i, desc_scale_bf16_i,
  engine_weight_idle_i,
  launch_valid_o, launch_ready_i, launch_tag_o, launch_reuse_o,
  launch_mode_o, launch_vector_count_o, launch_input_addr_o,
  launch_psum_addr_o, launch_output_addr_o, launch_scale_bf16_o,
  compute_valid_i, input_bf16_i, psum_bf16_i,
  scale_enable_i, scale_bf16_i,
  output_valid_o, output_bf16_o
);

input clk, rst_b;
input weight_start_i;
output weight_start_ready_o;
input [2:0] weight_format_i;
input weight_transpose_i, weight_load_valid_i;
output weight_load_ready_o;
input [127:0] weight_load_data_i;
input weight_drain_ready_i;
output weight_done_o;
input weight_reuse_i;
output weight_reuse_ready_o;
output weight_token_valid_o, weight_token_reuse_o, weight_active_valid_o;
input desc_valid_i;
output desc_ready_o;
input [3:0] desc_tag_i;
input [7:0] desc_mode_i;
input [15:0] desc_vector_count_i;
input [31:0] desc_input_addr_i, desc_psum_addr_i, desc_output_addr_i;
input [127:0] desc_scale_bf16_i;
input engine_weight_idle_i;
output launch_valid_o;
input launch_ready_i;
output [3:0] launch_tag_o;
output launch_reuse_o;
output [7:0] launch_mode_o;
output [15:0] launch_vector_count_o;
output [31:0] launch_input_addr_o, launch_psum_addr_o, launch_output_addr_o;
output [127:0] launch_scale_bf16_o;
input compute_valid_i;
input [127:0] input_bf16_i, psum_bf16_i;
input scale_enable_i;
input [127:0] scale_bf16_i;
output output_valid_o;
output [127:0] output_bf16_o;

localparam Q_EMPTY = 2'd0;
localparam Q_BOUND = 2'd1;
localparam Q_READY = 2'd2;
reg [1:0] state_q;
reg [3:0] tag_q;
reg reuse_q;
reg [7:0] mode_q;
reg [15:0] vector_count_q;
reg [31:0] input_addr_q, psum_addr_q, output_addr_q;
reg [127:0] scale_bf16_q;
wire token_consume = (state_q == Q_BOUND) && engine_weight_idle_i;
wire desc_accept = desc_valid_i && desc_ready_o;
wire launch_accept = launch_valid_o && launch_ready_i;

assign desc_ready_o = (state_q == Q_EMPTY) && weight_token_valid_o;
assign launch_valid_o = (state_q == Q_READY);
assign launch_tag_o = tag_q;
assign launch_reuse_o = reuse_q;
assign launch_mode_o = mode_q;
assign launch_vector_count_o = vector_count_q;
assign launch_input_addr_o = input_addr_q;
assign launch_psum_addr_o = psum_addr_q;
assign launch_output_addr_o = output_addr_q;
assign launch_scale_bf16_o = scale_bf16_q;

edge_tensor_packed_token_sidecar x_token (
  .clk(clk), .rst_b(rst_b),
  .weight_start_i(weight_start_i), .weight_start_ready_o(weight_start_ready_o),
  .weight_format_i(weight_format_i), .weight_transpose_i(weight_transpose_i),
  .weight_load_valid_i(weight_load_valid_i),
  .weight_load_ready_o(weight_load_ready_o),
  .weight_load_data_i(weight_load_data_i),
  .weight_drain_ready_i(weight_drain_ready_i), .weight_done_o(weight_done_o),
  .weight_reuse_i(weight_reuse_i), .weight_reuse_ready_o(weight_reuse_ready_o),
  .weight_token_valid_o(weight_token_valid_o),
  .weight_token_reuse_o(weight_token_reuse_o),
  .weight_token_consume_i(token_consume),
  .weight_active_valid_o(weight_active_valid_o),
  .compute_valid_i(compute_valid_i), .input_bf16_i(input_bf16_i),
  .psum_bf16_i(psum_bf16_i), .scale_enable_i(scale_enable_i),
  .scale_bf16_i(scale_bf16_i),
  .output_valid_o(output_valid_o), .output_bf16_o(output_bf16_o)
);

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    state_q <= Q_EMPTY;
    tag_q <= 4'b0;
    reuse_q <= 1'b0;
    mode_q <= 8'b0;
    vector_count_q <= 16'b0;
    input_addr_q <= 32'b0;
    psum_addr_q <= 32'b0;
    output_addr_q <= 32'b0;
    scale_bf16_q <= 128'b0;
  end else begin
    case (state_q)
      Q_EMPTY: if (desc_accept) begin
        tag_q <= desc_tag_i;
        reuse_q <= weight_token_reuse_o;
        mode_q <= desc_mode_i;
        vector_count_q <= desc_vector_count_i;
        input_addr_q <= desc_input_addr_i;
        psum_addr_q <= desc_psum_addr_i;
        output_addr_q <= desc_output_addr_i;
        scale_bf16_q <= desc_scale_bf16_i;
        state_q <= Q_BOUND;
      end
      Q_BOUND: if (engine_weight_idle_i)
        state_q <= Q_READY;
      Q_READY: if (launch_accept)
        state_q <= Q_EMPTY;
      default: state_q <= Q_EMPTY;
    endcase
  end
end
endmodule
