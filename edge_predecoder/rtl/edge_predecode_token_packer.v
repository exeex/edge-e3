// 64-bit parcel window to split scalar32/accel64 enqueue candidates.
module edge_predecode_token_packer #(
  parameter PC_WIDTH             = 40,
  parameter SEQ_ID_WIDTH         = 8,
  parameter EPOCH_WIDTH          = 4,
  parameter EDGE64_LENGTH_MARKER = 7'b0111111
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,
  input  wire                         flush_valid,

  input  wire                         packet_valid,
  output wire                         packet_ready,
  input  wire [1:0]                   packet_slot_valid,
  input  wire [31:0]                  packet_slot0_inst32,
  input  wire [31:0]                  packet_slot1_inst32,
  input  wire [PC_WIDTH-1:0]          packet_slot0_pc,
  input  wire [PC_WIDTH-1:0]          packet_slot1_pc,
  input  wire [SEQ_ID_WIDTH-1:0]      packet_slot0_seq_id,
  input  wire [SEQ_ID_WIDTH-1:0]      packet_slot1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       packet_epoch,

  input  wire                         scalar_ready,
  input  wire                         accel_ready,

  output wire                         scalar0_valid,
  output wire [31:0]                  scalar0_inst32,
  output wire [PC_WIDTH-1:0]          scalar0_pc,
  output wire [SEQ_ID_WIDTH-1:0]      scalar0_seq_id,
  output wire [EPOCH_WIDTH-1:0]       scalar0_epoch,
  output wire                         scalar1_valid,
  output wire [31:0]                  scalar1_inst32,
  output wire [PC_WIDTH-1:0]          scalar1_pc,
  output wire [SEQ_ID_WIDTH-1:0]      scalar1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       scalar1_epoch,

  output wire                         accel0_valid,
  output wire                         accel0_is_tensor,
  output wire [63:0]                  accel0_inst64,
  output wire [PC_WIDTH-1:0]          accel0_pc,
  output wire [SEQ_ID_WIDTH-1:0]      accel0_seq_id,
  output wire [EPOCH_WIDTH-1:0]       accel0_epoch,

  output wire                         debug_pending64_valid,
  output wire [31:0]                  debug_pending64_low32,
  output wire [PC_WIDTH-1:0]          debug_pending64_pc,
  output wire [SEQ_ID_WIDTH-1:0]      debug_pending64_seq_id,
  output wire [EPOCH_WIDTH-1:0]       debug_pending64_epoch,
  output wire                         debug_pending64_is_tensor
);

  reg pending64_valid_q;
  reg [31:0] pending64_low32_q;
  reg [PC_WIDTH-1:0] pending64_pc_q;
  reg [SEQ_ID_WIDTH-1:0] pending64_seq_id_q;
  reg [EPOCH_WIDTH-1:0] pending64_epoch_q;

  reg [1:0] scalar_valid_c;
  reg [31:0] scalar_inst32_c [0:1];
  reg [PC_WIDTH-1:0] scalar_pc_c [0:1];
  reg [SEQ_ID_WIDTH-1:0] scalar_seq_id_c [0:1];
  reg [EPOCH_WIDTH-1:0] scalar_epoch_c [0:1];
  reg accel_valid_c;
  reg accel_is_tensor_c;
  reg [63:0] accel_inst64_c;
  reg [PC_WIDTH-1:0] accel_pc_c;
  reg [SEQ_ID_WIDTH-1:0] accel_seq_id_c;
  reg [EPOCH_WIDTH-1:0] accel_epoch_c;
  reg pending64_set_c;
  reg [31:0] pending64_low32_c;
  reg [PC_WIDTH-1:0] pending64_pc_c;
  reg [SEQ_ID_WIDTH-1:0] pending64_seq_id_c;
  reg [EPOCH_WIDTH-1:0] pending64_epoch_c;
  reg packet_shape_ready_c;

  wire packet_fire;
  assign packet_ready = !flush_valid && packet_shape_ready_c &&
                        scalar_ready && accel_ready;
  assign packet_fire = packet_valid && packet_ready;

  function slot_is_accel_low;
    input [31:0] inst32;
    begin
      slot_is_accel_low = (inst32[6:0] == EDGE64_LENGTH_MARKER);
    end
  endfunction

  always @* begin
    scalar_valid_c[0] = 1'b0;
    scalar_valid_c[1] = 1'b0;
    scalar_inst32_c[0] = 32'd0;
    scalar_inst32_c[1] = 32'd0;
    scalar_pc_c[0] = {PC_WIDTH{1'b0}};
    scalar_pc_c[1] = {PC_WIDTH{1'b0}};
    scalar_seq_id_c[0] = {SEQ_ID_WIDTH{1'b0}};
    scalar_seq_id_c[1] = {SEQ_ID_WIDTH{1'b0}};
    scalar_epoch_c[0] = {EPOCH_WIDTH{1'b0}};
    scalar_epoch_c[1] = {EPOCH_WIDTH{1'b0}};
    accel_valid_c = 1'b0;
    accel_is_tensor_c = 1'b0;
    accel_inst64_c = 64'd0;
    accel_pc_c = {PC_WIDTH{1'b0}};
    accel_seq_id_c = {SEQ_ID_WIDTH{1'b0}};
    accel_epoch_c = {EPOCH_WIDTH{1'b0}};
    pending64_set_c = 1'b0;
    pending64_low32_c = 32'd0;
    pending64_pc_c = {PC_WIDTH{1'b0}};
    pending64_seq_id_c = {SEQ_ID_WIDTH{1'b0}};
    pending64_epoch_c = {EPOCH_WIDTH{1'b0}};
    packet_shape_ready_c = packet_slot_valid[0];

    if (pending64_valid_q) begin
      // slot0 is the high half of the previous window's low half.
      if (packet_slot_valid[0]) begin
        accel_valid_c = 1'b1;
        accel_is_tensor_c = packet_slot0_inst32[7];
        accel_inst64_c = {packet_slot0_inst32, pending64_low32_q};
        accel_pc_c = pending64_pc_q;
        accel_seq_id_c = pending64_seq_id_q;
        accel_epoch_c = pending64_epoch_q;
        if (packet_slot_valid[1]) begin
          if (slot_is_accel_low(packet_slot1_inst32)) begin
            pending64_set_c = 1'b1;
            pending64_low32_c = packet_slot1_inst32;
            pending64_pc_c = packet_slot1_pc;
            pending64_seq_id_c = packet_slot1_seq_id;
            pending64_epoch_c = packet_epoch;
          end else begin
            scalar_valid_c[0] = 1'b1;
            scalar_inst32_c[0] = packet_slot1_inst32;
            scalar_pc_c[0] = packet_slot1_pc;
            scalar_seq_id_c[0] = packet_slot1_seq_id;
            scalar_epoch_c[0] = packet_epoch;
          end
        end
      end
    end else if (packet_slot_valid[0]) begin
      if (slot_is_accel_low(packet_slot0_inst32)) begin
        if (packet_slot_valid[1]) begin
          accel_valid_c = 1'b1;
          accel_is_tensor_c = packet_slot1_inst32[7];
          accel_inst64_c = {packet_slot1_inst32, packet_slot0_inst32};
          accel_pc_c = packet_slot0_pc;
          accel_seq_id_c = packet_slot0_seq_id;
          accel_epoch_c = packet_epoch;
        end else begin
          pending64_set_c = 1'b1;
          pending64_low32_c = packet_slot0_inst32;
          pending64_pc_c = packet_slot0_pc;
          pending64_seq_id_c = packet_slot0_seq_id;
          pending64_epoch_c = packet_epoch;
        end
      end else begin
        scalar_valid_c[0] = 1'b1;
        scalar_inst32_c[0] = packet_slot0_inst32;
        scalar_pc_c[0] = packet_slot0_pc;
        scalar_seq_id_c[0] = packet_slot0_seq_id;
        scalar_epoch_c[0] = packet_epoch;
        if (packet_slot_valid[1]) begin
          if (slot_is_accel_low(packet_slot1_inst32)) begin
            pending64_set_c = 1'b1;
            pending64_low32_c = packet_slot1_inst32;
            pending64_pc_c = packet_slot1_pc;
            pending64_seq_id_c = packet_slot1_seq_id;
            pending64_epoch_c = packet_epoch;
          end else begin
            scalar_valid_c[1] = 1'b1;
            scalar_inst32_c[1] = packet_slot1_inst32;
            scalar_pc_c[1] = packet_slot1_pc;
            scalar_seq_id_c[1] = packet_slot1_seq_id;
            scalar_epoch_c[1] = packet_epoch;
          end
        end
      end
    end
  end

  assign scalar0_valid = packet_valid && packet_ready && scalar_valid_c[0];
  assign scalar0_inst32 = scalar_inst32_c[0];
  assign scalar0_pc = scalar_pc_c[0];
  assign scalar0_seq_id = scalar_seq_id_c[0];
  assign scalar0_epoch = scalar_epoch_c[0];
  assign scalar1_valid = packet_valid && packet_ready && scalar_valid_c[1];
  assign scalar1_inst32 = scalar_inst32_c[1];
  assign scalar1_pc = scalar_pc_c[1];
  assign scalar1_seq_id = scalar_seq_id_c[1];
  assign scalar1_epoch = scalar_epoch_c[1];
  assign accel0_valid = packet_valid && packet_ready && accel_valid_c;
  assign accel0_is_tensor = accel_is_tensor_c;
  assign accel0_inst64 = accel_inst64_c;
  assign accel0_pc = accel_pc_c;
  assign accel0_seq_id = accel_seq_id_c;
  assign accel0_epoch = accel_epoch_c;

  assign debug_pending64_valid = pending64_valid_q;
  assign debug_pending64_low32 = pending64_low32_q;
  assign debug_pending64_pc = pending64_pc_q;
  assign debug_pending64_seq_id = pending64_seq_id_q;
  assign debug_pending64_epoch = pending64_epoch_q;
  assign debug_pending64_is_tensor = 1'b0;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      pending64_valid_q <= 1'b0;
      pending64_low32_q <= 32'd0;
      pending64_pc_q <= {PC_WIDTH{1'b0}};
      pending64_seq_id_q <= {SEQ_ID_WIDTH{1'b0}};
      pending64_epoch_q <= {EPOCH_WIDTH{1'b0}};
    end else if (flush_valid) begin
      pending64_valid_q <= 1'b0;
    end else if (packet_fire) begin
      pending64_valid_q <= pending64_set_c;
      pending64_low32_q <= pending64_low32_c;
      pending64_pc_q <= pending64_pc_c;
      pending64_seq_id_q <= pending64_seq_id_c;
      pending64_epoch_q <= pending64_epoch_c;
    end
  end
endmodule
