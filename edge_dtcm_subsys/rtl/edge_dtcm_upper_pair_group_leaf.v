module edge_dtcm_upper_pair_group_leaf(
  request_select,
  request_payload_a,
  request_payload_b,
  physical_request_payload,
  response_parity,
  physical_response_payload,
  grouped_response_payload
);

parameter REQUEST_WIDTH = 1;
parameter RESPONSE_WIDTH = 1;

input                         request_select;
input  [REQUEST_WIDTH-1:0]    request_payload_a;
input  [REQUEST_WIDTH-1:0]    request_payload_b;
output [2*REQUEST_WIDTH-1:0]  physical_request_payload;
input                         response_parity;
input  [2*RESPONSE_WIDTH-1:0] physical_response_payload;
output [RESPONSE_WIDTH-1:0]   grouped_response_payload;

wire [REQUEST_WIDTH-1:0] selected_request_payload;

assign selected_request_payload[REQUEST_WIDTH-1:0] =
    request_select
    ? request_payload_b[REQUEST_WIDTH-1:0]
    : request_payload_a[REQUEST_WIDTH-1:0];

// The SRAM-door upper/lower mux consumes only the parity owned by upper.
assign physical_request_payload[REQUEST_WIDTH-1:0] =
    selected_request_payload[REQUEST_WIDTH-1:0];
assign physical_request_payload[2*REQUEST_WIDTH-1:REQUEST_WIDTH] =
    selected_request_payload[REQUEST_WIDTH-1:0];

assign grouped_response_payload[RESPONSE_WIDTH-1:0] =
    response_parity
    ? physical_response_payload[RESPONSE_WIDTH-1:0]
    : physical_response_payload[2*RESPONSE_WIDTH-1:RESPONSE_WIDTH];

endmodule
