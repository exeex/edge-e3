// Scalar LSU memory backend selector for DTCM-window bypass and D-cache fallback.
module edge_lsu_mem_selector #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH  = 4,
  parameter ADDR_WIDTH   = 40,
  parameter VALUE_WIDTH  = 64
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,
  input  wire                         redirect_kill_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      redirect_kill_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       redirect_kill_epoch,

  input  wire                         edge_dtcm_enable,
  input  wire [ADDR_WIDTH-1:0]        edge_dtcm_base,
  input  wire [ADDR_WIDTH-1:0]        edge_dtcm_mask,

  input  wire                         lsu_load_req_valid,
  output wire                         lsu_load_req_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_load_req_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_load_req_epoch,
  input  wire [VALUE_WIDTH-1:0]       lsu_load_req_addr,
  input  wire [1:0]                   lsu_load_req_size,
  input  wire                         lsu_load_req_signed,
  input  wire                         lsu_load_req1_valid,
  output wire                         lsu_load_req1_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_load_req1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_load_req1_epoch,
  input  wire [VALUE_WIDTH-1:0]       lsu_load_req1_addr,
  input  wire [1:0]                   lsu_load_req1_size,
  input  wire                         lsu_load_req1_signed,

  input  wire                         lsu_store_req_valid,
  output wire                         lsu_store_req_ready,
  input  wire [VALUE_WIDTH-1:0]       lsu_store_req_addr,
  input  wire [VALUE_WIDTH-1:0]       lsu_store_req_data,
  input  wire [(VALUE_WIDTH/8)-1:0]   lsu_store_req_wstrb,
  input  wire                         lsu_store_req1_valid,
  output wire                         lsu_store_req1_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_store_req1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_store_req1_epoch,
  input  wire [VALUE_WIDTH-1:0]       lsu_store_req1_addr,
  input  wire [1:0]                   lsu_store_req1_size,
  input  wire [VALUE_WIDTH-1:0]       lsu_store_req1_data,
  input  wire [(VALUE_WIDTH/8)-1:0]   lsu_store_req1_wstrb,

  output wire                         lsu_load_resp_valid,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_load_resp_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_load_resp_epoch,
  output wire                         lsu_load_resp_error,
  output wire [VALUE_WIDTH-1:0]       lsu_load_resp_value,

  output wire                         dcache_load_req_valid,
  input  wire                         dcache_load_req_ready,
  output wire                         dcache_load_req1_valid,
  input  wire                         dcache_load_req1_ready,
  input  wire                         dcache_load_resp_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      dcache_load_resp_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       dcache_load_resp_epoch,
  input  wire                         dcache_load_resp_error,
  input  wire [VALUE_WIDTH-1:0]       dcache_load_resp_value,
  output wire                         dcache_store_req_valid,
  input  wire                         dcache_store_req_ready,
  output wire                         dcache_store_req1_valid,
  input  wire                         dcache_store_req1_ready,
  input  wire                         dcache_store_predict_phase,
  input  wire                         dcache_store_predict_mem_active,
  input  wire                         dcache_store_predict_backend_blocked,
  input  wire                         dcache_debug_load_pending,

  output wire                         dtcm_scalar_lsu_req,
  output wire                         dtcm_scalar_lsu_we,
  output wire [15:0]                  dtcm_scalar_lsu_addr,
  output wire [63:0]                  dtcm_scalar_lsu_wdata,
  output wire [7:0]                   dtcm_scalar_lsu_wstrb,
  input  wire [63:0]                  dtcm_scalar_lsu_rdata,
  input  wire                         dtcm_scalar_lsu_ready,
  input  wire                         dtcm_scalar_lsu_rvalid,

  output wire                         debug_load_dtcm_hit,
  output wire                         debug_store_dtcm_hit,
  output wire                         debug_dtcm_load_pending
);

  reg                    dtcm_load_pending_q;
  reg [SEQ_ID_WIDTH-1:0] dtcm_load_seq_id_q;
  reg [EPOCH_WIDTH-1:0]  dtcm_load_epoch_q;
  reg [1:0]              dtcm_load_size_q;
  reg                    dtcm_load_signed_q;
  reg                    dtcm_load_stale_q;
  reg [2:0]              dtcm_load_byte_offset_q;

  wire                   lsu_load_dtcm_hit;
  wire                   lsu_load1_dtcm_hit;
  wire                   lsu_store_dtcm_hit;
  wire                   lsu_store1_dtcm_hit;
  wire                   dtcm_load_valid;
  wire                   dtcm_store_valid;
  wire                   dtcm_store_can_issue;
  wire                   dtcm_load_fire;
  wire [ADDR_WIDTH-1:0]  dtcm_load_offset;
  wire [ADDR_WIDTH-1:0]  dtcm_store_offset;
  wire [VALUE_WIDTH-1:0] dtcm_load_resp_value;
  wire                   dcache_store_pair_same_line;
  wire                   dcache_store_pred_ready;
  wire                   dcache_store_pred1_ready;

  assign lsu_load_dtcm_hit =
    edge_dtcm_enable &&
    (((lsu_load_req_addr[ADDR_WIDTH-1:0]) & edge_dtcm_mask[ADDR_WIDTH-1:0]) ==
     edge_dtcm_base[ADDR_WIDTH-1:0]);
  assign lsu_store_dtcm_hit =
    edge_dtcm_enable &&
    (((lsu_store_req_addr[ADDR_WIDTH-1:0]) & edge_dtcm_mask[ADDR_WIDTH-1:0]) ==
     edge_dtcm_base[ADDR_WIDTH-1:0]);
  assign lsu_load1_dtcm_hit =
    edge_dtcm_enable &&
    (((lsu_load_req1_addr[ADDR_WIDTH-1:0]) & edge_dtcm_mask[ADDR_WIDTH-1:0]) ==
     edge_dtcm_base[ADDR_WIDTH-1:0]);
  assign lsu_store1_dtcm_hit =
    edge_dtcm_enable &&
    (((lsu_store_req1_addr[ADDR_WIDTH-1:0]) & edge_dtcm_mask[ADDR_WIDTH-1:0]) ==
     edge_dtcm_base[ADDR_WIDTH-1:0]);

  assign dtcm_load_valid = lsu_load_req_valid && lsu_load_dtcm_hit;
  assign dtcm_store_valid = lsu_store_req_valid && lsu_store_dtcm_hit;
  assign dtcm_load_offset = lsu_load_req_addr[ADDR_WIDTH-1:0] -
                            edge_dtcm_base[ADDR_WIDTH-1:0];
  assign dtcm_store_offset = lsu_store_req_addr[ADDR_WIDTH-1:0] -
                             edge_dtcm_base[ADDR_WIDTH-1:0];
  assign dtcm_store_can_issue =
    dtcm_store_valid && !dtcm_load_pending_q && !dtcm_scalar_lsu_rvalid;
  assign dtcm_load_fire =
    dtcm_load_valid && !dtcm_store_can_issue && !dtcm_load_pending_q &&
    !dcache_debug_load_pending && dtcm_scalar_lsu_ready;
  assign dcache_store_pair_same_line =
    lsu_store_req_addr[VALUE_WIDTH-1:6] ==
    lsu_store_req1_addr[VALUE_WIDTH-1:6];
  assign dtcm_scalar_lsu_req =
    dtcm_store_can_issue ||
    (dtcm_load_valid && !dtcm_store_can_issue && !dtcm_load_pending_q &&
     !dcache_debug_load_pending);
  assign dtcm_scalar_lsu_we = dtcm_store_can_issue;
  assign dtcm_scalar_lsu_addr = dtcm_store_can_issue ?
    dtcm_store_offset[18:3] : dtcm_load_offset[18:3];
  assign dtcm_scalar_lsu_wdata = lsu_store_req_data[63:0];
  assign dtcm_scalar_lsu_wstrb = lsu_store_req_wstrb[7:0];

  assign dcache_load_req_valid =
    lsu_load_req_valid && !lsu_load_dtcm_hit && !dtcm_load_pending_q &&
    !dtcm_scalar_lsu_rvalid;
  assign dcache_load_req1_valid =
    dcache_load_req_valid && lsu_load_req1_valid && !lsu_load1_dtcm_hit;
  assign dcache_store_req_valid =
    lsu_store_req_valid && !lsu_store_dtcm_hit;
  assign dcache_store_req1_valid =
    dcache_store_req_valid && lsu_store_req1_valid && !lsu_store1_dtcm_hit;
  assign lsu_load_req_ready = lsu_load_dtcm_hit ?
    (!dtcm_store_can_issue && !dtcm_load_pending_q &&
     !dcache_debug_load_pending && dtcm_scalar_lsu_ready) :
    (!dtcm_load_pending_q && !dtcm_scalar_lsu_rvalid && dcache_load_req_ready);
  assign lsu_store_req_ready = lsu_store_dtcm_hit ?
    (!dtcm_load_pending_q && !dtcm_scalar_lsu_rvalid &&
     dtcm_scalar_lsu_ready) :
    (dcache_store_pred_ready && dcache_store_req_ready);
  assign lsu_load_req1_ready =
    lsu_load_req_valid && !lsu_load_dtcm_hit && !lsu_load1_dtcm_hit &&
    !dtcm_load_pending_q && !dtcm_scalar_lsu_rvalid &&
    dcache_load_req1_ready;
  assign lsu_store_req1_ready =
    lsu_store_req_valid && !lsu_store_dtcm_hit && !lsu_store1_dtcm_hit &&
    (dcache_store_pred1_ready && dcache_store_req1_ready);

  function seq_is_younger;
    input [SEQ_ID_WIDTH-1:0] seq_value;
    input [SEQ_ID_WIDTH-1:0] boundary;
    reg [SEQ_ID_WIDTH-1:0] distance;
    begin
      distance = seq_value - boundary;
      seq_is_younger = (distance != {SEQ_ID_WIDTH{1'b0}}) &&
                       !distance[SEQ_ID_WIDTH-1];
    end
  endfunction

  wire dtcm_load_killed_now = redirect_kill_valid && dtcm_load_pending_q &&
    dtcm_load_epoch_q == redirect_kill_epoch &&
    seq_is_younger(dtcm_load_seq_id_q, redirect_kill_seq_id);

  assign lsu_load_resp_valid =
    (dtcm_scalar_lsu_rvalid && !dtcm_load_stale_q &&
     !dtcm_load_killed_now) || dcache_load_resp_valid;
  assign lsu_load_resp_seq_id = dtcm_scalar_lsu_rvalid ?
    dtcm_load_seq_id_q : dcache_load_resp_seq_id;
  assign lsu_load_resp_epoch = dtcm_scalar_lsu_rvalid ?
    dtcm_load_epoch_q : dcache_load_resp_epoch;
  assign lsu_load_resp_error = !dtcm_scalar_lsu_rvalid &&
                               dcache_load_resp_valid &&
                               dcache_load_resp_error;
  assign lsu_load_resp_value = dtcm_scalar_lsu_rvalid ?
    dtcm_load_resp_value : dcache_load_resp_value;

  assign dtcm_load_resp_value = format_dtcm_load_value(
    dtcm_scalar_lsu_rdata[63:0],
    dtcm_load_byte_offset_q[2:0],
    dtcm_load_size_q[1:0],
    dtcm_load_signed_q
  );

  assign debug_load_dtcm_hit =
    (lsu_load_req_valid && lsu_load_dtcm_hit) ||
    (lsu_load_req1_valid && lsu_load1_dtcm_hit);
  assign debug_store_dtcm_hit =
    (lsu_store_req_valid && lsu_store_dtcm_hit) ||
    (lsu_store_req1_valid && lsu_store1_dtcm_hit);
  assign debug_dtcm_load_pending = dtcm_load_pending_q;

  edge_dcache_pair_predictor #(
    .VALUE_WIDTH(VALUE_WIDTH)
  ) dcache_store_pair_predictor (
    .phase(dcache_store_predict_phase),
    .mem_active(dcache_store_predict_mem_active),
    .load0_valid(1'b0),
    .load0_addr({VALUE_WIDTH{1'b0}}),
    .load1_valid(1'b0),
    .load1_addr({VALUE_WIDTH{1'b0}}),
    .load_metadata_hit(1'b0),
    .load_dirty_conflict(1'b0),
    .load_backend_blocked(1'b1),
    .load1_same_line(1'b0),
    .load0_ready(),
    .load1_ready(),
    .load1_same_bank_conflict(),
    .store0_valid(dcache_store_req_valid),
    .store0_addr(lsu_store_req_addr),
    .store1_valid(dcache_store_req1_valid),
    .store1_addr(lsu_store_req1_addr),
    .store_backend_blocked(dcache_store_predict_backend_blocked),
    .store1_same_line(dcache_store_pair_same_line),
    .store0_ready(dcache_store_pred_ready),
    .store1_ready(dcache_store_pred1_ready),
    .store1_same_bank_conflict()
  );

  function [VALUE_WIDTH-1:0] format_dtcm_load_value;
    input [63:0] word;
    input [2:0] byte_offset;
    input [1:0] size;
    input load_signed;
    reg [63:0] shifted;
    reg [7:0] byte_value;
    reg [15:0] half_value;
    reg [31:0] word_value;
    begin
      shifted = word >> {byte_offset, 3'b000};
      byte_value = shifted[7:0];
      half_value = shifted[15:0];
      word_value = shifted[31:0];
      case (size)
        2'b00: format_dtcm_load_value = load_signed ?
               {{(VALUE_WIDTH-8){byte_value[7]}}, byte_value} :
               {{(VALUE_WIDTH-8){1'b0}}, byte_value};
        2'b01: format_dtcm_load_value = load_signed ?
               {{(VALUE_WIDTH-16){half_value[15]}}, half_value} :
               {{(VALUE_WIDTH-16){1'b0}}, half_value};
        2'b10: format_dtcm_load_value = load_signed ?
               {{(VALUE_WIDTH-32){word_value[31]}}, word_value} :
               {{(VALUE_WIDTH-32){1'b0}}, word_value};
        default: format_dtcm_load_value = shifted[VALUE_WIDTH-1:0];
      endcase
    end
  endfunction

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      dtcm_load_pending_q <= 1'b0;
      dtcm_load_seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
      dtcm_load_epoch_q <= {EPOCH_WIDTH{1'b0}};
      dtcm_load_size_q <= 2'b00;
      dtcm_load_signed_q <= 1'b0;
      dtcm_load_stale_q <= 1'b0;
      dtcm_load_byte_offset_q <= 3'b000;
    end else begin
      if (dtcm_scalar_lsu_rvalid)
        dtcm_load_pending_q <= 1'b0;
      if (dtcm_scalar_lsu_rvalid)
        dtcm_load_stale_q <= 1'b0;
      else if (dtcm_load_killed_now)
        dtcm_load_stale_q <= 1'b1;

      if (dtcm_load_fire) begin
        dtcm_load_pending_q <= 1'b1;
        dtcm_load_seq_id_q <= lsu_load_req_seq_id;
        dtcm_load_epoch_q <= lsu_load_req_epoch;
        dtcm_load_stale_q <= 1'b0;
        dtcm_load_size_q <= lsu_load_req_size;
        dtcm_load_signed_q <= lsu_load_req_signed;
        dtcm_load_byte_offset_q <= lsu_load_req_addr[2:0];
      end
    end
  end

`ifdef IVERILOG_SIM
  initial begin
    if (VALUE_WIDTH != 64) begin
      $display("EDGE_LSU_MEM_SELECTOR CONFIG FAIL: VALUE_WIDTH must be 64");
      $finish;
    end
    if (ADDR_WIDTH < 19) begin
      $display("EDGE_LSU_MEM_SELECTOR CONFIG FAIL: ADDR_WIDTH must cover DTCM");
      $finish;
    end
  end
`endif

endmodule
