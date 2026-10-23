// Minimal stream engine around the packed descriptor/token sidecar.
module edge_tensor_packed_stream_engine_sidecar(
  clk, rst_b,
  weight_start_i, weight_start_ready_o, weight_format_i, weight_transpose_i,
  weight_load_valid_i, weight_load_ready_o, weight_load_data_i,
  weight_drain_ready_i, weight_done_o, weight_reuse_i, weight_reuse_ready_o,
  desc_valid_i, desc_ready_o, desc_tag_i, desc_mode_i,
  desc_vector_count_i, desc_input_addr_i, desc_psum_addr_i,
  desc_output_addr_i, desc_scale_bf16_i,
  stream_valid_i, stream_ready_o, stream_input_bf16_i, stream_psum_bf16_i,
  output_valid_o, output_bf16_o, busy_o, done_o, done_tag_o
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
input desc_valid_i;
output desc_ready_o;
input [3:0] desc_tag_i;
input [7:0] desc_mode_i;
input [15:0] desc_vector_count_i;
input [31:0] desc_input_addr_i, desc_psum_addr_i, desc_output_addr_i;
input [127:0] desc_scale_bf16_i;
input stream_valid_i;
output stream_ready_o;
input [127:0] stream_input_bf16_i, stream_psum_bf16_i;
output output_valid_o;
output [127:0] output_bf16_o;
output busy_o, done_o;
output [3:0] done_tag_o;

wire launch_valid, launch_reuse;
wire [3:0] launch_tag;
wire [7:0] launch_mode;
wire [15:0] launch_vector_count;
wire [31:0] unused_launch_input_addr, unused_launch_psum_addr;
wire [31:0] unused_launch_output_addr;
wire [127:0] launch_scale;
wire token_valid, token_reuse, active_valid;
wire tile_output_valid;
reg busy_q, done_q;
reg [3:0] active_tag_q, done_tag_q;
reg [7:0] active_mode_q;
reg [15:0] target_count_q, issue_count_q, output_count_q;
reg [127:0] active_scale_q;
wire launch_accept = launch_valid && !busy_q;
wire stream_accept = stream_valid_i && stream_ready_o;

assign stream_ready_o = busy_q && (issue_count_q < target_count_q);
assign output_valid_o = tile_output_valid;
assign busy_o = busy_q;
assign done_o = done_q;
assign done_tag_o = done_tag_q;

edge_tensor_packed_start_queue_sidecar x_queue (
  .clk(clk), .rst_b(rst_b),
  .weight_start_i(weight_start_i), .weight_start_ready_o(weight_start_ready_o),
  .weight_format_i(weight_format_i), .weight_transpose_i(weight_transpose_i),
  .weight_load_valid_i(weight_load_valid_i),
  .weight_load_ready_o(weight_load_ready_o),
  .weight_load_data_i(weight_load_data_i),
  .weight_drain_ready_i(weight_drain_ready_i), .weight_done_o(weight_done_o),
  .weight_reuse_i(weight_reuse_i), .weight_reuse_ready_o(weight_reuse_ready_o),
  .weight_token_valid_o(token_valid), .weight_token_reuse_o(token_reuse),
  .weight_active_valid_o(active_valid),
  .desc_valid_i(desc_valid_i), .desc_ready_o(desc_ready_o),
  .desc_tag_i(desc_tag_i), .desc_mode_i(desc_mode_i),
  .desc_vector_count_i(desc_vector_count_i),
  .desc_input_addr_i(desc_input_addr_i), .desc_psum_addr_i(desc_psum_addr_i),
  .desc_output_addr_i(desc_output_addr_i),
  .desc_scale_bf16_i(desc_scale_bf16_i),
  .engine_weight_idle_i(!busy_q),
  .launch_valid_o(launch_valid), .launch_ready_i(!busy_q),
  .launch_tag_o(launch_tag), .launch_reuse_o(launch_reuse),
  .launch_mode_o(launch_mode), .launch_vector_count_o(launch_vector_count),
  .launch_input_addr_o(unused_launch_input_addr),
  .launch_psum_addr_o(unused_launch_psum_addr),
  .launch_output_addr_o(unused_launch_output_addr),
  .launch_scale_bf16_o(launch_scale),
  .compute_valid_i(stream_accept), .input_bf16_i(stream_input_bf16_i),
  .psum_bf16_i(stream_psum_bf16_i),
  .scale_enable_i(active_mode_q[0]), .scale_bf16_i(active_scale_q),
  .output_valid_o(tile_output_valid), .output_bf16_o(output_bf16_o)
);

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    busy_q<=0; done_q<=0; active_tag_q<=0; done_tag_q<=0;
    active_mode_q<=0; target_count_q<=0; issue_count_q<=0;
    output_count_q<=0; active_scale_q<=0;
  end else begin
    done_q <= 1'b0;
    if (launch_accept) begin
      active_tag_q <= launch_tag;
      active_mode_q <= launch_mode;
      target_count_q <= launch_vector_count;
      issue_count_q <= 0;
      output_count_q <= 0;
      active_scale_q <= launch_scale;
      if (launch_vector_count == 0) begin
        busy_q <= 0;
        done_q <= 1;
        done_tag_q <= launch_tag;
      end else begin
        busy_q <= 1;
      end
    end
    if (stream_accept)
      issue_count_q <= issue_count_q + 1'b1;
    if (tile_output_valid) begin
      output_count_q <= output_count_q + 1'b1;
      if (output_count_q + 1'b1 == target_count_q) begin
        busy_q <= 0;
        done_q <= 1;
        done_tag_q <= active_tag_q;
      end
    end
  end
end

wire unused_token_state = token_valid || token_reuse || active_valid
                        || launch_reuse;
endmodule
