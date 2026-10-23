// Experimental E3 wide schedule. Eight 128-bit lanes form four 256-bit
// ports: P, O, narrow A0/A1, narrow B0/B1. Addresses are 16-byte units.
// Raw SRAM never stalls; ready only describes this cycle's route ownership.
module edge_dtcm_h4_wide (
  input wire clk, rst_b,
  output wire ready_o,
  output wire [2:0] phase_o,
  input wire [7:0] req_i, write_i,
  input wire [103:0] addr_i,
  input wire [1023:0] data_i,
  input wire [127:0] strb_i,
  output wire [7:0] grant_o,
  output reg [7:0] valid_o,
  output reg [1023:0] data_o
);
  reg [2:0] phase_q;
  reg [8:0] fill_q;
  always @(posedge clk or negedge rst_b)
    if (!rst_b) begin phase_q <= 0; fill_q <= 0; end
    else begin
      phase_q <= phase_q + 3'd1;
      if (fill_q != 9'd256) fill_q <= fill_q + 9'd1;
    end
  assign phase_o = phase_q;
  assign ready_o = fill_q == 9'd256;

  // Keep leaf phase-hop waveforms canonical. Logical 256-bit rotation is
  // separate; speeding up the legacy phase spine would break its identities.
  wire [2:0] h2_phase = phase_q + 3'd1;
  wire [2:0] h1_phase = phase_q + 3'd2;
  wire [4:0] h1_link, h2_link, h4_link;
  assign h1_link[0] = phase_q[0];
  assign h2_link[0] = phase_q[1];
  assign h4_link[0] = phase_q[2];
  reg [1:0] route_tag [0:2];
  reg [2:0] byte_tag;
  always @(posedge clk) begin
    route_tag[0] <= phase_q[1:0];
    route_tag[1] <= route_tag[0];
    route_tag[2] <= route_tag[1];
    byte_tag <= {byte_tag[1:0], h2_phase[1]};
  end

  wire [3:0] tile_ready;
  wire [7:0] eligible;
  assign grant_o[0] = eligible[0] && eligible[1];
  assign grant_o[1] = eligible[0] && eligible[1];
  assign grant_o[2] = eligible[2] && eligible[3];
  assign grant_o[3] = eligible[2] && eligible[3];
  assign grant_o[7:4] = eligible[7:4];
  wire [127:0] rsp_valid;
  wire [1023:0] rsp_data;
  genvar tile, b, lane;
  generate for (lane=0; lane<8; lane=lane+1) begin: OWNERSHIP
    wire [1:0] group_idx = phase_q[1:0] + 2'(lane/2);
    wire half_idx = 1'(lane%2) ^ ((lane >= 4) && phase_q[2]);
    assign eligible[lane] = ready_o && req_i[lane]
        && addr_i[lane*13 +: 3] == {group_idx, half_idx};
  end
  for (tile=0; tile<4; tile=tile+1) begin: H4
    wire [1:0] port_idx = 2'(tile) - phase_q[1:0];
    wire swap = port_idx[1] && phase_q[2];
    wire [31:0] valid, wr, mask, half;
    wire [287:0] address;
    wire [255:0] payload;
    for (b=0; b<32; b=b+1) begin: BYTE
      wire [2:0] client = {port_idx, 1'(b/16)};
      // Compensate H2 byte-quartet rotation only. H4's physical swap
      // performs the desired narrow-client exchange, not a wrapper mux.
      wire [3:0] byte_idx = {1'((b%16)/8), 1'((b/4)%2) ^ h2_phase[1], 2'(b%4)};
      assign valid[b] = grant_o[client];
      assign wr[b] = write_i[client];
      assign mask[b] = strb_i[client*16+byte_idx];
      assign half[b] = addr_i[client*13+12] ^ h1_phase[0];
      assign address[b*9 +: 9] = addr_i[client*13+3 +: 9];
      assign payload[b*8 +: 8] = data_i[client*128+byte_idx*8 +: 8];
    end
    edge_sram_h4_tile32k #(.EXPLICIT_SWAP(1)) x_tile (
      .clk(clk), .rst_b(rst_b), .swap_i(swap),
      .phase_h1_i(h1_link[tile]), .phase_h2_i(h2_link[tile]),
      .phase_h4_i(h4_link[tile]), .phase_h1_o(h1_link[tile+1]),
      .phase_h2_o(h2_link[tile+1]), .phase_h4_o(h4_link[tile+1]),
      .phase_ready_o(tile_ready[tile]),
      .req_valid_i(valid), .req_write_i(wr), .req_wstrb_i(mask),
      .req_bank_half_i(half), .req_addr_i(address), .req_wdata_i(payload),
      .rsp_valid_o(rsp_valid[tile*32 +: 32]),
      .rsp_data_o(rsp_data[tile*256 +: 256]));
  end
  for (lane=0; lane<8; lane=lane+1) begin: RESPONSE
    wire [1:0] source_tile = 2'(lane/2) + route_tag[2];
    wire [15:0] byte_valid;
    wire [127:0] payload;
    for (b=0; b<16; b=b+1) begin: BYTE
      wire [4:0] source_byte = {1'(lane%2), 1'(b/8),
          1'((b/4)%2) ^ byte_tag[2], 2'(b%4)};
      assign byte_valid[b] = rsp_valid[source_tile*32+source_byte];
      assign payload[b*8 +: 8] = rsp_data[source_tile*256+source_byte*8 +: 8];
    end
    always @(posedge clk or negedge rst_b)
      if (!rst_b) valid_o[lane] <= 0;
      else valid_o[lane] <= &byte_valid;
    always @(posedge clk) data_o[lane*128 +: 128] <= payload;
  end endgenerate
`ifndef SYNTHESIS
  always @(posedge clk) if (rst_b && ready_o) begin
    if (tile_ready != 4'hf || h1_link[4] !== phase_q[0] ||
        h2_link[4] !== phase_q[1] || h4_link[4] !== phase_q[2])
      $fatal(1, "wide H4 canonical phase chain mismatch");
    if (grant_o[0] != grant_o[1] || grant_o[2] != grant_o[3])
      $fatal(1, "wide P/O must issue atomically");
  end
`endif
endmodule
