module edge_dtcm_pair_rotator4(
  phase,
  in_payload,
  out_payload
);

parameter PAYLOAD_WIDTH = 1;

input  [1:0]                   phase;
input  [4*PAYLOAD_WIDTH-1:0]   in_payload;
output [4*PAYLOAD_WIDTH-1:0]   out_payload;

wire [4*PAYLOAD_WIDTH-1:0] shift1_payload;

genvar lane_i;

generate
  for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin: ROTATE_LANE
    assign shift1_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
        phase[0]
        ? in_payload[((lane_i + 3) % 4)*PAYLOAD_WIDTH +: PAYLOAD_WIDTH]
        : in_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
    assign out_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
        phase[1]
        ? shift1_payload[((lane_i + 2) % 4)*PAYLOAD_WIDTH +: PAYLOAD_WIDTH]
        : shift1_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
  end
endgenerate

endmodule
