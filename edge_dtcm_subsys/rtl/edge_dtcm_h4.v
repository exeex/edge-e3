// E3 word address: {row[9:0], bank[3:0]}; each bank is 64 bits.
// Four H4s supply 16 banks / eight 128-bit channels / 128 KiB.
// H4 -> H2 -> H1/SRAM takes three edges; DTCM registers the fourth response edge.
module edge_dtcm_h4 (
  input wire clk, cpurst_b,
  input wire [2:0] pair_phase,
  output wire phase_ready,
  input wire [15:0] bank_req, bank_we,
  input wire [159:0] bank_addr,
  input wire [1023:0] bank_wdata,
  input wire [127:0] bank_wstrb,
  output reg [1023:0] bank_rdata,
  output reg [15:0] bank_rvalid
);
  // The four chained H4s have 256 H1 phase hops. Phase keeps advancing
  // during fill; clients may issue only after phase_ready.
  reg [8:0] fill_q;
  always @(posedge clk or negedge cpurst_b)
    if (!cpurst_b) fill_q <= 0;
    else if (fill_q != 9'd256) fill_q <= fill_q + 9'd1;
  assign phase_ready = (fill_q == 9'd256);

  wire [2:0] h2_phase = pair_phase + 3'd1;
  wire [2:0] h1_phase = pair_phase + 3'd2;
  reg [2:0] h4_tag, h2_tag;
  wire [1023:0] response_data;
  wire [15:0] response_valid;
  always @(posedge clk or negedge cpurst_b)
    if (!cpurst_b) bank_rvalid <= 0;
    else bank_rvalid <= response_valid;
  always @(posedge clk) bank_rdata <= response_data;
  always @(posedge clk or negedge cpurst_b)
    if (!cpurst_b) begin
      h4_tag <= 0;
      h2_tag <= 0;
    end else begin
      h4_tag <= {h4_tag[1:0], pair_phase[2]};
      h2_tag <= {h2_tag[1:0], h2_phase[1]};
    end

  wire [127:0] req_valid, req_write, req_strb, req_half, rsp_valid;
  wire [1151:0] req_addr;
  wire [1023:0] req_data, rsp_data;
  wire [4:0] h1_link, h2_link, h4_link;
  wire [3:0] tile_ready;
  assign h1_link[0] = pair_phase[0];
  assign h2_link[0] = pair_phase[1];
  assign h4_link[0] = pair_phase[2];

  genvar tile, lane, bank, byte_no;
  generate
    // A fixed local butterfly (two 2:1 muxes), not a global crossbar.
    // At cut t: H4 swaps pairs using phase[t][2]; H2 at t+1 swaps
    // quartets using phase[t+1][1]; H1 at t+2 selects the row half.
    for (tile=0; tile<4; tile=tile+1) begin: H4
      for (lane=0; lane<32; lane=lane+1) begin: REQUEST
        wire [1:0] source_bank =
            {1'(lane/16) ^ pair_phase[2], 1'((lane/8)%2)};
        wire [2:0] source_byte =
            {1'((lane/4)%2) ^ h2_phase[1], 2'(lane%4)};
        wire [3:0] source_word = {2'(tile), source_bank};
        assign req_valid[tile*32+lane] = phase_ready && bank_req[source_word];
        assign req_write[tile*32+lane] = bank_we[source_word];
        assign req_strb[tile*32+lane] = bank_wstrb[source_word*8+source_byte];
        assign req_half[tile*32+lane] = bank_addr[source_word*10+9] ^ h1_phase[0];
        assign req_addr[(tile*32+lane)*9 +: 9] = bank_addr[source_word*10 +: 9];
        assign req_data[(tile*32+lane)*8 +: 8] =
            bank_wdata[source_word*64+source_byte*8 +: 8];
      end
      edge_sram_h4_tile32k x_tile (
        .clk(clk), .rst_b(cpurst_b), .swap_i(1'b0),
        .phase_h1_i(h1_link[tile]), .phase_h2_i(h2_link[tile]),
        .phase_h4_i(h4_link[tile]), .phase_h1_o(h1_link[tile+1]),
        .phase_h2_o(h2_link[tile+1]), .phase_h4_o(h4_link[tile+1]),
        .phase_ready_o(tile_ready[tile]),
        .req_valid_i(req_valid[tile*32 +: 32]),
        .req_write_i(req_write[tile*32 +: 32]),
        .req_wstrb_i(req_strb[tile*32 +: 32]),
        .req_bank_half_i(req_half[tile*32 +: 32]),
        .req_addr_i(req_addr[tile*288 +: 288]),
        .req_wdata_i(req_data[tile*256 +: 256]),
        .rsp_valid_o(rsp_valid[tile*32 +: 32]),
        .rsp_data_o(rsp_data[tile*256 +: 256]));
    end
    for (bank=0; bank<16; bank=bank+1) begin: RESPONSE
      wire [7:0] byte_valid;
      for (byte_no=0; byte_no<8; byte_no=byte_no+1) begin: BYTE
        wire [4:0] lane_idx =
            {1'((bank/2)%2) ^ h4_tag[2], 1'(bank%2),
             1'(byte_no/4) ^ h2_tag[2], 2'(byte_no%4)};
        assign response_data[bank*64+byte_no*8 +: 8] =
            rsp_data[(bank/4)*256+lane_idx*8 +: 8];
        assign byte_valid[byte_no] = rsp_valid[(bank/4)*32+lane_idx];
      end
      assign response_valid[bank] = &byte_valid;
    end
  endgenerate
`ifndef SYNTHESIS
  always @(posedge clk) if (cpurst_b && phase_ready) begin
    if (tile_ready !== 4'hf || h1_link[4] !== pair_phase[0] ||
        h2_link[4] !== pair_phase[1] || h4_link[4] !== pair_phase[2])
      $fatal(1, "E3 H4 phase chain not filled");
  end
`endif
endmodule
