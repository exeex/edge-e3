// Edge scalar memory-ordering subsystem placeholder.
module edge_lsu_top #(
  parameter SEQ_ID_WIDTH    = 8,
  parameter EPOCH_WIDTH     = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter VALUE_WIDTH     = 64,
  parameter STB_DEPTH       = 8,
  parameter STB_COUNT_WIDTH = 4,
  parameter LOADQ_DEPTH     = 8,
  parameter LOADQ_COUNT_WIDTH = $clog2(LOADQ_DEPTH + 1),
  parameter ENABLE_COMMITTED_STORE_DRAIN = 0
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,
  input  wire                         edge_dtcm_enable,
  input  wire [VALUE_WIDTH-1:0]       edge_dtcm_base,
  input  wire [VALUE_WIDTH-1:0]       edge_dtcm_mask,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_dtcm_store_query_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_dtcm_store_query_epoch,

  input  wire                         lsu_issue_valid,
  output wire                         lsu_issue_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_issue_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_issue_epoch,
  input  wire                         lsu_issue_is_store,
  input  wire [2:0]                   lsu_issue_funct3,
  input  wire [REG_INDEX_WIDTH-1:0]   lsu_issue_rd,
  input  wire                         lsu_issue_bank,
  input  wire                         lsu_issue_domain,
  input  wire [VALUE_WIDTH-1:0]       lsu_issue_base_value,
  input  wire [VALUE_WIDTH-1:0]       lsu_issue_offset,
  input  wire [VALUE_WIDTH-1:0]       lsu_issue_store_data,
  input  wire                         lsu_issue1_valid,
  output wire                         lsu_issue1_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_issue1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_issue1_epoch,
  input  wire                         lsu_issue1_is_store,
  input  wire [2:0]                   lsu_issue1_funct3,
  input  wire [REG_INDEX_WIDTH-1:0]   lsu_issue1_rd,
  input  wire                         lsu_issue1_bank,
  input  wire                         lsu_issue1_domain,
  input  wire [VALUE_WIDTH-1:0]       lsu_issue1_base_value,
  input  wire [VALUE_WIDTH-1:0]       lsu_issue1_offset,
  input  wire [VALUE_WIDTH-1:0]       lsu_issue1_store_data,

  input  wire                         lsu_store_commit0_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_store_commit0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_store_commit0_epoch,
  input  wire                         lsu_store_commit1_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_store_commit1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_store_commit1_epoch,

  output wire                         lsu_complete_valid,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_complete_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_complete_epoch,
  output wire                         lsu_complete_is_store,
  output wire [1:0]                   lsu_complete_size,
  output wire                         lsu_complete_load_signed,
  output wire [VALUE_WIDTH-1:0]       lsu_complete_addr,
  output wire [VALUE_WIDTH-1:0]       lsu_complete_store_data,
  output wire                         lsu_misaligned_valid,
  output wire                         lsu_misaligned_lane1,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_misaligned_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_misaligned_epoch,
  output wire                         lsu_misaligned_is_store,
  output wire [1:0]                   lsu_misaligned_size,
  output wire [VALUE_WIDTH-1:0]       lsu_misaligned_addr,
  output wire                         lsu_complete1_valid,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_complete1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_complete1_epoch,
  output wire                         lsu_complete1_is_store,
  output wire [1:0]                   lsu_complete1_size,
  output wire                         lsu_complete1_load_signed,
  output wire [VALUE_WIDTH-1:0]       lsu_complete1_addr,
  output wire [VALUE_WIDTH-1:0]       lsu_complete1_store_data,
  output wire                         lsu_load_accept_valid,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_load_accept_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_load_accept_epoch,
  output wire                         lsu_load_accept_domain,
  output wire                         lsu_load_accept1_valid,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_load_accept1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_load_accept1_epoch,
  output wire                         lsu_load_accept1_domain,

  input  wire                         lsu_load_resp_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_load_resp_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_load_resp_epoch,
  input  wire                         lsu_load_resp_error,
  input  wire [VALUE_WIDTH-1:0]       lsu_load_resp_value,
  output wire                         lsu_load_req_valid,
  input  wire                         lsu_load_req_ready,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_load_req_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_load_req_epoch,
  output wire [VALUE_WIDTH-1:0]       lsu_load_req_addr,
  output wire [1:0]                   lsu_load_req_size,
  output wire                         lsu_load_req_signed,
  output wire                         lsu_load_req1_valid,
  input  wire                         lsu_load_req1_ready,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_load_req1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_load_req1_epoch,
  output wire [VALUE_WIDTH-1:0]       lsu_load_req1_addr,
  output wire [1:0]                   lsu_load_req1_size,
  output wire                         lsu_load_req1_signed,
  output wire                         lsu_store_req_valid,
  input  wire                         lsu_store_req_ready,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_store_req_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_store_req_epoch,
  output wire [VALUE_WIDTH-1:0]       lsu_store_req_addr,
  output wire [1:0]                   lsu_store_req_size,
  output wire [VALUE_WIDTH-1:0]       lsu_store_req_data,
  output wire [(VALUE_WIDTH/8)-1:0]   lsu_store_req_wstrb,
  output wire                         lsu_store_req1_valid,
  input  wire                         lsu_store_req1_ready,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_store_req1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_store_req1_epoch,
  output wire [VALUE_WIDTH-1:0]       lsu_store_req1_addr,
  output wire [1:0]                   lsu_store_req1_size,
  output wire [VALUE_WIDTH-1:0]       lsu_store_req1_data,
  output wire [(VALUE_WIDTH/8)-1:0]   lsu_store_req1_wstrb,
  output wire                         lsu_load_complete_valid,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_load_complete_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_load_complete_epoch,
  output wire [REG_INDEX_WIDTH-1:0]   lsu_load_complete_reg,
  output wire                         lsu_load_complete_bank,
  output wire                         lsu_load_complete_domain,
  output wire [1:0]                   lsu_load_complete_size,
  output wire                         lsu_load_complete_error,
  output wire [VALUE_WIDTH-1:0]       lsu_load_complete_value,

  input  wire                         lsu_flush_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_flush_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_flush_epoch,
  output wire [STB_COUNT_WIDTH-1:0]   lsu_debug_stb_count,
  output wire                         lsu_debug_stb_drain_valid,
  output wire [VALUE_WIDTH-1:0]       lsu_debug_stb_drain_data,
  output wire [(VALUE_WIDTH/8)-1:0]   lsu_debug_stb_drain_wstrb,
  output wire                         lsu_debug_stb_dtcm_pending,
  output wire [LOADQ_COUNT_WIDTH-1:0] lsu_debug_loadq_count,
  output wire                         lsu_debug_load_req_valid,
  output wire [VALUE_WIDTH-1:0]       lsu_debug_load_req_addr
);

  function seq_is_younger;
    input [SEQ_ID_WIDTH-1:0] candidate;
    input [SEQ_ID_WIDTH-1:0] boundary;
    reg [SEQ_ID_WIDTH-1:0] distance;
    begin
      distance = candidate - boundary;
      seq_is_younger = (distance != {SEQ_ID_WIDTH{1'b0}}) &&
                       !distance[SEQ_ID_WIDTH-1];
    end
  endfunction

  wire scalar_issue_valid;
  wire scalar_issue_ready;
  wire scalar_issue1_valid;
  wire scalar_issue1_ready;
  wire scalar_complete_valid;
  wire [SEQ_ID_WIDTH-1:0] scalar_complete_seq_id;
  wire [EPOCH_WIDTH-1:0] scalar_complete_epoch;
  wire scalar_complete_is_store;
  wire [1:0] scalar_complete_size;
  wire scalar_complete_load_signed;
  wire scalar_complete_misaligned;
  wire [VALUE_WIDTH-1:0] scalar_complete_addr;
  wire [VALUE_WIDTH-1:0] scalar_complete_store_data;
  wire scalar_complete1_valid;
  wire [SEQ_ID_WIDTH-1:0] scalar_complete1_seq_id;
  wire [EPOCH_WIDTH-1:0] scalar_complete1_epoch;
  wire scalar_complete1_is_store;
  wire [1:0] scalar_complete1_size;
  wire scalar_complete1_load_signed;
  wire scalar_complete1_misaligned;
  wire [VALUE_WIDTH-1:0] scalar_complete1_addr;
  wire [VALUE_WIDTH-1:0] scalar_complete1_store_data;
  wire [VALUE_WIDTH-1:0] formatted_store_data;
  wire [(VALUE_WIDTH/8)-1:0] formatted_store_wstrb;
  wire [VALUE_WIDTH-1:0] formatted_store1_data;
  wire [(VALUE_WIDTH/8)-1:0] formatted_store1_wstrb;
  wire scalar_complete_flushed;
  wire scalar_complete1_flushed;
  wire scalar_complete_misaligned_report;
  wire scalar_complete1_misaligned_report;
  wire stb_enqueue_ready;
  wire stb_enqueue1_ready;
  wire loadq_enqueue_ready;
  wire loadq_enqueue1_ready;
  wire loadq_request_valid;
  wire [SEQ_ID_WIDTH-1:0] loadq_request_seq_id;
  wire [EPOCH_WIDTH-1:0] loadq_request_epoch;
  wire [REG_INDEX_WIDTH-1:0] loadq_request_rd;
  wire loadq_request_bank;
  wire loadq_request_domain;
  wire [VALUE_WIDTH-1:0] loadq_request_addr;
  wire [1:0] loadq_request_size;
  wire loadq_request_signed;
  wire loadq_request1_valid;
  wire [SEQ_ID_WIDTH-1:0] loadq_request1_seq_id;
  wire [EPOCH_WIDTH-1:0] loadq_request1_epoch;
  wire [REG_INDEX_WIDTH-1:0] loadq_request1_rd;
  wire loadq_request1_bank;
  wire loadq_request1_domain;
  wire [VALUE_WIDTH-1:0] loadq_request1_addr;
  wire [1:0] loadq_request1_size;
  wire loadq_request1_signed;
  wire loadq_complete_ready;
  wire loadreq_fifo_in0_ready, loadreq_fifo_in1_ready;
  wire loadreq_front0_ready, loadreq_front1_ready;
  wire loadreq_direct0_fire, loadreq_direct1_fire;
  wire loadreq_fifo_out_valid, loadreq_fifo_out1_valid;
  wire [SEQ_ID_WIDTH-1:0] loadreq_fifo_out_seq_id, loadreq_fifo_out1_seq_id;
  wire [EPOCH_WIDTH-1:0] loadreq_fifo_out_epoch, loadreq_fifo_out1_epoch;
  wire [VALUE_WIDTH-1:0] loadreq_fifo_out_addr, loadreq_fifo_out1_addr;
  wire [1:0] loadreq_fifo_out_size, loadreq_fifo_out1_size;
  wire loadreq_fifo_out_signed, loadreq_fifo_out1_signed;
  wire [1:0] loadreq_fifo_count;
  wire loadreq_fifo_empty;
  wire [REG_INDEX_WIDTH-1:0] loadq_complete_rd;
  wire loadq_complete_bank;
  wire loadq_complete_domain;
  wire [1:0] loadq_complete_size;
  wire stb_drain_valid;
  wire [SEQ_ID_WIDTH-1:0] stb_drain_seq_id;
  wire [EPOCH_WIDTH-1:0] stb_drain_epoch;
  wire [VALUE_WIDTH-1:0] stb_drain_addr;
  wire [1:0] stb_drain_size;
  wire [VALUE_WIDTH-1:0] stb_drain_data;
  wire [(VALUE_WIDTH/8)-1:0] stb_drain_wstrb;
  wire stb_drain1_valid;
  wire [SEQ_ID_WIDTH-1:0] stb_drain1_seq_id;
  wire [EPOCH_WIDTH-1:0] stb_drain1_epoch;
  wire [VALUE_WIDTH-1:0] stb_drain1_addr;
  wire [1:0] stb_drain1_size;
  wire [VALUE_WIDTH-1:0] stb_drain1_data;
  wire [(VALUE_WIDTH/8)-1:0] stb_drain1_wstrb;

  assign lsu_issue_ready = lsu_issue_is_store ?
                           stb_enqueue_ready :
                           (scalar_issue_ready && loadq_enqueue_ready);
  assign lsu_issue1_ready = lsu_issue1_is_store ?
                            stb_enqueue1_ready :
                            (scalar_issue1_ready && loadq_enqueue1_ready);
  assign scalar_issue_valid = lsu_issue_valid && lsu_issue_ready;
  assign scalar_issue1_valid = lsu_issue1_valid && lsu_issue1_ready;
  assign scalar_complete_flushed =
    lsu_flush_valid &&
    ((lsu_flush_seq_id == {SEQ_ID_WIDTH{1'b0}}) ||
     ((scalar_complete_epoch == lsu_flush_epoch) &&
      seq_is_younger(scalar_complete_seq_id, lsu_flush_seq_id)));
  assign scalar_complete1_flushed =
    lsu_flush_valid &&
    ((lsu_flush_seq_id == {SEQ_ID_WIDTH{1'b0}}) ||
     ((scalar_complete1_epoch == lsu_flush_epoch) &&
      seq_is_younger(scalar_complete1_seq_id, lsu_flush_seq_id)));
  assign scalar_complete_misaligned_report =
    scalar_complete_misaligned && !scalar_complete_flushed;
  assign scalar_complete1_misaligned_report =
    scalar_complete1_misaligned && !scalar_complete1_flushed;
  assign lsu_complete_valid = scalar_complete_valid && !scalar_complete_misaligned;
  assign lsu_complete_seq_id = scalar_complete_seq_id;
  assign lsu_complete_epoch = scalar_complete_epoch;
  assign lsu_complete_is_store = scalar_complete_is_store;
  assign lsu_complete_size = scalar_complete_size;
  assign lsu_complete_load_signed = scalar_complete_load_signed;
  assign lsu_complete_addr = scalar_complete_addr;
  assign lsu_complete_store_data = scalar_complete_store_data;
  assign lsu_complete1_valid = scalar_complete1_valid && !scalar_complete1_misaligned;
  assign lsu_complete1_seq_id = scalar_complete1_seq_id;
  assign lsu_complete1_epoch = scalar_complete1_epoch;
  assign lsu_complete1_is_store = scalar_complete1_is_store;
  assign lsu_complete1_size = scalar_complete1_size;
  assign lsu_complete1_load_signed = scalar_complete1_load_signed;
  assign lsu_complete1_addr = scalar_complete1_addr;
  assign lsu_complete1_store_data = scalar_complete1_store_data;
  assign lsu_load_accept_valid = scalar_complete_valid &&
                                 !scalar_complete_is_store &&
                                 !scalar_complete_misaligned &&
                                 loadq_enqueue_ready &&
                                 !scalar_complete_flushed;
  assign lsu_load_accept_seq_id = scalar_complete_seq_id;
  assign lsu_load_accept_epoch = scalar_complete_epoch;
  assign lsu_load_accept_domain = lsu_issue_domain;
  assign lsu_load_accept1_valid = scalar_complete1_valid &&
                                  !scalar_complete1_is_store &&
                                  !scalar_complete1_misaligned &&
                                  loadq_enqueue1_ready &&
                                  !scalar_complete1_flushed;
  assign lsu_load_accept1_seq_id = scalar_complete1_seq_id;
  assign lsu_load_accept1_epoch = scalar_complete1_epoch;
  assign lsu_load_accept1_domain = lsu_issue1_domain;
  assign lsu_store_req_valid = stb_drain_valid;
  assign lsu_store_req_seq_id = stb_drain_seq_id;
  assign lsu_store_req_epoch = stb_drain_epoch;
  assign lsu_store_req_addr = stb_drain_addr;
  assign lsu_store_req_size = stb_drain_size;
  assign lsu_store_req_data = stb_drain_data;
  assign lsu_store_req_wstrb = stb_drain_wstrb;
  assign loadreq_fifo_empty = loadreq_fifo_count == 3'd0;
  assign loadreq_direct0_fire = !lsu_flush_valid && loadreq_fifo_empty &&
                                loadq_request_valid && lsu_load_req_ready;
  assign loadreq_direct1_fire = loadreq_direct0_fire && loadq_request1_valid &&
                                lsu_load_req1_ready;
  assign loadreq_front0_ready = !lsu_flush_valid &&
                                (loadreq_direct0_fire || loadreq_fifo_in0_ready);
  assign loadreq_front1_ready = !lsu_flush_valid &&
                                (loadreq_direct1_fire || loadreq_fifo_in1_ready);
  assign lsu_load_req_valid = !lsu_flush_valid &&
                              (loadreq_fifo_empty ? loadq_request_valid :
                                                    loadreq_fifo_out_valid);
  assign lsu_load_req_seq_id = loadreq_fifo_empty ? loadq_request_seq_id :
                                                    loadreq_fifo_out_seq_id;
  assign lsu_load_req_epoch = loadreq_fifo_empty ? loadq_request_epoch :
                                                   loadreq_fifo_out_epoch;
  assign lsu_load_req_addr = loadreq_fifo_empty ? loadq_request_addr :
                                                  loadreq_fifo_out_addr;
  assign lsu_load_req_size = loadreq_fifo_empty ? loadq_request_size :
                                                  loadreq_fifo_out_size;
  assign lsu_load_req_signed = loadreq_fifo_empty ? loadq_request_signed :
                                                    loadreq_fifo_out_signed;
  assign lsu_load_req1_valid = !lsu_flush_valid &&
                               (loadreq_fifo_empty ? loadq_request1_valid :
                                                     loadreq_fifo_out1_valid);
  assign lsu_load_req1_seq_id = loadreq_fifo_empty ? loadq_request1_seq_id :
                                                     loadreq_fifo_out1_seq_id;
  assign lsu_load_req1_epoch = loadreq_fifo_empty ? loadq_request1_epoch :
                                                    loadreq_fifo_out1_epoch;
  assign lsu_load_req1_addr = loadreq_fifo_empty ? loadq_request1_addr :
                                                   loadreq_fifo_out1_addr;
  assign lsu_load_req1_size = loadreq_fifo_empty ? loadq_request1_size :
                                                   loadreq_fifo_out1_size;
  assign lsu_load_req1_signed = loadreq_fifo_empty ? loadq_request1_signed :
                                                     loadreq_fifo_out1_signed;
  assign lsu_store_req1_valid = stb_drain1_valid;
  assign lsu_store_req1_seq_id = stb_drain1_seq_id;
  assign lsu_store_req1_epoch = stb_drain1_epoch;
  assign lsu_store_req1_addr = stb_drain1_addr;
  assign lsu_store_req1_size = stb_drain1_size;
  assign lsu_store_req1_data = stb_drain1_data;
  assign lsu_store_req1_wstrb = stb_drain1_wstrb;
  assign lsu_debug_stb_drain_valid = lsu_store_req_valid;
  assign lsu_debug_stb_drain_data = lsu_store_req_data;
  assign lsu_debug_stb_drain_wstrb = lsu_store_req_wstrb;
  assign lsu_debug_load_req_valid = lsu_load_req_valid;
  assign lsu_debug_load_req_addr = lsu_load_req_addr;
  assign lsu_load_complete_valid = lsu_load_resp_valid && loadq_complete_ready;
  assign lsu_load_complete_seq_id = lsu_load_resp_seq_id;
  assign lsu_load_complete_epoch = lsu_load_resp_epoch;
  assign lsu_load_complete_reg = loadq_complete_rd;
  assign lsu_load_complete_bank = loadq_complete_bank;
  assign lsu_load_complete_domain = loadq_complete_domain;
  assign lsu_load_complete_size = loadq_complete_size;
  assign lsu_load_complete_error = lsu_load_complete_valid &&
                                   lsu_load_resp_error;
  assign lsu_load_complete_value = lsu_load_resp_value;
  assign lsu_misaligned_valid = (scalar_complete_valid &&
                                 scalar_complete_misaligned_report) ||
                                (scalar_complete1_valid &&
                                 scalar_complete1_misaligned_report);
  assign lsu_misaligned_lane1 = !(scalar_complete_valid &&
                                  scalar_complete_misaligned_report) &&
                                (scalar_complete1_valid &&
                                 scalar_complete1_misaligned_report);
  assign lsu_misaligned_seq_id = lsu_misaligned_lane1 ?
                                 scalar_complete1_seq_id :
                                 scalar_complete_seq_id;
  assign lsu_misaligned_epoch = lsu_misaligned_lane1 ?
                                scalar_complete1_epoch :
                                scalar_complete_epoch;
  assign lsu_misaligned_is_store = lsu_misaligned_lane1 ?
                                   scalar_complete1_is_store :
                                   scalar_complete_is_store;
  assign lsu_misaligned_size = lsu_misaligned_lane1 ?
                               scalar_complete1_size :
                               scalar_complete_size;
  assign lsu_misaligned_addr = lsu_misaligned_lane1 ?
                               scalar_complete1_addr :
                               scalar_complete_addr;

  function [VALUE_WIDTH-1:0] store_data_shifted;
    input [VALUE_WIDTH-1:0] raw_data;
    input [1:0] size;
    input [2:0] byte_offset;
    reg [VALUE_WIDTH-1:0] narrow_data;
    begin
      case (size)
        2'b00: narrow_data = {{(VALUE_WIDTH-8){1'b0}}, raw_data[7:0]};
        2'b01: narrow_data = {{(VALUE_WIDTH-16){1'b0}}, raw_data[15:0]};
        2'b10: narrow_data = {{(VALUE_WIDTH-32){1'b0}}, raw_data[31:0]};
        default: narrow_data = raw_data;
      endcase
      store_data_shifted = narrow_data << {byte_offset, 3'b000};
    end
  endfunction

  function [(VALUE_WIDTH/8)-1:0] store_wstrb;
    input [1:0] size;
    input [2:0] byte_offset;
    reg [(VALUE_WIDTH/8)-1:0] base_mask;
    begin
      case (size)
        2'b00: base_mask = 8'h01;
        2'b01: base_mask = 8'h03;
        2'b10: base_mask = 8'h0f;
        default: base_mask = 8'hff;
      endcase
      store_wstrb = base_mask << byte_offset;
    end
  endfunction

  assign formatted_store_data = store_data_shifted(
    scalar_complete_store_data,
    scalar_complete_size,
    scalar_complete_addr[2:0]
  );
  assign formatted_store_wstrb = store_wstrb(
    scalar_complete_size,
    scalar_complete_addr[2:0]
  );
  assign formatted_store1_data = store_data_shifted(
    scalar_complete1_store_data,
    scalar_complete1_size,
    scalar_complete1_addr[2:0]
  );
  assign formatted_store1_wstrb = store_wstrb(
    scalar_complete1_size,
    scalar_complete1_addr[2:0]
  );

  edge_scalar_lsu #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH)
  ) scalar_addrgen (
    .lsu_issue_valid(scalar_issue_valid),
    .lsu_issue_ready(scalar_issue_ready),
    .lsu_issue_seq_id(lsu_issue_seq_id),
    .lsu_issue_epoch(lsu_issue_epoch),
    .lsu_issue_is_store(lsu_issue_is_store),
    .lsu_issue_funct3(lsu_issue_funct3),
    .lsu_issue_base_value(lsu_issue_base_value),
    .lsu_issue_offset(lsu_issue_offset),
    .lsu_issue_store_data(lsu_issue_store_data),
    .lsu_complete_valid(scalar_complete_valid),
    .lsu_complete_seq_id(scalar_complete_seq_id),
    .lsu_complete_epoch(scalar_complete_epoch),
    .lsu_complete_is_store(scalar_complete_is_store),
    .lsu_complete_size(scalar_complete_size),
    .lsu_complete_load_signed(scalar_complete_load_signed),
    .lsu_complete_misaligned(scalar_complete_misaligned),
    .lsu_complete_addr(scalar_complete_addr),
    .lsu_complete_store_data(scalar_complete_store_data)
  );

  edge_scalar_lsu #(
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH)
  ) scalar_addrgen1 (
    .lsu_issue_valid(scalar_issue1_valid),
    .lsu_issue_ready(scalar_issue1_ready),
    .lsu_issue_seq_id(lsu_issue1_seq_id),
    .lsu_issue_epoch(lsu_issue1_epoch),
    .lsu_issue_is_store(lsu_issue1_is_store),
    .lsu_issue_funct3(lsu_issue1_funct3),
    .lsu_issue_base_value(lsu_issue1_base_value),
    .lsu_issue_offset(lsu_issue1_offset),
    .lsu_issue_store_data(lsu_issue1_store_data),
    .lsu_complete_valid(scalar_complete1_valid),
    .lsu_complete_seq_id(scalar_complete1_seq_id),
    .lsu_complete_epoch(scalar_complete1_epoch),
    .lsu_complete_is_store(scalar_complete1_is_store),
    .lsu_complete_size(scalar_complete1_size),
    .lsu_complete_load_signed(scalar_complete1_load_signed),
    .lsu_complete_misaligned(scalar_complete1_misaligned),
    .lsu_complete_addr(scalar_complete1_addr),
    .lsu_complete_store_data(scalar_complete1_store_data)
  );

  edge_store_buffer #(
    .DEPTH(STB_DEPTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .COUNT_WIDTH(STB_COUNT_WIDTH),
    .ENABLE_COMMITTED_DRAIN(ENABLE_COMMITTED_STORE_DRAIN)
  ) store_buffer (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .edge_dtcm_enable(edge_dtcm_enable),
    .edge_dtcm_base(edge_dtcm_base),
    .edge_dtcm_mask(edge_dtcm_mask),
    .dtcm_pending_query_seq_id(lsu_dtcm_store_query_seq_id),
    .dtcm_pending_query_epoch(lsu_dtcm_store_query_epoch),
    .enqueue_valid(scalar_complete_valid && scalar_complete_is_store &&
                   !scalar_complete_misaligned),
    .enqueue_ready(stb_enqueue_ready),
    .enqueue_seq_id(scalar_complete_seq_id),
    .enqueue_epoch(scalar_complete_epoch),
    .enqueue_addr(scalar_complete_addr),
    .enqueue_size(scalar_complete_size),
    .enqueue_data(formatted_store_data),
    .enqueue_wstrb(formatted_store_wstrb),
    .enqueue1_valid(scalar_complete1_valid && scalar_complete1_is_store &&
                    !scalar_complete1_misaligned),
    .enqueue1_ready(stb_enqueue1_ready),
    .enqueue1_seq_id(scalar_complete1_seq_id),
    .enqueue1_epoch(scalar_complete1_epoch),
    .enqueue1_addr(scalar_complete1_addr),
    .enqueue1_size(scalar_complete1_size),
    .enqueue1_data(formatted_store1_data),
    .enqueue1_wstrb(formatted_store1_wstrb),
    .commit0_valid(lsu_store_commit0_valid),
    .commit0_seq_id(lsu_store_commit0_seq_id),
    .commit0_epoch(lsu_store_commit0_epoch),
    .commit1_valid(lsu_store_commit1_valid),
    .commit1_seq_id(lsu_store_commit1_seq_id),
    .commit1_epoch(lsu_store_commit1_epoch),
    .drain_valid(stb_drain_valid),
    .drain_ready(lsu_store_req_ready),
    .drain_seq_id(stb_drain_seq_id),
    .drain_epoch(stb_drain_epoch),
    .drain_addr(stb_drain_addr),
    .drain_size(stb_drain_size),
    .drain_data(stb_drain_data),
    .drain_wstrb(stb_drain_wstrb),
    .drain1_valid(stb_drain1_valid),
    .drain1_ready(lsu_store_req1_ready),
    .drain1_seq_id(stb_drain1_seq_id),
    .drain1_epoch(stb_drain1_epoch),
    .drain1_addr(stb_drain1_addr),
    .drain1_size(stb_drain1_size),
    .drain1_data(stb_drain1_data),
    .drain1_wstrb(stb_drain1_wstrb),
    .flush_valid(lsu_flush_valid),
    .flush_seq_id(lsu_flush_seq_id),
    .flush_epoch(lsu_flush_epoch),
    .debug_count(lsu_debug_stb_count),
    .debug_committed_count(),
    .debug_dtcm_pending(lsu_debug_stb_dtcm_pending)
  );

  edge_load_queue #(
    .DEPTH(LOADQ_DEPTH),
    .SEQ_ID_WIDTH(SEQ_ID_WIDTH),
    .EPOCH_WIDTH(EPOCH_WIDTH),
    .REG_INDEX_WIDTH(REG_INDEX_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH),
    .COUNT_WIDTH(LOADQ_COUNT_WIDTH)
  ) load_queue (
    .forever_cpuclk(forever_cpuclk),
    .cpurst_b(cpurst_b),
    .enqueue_valid(scalar_complete_valid && !scalar_complete_is_store &&
                   !scalar_complete_misaligned),
    .enqueue_ready(loadq_enqueue_ready),
    .enqueue_seq_id(scalar_complete_seq_id),
    .enqueue_epoch(scalar_complete_epoch),
    .enqueue_rd(lsu_issue_rd),
    .enqueue_bank(lsu_issue_bank),
    .enqueue_domain(lsu_issue_domain),
    .enqueue_addr(scalar_complete_addr),
    .enqueue_size(scalar_complete_size),
    .enqueue_load_signed(scalar_complete_load_signed),
    .enqueue1_valid(scalar_complete1_valid && !scalar_complete1_is_store &&
                    !scalar_complete1_misaligned),
    .enqueue1_ready(loadq_enqueue1_ready),
    .enqueue1_seq_id(scalar_complete1_seq_id),
    .enqueue1_epoch(scalar_complete1_epoch),
    .enqueue1_rd(lsu_issue1_rd),
    .enqueue1_bank(lsu_issue1_bank),
    .enqueue1_domain(lsu_issue1_domain),
    .enqueue1_addr(scalar_complete1_addr),
    .enqueue1_size(scalar_complete1_size),
    .enqueue1_load_signed(scalar_complete1_load_signed),
    .request_valid(loadq_request_valid),
    .request_ready(loadreq_front0_ready),
    .request_seq_id(loadq_request_seq_id),
    .request_epoch(loadq_request_epoch),
    .request_rd(loadq_request_rd),
    .request_bank(loadq_request_bank),
    .request_domain(loadq_request_domain),
    .request_addr(loadq_request_addr),
    .request_size(loadq_request_size),
    .request_load_signed(loadq_request_signed),
    .request1_valid(loadq_request1_valid),
    .request1_ready(loadreq_front1_ready),
    .request1_seq_id(loadq_request1_seq_id),
    .request1_epoch(loadq_request1_epoch),
    .request1_rd(loadq_request1_rd),
    .request1_bank(loadq_request1_bank),
    .request1_domain(loadq_request1_domain),
    .request1_addr(loadq_request1_addr),
    .request1_size(loadq_request1_size),
    .request1_load_signed(loadq_request1_signed),
    .backend_issue0_valid(lsu_load_req_valid && lsu_load_req_ready),
    .backend_issue0_seq_id(lsu_load_req_seq_id),
    .backend_issue0_epoch(lsu_load_req_epoch),
    .backend_issue1_valid(lsu_load_req1_valid && lsu_load_req1_ready),
    .backend_issue1_seq_id(lsu_load_req1_seq_id),
    .backend_issue1_epoch(lsu_load_req1_epoch),
    .complete_valid(lsu_load_resp_valid),
    .complete_ready(loadq_complete_ready),
    .complete_seq_id(lsu_load_resp_seq_id),
    .complete_epoch(lsu_load_resp_epoch),
    .complete_rd(loadq_complete_rd),
    .complete_bank(loadq_complete_bank),
    .complete_domain(loadq_complete_domain),
    .complete_size(loadq_complete_size),
    .flush_valid(lsu_flush_valid),
    .flush_seq_id(lsu_flush_seq_id),
    .flush_epoch(lsu_flush_epoch),
    .debug_count(lsu_debug_loadq_count)
  );

  edge_load_request_fifo #(
    .DEPTH(2), .SEQ_ID_WIDTH(SEQ_ID_WIDTH), .EPOCH_WIDTH(EPOCH_WIDTH),
    .VALUE_WIDTH(VALUE_WIDTH)
  ) load_request_fifo (
    .forever_cpuclk(forever_cpuclk), .cpurst_b(cpurst_b),
    .flush(lsu_flush_valid), .flush_seq_id(lsu_flush_seq_id),
    .flush_epoch(lsu_flush_epoch),
    .in0_valid(loadq_request_valid && !loadreq_direct0_fire),
    .in0_ready(loadreq_fifo_in0_ready), .in0_seq_id(loadq_request_seq_id),
    .in0_epoch(loadq_request_epoch), .in0_addr(loadq_request_addr),
    .in0_size(loadq_request_size), .in0_signed(loadq_request_signed),
    .in1_valid(loadq_request1_valid && !loadreq_direct1_fire),
    .in1_ready(loadreq_fifo_in1_ready),
    .in1_seq_id(loadq_request1_seq_id),
    .in1_epoch(loadq_request1_epoch),
    .in1_addr(loadq_request1_addr),
    .in1_size(loadq_request1_size),
    .in1_signed(loadq_request1_signed),
    .out_valid(loadreq_fifo_out_valid), .out_ready(lsu_load_req_ready),
    .out_seq_id(loadreq_fifo_out_seq_id), .out_epoch(loadreq_fifo_out_epoch),
    .out_addr(loadreq_fifo_out_addr), .out_size(loadreq_fifo_out_size),
    .out_signed(loadreq_fifo_out_signed),
    .out1_valid(loadreq_fifo_out1_valid), .out1_ready(lsu_load_req1_ready),
    .out1_seq_id(loadreq_fifo_out1_seq_id),
    .out1_epoch(loadreq_fifo_out1_epoch),
    .out1_addr(loadreq_fifo_out1_addr), .out1_size(loadreq_fifo_out1_size),
    .out1_signed(loadreq_fifo_out1_signed),
    .debug_count(loadreq_fifo_count)
  );

endmodule
