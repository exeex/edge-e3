module edge_dtcm_pair_rotator8(
  phase,
  in_payload,
  out_payload
);

parameter PAYLOAD_WIDTH = 1;
parameter [7:0] INPUT_MASK = 8'hff;
parameter [7:0] OUTPUT_MASK = 8'hff;

input  [2:0]                   phase;
input  [8*PAYLOAD_WIDTH-1:0]   in_payload;
output [8*PAYLOAD_WIDTH-1:0]   out_payload;

wire [8*PAYLOAD_WIDTH-1:0] shift1_payload;
wire [8*PAYLOAD_WIDTH-1:0] shift2_payload;
wire [8*PAYLOAD_WIDTH-1:0] masked_input_payload;
wire [8*PAYLOAD_WIDTH-1:0] rotated_payload;

genvar lane_i;

generate
  for (lane_i = 0; lane_i < 8; lane_i = lane_i + 1) begin: ROTATE_LANE
    assign masked_input_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
        INPUT_MASK[lane_i]
        ? in_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH]
        : {PAYLOAD_WIDTH{1'b0}};
    assign shift1_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
        phase[0]
        ? masked_input_payload[((lane_i + 7) % 8)*PAYLOAD_WIDTH
                               +: PAYLOAD_WIDTH]
        : masked_input_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
    assign shift2_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
        phase[1]
        ? shift1_payload[((lane_i + 6) % 8)*PAYLOAD_WIDTH +: PAYLOAD_WIDTH]
        : shift1_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
    assign rotated_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
        phase[2]
        ? shift2_payload[((lane_i + 4) % 8)*PAYLOAD_WIDTH +: PAYLOAD_WIDTH]
        : shift2_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
    assign out_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
        OUTPUT_MASK[lane_i]
        ? rotated_payload[lane_i*PAYLOAD_WIDTH +: PAYLOAD_WIDTH]
        : {PAYLOAD_WIDTH{1'b0}};
  end
endgenerate

endmodule
