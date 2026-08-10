module edge_dtcm_upper_pair_router(
  clk,
  cpurst_b,
  pair_phase,
  logical_request_payload,
  physical_request_payload,
  physical_response_payload,
  logical_response_payload
);

parameter REQUEST_WIDTH = 1;
parameter RESPONSE_WIDTH = 1;

input                         clk;
input                         cpurst_b;
input  [2:0]                  pair_phase;
input  [4*REQUEST_WIDTH-1:0]  logical_request_payload;
output [8*REQUEST_WIDTH-1:0]  physical_request_payload;
input  [8*RESPONSE_WIDTH-1:0] physical_response_payload;
output [4*RESPONSE_WIDTH-1:0] logical_response_payload;

wire [1:0]                    request_rotation_phase;
wire [1:0]                    response_rotation_phase;
wire [1:0]                    inverse_response_phase;
wire [4*REQUEST_WIDTH-1:0]    grouped_request_payload;
wire [4*RESPONSE_WIDTH-1:0]   grouped_response_payload;
reg  [2:0]                    response_pair_phase_q;

genvar group_i;

// Odd logical channels 1/3/5/7 become four upper groups.  The parity bit is
// handled by the SRAM-door upper/lower mux, including its carry into the
// four-group rotation.
assign request_rotation_phase[1:0] =
    pair_phase[2:1] + {1'b0, pair_phase[0]};
assign response_rotation_phase[1:0] =
    response_pair_phase_q[2:1] + {1'b0, response_pair_phase_q[0]};
assign inverse_response_phase[1:0] =
    2'd0 - response_rotation_phase[1:0];

edge_dtcm_pair_rotator4 #(
  .PAYLOAD_WIDTH(REQUEST_WIDTH)
) x_request_rotator (
  .phase(request_rotation_phase[1:0]),
  .in_payload(logical_request_payload[4*REQUEST_WIDTH-1:0]),
  .out_payload(grouped_request_payload[4*REQUEST_WIDTH-1:0])
);

generate
  for (group_i = 0; group_i < 4; group_i = group_i + 1) begin: UPPER_GROUP
    // Both physical pair parities receive the same upper payload.  The
    // existing raw-fabric upper/lower mux consumes only the owned parity.
    assign physical_request_payload[(2*group_i)*REQUEST_WIDTH
                                    +: REQUEST_WIDTH] =
        grouped_request_payload[group_i*REQUEST_WIDTH +: REQUEST_WIDTH];
    assign physical_request_payload[(2*group_i+1)*REQUEST_WIDTH
                                    +: REQUEST_WIDTH] =
        grouped_request_payload[group_i*REQUEST_WIDTH +: REQUEST_WIDTH];

    // SRAM read data is shared, so select the parity that belonged to upper
    // on the captured request phase before applying the two internal layers.
    assign grouped_response_payload[group_i*RESPONSE_WIDTH
                                    +: RESPONSE_WIDTH] =
        response_pair_phase_q[0]
        ? physical_response_payload[(2*group_i)*RESPONSE_WIDTH
                                    +: RESPONSE_WIDTH]
        : physical_response_payload[(2*group_i+1)*RESPONSE_WIDTH
                                    +: RESPONSE_WIDTH];
  end
endgenerate

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b)
    response_pair_phase_q[2:0] <= 3'd0;
  else
    response_pair_phase_q[2:0] <= pair_phase[2:0];
end

edge_dtcm_pair_rotator4 #(
  .PAYLOAD_WIDTH(RESPONSE_WIDTH)
) x_response_rotator (
  .phase(inverse_response_phase[1:0]),
  .in_payload(grouped_response_payload[4*RESPONSE_WIDTH-1:0]),
  .out_payload(logical_response_payload[4*RESPONSE_WIDTH-1:0])
);

endmodule
