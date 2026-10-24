// Wide-schedule bank doors. Four dual-port H1 tiles supply 128 KiB.
// Two request cuts, the H1 SRAM edge, then the DTCM response edge.
// The original H4 hierarchy remains available as a reference/physical branch.
module edge_dtcm_h4_wide_bank_direct #(
`ifdef EDGE_SRAM_H4_WIDE_HARDENED
  parameter H1_TILE32K = 0
`else
  parameter H1_TILE32K = 1
`endif
)(
  input wire clk, cpurst_b,
  output wire [3:0] phase,
  output wire phase_ready,
  input wire [15:0] bank_req, bank_we,
  input wire [159:0] bank_addr,
  input wire [1023:0] bank_wdata,
  input wire [127:0] bank_wstrb,
  output reg [1023:0] bank_rdata,
  output reg [15:0] bank_rvalid
);
  generate if (H1_TILE32K) begin: H1_STORAGE
    reg [2:0] q;
    reg [8:0] fill;
    always @(posedge clk or negedge cpurst_b)
      if (!cpurst_b) begin q<=0; fill<=0; end
      else begin q<=q+1'b1; if(fill!=256) fill<=fill+1'b1; end
    assign phase={q,1'b0};
    assign phase_ready=(fill==256);
    // Retain the two request cuts before the sole SRAM payload edge.
    reg [15:0] read_tag [0:2];
    always @(posedge clk or negedge cpurst_b)
      if(!cpurst_b) begin
        for(integer n=0;n<3;n=n+1) read_tag[n]<=0;
        bank_rvalid<=0;
      end else begin
        read_tag[0]<=bank_req & ~bank_we & {16{phase_ready}};
        read_tag[1]<=read_tag[0]; read_tag[2]<=read_tag[1];
        bank_rvalid<=read_tag[2];
      end
    wire [4:0] phase_link;
    wire [3:0] ready;
    assign phase_link[0]=q[0];
    for(genvar t=0;t<4;t=t+1) begin: TILE
      reg [1:0] valid_q[0:1], write_q[0:1];
      reg [19:0] addr_q[0:1];
      reg [255:0] data_q[0:1];
      reg [31:0] strb_q[0:1];
      wire [1:0] v,w,rv;
      wire [19:0] a;
      wire [255:0] d,rd;
      wire [31:0] be;
      reg response_swap;
      always @(posedge clk) response_swap<=phase_link[t];
      for(genvar p=0;p<2;p=p+1) begin: PAIR
        localparam B=4*t+2*p;
        always @(posedge clk or negedge cpurst_b)
          if(!cpurst_b) begin valid_q[0][p]<=0;valid_q[1][p]<=0;end
          else begin
            valid_q[0][p]<=phase_ready && (bank_req[B] || bank_req[B+1]);
            valid_q[1][p]<=valid_q[0][p];
          end
        always @(posedge clk) begin
          write_q[0][p]<=(bank_req[B] && bank_we[B]) || (bank_req[B+1] && bank_we[B+1]);
          addr_q[0][p*10+:10]<=bank_req[B] ? bank_addr[B*10+:10] : bank_addr[(B+1)*10+:10];
          data_q[0][p*128+:128]<=bank_wdata[B*64+:128];
          strb_q[0][p*16+:16]<=bank_wstrb[B*8+:16] &
              {{8{bank_req[B+1] && bank_we[B+1]}},{8{bank_req[B] && bank_we[B]}}};
          write_q[1][p]<=write_q[0][p];
          addr_q[1][p*10+:10]<=addr_q[0][p*10+:10];
          data_q[1][p*128+:128]<=data_q[0][p*128+:128];
          strb_q[1][p*16+:16]<=strb_q[0][p*16+:16];
        end
        // H1 maps logical port p to physical pair p XOR phase at the
        // SRAM edge. Compensate locally so the public bank identity is fixed.
        wire source=1'(p)^phase_link[t];
        assign v[p]=valid_q[1][source];
        assign w[p]=write_q[1][source];
        assign a[p*10+:10]=addr_q[1][source*10+:10];
        assign d[p*128+:128]=data_q[1][source*128+:128];
        assign be[p*16+:16]=strb_q[1][source*16+:16];
        wire returned=1'(p)^response_swap;
        always @(posedge clk) bank_rdata[B*64+:128]<=rd[returned*128+:128];
`ifndef SYNTHESIS
        always @(posedge clk) if(cpurst_b && read_tag[2][B+:2]!=0 && !rv[returned])
          $fatal(1,"H1 missing pair response");
