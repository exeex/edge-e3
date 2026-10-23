`timescale 1ns/1ps

// Shared accelerator data-movement and Tensor circular-stream control.
// Command production (dual-issue queue or serialized lite owner) stays outside.
module edge_accel_data_ctrl #(
  parameter ADDR_WIDTH = 40,
  parameter VALUE_WIDTH = 64,
  parameter WSLD_SLOT_CONFIG = 0,
  parameter CIRCULAR_FRAGMENT_WORDS = 2
) (
  input  wire                   forever_cpuclk,
  input  wire                   cpurst_b,
  input  wire [ADDR_WIDTH-1:0]  mem_region_base,

  input  wire                   edge_start_req,
  input  wire [ADDR_WIDTH-1:0]  edge_start_src,
  input  wire [ADDR_WIDTH-1:0]  edge_start_dst,
  input  wire [31:0]            edge_start_len,
  input  wire                   scalar_start_valid,
  input  wire [VALUE_WIDTH-1:0] scalar_start_src,
  input  wire [VALUE_WIDTH-1:0] scalar_start_dst,
  input  wire [VALUE_WIDTH-1:0] scalar_start_len,

  input  wire                   tensor_dma_start_req,
  input  wire                   tensor_dma_start_circular_req,
  input  wire [VALUE_WIDTH-1:0] tensor_dma_start_src,
  input  wire [VALUE_WIDTH-1:0] tensor_dma_start_dst,
  input  wire [31:0]            tensor_dma_start_len,
  input  wire [31:0]            tensor_dma_start_entry_bytes,
  input  wire [15:0]            tensor_dma_start_circular_tiles,
  input  wire                   tensor_dma_start_use_xy,
  input  wire                   tensor_dma_start_circular,
  input  wire [63:0]            tensor_dma_start_x,
  input  wire [63:0]            tensor_dma_start_y,

  input  wire                   edge_dma_busy,
  input  wire                   dma_stream_cmd_ready,
  input  wire                   dma_stream_beat_done,
  input  wire                   dma_stream_busy,

  input  wire                   tensor_cmd_wld_req,
  input  wire                   tensor_cmd_wld_circular_req,
  input  wire                   tensor_cmd_wld_trans_req,
  input  wire                   tensor_cmd_wld_reuse,
  input  wire [15:0]            tensor_cmd_wld_ptr,
  input wire [31:0] tensor_cmd_wsld_circular_config,
  input  wire                   tensor_cmd_wsld_circular_req,
  input  wire                   tensor_cmd_wsld_circular_transpose,
  input  wire                   tensor_cmd_sld_req,
  input  wire                   tensor_cmd_sld_circular_req,
  input  wire                   tensor_cmd_sld_reuse,
  input  wire [15:0]            tensor_cmd_sld_ptr,
  input  wire                   tensor_unit_sync_stall,
  input  wire                   tensor_wld_unit_cmd_ready,
  input  wire                   tensor_sld_unit_cmd_ready,
  input  wire                   tensor_wld_fill_done,
  input  wire                   tensor_sld_fill_done,
  input  wire [6:0]             tensor_wld_tile_words,
  input  wire                   tensor_start_retire_valid,

  output wire                   dma_start_ready,
  output wire                   dma_start_circular_ready,
  output wire                   dma_sync_done,
  output wire                   dma_active,
  output wire                   scalar_start_ready,
  output wire                   scalar_sync_ready,
  output wire                   dtcm_dma_start_req,
  output wire [ADDR_WIDTH-1:0]  dtcm_dma_start_src,
  output wire [ADDR_WIDTH-1:0]  dtcm_dma_start_dst,
  output wire [31:0]            dtcm_dma_start_len,
  output wire                   dma_stream_cmd_valid,
  output wire [ADDR_WIDTH-1:0]  dma_stream_cmd_axi_addr,
  output wire [15:0]            dma_stream_cmd_dtcm_addr,

  output wire  tensor_wsld_slot_active,
  output wire  tensor_wsld_slot_start,
  output wire [15:0] tensor_wsld_slot_addr,
  output wire [31:0] tensor_wsld_slot_config,
  output wire                   tensor_wld_cmd_ready,
  output wire                   tensor_sld_cmd_ready,
  output wire                   tensor_wld_circular_ready,
  output wire                   tensor_wsld_circular_ready,
  output wire                   tensor_sld_circular_ready,
  output wire                   tensor_sync_stall,
  output wire [15:0]            tensor_unit_cmd_wld_ptr,
  output wire                   tensor_unit_cmd_wld_req,
  output wire                   tensor_unit_cmd_wld_trans_req,
  output wire                   tensor_unit_cmd_wld_reuse,
  output wire [15:0]            tensor_unit_cmd_sld_ptr,
  output wire                   tensor_unit_cmd_sld_req,
  output wire                   tensor_unit_cmd_sld_reuse,
  output wire                   tensor_unit_cmd_sld_stream
);
  reg edge_dma_active_q;
  reg circular_dma_active_q, circular_dma_inflight_q;
  reg [VALUE_WIDTH-1:0] circular_dma_src_addr_q, circular_dma_group_base_q;
  reg [15:0] circular_base_q, circular_ring_capacity_entries_q;
  reg [31:0] circular_dma_total_fragments_q;
  reg [15:0] circular_dma_inner_q, circular_dma_x_max_q;
  reg [15:0] circular_dma_source_offset_words_q, circular_dma_fragment_words_q;
  reg circular_dma_use_xy_q;
  reg [31:0] circular_dma_len_q, circular_dma_stride_q, circular_dma_y_stride_q;
  reg [31:0] circular_dma_issued_fragments_q;
  reg [15:0] circular_produced_entries_q, circular_consumed_entries_q;
  reg [15:0] circular_producer_entry_q, circular_consumer_entry_q;
  reg [15:0] circular_producer_addr_q, circular_consumer_addr_q;
  reg [15:0] circular_entry_words_q;
  reg [15:0] circular_producer_entry_offset_words_q;
  reg [15:0] circular_complete_entry_offset_words_q;
  reg [15:0] circular_reserved_entries_q;
  reg circular_wld_active_q, wsld_active_q, sld_circular_active_q;
  reg sld_circular_inflight_q, wsld_group_active_q, wsld_transpose_q;
  reg [8:0] wsld_sld_issued_q, wsld_wld_issued_q;
  reg wsld_sld_done_q;
  reg [8:0] wsld_wld_done_q, wsld_start_done_q;
  reg [15:0] wsld_group_addr_q;
  reg [31:0] wsld_config_q;
  wire [15:0] wsld_tile_offset = wsld_config_q[19:16] == 1 ?
      {wsld_wld_issued_q,7'b0} : wsld_config_q[19:16] == 4 ?
      {2'b0,wsld_wld_issued_q,5'b0} : {1'b0,wsld_wld_issued_q,6'b0};
  wire [15:0] wsld_weight_byte_offset = {11'd0,wsld_config_q[11:8],1'b0} +
      wsld_tile_offset;
  // Pointer is informational in slot mode: the reader owns the byte cursor.
  wire [7:0] wsld_tiles = wsld_config_q[7:0];
  wire [31:0] wsld_config_in = (!WSLD_SLOT_CONFIG || tensor_cmd_wsld_circular_config == 0)
      ? 32'h00020804 : tensor_cmd_wsld_circular_config;
  wire [15:0] wsld_weight_bytes_in = wsld_config_in[19:16] == 1 ?
      {1'b0,wsld_config_in[7:0],7'b0} : wsld_config_in[19:16] == 4 ?
      {3'b0,wsld_config_in[7:0],5'b0} : {2'b0,wsld_config_in[7:0],6'b0};
  wire [15:0] wsld_payload_bytes_in = wsld_weight_bytes_in +
      {11'd0,wsld_config_in[11:8],1'b0};
  wire [15:0] wsld_slot_words_in = ((wsld_payload_bytes_in + 16'd15) >> 4) << 1;
  wire wsld_config_valid = wsld_config_in[7:0] != 0 &&
      (wsld_config_in[11:8] == 1 || wsld_config_in[11:8] == 8) &&
      wsld_config_in[15:12] == 0 && wsld_config_in[31:20] == 0 &&
      wsld_config_in[19:16] >= 1 && wsld_config_in[19:16] <= 5;
  assign tensor_wsld_slot_active = wsld_group_active_q;
  assign tensor_wsld_slot_start = wsld_group_claim;
  assign tensor_wsld_slot_addr = circular_consumer_addr_q;
  assign tensor_wsld_slot_config = wsld_config_q;


  wire [63:0] dma_xy_total = tensor_dma_start_x[63:32] *
                             tensor_dma_start_y[63:32];
  wire [31:0] circular_xy_fragments_per_item =
    {16'b0, tensor_dma_start_len[18:3]} / CIRCULAR_FRAGMENT_WORDS;
  wire [31:0] circular_tile_fragments =
    {25'b0, tensor_wld_tile_words} / CIRCULAR_FRAGMENT_WORDS;
  wire circular_config_valid = (circular_ring_capacity_entries_q != 16'd0) &&
                               (circular_entry_words_q != 16'd0);
  wire circular_ring_empty = circular_produced_entries_q ==
                             circular_consumed_entries_q;
  wire circular_ring_full = circular_config_valid &&
    ((circular_reserved_entries_q - circular_consumed_entries_q) >=
     circular_ring_capacity_entries_q);
  wire tensor_dma_direct_start_req = tensor_dma_start_req &&
                                     !tensor_dma_start_use_xy &&
                                     !tensor_dma_start_circular;
  wire tensor_dma_strided_start_req = tensor_dma_start_req &&
                                      tensor_dma_start_use_xy &&
                                      !tensor_dma_start_circular;
  wire strided_launch, strided_busy;
  wire [ADDR_WIDTH-1:0] strided_src, strided_dst;
  wire [31:0] strided_len;
  wire circular_dma_launch;
  wire circular_dma_cmd_valid = circular_dma_active_q &&
    circular_config_valid &&
    (!circular_ring_full || (circular_producer_entry_offset_words_q != 16'd0)) &&
    (circular_dma_issued_fragments_q < circular_dma_total_fragments_q) &&
    !edge_start_req && !tensor_dma_start_req;
  wire [ADDR_WIDTH-1:0] circular_start_offset =
    tensor_dma_start_dst[ADDR_WIDTH-1:0] - mem_region_base;
  wire [15:0] circular_start_base = circular_start_offset[18:3];
  wire [ADDR_WIDTH-1:0] circular_src_addr = circular_dma_src_addr_q +
    {{(ADDR_WIDTH-19){1'b0}}, circular_dma_source_offset_words_q, 3'b000};
  wire [ADDR_WIDTH-1:0] circular_dst_addr = mem_region_base +
    {{(ADDR_WIDTH-19){1'b0}},
      (circular_producer_addr_q + circular_producer_entry_offset_words_q), 3'b000};
  wire circular_entry_complete =
    (circular_producer_entry_offset_words_q + circular_dma_fragment_words_q) ==
    circular_entry_words_q;
  wire circular_source_item_complete =
    (circular_dma_source_offset_words_q + circular_dma_fragment_words_q) ==
    circular_dma_len_q[18:3];
  wire circular_stream_drained = !circular_dma_active_q && !dma_stream_busy &&
    ((circular_consumed_entries_q + 16'd1) >= circular_produced_entries_q);
  wire circular_busy = circular_dma_active_q || dma_stream_busy ||
                       (circular_produced_entries_q != circular_consumed_entries_q);
  wire circular_wld_launch, wsld_group_claim, wsld_sld_launch;
  wire wsld_wld_launch, wsld_group_release, sld_circular_launch;

  assign circular_dma_launch = circular_dma_cmd_valid && dma_stream_cmd_ready;
  assign dma_stream_cmd_valid = circular_dma_cmd_valid;
  assign dma_stream_cmd_axi_addr = circular_src_addr;
  assign dma_stream_cmd_dtcm_addr = circular_dst_addr[18:3];

  edge_core_strided_dma_ctrl #(
    .ADDR_WIDTH(ADDR_WIDTH), .VALUE_WIDTH(VALUE_WIDTH)
  ) strided_dma_ctrl (
    .forever_cpuclk(forever_cpuclk), .cpurst_b(cpurst_b),
    .start_req(tensor_dma_strided_start_req),
    .start_src(tensor_dma_start_src), .start_dst(tensor_dma_start_dst),
    .start_len(tensor_dma_start_len),
    .start_x_stride(tensor_dma_start_x[31:0]),
    .start_y_stride(tensor_dma_start_y[31:0]),
    .start_x_count(tensor_dma_start_x[63:32]),
    .start_y_count(tensor_dma_start_y[63:32]),
    .start_total(dma_xy_total[31:0]), .dma_busy(edge_dma_busy),
    .edge_start_pending(edge_start_req),
    .tensor_start_pending(tensor_dma_start_req),
    .circular_launch(circular_dma_launch), .launch(strided_launch),
    .launch_src(strided_src), .launch_dst(strided_dst),
    .launch_len(strided_len), .busy(strided_busy)
  );

  assign dma_start_ready = !edge_dma_busy && !edge_start_req &&
                           !circular_dma_inflight_q && !strided_busy &&
                           !circular_dma_launch && !strided_launch;
  assign dma_start_circular_ready = !edge_dma_busy && !edge_start_req &&
                                    !circular_dma_active_q &&
                                    !circular_dma_inflight_q && !strided_busy;
  assign dma_sync_done = !edge_dma_busy && !edge_start_req &&
                         !edge_dma_active_q && !circular_dma_inflight_q &&
                         !circular_dma_launch && !strided_busy;
  assign dma_active = edge_dma_active_q;
  assign scalar_start_ready = !edge_dma_busy && !edge_start_req &&
                              !tensor_dma_start_req && !circular_dma_launch &&
                              !strided_launch;
  assign scalar_sync_ready = !edge_dma_busy && !edge_start_req &&
                             !edge_dma_active_q && !tensor_dma_start_req &&
                             !circular_busy && !strided_busy;
  assign dtcm_dma_start_req = edge_start_req || tensor_dma_direct_start_req ||
                              strided_launch || scalar_start_valid;
  assign dtcm_dma_start_src = edge_start_req ? edge_start_src :
    (tensor_dma_direct_start_req ? tensor_dma_start_src[ADDR_WIDTH-1:0] :
      (strided_launch ? strided_src : scalar_start_src[ADDR_WIDTH-1:0]));
  assign dtcm_dma_start_dst = edge_start_req ? edge_start_dst :
    (tensor_dma_direct_start_req ? tensor_dma_start_dst[ADDR_WIDTH-1:0] :
      (strided_launch ? strided_dst : scalar_start_dst[ADDR_WIDTH-1:0]));
  assign dtcm_dma_start_len = edge_start_req ? edge_start_len :
    (tensor_dma_direct_start_req ? tensor_dma_start_len :
      (strided_launch ? strided_len : scalar_start_len[31:0]));

  assign tensor_wld_cmd_ready = tensor_wld_unit_cmd_ready &&
                                !wsld_active_q && !sld_circular_active_q;
  assign tensor_sld_cmd_ready = tensor_sld_unit_cmd_ready &&
                                !wsld_active_q && !sld_circular_active_q;
  assign tensor_wld_circular_ready = tensor_wld_cmd_ready &&
    circular_config_valid && !circular_ring_empty &&
    (circular_entry_words_q == {9'b0, tensor_wld_tile_words});
  assign tensor_wsld_circular_ready = circular_config_valid &&
    !wsld_active_q && !sld_circular_active_q && !circular_wld_active_q && !tensor_unit_sync_stall &&
    tensor_wld_unit_cmd_ready && tensor_sld_unit_cmd_ready &&
    wsld_config_valid && (circular_entry_words_q == wsld_slot_words_in) && !circular_base_q[0];
  assign tensor_sld_circular_ready = circular_config_valid &&
    !sld_circular_active_q && !wsld_active_q && !circular_wld_active_q &&
    (circular_entry_words_q == 16'd2);
  assign tensor_sync_stall = tensor_unit_sync_stall || wsld_active_q ||
                             sld_circular_active_q;
  assign sld_circular_launch = sld_circular_active_q &&
    !sld_circular_inflight_q && !circular_ring_empty && tensor_sld_unit_cmd_ready;
  assign circular_wld_launch = tensor_cmd_wld_circular_req &&
                               tensor_wld_circular_ready;
  assign wsld_group_claim = wsld_active_q && !wsld_group_active_q &&
                            !circular_ring_empty;
  assign wsld_sld_launch = wsld_group_active_q && (wsld_sld_issued_q < {1'b0,wsld_tiles}) &&
                           (wsld_sld_issued_q <= wsld_start_done_q) &&
                           tensor_sld_unit_cmd_ready;
  assign wsld_wld_launch = wsld_group_active_q && wsld_sld_done_q &&
                           (wsld_wld_issued_q < {1'b0,wsld_tiles}) &&
                           (wsld_wld_issued_q < wsld_sld_issued_q) &&
                           (wsld_wld_issued_q <= wsld_start_done_q) &&
                           tensor_wld_unit_cmd_ready;
  assign wsld_group_release = wsld_group_active_q &&
                              (wsld_wld_done_q == {1'b0,wsld_tiles}) &&
                              (wsld_start_done_q == {1'b0,wsld_tiles});
  assign tensor_unit_cmd_wld_ptr = wsld_wld_launch ?
    (wsld_group_addr_q + (wsld_weight_byte_offset >> 3)) :
    (circular_wld_launch ? circular_consumer_addr_q : tensor_cmd_wld_ptr);
  assign tensor_unit_cmd_wld_req =
    (tensor_cmd_wld_req && !wsld_active_q) ||
    (wsld_wld_launch && !wsld_transpose_q) ||
    (circular_wld_launch && !tensor_cmd_wld_trans_req);
  assign tensor_unit_cmd_wld_trans_req =
    (tensor_cmd_wld_trans_req && !wsld_active_q) ||
    (wsld_wld_launch && wsld_transpose_q);
  assign tensor_unit_cmd_wld_reuse = tensor_cmd_wld_reuse && !wsld_active_q;
  assign tensor_unit_cmd_sld_ptr = sld_circular_launch ?
    circular_consumer_addr_q :
    (wsld_sld_launch ? wsld_group_addr_q : tensor_cmd_sld_ptr);
  assign tensor_unit_cmd_sld_req = sld_circular_launch || wsld_sld_launch ||
    (tensor_cmd_sld_req && !wsld_active_q && !sld_circular_active_q);
  assign tensor_unit_cmd_sld_reuse = wsld_active_q ?
    (wsld_sld_issued_q != 9'd0) : tensor_cmd_sld_reuse;
  assign tensor_unit_cmd_sld_stream = sld_circular_launch;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b)
      edge_dma_active_q <= 1'b0;
    else if (dtcm_dma_start_req)
      edge_dma_active_q <= 1'b1;
    else if (edge_dma_active_q && !edge_dma_busy)
      edge_dma_active_q <= 1'b0;
  end

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      circular_dma_active_q <= 1'b0;
      circular_dma_inflight_q <= 1'b0;
      circular_dma_src_addr_q <= {VALUE_WIDTH{1'b0}};
      circular_dma_group_base_q <= {VALUE_WIDTH{1'b0}};
      circular_base_q <= 16'd0;
      circular_ring_capacity_entries_q <= 16'd0;
      circular_dma_total_fragments_q <= 32'd0;
      circular_dma_inner_q <= 16'd0;
      circular_dma_x_max_q <= 16'd0;
      circular_dma_source_offset_words_q <= 16'd0;
      circular_dma_fragment_words_q <= CIRCULAR_FRAGMENT_WORDS;
      circular_dma_use_xy_q <= 1'b0;
      circular_dma_len_q <= 32'd64;
      circular_dma_stride_q <= 32'd64;
      circular_dma_y_stride_q <= 32'd0;
      circular_dma_issued_fragments_q <= 32'd0;
      circular_produced_entries_q <= 16'd0;
      circular_consumed_entries_q <= 16'd0;
      circular_producer_entry_q <= 16'd0;
      circular_consumer_entry_q <= 16'd0;
      circular_producer_addr_q <= 16'd0;
      circular_consumer_addr_q <= 16'd0;
      circular_entry_words_q <= 16'd8;
      circular_producer_entry_offset_words_q <= 16'd0;
      circular_complete_entry_offset_words_q <= 16'd0;
      circular_reserved_entries_q <= 16'd0;
      circular_wld_active_q <= 1'b0;
      wsld_active_q <= 1'b0;
      sld_circular_active_q <= 1'b0;
      sld_circular_inflight_q <= 1'b0;
      wsld_group_active_q <= 1'b0;
      wsld_transpose_q <= 1'b0;
      wsld_config_q <= 32'h00020804;
      wsld_sld_issued_q <= 9'd0;
      wsld_sld_done_q <= 1'b0;
      wsld_wld_issued_q <= 9'd0;
      wsld_wld_done_q <= 9'd0;
      wsld_start_done_q <= 9'd0;
      wsld_group_addr_q <= 16'd0;
    end else begin
      if (tensor_dma_start_circular_req) begin
        circular_dma_active_q <= (tensor_dma_start_circular_tiles != 16'b0) &&
          (!tensor_dma_start_use_xy ||
           ((tensor_dma_start_len != 32'b0) &&
            (tensor_dma_start_entry_bytes != 32'b0) &&
            (tensor_dma_start_len[2:0] == 3'b0) &&
            (tensor_dma_start_entry_bytes[2:0] == 3'b0) &&
            (tensor_dma_start_len <= tensor_dma_start_entry_bytes) &&
            (tensor_dma_start_x[63:32] != 32'b0) &&
            (tensor_dma_start_y[63:32] != 32'b0)));
        circular_dma_src_addr_q <= tensor_dma_start_src;
        circular_dma_group_base_q <= tensor_dma_start_src;
        circular_base_q <= circular_start_base;
        circular_ring_capacity_entries_q <= tensor_dma_start_circular_tiles;
        circular_dma_total_fragments_q <=
          (tensor_dma_start_use_xy ? {16'b0, dma_xy_total[15:0]} :
                                     {16'b0, tensor_dma_start_circular_tiles}) *
          (tensor_dma_start_use_xy ? circular_xy_fragments_per_item :
                                     circular_tile_fragments);
        circular_dma_inner_q <= 16'd0;
        circular_dma_x_max_q <= tensor_dma_start_use_xy ?
          tensor_dma_start_x[47:32] : tensor_dma_start_circular_tiles;
        circular_dma_use_xy_q <= tensor_dma_start_use_xy;
        circular_dma_source_offset_words_q <= 16'd0;
        circular_dma_fragment_words_q <= CIRCULAR_FRAGMENT_WORDS;
        circular_dma_len_q <= tensor_dma_start_use_xy ? tensor_dma_start_len :
          {22'b0, tensor_wld_tile_words, 3'b000};
        circular_dma_stride_q <= tensor_dma_start_use_xy ?
          tensor_dma_start_x[31:0] : {22'b0, tensor_wld_tile_words, 3'b000};
        circular_dma_y_stride_q <= tensor_dma_start_use_xy ?
          tensor_dma_start_y[31:0] : 32'd0;
        circular_dma_issued_fragments_q <= 32'd0;
        circular_produced_entries_q <= 16'd0;
        circular_consumed_entries_q <= 16'd0;
        circular_producer_entry_q <= 16'd0;
        circular_consumer_entry_q <= 16'd0;
        circular_producer_addr_q <= circular_start_base;
        circular_consumer_addr_q <= circular_start_base;
        circular_entry_words_q <= tensor_dma_start_use_xy ?
          tensor_dma_start_entry_bytes[18:3] : {9'b0, tensor_wld_tile_words};
        circular_producer_entry_offset_words_q <= 16'd0;
        circular_complete_entry_offset_words_q <= 16'd0;
        circular_reserved_entries_q <= 16'd0;
        circular_wld_active_q <= 1'b0;
        wsld_active_q <= 1'b0;
        sld_circular_active_q <= 1'b0;
        sld_circular_inflight_q <= 1'b0;
        wsld_group_active_q <= 1'b0;
      end

      if (circular_dma_launch) begin
        circular_dma_issued_fragments_q <= circular_dma_issued_fragments_q + 32'd1;
        if (circular_producer_entry_offset_words_q == 16'd0)
          circular_reserved_entries_q <= circular_reserved_entries_q + 16'd1;
        if (circular_entry_complete) begin
          circular_producer_entry_offset_words_q <= 16'd0;
          if (circular_producer_entry_q == circular_ring_capacity_entries_q - 16'd1) begin
            circular_producer_entry_q <= 16'd0;
            circular_producer_addr_q <= circular_base_q;
          end else begin
            circular_producer_entry_q <= circular_producer_entry_q + 16'd1;
            circular_producer_addr_q <= circular_producer_addr_q + circular_entry_words_q;
          end
        end else begin
          circular_producer_entry_offset_words_q <=
            circular_producer_entry_offset_words_q + circular_dma_fragment_words_q;
        end
        if (circular_dma_issued_fragments_q + 32'd1 >= circular_dma_total_fragments_q)
          circular_dma_active_q <= 1'b0;
        if (circular_source_item_complete) begin
          circular_dma_source_offset_words_q <= 16'd0;
          if (circular_dma_use_xy_q) begin
            if (circular_dma_inner_q == circular_dma_x_max_q - 16'd1) begin
              circular_dma_inner_q <= 16'd0;
              circular_dma_group_base_q <= circular_dma_group_base_q +
                {{(VALUE_WIDTH-32){1'b0}}, circular_dma_y_stride_q};
              circular_dma_src_addr_q <= circular_dma_group_base_q +
                {{(VALUE_WIDTH-32){1'b0}}, circular_dma_y_stride_q};
            end else begin
              circular_dma_inner_q <= circular_dma_inner_q + 16'd1;
              circular_dma_src_addr_q <= circular_dma_src_addr_q +
                {{(VALUE_WIDTH-32){1'b0}}, circular_dma_stride_q};
            end
          end else begin
            circular_dma_src_addr_q <= circular_dma_src_addr_q +
              {{(VALUE_WIDTH-32){1'b0}}, circular_dma_stride_q};
          end
        end else begin
          circular_dma_source_offset_words_q <=
            circular_dma_source_offset_words_q + circular_dma_fragment_words_q;
        end
      end

      if (dma_stream_beat_done) begin
        if (circular_complete_entry_offset_words_q +
            circular_dma_fragment_words_q == circular_entry_words_q) begin
          circular_produced_entries_q <= circular_produced_entries_q + 16'd1;
          circular_complete_entry_offset_words_q <= 16'd0;
        end else begin
          circular_complete_entry_offset_words_q <=
            circular_complete_entry_offset_words_q + circular_dma_fragment_words_q;
        end
      end
      circular_dma_inflight_q <= dma_stream_busy;

      if (tensor_wld_fill_done && circular_wld_active_q)
        circular_wld_active_q <= 1'b0;
      if (circular_wld_launch) begin
        circular_wld_active_q <= 1'b1;
        if (circular_consumer_entry_q == circular_ring_capacity_entries_q - 16'd1) begin
          circular_consumer_entry_q <= 16'd0;
          circular_consumer_addr_q <= circular_base_q;
        end else begin
          circular_consumer_entry_q <= circular_consumer_entry_q + 16'd1;
          circular_consumer_addr_q <= circular_consumer_addr_q + circular_entry_words_q;
        end
      end
      if (tensor_cmd_wsld_circular_req && tensor_wsld_circular_ready) begin
        wsld_active_q <= 1'b1;
        wsld_transpose_q <= tensor_cmd_wsld_circular_transpose;
        wsld_config_q <= wsld_config_in;
      end
      if (tensor_cmd_sld_circular_req && tensor_sld_circular_ready)
        sld_circular_active_q <= 1'b1;
      if (sld_circular_launch) begin
        sld_circular_inflight_q <= 1'b1;
        if (circular_consumer_entry_q == circular_ring_capacity_entries_q - 16'd1) begin
          circular_consumer_entry_q <= 16'd0;
          circular_consumer_addr_q <= circular_base_q;
        end else begin
          circular_consumer_entry_q <= circular_consumer_entry_q + 16'd1;
          circular_consumer_addr_q <= circular_consumer_addr_q + circular_entry_words_q;
        end
      end
      if (sld_circular_active_q && sld_circular_inflight_q && tensor_sld_fill_done) begin
        sld_circular_inflight_q <= 1'b0;
        circular_consumed_entries_q <= circular_consumed_entries_q + 16'd1;
        if (circular_stream_drained)
          sld_circular_active_q <= 1'b0;
      end
      if (wsld_group_claim) begin
        wsld_group_active_q <= 1'b1;
        wsld_group_addr_q <= circular_consumer_addr_q;
        wsld_sld_issued_q <= 9'd0;
        wsld_sld_done_q <= 1'b0;
        wsld_wld_issued_q <= 9'd0;
        wsld_wld_done_q <= 9'd0;
        wsld_start_done_q <= 9'd0;
        if (circular_consumer_entry_q == circular_ring_capacity_entries_q - 16'd1) begin
          circular_consumer_entry_q <= 16'd0;
          circular_consumer_addr_q <= circular_base_q;
        end else begin
          circular_consumer_entry_q <= circular_consumer_entry_q + 16'd1;
          circular_consumer_addr_q <= circular_consumer_addr_q + circular_entry_words_q;
        end
      end
      if (wsld_sld_launch)
        wsld_sld_issued_q <= wsld_sld_issued_q + 9'd1;
      if (wsld_active_q && tensor_sld_fill_done)
        wsld_sld_done_q <= 1'b1;
      if (wsld_wld_launch)
        wsld_wld_issued_q <= wsld_wld_issued_q + 9'd1;
      if (wsld_group_active_q && tensor_wld_fill_done && wsld_wld_done_q < {1'b0,wsld_tiles})
        wsld_wld_done_q <= wsld_wld_done_q + 9'd1;
      if (wsld_group_active_q && tensor_start_retire_valid && wsld_start_done_q < {1'b0,wsld_tiles})
        wsld_start_done_q <= wsld_start_done_q + 9'd1;
      if (wsld_group_release) begin
        wsld_group_active_q <= 1'b0;
        circular_consumed_entries_q <= circular_consumed_entries_q + 16'd1;
        if (circular_stream_drained)
          wsld_active_q <= 1'b0;
      end
      if (!wsld_active_q && circular_wld_active_q && tensor_wld_fill_done &&
          circular_produced_entries_q != circular_consumed_entries_q)
        circular_consumed_entries_q <= circular_consumed_entries_q + 16'd1;
      if (circular_config_valid &&
          ((circular_consumed_entries_q +
            ((!wsld_active_q && circular_wld_active_q && tensor_wld_fill_done &&
              circular_produced_entries_q != circular_consumed_entries_q) ?
             16'd1 : 16'd0)) >= circular_produced_entries_q) &&
          !circular_dma_active_q && !circular_dma_inflight_q)
        circular_wld_active_q <= 1'b0;
    end
  end
endmodule
