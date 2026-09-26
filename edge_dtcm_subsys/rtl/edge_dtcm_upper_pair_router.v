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
// Odd channels (1/3/5/7) are the maintained upper plane.  Even channels
// (0/2/4/6) use the same four-group route with the carry/parity reversed.
parameter CHANNEL_PARITY = 1;
parameter READ_LATENCY = 1;

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
wire [4*REQUEST_WIDTH-1:0]    request_shift1_payload;
wire [4*REQUEST_WIDTH-1:0]    grouped_request_payload;
wire [4*RESPONSE_WIDTH-1:0]   grouped_response_payload;
wire [2:0] response_pair_phase_q;
reg [2:0] phase_pipe [0:READ_LATENCY-1];
integer stage;

genvar group_i;

// Four same-parity logical channels become four routed groups.  Pair parity is
// handled by the SRAM-door upper/lower mux.  Odd channels carry pair_phase[0]
// into the group rotation; even channels do not.
assign request_rotation_phase[1:0] =
    pair_phase[2:1]
  + {1'b0, (pair_phase[0] && (CHANNEL_PARITY != 0))};
assign response_rotation_phase[1:0] =
    response_pair_phase_q[2:1]
  + {1'b0, (response_pair_phase_q[0] && (CHANNEL_PARITY != 0))};
assign inverse_response_phase[1:0] =
    2'd0 - response_rotation_phase[1:0];

generate
  for (group_i = 0; group_i < 4; group_i = group_i + 1) begin: UPPER_GROUP
    // The first request layer remains a shared spine.  Each group-local leaf
    // owns the second layer and the final physical SRAM-pair connections.
    assign request_shift1_payload[group_i*REQUEST_WIDTH
                                  +: REQUEST_WIDTH] =
        request_rotation_phase[0]
        ? logical_request_payload[((group_i + 3) % 4)*REQUEST_WIDTH
                                  +: REQUEST_WIDTH]
        : logical_request_payload[group_i*REQUEST_WIDTH +: REQUEST_WIDTH];

    edge_dtcm_upper_pair_group_leaf #(
      .REQUEST_WIDTH(REQUEST_WIDTH),
      .RESPONSE_WIDTH(RESPONSE_WIDTH)
    ) x_group_leaf (
      .request_select(request_rotation_phase[1]),
      .request_payload_a(
          request_shift1_payload[group_i*REQUEST_WIDTH +: REQUEST_WIDTH]),
      .request_payload_b(
          request_shift1_payload[((group_i + 2) % 4)*REQUEST_WIDTH
                                 +: REQUEST_WIDTH]),
      .physical_request_payload(
          physical_request_payload[(2*group_i)*REQUEST_WIDTH
                                   +: 2*REQUEST_WIDTH]),
      .response_parity(
          CHANNEL_PARITY != 0
          ? response_pair_phase_q[0]
          : !response_pair_phase_q[0]),
      .physical_response_payload(
          physical_response_payload[(2*group_i)*RESPONSE_WIDTH
                                    +: 2*RESPONSE_WIDTH]),
      .grouped_response_payload(
          grouped_response_payload[group_i*RESPONSE_WIDTH
                                   +: RESPONSE_WIDTH])
    );
  end
endgenerate

always @(posedge clk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    for (stage=0; stage<READ_LATENCY; stage=stage+1) phase_pipe[stage] <= 0;
  end else begin
    phase_pipe[0] <= pair_phase;
    for (stage=1; stage<READ_LATENCY; stage=stage+1)
      phase_pipe[stage] <= phase_pipe[stage-1];
  end
end
assign response_pair_phase_q = phase_pipe[READ_LATENCY-1];

edge_dtcm_pair_rotator4 #(
  .PAYLOAD_WIDTH(RESPONSE_WIDTH)
) x_response_rotator (
  .phase(inverse_response_phase[1:0]),
  .in_payload(grouped_response_payload[4*RESPONSE_WIDTH-1:0]),
  .out_payload(logical_response_payload[4*RESPONSE_WIDTH-1:0])
);

endmodule
