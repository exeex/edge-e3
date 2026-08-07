// Ordered predecode-entry window for tokenized scalar/vector issue selection.
module edge_predecode_issue_window #(
  parameter DEPTH        = 8,
  parameter PTR_WIDTH    = 3,
  parameter COUNT_WIDTH  = 4,
  parameter PC_WIDTH     = 40,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH  = 4,
  parameter INST_WIDTH   = 64,
  parameter KIND_WIDTH   = 2,
  parameter CLASS_WIDTH  = 3
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,
  input  wire                         flush_valid,

  input  wire                         enqueue0_valid,
  input  wire [KIND_WIDTH-1:0]        enqueue0_kind,
  input  wire [CLASS_WIDTH-1:0]       enqueue0_class,
  input  wire [PC_WIDTH-1:0]          enqueue0_pc,
  input  wire [INST_WIDTH-1:0]        enqueue0_inst,
  input  wire [SEQ_ID_WIDTH-1:0]      enqueue0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       enqueue0_epoch,
  input  wire                         enqueue1_valid,
  input  wire [KIND_WIDTH-1:0]        enqueue1_kind,
  input  wire [CLASS_WIDTH-1:0]       enqueue1_class,
  input  wire [PC_WIDTH-1:0]          enqueue1_pc,
  input  wire [INST_WIDTH-1:0]        enqueue1_inst,
  input  wire [SEQ_ID_WIDTH-1:0]      enqueue1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       enqueue1_epoch,
  input  wire                         enqueue2_valid,
  input  wire [KIND_WIDTH-1:0]        enqueue2_kind,
  input  wire [CLASS_WIDTH-1:0]       enqueue2_class,
  input  wire [PC_WIDTH-1:0]          enqueue2_pc,
  input  wire [INST_WIDTH-1:0]        enqueue2_inst,
  input  wire [SEQ_ID_WIDTH-1:0]      enqueue2_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       enqueue2_epoch,
  input  wire                         enqueue3_valid,
  input  wire [KIND_WIDTH-1:0]        enqueue3_kind,
  input  wire [CLASS_WIDTH-1:0]       enqueue3_class,
  input  wire [PC_WIDTH-1:0]          enqueue3_pc,
  input  wire [INST_WIDTH-1:0]        enqueue3_inst,
  input  wire [SEQ_ID_WIDTH-1:0]      enqueue3_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       enqueue3_epoch,
  output wire                         enqueue_ready,

  input  wire [1:0]                   pop_count,

  output wire                         head0_valid,
  output wire [KIND_WIDTH-1:0]        head0_kind,
  output wire [CLASS_WIDTH-1:0]       head0_class,
  output wire [PC_WIDTH-1:0]          head0_pc,
  output wire [INST_WIDTH-1:0]        head0_inst,
  output wire [SEQ_ID_WIDTH-1:0]      head0_seq_id,
  output wire [EPOCH_WIDTH-1:0]       head0_epoch,
  output wire                         head1_valid,
  output wire [KIND_WIDTH-1:0]        head1_kind,
  output wire [CLASS_WIDTH-1:0]       head1_class,
  output wire [PC_WIDTH-1:0]          head1_pc,
  output wire [INST_WIDTH-1:0]        head1_inst,
  output wire [SEQ_ID_WIDTH-1:0]      head1_seq_id,
  output wire [EPOCH_WIDTH-1:0]       head1_epoch,

  output wire [COUNT_WIDTH-1:0]       debug_count
);

  localparam [COUNT_WIDTH-1:0] DEPTH_COUNT = DEPTH;

  reg [KIND_WIDTH-1:0] kind_q [0:DEPTH-1];
  reg [CLASS_WIDTH-1:0] class_q [0:DEPTH-1];
  reg [PC_WIDTH-1:0] pc_q [0:DEPTH-1];
  reg [INST_WIDTH-1:0] inst_q [0:DEPTH-1];
  reg [SEQ_ID_WIDTH-1:0] seq_id_q [0:DEPTH-1];
  reg [EPOCH_WIDTH-1:0] epoch_q [0:DEPTH-1];
  reg [PTR_WIDTH-1:0] head_q;
  reg [PTR_WIDTH-1:0] tail_q;
  reg [COUNT_WIDTH-1:0] count_q;

  wire [PTR_WIDTH-1:0] head1_ptr;
  wire [2:0] enqueue_count;
  wire [1:0] pop_actual;
  wire [COUNT_WIDTH-1:0] free_after_pop;
  wire enqueue_fire;

  assign head1_ptr = head_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
  assign enqueue_count = enqueue0_valid ?
                         (enqueue1_valid ?
                          (enqueue2_valid ? (enqueue3_valid ? 3'd4 : 3'd3) : 3'd2) :
                          3'd1) :
                         3'd0;
  assign pop_actual = (pop_count == 2'd2 && count_q >= 2) ? 2'd2 :
                      ((pop_count != 2'd0 && count_q != {COUNT_WIDTH{1'b0}}) ? 2'd1 : 2'd0);
  assign free_after_pop = (DEPTH_COUNT - count_q) +
                          {{(COUNT_WIDTH-2){1'b0}}, pop_actual};
  assign enqueue_ready = ({{(COUNT_WIDTH-3){1'b0}}, enqueue_count} <= free_after_pop);
  assign enqueue_fire = enqueue_ready && enqueue0_valid;

  assign head0_valid = count_q != {COUNT_WIDTH{1'b0}};
  assign head0_kind = kind_q[head_q];
  assign head0_class = class_q[head_q];
  assign head0_pc = pc_q[head_q];
  assign head0_inst = inst_q[head_q];
  assign head0_seq_id = seq_id_q[head_q];
  assign head0_epoch = epoch_q[head_q];
  assign head1_valid = count_q >= {{(COUNT_WIDTH-2){1'b0}}, 2'd2};
  assign head1_kind = kind_q[head1_ptr];
  assign head1_class = class_q[head1_ptr];
  assign head1_pc = pc_q[head1_ptr];
  assign head1_inst = inst_q[head1_ptr];
  assign head1_seq_id = seq_id_q[head1_ptr];
  assign head1_epoch = epoch_q[head1_ptr];
  assign debug_count = count_q;

  integer i;
  reg [PTR_WIDTH-1:0] tail_next;
  reg [COUNT_WIDTH-1:0] count_next;

  task write_entry;
    input [PTR_WIDTH-1:0] ptr;
    input [KIND_WIDTH-1:0] kind;
    input [CLASS_WIDTH-1:0] class_id;
    input [PC_WIDTH-1:0] pc;
    input [INST_WIDTH-1:0] inst;
    input [SEQ_ID_WIDTH-1:0] seq_id;
    input [EPOCH_WIDTH-1:0] epoch;
    begin
      kind_q[ptr] <= kind;
      class_q[ptr] <= class_id;
      pc_q[ptr] <= pc;
      inst_q[ptr] <= inst;
      seq_id_q[ptr] <= seq_id;
      epoch_q[ptr] <= epoch;
    end
  endtask

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      head_q <= {PTR_WIDTH{1'b0}};
      tail_q <= {PTR_WIDTH{1'b0}};
      count_q <= {COUNT_WIDTH{1'b0}};
      for (i = 0; i < DEPTH; i = i + 1) begin
        kind_q[i] <= {KIND_WIDTH{1'b0}};
        class_q[i] <= {CLASS_WIDTH{1'b0}};
        pc_q[i] <= {PC_WIDTH{1'b0}};
        inst_q[i] <= {INST_WIDTH{1'b0}};
        seq_id_q[i] <= {SEQ_ID_WIDTH{1'b0}};
        epoch_q[i] <= {EPOCH_WIDTH{1'b0}};
      end
    end else if (flush_valid) begin
      head_q <= {PTR_WIDTH{1'b0}};
      tail_q <= {PTR_WIDTH{1'b0}};
      count_q <= {COUNT_WIDTH{1'b0}};
    end else begin
      tail_next = tail_q;
      count_next = count_q - {{(COUNT_WIDTH-2){1'b0}}, pop_actual};

      if (pop_actual != 2'd0) begin
        head_q <= head_q + {{(PTR_WIDTH-2){1'b0}}, pop_actual};
      end

      if (enqueue_fire) begin
        write_entry(tail_next, enqueue0_kind, enqueue0_class, enqueue0_pc,
                    enqueue0_inst, enqueue0_seq_id, enqueue0_epoch);
        tail_next = tail_next + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
        count_next = count_next + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        if (enqueue1_valid) begin
          write_entry(tail_next, enqueue1_kind, enqueue1_class, enqueue1_pc,
                      enqueue1_inst, enqueue1_seq_id, enqueue1_epoch);
          tail_next = tail_next + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
          count_next = count_next + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        end
        if (enqueue2_valid) begin
          write_entry(tail_next, enqueue2_kind, enqueue2_class, enqueue2_pc,
                      enqueue2_inst, enqueue2_seq_id, enqueue2_epoch);
          tail_next = tail_next + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
          count_next = count_next + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        end
        if (enqueue3_valid) begin
          write_entry(tail_next, enqueue3_kind, enqueue3_class, enqueue3_pc,
                      enqueue3_inst, enqueue3_seq_id, enqueue3_epoch);
          tail_next = tail_next + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
          count_next = count_next + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        end
      end

      tail_q <= tail_next;
      count_q <= count_next;
    end
  end
endmodule
