// Single-cycle scalar LSU placeholder execute unit.
module edge_scalar_lsu #(
  parameter SEQ_ID_WIDTH    = 8,
  parameter EPOCH_WIDTH     = 4,
  parameter VALUE_WIDTH     = 64
) (
  input  wire                         lsu_issue_valid,
  output wire                         lsu_issue_ready,
  input  wire [SEQ_ID_WIDTH-1:0]      lsu_issue_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       lsu_issue_epoch,
  input  wire                         lsu_issue_is_store,
  input  wire [2:0]                   lsu_issue_funct3,
  input  wire [VALUE_WIDTH-1:0]       lsu_issue_base_value,
  input  wire [VALUE_WIDTH-1:0]       lsu_issue_offset,
  input  wire [VALUE_WIDTH-1:0]       lsu_issue_store_data,

  output wire                         lsu_complete_valid,
  output wire [SEQ_ID_WIDTH-1:0]      lsu_complete_seq_id,
  output wire [EPOCH_WIDTH-1:0]       lsu_complete_epoch,
  output wire                         lsu_complete_is_store,
  output wire [1:0]                   lsu_complete_size,
  output wire                         lsu_complete_load_signed,
  output wire                         lsu_complete_misaligned,
  output wire [VALUE_WIDTH-1:0]       lsu_complete_addr,
  output wire [VALUE_WIDTH-1:0]       lsu_complete_store_data
);

  wire [VALUE_WIDTH-1:0] effective_addr;
  wire [1:0] access_size;

  assign effective_addr = lsu_issue_base_value + lsu_issue_offset;
  assign access_size = lsu_issue_funct3[1:0];
  assign lsu_issue_ready = 1'b1;
  assign lsu_complete_valid = lsu_issue_valid && lsu_issue_ready;
  assign lsu_complete_seq_id = lsu_issue_seq_id;
  assign lsu_complete_epoch = lsu_issue_epoch;
  assign lsu_complete_is_store = lsu_issue_is_store;
  assign lsu_complete_size = access_size;
  assign lsu_complete_load_signed = !lsu_issue_is_store && !lsu_issue_funct3[2];
  assign lsu_complete_misaligned =
    ((access_size == 2'b01) && effective_addr[0]) ||
    ((access_size == 2'b10) && (effective_addr[1:0] != 2'b00)) ||
    ((access_size == 2'b11) && (effective_addr[2:0] != 3'b000));
  assign lsu_complete_addr = effective_addr;
  assign lsu_complete_store_data = lsu_issue_store_data;

endmodule
