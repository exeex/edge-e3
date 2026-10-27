// In-order command queue with one shared scalar snapshot store.
module edge_accel_cmd_queue #(
  parameter SEQ_ID_WIDTH       = 8,
  parameter EPOCH_WIDTH        = 4,
  parameter VALUE_WIDTH        = 64,
  parameter QUEUE_DEPTH        = 8,
  parameter QUEUE_PTR_WIDTH    = 3,
  parameter SNAPSHOT_DEPTH     = 8,
  parameter SNAPSHOT_PTR_WIDTH = 3
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,

  input  wire                         cmd_valid,
  output wire                         cmd_ready,
  input  wire [63:0]                  cmd_inst64,
  input  wire [SEQ_ID_WIDTH-1:0]      cmd_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       cmd_epoch,
  input  wire                         cmd_n_capture_valid,

  // A command and its scalar holder use the same seq_id[2:0] snapshot slot.
  input  wire                         snapshot_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      snapshot_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       snapshot_epoch,
  input  wire [SNAPSHOT_PTR_WIDTH-1:0] snapshot_target,
  input  wire                         snapshot_n_valid,
  input  wire [VALUE_WIDTH-1:0]       snapshot_n_value,

  output wire                         issue_valid,
  input  wire                         issue_ready,
  output wire [7:0]                   issue_opcode8,
  output wire [7:0]                   issue_imm8,
  output wire [63:0]                  issue_inst64,
  output wire [SEQ_ID_WIDTH-1:0]      issue_seq_id,
  output wire [EPOCH_WIDTH-1:0]       issue_epoch,
  output wire                         issue_n_valid,
  output wire [VALUE_WIDTH-1:0]       issue_n_value,

  input  wire                         redirect_kill_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      redirect_kill_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       redirect_kill_epoch,

  output wire [QUEUE_DEPTH-1:0]       debug_entry_valid,
  output wire [QUEUE_PTR_WIDTH:0]     debug_count,
  output wire [QUEUE_PTR_WIDTH-1:0]   debug_head,
  output wire [QUEUE_PTR_WIDTH-1:0]   debug_tail
);

  reg [QUEUE_DEPTH-1:0] entry_valid;
  reg [QUEUE_DEPTH-1:0] entry_killed;
  reg [7:0] entry_opcode8 [0:QUEUE_DEPTH-1];
  reg [7:0] entry_imm8 [0:QUEUE_DEPTH-1];
  reg [SEQ_ID_WIDTH-1:0] entry_seq_id [0:QUEUE_DEPTH-1];
  reg [EPOCH_WIDTH-1:0] entry_epoch [0:QUEUE_DEPTH-1];
  reg entry_n_capture_valid [0:QUEUE_DEPTH-1];
  reg entry_snapshot_valid [0:QUEUE_DEPTH-1];
  reg entry_snapshot_n_valid [0:QUEUE_DEPTH-1];
  reg [VALUE_WIDTH-1:0] entry_snapshot_n_value [0:QUEUE_DEPTH-1];
  reg [QUEUE_PTR_WIDTH-1:0] head_ptr;
  reg [QUEUE_PTR_WIDTH-1:0] tail_ptr;
  reg [QUEUE_PTR_WIDTH:0] count;

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

  function [7:0] compact_imm8;
    input [63:0] inst64;
    begin
      case (inst64[38:32])
        7'h01: compact_imm8 = {6'b0, inst64[57:56]};
        7'h09: compact_imm8 = {7'b0, inst64[56]};
        7'h10,
        7'h20: compact_imm8 = {inst64[55:52], inst64[50:47]};
        7'h27: compact_imm8 = {4'b0, inst64[50:47]};
        7'h2f: compact_imm8 = {3'b0, inst64[52], inst64[50:47]};
        7'h11,
        7'h18,
        7'h1d: compact_imm8 = {6'b0, inst64[57:56]};
        7'h12, 7'h13, 7'h14, 7'h1a: compact_imm8 = {7'b0, inst64[56]};
        7'h15: compact_imm8 = inst64[63:56];
        7'h1e: compact_imm8 = {7'b0, inst64[56]};
        default: compact_imm8 = 8'b0;
      endcase
    end
  endfunction

  function [63:0] expand_inst64;
    input [7:0] opcode8;
    input [7:0] imm8;
    reg [63:0] inst64;
    begin
      inst64 = 64'b0;
      inst64[6:0] = 7'b0111111;
      inst64[39:32] = opcode8;
      case (opcode8[6:0])
        7'h01: inst64[57:56] = imm8[1:0];
        7'h09: inst64[56] = imm8[0];
        7'h10,
        7'h20: begin
          inst64[55:52] = imm8[7:4];
          inst64[50:47] = imm8[3:0];
        end
        7'h27: inst64[50:47] = imm8[3:0];
        7'h2f: begin
          inst64[52] = imm8[4];
          inst64[50:47] = imm8[3:0];
        end
        7'h11,
        7'h18,
        7'h1d: inst64[57:56] = imm8[1:0];
        7'h12, 7'h13, 7'h14, 7'h1a: inst64[56] = imm8[0];
        7'h15: inst64[63:56] = imm8;
        7'h1e: inst64[56] = imm8[0];
        default: begin end
      endcase
      expand_inst64 = inst64;
    end
  endfunction

  // Early holder results wait here until their command is enqueued. Once a
  // command exists, its operands live in that command entry and are matched by
  // the full seq_id/epoch rather than by a shared physical-slot owner.
  reg snapshot_store_valid [0:SNAPSHOT_DEPTH-1];
  reg [SEQ_ID_WIDTH-1:0] snapshot_owner_seq_id [0:SNAPSHOT_DEPTH-1];
  reg [EPOCH_WIDTH-1:0] snapshot_owner_epoch [0:SNAPSHOT_DEPTH-1];
  reg snapshot_store_n_valid [0:SNAPSHOT_DEPTH-1];
  reg [VALUE_WIDTH-1:0] snapshot_store_n_value [0:SNAPSHOT_DEPTH-1];

  wire queue_has_head;
  wire head_killed_by_redirect;
  wire head_live;
  wire n_operand_ready;
  wire issue_fire;
  wire head_kill_fire;
  wire pop_fire;
  wire enqueue_fire;
  wire queue_has_space;
  wire [SNAPSHOT_PTR_WIDTH-1:0] cmd_snapshot_slot;
  wire snapshot_matches_enqueue;
  wire cmd_matches_pending_snapshot;
  reg [QUEUE_PTR_WIDTH-1:0] next_head_ptr;
  reg [QUEUE_PTR_WIDTH-1:0] next_tail_ptr;

  assign queue_has_head = (count != {QUEUE_PTR_WIDTH+1{1'b0}}) &&
                          entry_valid[head_ptr];
  assign head_killed_by_redirect = entry_killed[head_ptr] ||
                                   (redirect_kill_valid &&
                                    (entry_epoch[head_ptr] == redirect_kill_epoch) &&
                                    seq_is_younger(entry_seq_id[head_ptr],
                                                   redirect_kill_seq_id));
  assign head_live = queue_has_head && !head_killed_by_redirect;
  assign n_operand_ready = !entry_n_capture_valid[head_ptr] ||
                           (entry_snapshot_valid[head_ptr] &&
                            entry_snapshot_n_valid[head_ptr]);

  assign cmd_snapshot_slot = cmd_seq_id[SNAPSHOT_PTR_WIDTH-1:0];
  // Input ready is a capacity property only. It must not depend on cmd_seq_id
  // or downstream issue readiness, because both participate in frontend
  // bundle selection.
  assign queue_has_space = (count < QUEUE_DEPTH[QUEUE_PTR_WIDTH:0]);
  assign cmd_ready = queue_has_space;
  assign enqueue_fire = cmd_valid && cmd_ready;
  assign issue_valid = head_live && n_operand_ready;
  assign issue_opcode8 = entry_opcode8[head_ptr];
  assign issue_imm8 = entry_imm8[head_ptr];
  assign issue_inst64 = expand_inst64(issue_opcode8, issue_imm8);
  assign issue_seq_id = entry_seq_id[head_ptr];
  assign issue_epoch = entry_epoch[head_ptr];
  assign issue_n_valid = head_live && entry_n_capture_valid[head_ptr];
  assign issue_n_value = issue_n_valid ? entry_snapshot_n_value[head_ptr] :
                                         {VALUE_WIDTH{1'b0}};

  assign issue_fire = issue_valid && issue_ready;
  assign head_kill_fire = queue_has_head && head_killed_by_redirect;
  assign pop_fire = issue_fire || head_kill_fire;
  assign snapshot_matches_enqueue = enqueue_fire &&
                                    (cmd_snapshot_slot == snapshot_target) &&
                                    (cmd_seq_id == snapshot_seq_id) &&
                                    (cmd_epoch == snapshot_epoch);
  assign cmd_matches_pending_snapshot = snapshot_store_valid[cmd_snapshot_slot] &&
                                        (snapshot_owner_seq_id[cmd_snapshot_slot] ==
                                         cmd_seq_id) &&
                                        (snapshot_owner_epoch[cmd_snapshot_slot] ==
                                         cmd_epoch);
  assign debug_entry_valid = entry_valid;
  assign debug_count = count;
  assign debug_head = head_ptr;
  assign debug_tail = tail_ptr;

  always @* begin
    next_head_ptr = head_ptr + {{(QUEUE_PTR_WIDTH-1){1'b0}}, 1'b1};
    next_tail_ptr = tail_ptr + {{(QUEUE_PTR_WIDTH-1){1'b0}}, 1'b1};
  end

  integer i;
  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      entry_valid <= {QUEUE_DEPTH{1'b0}};
      entry_killed <= {QUEUE_DEPTH{1'b0}};
      head_ptr <= {QUEUE_PTR_WIDTH{1'b0}};
      tail_ptr <= {QUEUE_PTR_WIDTH{1'b0}};
      count <= {QUEUE_PTR_WIDTH+1{1'b0}};
      for (i = 0; i < QUEUE_DEPTH; i = i + 1) begin
        entry_opcode8[i] <= 8'd0;
        entry_imm8[i] <= 8'd0;
        entry_seq_id[i] <= {SEQ_ID_WIDTH{1'b0}};
        entry_epoch[i] <= {EPOCH_WIDTH{1'b0}};
        entry_n_capture_valid[i] <= 1'b0;
        entry_snapshot_valid[i] <= 1'b0;
        entry_snapshot_n_valid[i] <= 1'b0;
        entry_snapshot_n_value[i] <= {VALUE_WIDTH{1'b0}};
      end
      for (i = 0; i < SNAPSHOT_DEPTH; i = i + 1) begin
        snapshot_store_valid[i] <= 1'b0;
        snapshot_owner_seq_id[i] <= {SEQ_ID_WIDTH{1'b0}};
        snapshot_owner_epoch[i] <= {EPOCH_WIDTH{1'b0}};
        snapshot_store_n_valid[i] <= 1'b0;
        snapshot_store_n_value[i] <= {VALUE_WIDTH{1'b0}};
      end
    end else begin
      if (pop_fire) begin
        entry_valid[head_ptr] <= 1'b0;
        entry_killed[head_ptr] <= 1'b0;
        entry_snapshot_valid[head_ptr] <= 1'b0;
        if (snapshot_store_valid[entry_seq_id[head_ptr][SNAPSHOT_PTR_WIDTH-1:0]] &&
            (snapshot_owner_seq_id[entry_seq_id[head_ptr][SNAPSHOT_PTR_WIDTH-1:0]] ==
             entry_seq_id[head_ptr]) &&
            (snapshot_owner_epoch[entry_seq_id[head_ptr][SNAPSHOT_PTR_WIDTH-1:0]] ==
             entry_epoch[head_ptr]))
          snapshot_store_valid[entry_seq_id[head_ptr][SNAPSHOT_PTR_WIDTH-1:0]] <= 1'b0;
        head_ptr <= next_head_ptr;
      end

      if (enqueue_fire) begin
        entry_valid[tail_ptr] <= 1'b1;
        entry_killed[tail_ptr] <= redirect_kill_valid &&
                                  (cmd_epoch == redirect_kill_epoch) &&
                                  seq_is_younger(cmd_seq_id,
                                                 redirect_kill_seq_id);
        entry_opcode8[tail_ptr] <= cmd_inst64[39:32];
        entry_imm8[tail_ptr] <= compact_imm8(cmd_inst64);
        entry_seq_id[tail_ptr] <= cmd_seq_id;
        entry_epoch[tail_ptr] <= cmd_epoch;
        entry_n_capture_valid[tail_ptr] <= cmd_n_capture_valid;
        entry_snapshot_valid[tail_ptr] <= cmd_matches_pending_snapshot ||
                                          snapshot_matches_enqueue;
        entry_snapshot_n_valid[tail_ptr] <= snapshot_matches_enqueue ?
                                             snapshot_n_valid :
                                             snapshot_store_n_valid[cmd_snapshot_slot];
        entry_snapshot_n_value[tail_ptr] <= snapshot_matches_enqueue ?
                                             snapshot_n_value :
                                             snapshot_store_n_value[cmd_snapshot_slot];
        if (cmd_matches_pending_snapshot)
          snapshot_store_valid[cmd_snapshot_slot] <= 1'b0;
        tail_ptr <= next_tail_ptr;
      end

      if (snapshot_valid) begin
        snapshot_store_valid[snapshot_target] <=
          !(redirect_kill_valid &&
            (snapshot_epoch == redirect_kill_epoch) &&
            seq_is_younger(snapshot_seq_id, redirect_kill_seq_id));
        snapshot_owner_seq_id[snapshot_target] <= snapshot_seq_id;
        snapshot_owner_epoch[snapshot_target] <= snapshot_epoch;
        snapshot_store_n_valid[snapshot_target] <= snapshot_n_valid;
        snapshot_store_n_value[snapshot_target] <= snapshot_n_value;
        for (i = 0; i < QUEUE_DEPTH; i = i + 1) begin
          if (entry_valid[i] &&
              (entry_seq_id[i] == snapshot_seq_id) &&
              (entry_epoch[i] == snapshot_epoch)) begin
            entry_snapshot_valid[i] <= 1'b1;
            entry_snapshot_n_valid[i] <= snapshot_n_valid;
            entry_snapshot_n_value[i] <= snapshot_n_value;
          end
        end
      end

      if (redirect_kill_valid) begin
        for (i = 0; i < QUEUE_DEPTH; i = i + 1) begin
          if (entry_valid[i] &&
              (entry_epoch[i] == redirect_kill_epoch) &&
              seq_is_younger(entry_seq_id[i], redirect_kill_seq_id))
            entry_killed[i] <= 1'b1;
        end
        for (i = 0; i < SNAPSHOT_DEPTH; i = i + 1) begin
          if (snapshot_store_valid[i] &&
              (snapshot_owner_epoch[i] == redirect_kill_epoch) &&
              seq_is_younger(snapshot_owner_seq_id[i], redirect_kill_seq_id))
            snapshot_store_valid[i] <= 1'b0;
        end
      end

      case ({enqueue_fire, pop_fire})
        2'b10: count <= count + {{QUEUE_PTR_WIDTH{1'b0}}, 1'b1};
        2'b01: count <= count - {{QUEUE_PTR_WIDTH{1'b0}}, 1'b1};
        default: count <= count;
      endcase
    end
  end

endmodule
