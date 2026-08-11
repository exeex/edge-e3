module edge_lite_accel_owner (
  input  wire        clk,
  input  wire        reset_n,
  input  wire        req_valid,
  output wire        req_ready,
  input  wire [63:0] req_inst,
  input  wire [63:0] req_capture_value,
  output wire        cmd_valid,
  input  wire        cmd_ready,
  output wire [63:0] cmd_inst,
  output wire        cmd_capture_valid,
  output wire [63:0] cmd_capture_value,
  input  wire        cmd_decode_illegal,
  input  wire        cmd_result_valid,
  input  wire [63:0] cmd_result_value,
  output reg         resp_valid,
  output reg         resp_error,
  output reg  [63:0] resp_value
);
  wire cmd_fire = cmd_valid && cmd_ready;

  assign cmd_valid = req_valid && !resp_valid;
  assign req_ready = cmd_ready && !resp_valid;
  assign cmd_inst = req_inst;
  assign cmd_capture_valid = 1'b1;
  assign cmd_capture_value = req_capture_value;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      resp_valid <= 1'b0;
      resp_error <= 1'b0;
      resp_value <= 64'b0;
    end else begin
      resp_valid <= cmd_fire;
      if (cmd_fire) begin
        resp_error <= cmd_decode_illegal;
        resp_value <= cmd_result_valid ? cmd_result_value : 64'b0;
      end
    end
  end
endmodule
