// Scale-first slot byte stream. Addresses are in 64-bit DTCM words.
module edge_wsld_slot_reader #(
  parameter ADDR_WIDTH = 16,
  parameter READ_LATENCY = 1,
  parameter PREFETCH_BEATS = READ_LATENCY + 2
)(
  input wire clk, cpurst_b,
  input wire start, active,
  input wire [ADDR_WIDTH-1:0] base_addr,
  input wire [31:0] config_i,
  output wire rd_req,
  output wire [ADDR_WIDTH-1:0] rd_addr,
  input wire rd_ready, rd_rvalid,
  input wire [127:0] rd_rdata,
  input wire sld_req, wld_req,
  output wire sld_ready, wld_ready,
  output wire sld_rvalid, wld_rvalid,
  output wire [127:0] sld_rdata, wld_rdata
);
  reg [255:0] bytes_q, bytes_next;
  reg [5:0] count_q, count_next;
  reg scale_q, scalar_q;
  reg [3:0] stype_q;
  reg [15:0] beats_left_q;
  reg [ADDR_WIDTH-1:0] addr_q;
  wire [15:0] weight_bytes = config_i[19:16] == 1 ?
      {1'b0,config_i[7:0],7'b0} : config_i[19:16] == 4 ?
      {3'b0,config_i[7:0],5'b0} : {2'b0,config_i[7:0],6'b0};
  wire [15:0] payload_bytes = weight_bytes +
      (config_i[15:12] == 0 ? {11'd0,config_i[11:8],1'b0} : {12'd0,config_i[11:8]});
  wire [5:0] take_bytes = !scale_q ? 6'd16 : stype_q == 0 ?
      (scalar_q ? 6'd2 : 6'd16) : (scalar_q ? 6'd1 : 6'd8);
  function [15:0] decode_scale8;
    input [7:0] code;
    input [3:0] stype;
    reg [7:0] exponent;
    reg [6:0] fraction;
    integer leading;
    begin
      if (stype == 1)
        decode_scale8 = code == 255 ? 16'h7fc0 :
                        code == 0 ? 16'h0040 : {1'b0,code,7'b0};
      else if (code[6:0] == 7'h7f)
        decode_scale8 = 16'h7fc0;
      else if (code[6:3] != 0) begin
        exponent = {4'b0,code[6:3]} + 8'd120;
        decode_scale8 = {code[7],exponent,code[2:0],4'b0};
      end else if (code[2:0] == 0)
        decode_scale8 = {code[7],15'b0};
      else begin
        leading = code[2] ? 2 : code[1] ? 1 : 0;
        exponent = 8'(118 + leading);
        fraction = 7'({4'b0,code[2:0]} << (7-leading));
        decode_scale8 = {code[7],exponent,fraction};
      end
    end
  endfunction
  reg [127:0] scale_data;
  integer lane;
  always @* begin
    scale_data = scalar_q ? {8{bytes_q[15:0]}} : bytes_q[127:0];
    if (stype_q != 0)
      for (lane=0;lane<8;lane=lane+1)
        scale_data[lane*16+:16] = decode_scale8(bytes_q[(scalar_q ? 0 : lane*8)+:8],stype_q);
  end
  wire take_scale = sld_req && sld_ready;
  wire take_weight = wld_req && wld_ready;
  wire take = take_scale || take_weight;
  // Each accepted read reserves a FIFO entry until the aligner pops it.
  // Responses never need backpressure, even if the consumer stops abruptly.
  localparam PTR_WIDTH = $clog2(PREFETCH_BEATS) > 0 ? $clog2(PREFETCH_BEATS) : 1;
  localparam CREDIT_WIDTH = $clog2(PREFETCH_BEATS + 1);
  reg [127:0] fifo_q [0:PREFETCH_BEATS-1];
  reg [PTR_WIDTH-1:0] head_q, tail_q;
  reg [CREDIT_WIDTH-1:0] reserved_q, available_q, outstanding_q;
  wire pop = available_q != 0 && (count_q - (take ? take_bytes : 6'd0)) <= 16;
  wire read_fire = rd_req && rd_ready;
  assign rd_req = active && !start && beats_left_q != 0 &&
      (reserved_q < PREFETCH_BEATS || pop);
  assign rd_addr = addr_q;
  assign sld_ready = active && !start && scale_q && count_q >= take_bytes;
  assign wld_ready = active && !start && !scale_q && count_q >= 16;
  reg [READ_LATENCY-1:0] scale_valid_q, weight_valid_q;
  reg [127:0] data_q [0:READ_LATENCY-1];
  integer i;
  assign sld_rvalid = scale_valid_q[READ_LATENCY-1];
  assign wld_rvalid = weight_valid_q[READ_LATENCY-1];
  assign sld_rdata = data_q[READ_LATENCY-1];
  assign wld_rdata = data_q[READ_LATENCY-1];
  always @* begin
    bytes_next = bytes_q;
    count_next = count_q;
    if (take) begin
      bytes_next = bytes_q >> (take_bytes * 8);
      count_next = count_q - take_bytes;
    end
    if (pop) begin
      bytes_next = bytes_next | ({128'd0,fifo_q[head_q]} << (count_next * 8));
      count_next = count_next + 6'd16;
    end
  end
  always @(posedge clk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      bytes_q <= 0; count_q <= 0;
      head_q <= 0; tail_q <= 0; reserved_q <= 0; available_q <= 0; outstanding_q <= 0;
      scale_q <= 1; scalar_q <= 0; stype_q <= 0; beats_left_q <= 0; addr_q <= 0;
      scale_valid_q <= 0; weight_valid_q <= 0;
      for (i=0;i<READ_LATENCY;i=i+1) data_q[i] <= 0;
    end else begin
      scale_valid_q[0] <= take_scale;
      weight_valid_q[0] <= take_weight;
      data_q[0] <= scale_q ? scale_data : bytes_q[127:0];
      for (i=1;i<READ_LATENCY;i=i+1) begin
        scale_valid_q[i] <= scale_valid_q[i-1];
        weight_valid_q[i] <= weight_valid_q[i-1];
        data_q[i] <= data_q[i-1];
      end
      if (start) begin
        bytes_q <= 0; count_q <= 0;
        head_q <= 0; tail_q <= 0; reserved_q <= 0; available_q <= 0; outstanding_q <= 0;
        scale_q <= 1; scalar_q <= config_i[11:8] == 1;
        stype_q <= config_i[15:12];
        beats_left_q <= (payload_bytes + 16'd15) >> 4;
        addr_q <= base_addr;
      end else begin
        bytes_q <= bytes_next; count_q <= count_next;
        if (take_scale) scale_q <= 0;
        if (read_fire) begin
          addr_q <= addr_q + 2;
          beats_left_q <= beats_left_q - 1'b1;
        end
        if (rd_rvalid) begin
          fifo_q[tail_q] <= rd_rdata;
          tail_q <= tail_q == PREFETCH_BEATS-1 ? 0 : tail_q + 1'b1;
        end
        if (pop) head_q <= head_q == PREFETCH_BEATS-1 ? 0 : head_q + 1'b1;
        case ({read_fire,pop})
          2'b10: reserved_q <= reserved_q + 1'b1;
          2'b01: reserved_q <= reserved_q - 1'b1;
          default: ;
        endcase
        case ({rd_rvalid,pop})
          2'b10: available_q <= available_q + 1'b1;
          2'b01: available_q <= available_q - 1'b1;
          default: ;
        endcase
        case ({read_fire,rd_rvalid})
          2'b10: outstanding_q <= outstanding_q + 1'b1;
          2'b01: outstanding_q <= outstanding_q - 1'b1;
          default: ;
        endcase
      end
    end
  end
`ifndef SYNTHESIS
  initial if (PREFETCH_BEATS < 1) $fatal(1,"WSLD needs at least one response credit");
  always @(posedge clk) if (cpurst_b) begin
    if (reserved_q != available_q + outstanding_q || reserved_q > PREFETCH_BEATS || count_next > 32)
      $fatal(1,"WSLD credit conservation failure");
    if (rd_rvalid && (outstanding_q == 0 || (available_q == PREFETCH_BEATS && !pop)))
      $fatal(1,"WSLD response without reserved byte capacity");
    if (start && (outstanding_q != 0 || base_addr[0]))
      $fatal(1,"WSLD slot overlap or unaligned slot base");
  end
`endif
endmodule
