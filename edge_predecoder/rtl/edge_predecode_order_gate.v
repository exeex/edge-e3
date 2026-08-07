// Program-order issue selector for split scalar32/accel64 windows.
module edge_predecode_order_gate #(
  parameter SEQ_ID_WIDTH = 8,
  parameter CLASS_WIDTH  = 3
) (
  input  wire                         scalar0_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      scalar0_seq_id,
  input  wire [CLASS_WIDTH-1:0]       scalar0_class,
  input  wire                         scalar1_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      scalar1_seq_id,
  input  wire [CLASS_WIDTH-1:0]       scalar1_class,
  input  wire                         accel_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      accel_seq_id,
  input  wire                         accel_is_tensor,

  input  wire                         scalar0_ready,
  input  wire                         scalar1_ready,
  input  wire                         vector_ready,
  input  wire                         tensor_ready,

  output wire                         scalar0_issue_valid,
  output wire                         scalar1_issue_valid,
  output wire                         accel_issue_valid,
  output wire                         accel_issue_is_tensor,
  output wire [1:0]                   scalar_pop_count,
  output wire                         accel_pop_valid
);

  localparam [CLASS_WIDTH-1:0] SCALAR_CLASS_LOAD  = 3'd1;
  localparam [CLASS_WIDTH-1:0] SCALAR_CLASS_STORE = 3'd2;
  localparam [CLASS_WIDTH-1:0] SCALAR_CLASS_ALU   = 3'd3;

  wire scalar_is_oldest;
  wire accel_is_oldest;
  wire scalar_pair_class_ok;
  wire scalar1_before_accel;
  wire scalar_pair_ok;
  wire accel_ready;

  assign scalar_is_oldest = scalar0_valid &&
                            (!accel_valid || (scalar0_seq_id < accel_seq_id));
  assign accel_is_oldest = accel_valid &&
                           (!scalar0_valid || (accel_seq_id < scalar0_seq_id));
  assign scalar_pair_class_ok =
    ((scalar0_class == SCALAR_CLASS_LOAD) && (scalar1_class == SCALAR_CLASS_LOAD)) ||
    ((scalar0_class == SCALAR_CLASS_STORE) && (scalar1_class == SCALAR_CLASS_STORE)) ||
    ((scalar0_class == SCALAR_CLASS_ALU) && (scalar1_class == SCALAR_CLASS_ALU));
  assign scalar1_before_accel = !accel_valid || (scalar1_seq_id < accel_seq_id);
  assign scalar_pair_ok = scalar1_valid && scalar_pair_class_ok &&
                          scalar1_before_accel && scalar1_ready;
  assign accel_ready = accel_is_tensor ? tensor_ready : vector_ready;

  assign scalar0_issue_valid = scalar_is_oldest && scalar0_ready;
  assign scalar1_issue_valid = scalar0_issue_valid && scalar_pair_ok;
  assign accel_issue_valid = accel_is_oldest && accel_ready;
  assign accel_issue_is_tensor = accel_is_tensor;
  assign scalar_pop_count = scalar1_issue_valid ? 2'd2 :
                            (scalar0_issue_valid ? 2'd1 : 2'd0);
  assign accel_pop_valid = accel_issue_valid;
endmodule