`endif
      end
      edge_sram_h1_tile32k x_tile (
        .clk(clk),.rst_b(cpurst_b),.phase_i(phase_link[t]),
        .phase_o(phase_link[t+1]),.ready_o(ready[t]),
        .req_valid_i(v),.req_write_i(w),.req_addr_i(a),
        .req_wdata_i(d),.req_wstrb_i(be),.rsp_valid_o(rv),.rsp_data_o(rd));
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(cpurst_b && phase_ready) begin
      if(ready!==4'hf || phase_link[4]!==q[0]) $fatal(1,"H1 phase chain not filled");
      for(integer b=0;b<16;b=b+2)
        if(bank_req[b] && bank_req[b+1] &&
           (bank_addr[b*10+:10]!=bank_addr[(b+1)*10+:10] || bank_we[b]!=bank_we[b+1]))
          $fatal(1,"H1 incompatible 64-bit halves");
    end
`endif
  end else begin: LEGACY_STORAGE
  reg [2:0] pair_phase;
  assign phase={pair_phase,1'b0};
  always @(posedge clk or negedge cpurst_b)
    if(!cpurst_b) pair_phase<=0;
    else pair_phase<=pair_phase+1'b1;
  // The four chained H4s have 256 H1 phase hops. Phase keeps advancing
  // during fill; clients may issue only after phase_ready.
  reg [8:0] fill_q;
  always @(posedge clk or negedge cpurst_b)
    if (!cpurst_b) fill_q <= 0;
    else if (fill_q != 9'd256) fill_q <= fill_q + 9'd1;
  assign phase_ready = (fill_q == 9'd256);

  wire [2:0] h2_phase = pair_phase + 3'd1;
  wire [2:0] h1_phase = pair_phase + 3'd2;
  reg [2:0] h2_tag;
  reg [15:0] read_tag [0:2];
  always @(posedge clk or negedge cpurst_b)
    if(!cpurst_b) begin
      for(integer k=0;k<3;k=k+1) read_tag[k]<=0;
    end else begin
      read_tag[0]<=phase_ready ? bank_req & ~bank_we : 16'b0;
      read_tag[1]<=read_tag[0];read_tag[2]<=read_tag[1];
    end
  wire [1023:0] response_data;
  wire [15:0] response_valid;
  always @(posedge clk or negedge cpurst_b)
    if (!cpurst_b) bank_rvalid <= 0;
    else bank_rvalid <= response_valid & read_tag[2];
  always @(posedge clk) bank_rdata <= response_data;
  always @(posedge clk or negedge cpurst_b)
    if (!cpurst_b) begin
      h2_tag <= 0;
    end else begin
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
    // Wide P/O reserve both 128-bit halves even for a partial BF16/COPY
    // access. Missing halves issue dummy reads or zero-strobe writes.
    for (tile=0; tile<4; tile=tile+1) begin: H4
      wire [1:0] port_idx=2'(tile)-pair_phase[1:0];
      wire swap=port_idx[1] && pair_phase[2];
      reg [2:0] swap_tag;
      always @(posedge clk) swap_tag<={swap_tag[1:0],swap};
      wire [1:0] pair_req, pair_write, enabled, write_mode;
      wire [9:0] row [0:1];
      for(genvar p=0;p<2;p=p+1) begin: PAIR
        localparam B=4*tile+2*p;
        assign pair_req[p]=bank_req[B] || bank_req[B+1];
        assign pair_write[p]=(bank_req[B] && bank_we[B]) || (bank_req[B+1] && bank_we[B+1]);
        assign enabled[p]=phase_ready && (pair_req[p] || (!port_idx[1] && pair_req[1-p]));
        assign write_mode[p]=pair_req[p] ? pair_write[p] : (!port_idx[1] && pair_write[1-p]);
        assign row[p]=bank_req[B] ? bank_addr[B*10+:10] : bank_addr[(B+1)*10+:10];
      end
      for (lane=0; lane<32; lane=lane+1) begin: REQUEST
        wire source_pair=1'(lane/16)^swap;
        wire [1:0] source_bank={source_pair,1'((lane/8)%2)};
        wire [2:0] source_byte={1'((lane/4)%2)^h2_phase[1],2'(lane%4)};
        // Only a 4-bank local select; tile is a generate constant.
        wire [3:0] source_word={2'(tile),source_bank};
        assign req_valid[tile*32+lane]=enabled[source_pair];
        assign req_write[tile*32+lane]=write_mode[source_pair];
        assign req_strb[tile*32+lane]=bank_req[source_word] && bank_we[source_word]
            && bank_wstrb[source_word*8+source_byte];
        assign req_half[tile*32+lane]=row[source_pair][9]^h1_phase[0];
        assign req_addr[(tile*32+lane)*9+:9]=row[source_pair][8:0];
        assign req_data[(tile*32+lane)*8+:8]=bank_wdata[source_word*64+source_byte*8+:8];
      end
`ifdef EDGE_SRAM_H4_WIDE_HARDENED
      edge_sram_h4_wide_tile32k x_tile (
`else
      edge_sram_h4_tile32k #(.EXPLICIT_SWAP(1)) x_tile (
`endif
        .clk(clk), .rst_b(cpurst_b), .swap_i(swap),
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
            {1'((bank/2)%2) ^ H4[bank/4].swap_tag[2], 1'(bank%2),
             1'(byte_no/4) ^ h2_tag[2], 2'(byte_no%4)};
        assign response_data[bank*64+byte_no*8 +: 8] =
            rsp_data[(bank/4)*256+lane_idx*8 +: 8];
        assign byte_valid[byte_no] = rsp_valid[(bank/4)*32+lane_idx];
      end
      assign response_valid[bank] = &byte_valid;
    end
`ifndef SYNTHESIS
  always @(posedge clk) if (cpurst_b && phase_ready) begin
    for(integer b=0;b<16;b=b+2)
      if(bank_req[b] && bank_req[b+1] &&
          (bank_addr[b*10+:10]!=bank_addr[(b+1)*10+:10] || bank_we[b]!=bank_we[b+1]))
        $fatal(1,"direct H4 incompatible 64-bit halves");
    if (tile_ready !== 4'hf || h1_link[4] !== pair_phase[0] ||
        h2_link[4] !== pair_phase[1] || h4_link[4] !== pair_phase[2])
      $fatal(1, "E3 H4 phase chain not filled");
  end
`endif
  end endgenerate
endmodule
