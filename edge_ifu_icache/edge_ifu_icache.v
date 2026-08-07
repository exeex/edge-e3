// First Edge IFU I-cache slice.
module edge_ifu_icache #(
  parameter PC_WIDTH = 40,
  parameter ICACHE_BYTES = 16384,
  parameter LINE_BYTES = 16
) (
  input  wire                    forever_cpuclk,
  input  wire                    cpurst_b,

  input  wire                    fetch_req_valid,
  output wire                    fetch_req_ready,
  input  wire [PC_WIDTH-1:0]     fetch_req_addr,

  input  wire                    invalidate_valid,
  output wire                    invalidate_ready,

  output wire                    fetch_resp_valid,
  input  wire                    fetch_resp_ready,
  output wire [127:0]            fetch_resp_bits,

  output wire                    imem_req_valid,
  input  wire                    imem_req_ready,
  output wire [PC_WIDTH-1:0]     imem_req_addr,

  input  wire                    imem_resp_valid,
  output wire                    imem_resp_ready,
  input  wire [127:0]            imem_resp_bits,

  output wire [31:0]             debug_icache_bytes,
  output wire                    debug_hit,
  output wire                    debug_miss_pending,
  output wire                    debug_invalidate_busy
);

  localparam LINES = ICACHE_BYTES / LINE_BYTES;
  localparam LINE_OFFSET_WIDTH = (LINE_BYTES <= 2) ? 1 : $clog2(LINE_BYTES);
  localparam LINE_INDEX_WIDTH = (LINES <= 2) ? 1 : $clog2(LINES);
  localparam TAG_WIDTH = PC_WIDTH - LINE_OFFSET_WIDTH - LINE_INDEX_WIDTH;
  localparam [31:0] ICACHE_BYTES_U32 = ICACHE_BYTES;

  reg resp_valid_q;
  reg [127:0] resp_bits_q;
  reg miss_resp_buf_valid_q;
  reg [127:0] miss_resp_buf_bits_q;

  reg miss_pending_q;
  reg [LINE_INDEX_WIDTH-1:0] miss_index_q;
  reg [TAG_WIDTH-1:0] miss_tag_q;
  reg invalidate_active_q;
  reg [LINE_INDEX_WIDTH-1:0] invalidate_index_q;

  wire [PC_WIDTH-1:0] aligned_req_addr;
  wire [LINE_INDEX_WIDTH-1:0] req_index;
  wire [TAG_WIDTH-1:0] req_tag;
  wire [127:0] req_data;
  wire [TAG_WIDTH-1:0] req_array_tag;
  wire req_array_valid;
  wire req_hit;
  wire req_can_complete;
  wire req_fire;
  wire miss_req_fire;
  wire miss_resp_fire;
  wire resp_can_update;
  wire resp_primary_ready;
  wire miss_resp_to_primary;
  wire miss_resp_to_buffer;
  wire miss_buf_promote;
  wire invalidate_fire;
  wire invalidate_last;
  wire tag_clear_valid;

  assign aligned_req_addr = {fetch_req_addr[PC_WIDTH-1:LINE_OFFSET_WIDTH],
                             {LINE_OFFSET_WIDTH{1'b0}}};
  assign req_index =
    fetch_req_addr[LINE_OFFSET_WIDTH +: LINE_INDEX_WIDTH];
  assign req_tag =
    fetch_req_addr[LINE_OFFSET_WIDTH + LINE_INDEX_WIDTH +: TAG_WIDTH];
  assign req_hit =
    req_array_valid &&
    (req_array_tag[TAG_WIDTH-1:0] == req_tag[TAG_WIDTH-1:0]);
  assign resp_primary_ready = !resp_valid_q || fetch_resp_ready;
  assign resp_can_update = resp_primary_ready && !miss_resp_buf_valid_q;
  assign req_can_complete = req_hit || imem_req_ready;
  assign fetch_req_ready =
    !invalidate_active_q && !miss_pending_q && resp_can_update &&
    req_can_complete;
  assign req_fire = fetch_req_valid && fetch_req_ready;
  assign miss_req_fire = req_fire && !req_hit;

  assign imem_req_valid = fetch_req_valid && !invalidate_active_q &&
                          !miss_pending_q &&
                          resp_can_update && !req_hit;
  assign imem_req_addr = aligned_req_addr;
  assign imem_resp_ready = miss_pending_q && !miss_resp_buf_valid_q;
  assign miss_resp_fire = imem_resp_valid && imem_resp_ready;
  assign miss_resp_to_primary = miss_resp_fire && resp_primary_ready;
  assign miss_resp_to_buffer = miss_resp_fire && !resp_primary_ready;
  assign miss_buf_promote =
    miss_resp_buf_valid_q && resp_primary_ready && !miss_resp_to_primary;
  assign invalidate_ready =
    !invalidate_active_q && !miss_pending_q && !resp_valid_q;
  assign invalidate_fire = invalidate_valid && invalidate_ready;
  assign invalidate_last = invalidate_index_q == {LINE_INDEX_WIDTH{1'b1}};
  assign tag_clear_valid = invalidate_active_q;

  assign fetch_resp_valid = resp_valid_q;
  assign fetch_resp_bits = resp_bits_q;
  assign debug_icache_bytes = ICACHE_BYTES_U32;
  assign debug_hit = req_fire && req_hit;
  assign debug_miss_pending = miss_pending_q;
  assign debug_invalidate_busy = invalidate_active_q;

  edge_ifu_icache_data_array #(
    .LINE_BITS(128),
    .LINES(LINES)
  ) data_array (
    .clk(forever_cpuclk),
    .write_valid(miss_resp_fire),
    .write_index(miss_index_q),
    .write_data(imem_resp_bits),
    .read_index(req_index),
    .read_data(req_data)
  );

  edge_ifu_icache_tag_array #(
    .TAG_WIDTH(TAG_WIDTH),
    .LINES(LINES)
  ) tag_array (
    .clk(forever_cpuclk),
    .rst_b(cpurst_b),
    .write_valid(miss_resp_fire),
    .write_index(miss_index_q),
    .write_tag(miss_tag_q),
    .write_valid_bit(1'b1),
    .clear_valid(tag_clear_valid),
    .clear_index(invalidate_index_q),
    .read_index(req_index),
    .read_tag(req_array_tag),
    .read_valid_bit(req_array_valid)
  );

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      resp_valid_q <= 1'b0;
      resp_bits_q <= 128'd0;
      miss_resp_buf_valid_q <= 1'b0;
      miss_resp_buf_bits_q <= 128'd0;
      miss_pending_q <= 1'b0;
      miss_index_q <= {LINE_INDEX_WIDTH{1'b0}};
      miss_tag_q <= {TAG_WIDTH{1'b0}};
      invalidate_active_q <= 1'b0;
      invalidate_index_q <= {LINE_INDEX_WIDTH{1'b0}};
    end else begin
      if (invalidate_active_q) begin
        if (invalidate_last) begin
          invalidate_active_q <= 1'b0;
        end
        invalidate_index_q <= invalidate_index_q +
          {{(LINE_INDEX_WIDTH-1){1'b0}}, 1'b1};
      end else if (invalidate_fire) begin
        invalidate_active_q <= 1'b1;
        invalidate_index_q <= {LINE_INDEX_WIDTH{1'b0}};
      end

      if (resp_valid_q && fetch_resp_ready) begin
        resp_valid_q <= 1'b0;
      end

      if (miss_buf_promote) begin
        resp_valid_q <= 1'b1;
        resp_bits_q <= miss_resp_buf_bits_q;
        miss_resp_buf_valid_q <= 1'b0;
      end

      if (req_fire && req_hit) begin
        resp_valid_q <= 1'b1;
        resp_bits_q <= req_data;
      end else if (miss_resp_to_primary) begin
        resp_valid_q <= 1'b1;
        resp_bits_q <= imem_resp_bits;
      end

      if (miss_resp_to_buffer) begin
        miss_resp_buf_valid_q <= 1'b1;
        miss_resp_buf_bits_q <= imem_resp_bits;
      end

      if (miss_req_fire) begin
        miss_pending_q <= 1'b1;
        miss_index_q <= req_index;
        miss_tag_q <= req_tag;
      end else if (miss_resp_fire) begin
        miss_pending_q <= 1'b0;
      end
    end
  end

`ifdef IVERILOG_SIM
  initial begin
    if (LINE_BYTES != 16) begin
      $display("edge_ifu_icache: first slice requires LINE_BYTES=16");
      $finish;
    end
    if (ICACHE_BYTES != 16384 && ICACHE_BYTES != 32768) begin
      $display("edge_ifu_icache: unsupported ICACHE_BYTES=%0d", ICACHE_BYTES);
      $finish;
    end
  end
`endif

endmodule
