// Tagged completion queue for pipelined D-cache hits.
module edge_dcache_hit_queue #(
  parameter DEPTH = 4,
  parameter PTR_WIDTH = 2,
  parameter COUNT_WIDTH = 3,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter VALUE_WIDTH = 64,
  parameter LOAD_LATENCY = 2,
  parameter LATENCY_WIDTH = 2
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,
  input  wire                       redirect_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    redirect_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     redirect_epoch,

  input  wire                       alloc0_valid,
  output wire                       alloc0_ready,
  output wire                       alloc0_buffered_ready,
  output wire [PTR_WIDTH-1:0]       alloc0_slot,
  input  wire [SEQ_ID_WIDTH-1:0]    alloc0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     alloc0_epoch,
  input  wire [VALUE_WIDTH-1:0]     alloc0_addr,
  input  wire [1:0]                 alloc0_size,
  input  wire                       alloc0_signed,

  input  wire                       alloc1_valid,
  output wire                       alloc1_ready,
  output wire                       alloc1_buffered_ready,
  output wire [PTR_WIDTH-1:0]       alloc1_slot,
  input  wire [SEQ_ID_WIDTH-1:0]    alloc1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     alloc1_epoch,
  input  wire [VALUE_WIDTH-1:0]     alloc1_addr,
  input  wire [1:0]                 alloc1_size,
  input  wire                       alloc1_signed,

  input  wire                       capture0_valid,
  input  wire [PTR_WIDTH-1:0]       capture0_slot,
  input  wire [VALUE_WIDTH-1:0]     capture0_word,
  input  wire                       capture1_valid,
  input  wire [PTR_WIDTH-1:0]       capture1_slot,
  input  wire [VALUE_WIDTH-1:0]     capture1_word,

  output wire                       complete_valid,
  input  wire                       complete_ready,
  output wire [SEQ_ID_WIDTH-1:0]    complete_seq_id,
  output wire [EPOCH_WIDTH-1:0]     complete_epoch,
  output wire [VALUE_WIDTH-1:0]     complete_addr,
  output wire [1:0]                 complete_size,
  output wire                       complete_signed,
  output wire [VALUE_WIDTH-1:0]     complete_word,
  output wire [COUNT_WIDTH-1:0]     debug_count
);

  localparam [PTR_WIDTH-1:0] LAST_PTR = DEPTH - 1;
  localparam [COUNT_WIDTH-1:0] DEPTH_COUNT = DEPTH;

  reg [PTR_WIDTH-1:0] head_q;
  reg [PTR_WIDTH-1:0] tail_q;
  reg [COUNT_WIDTH-1:0] count_q;
  reg [SEQ_ID_WIDTH-1:0] seq_q [0:DEPTH-1];
  reg [EPOCH_WIDTH-1:0] epoch_q [0:DEPTH-1];
  reg [VALUE_WIDTH-1:0] addr_q [0:DEPTH-1];
  reg [1:0] size_q [0:DEPTH-1];
  reg signed_q [0:DEPTH-1];
  reg stale_q [0:DEPTH-1];
  reg data_valid_q [0:DEPTH-1];
  reg [VALUE_WIDTH-1:0] word_q [0:DEPTH-1];
  reg [LATENCY_WIDTH-1:0] latency_q [0:DEPTH-1];

  function [PTR_WIDTH-1:0] ptr_inc;
    input [PTR_WIDTH-1:0] ptr;
    begin
      ptr_inc = (ptr == LAST_PTR) ? {PTR_WIDTH{1'b0}} :
                                   ptr + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
    end
  endfunction

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

  wire head_done = count_q != {COUNT_WIDTH{1'b0}} &&
                   data_valid_q[head_q] &&
                   latency_q[head_q] == {LATENCY_WIDTH{1'b0}};
  wire complete_fire = complete_valid && complete_ready;
  wire stale_pop = head_done && stale_q[head_q];
  wire pop_fire = complete_fire || stale_pop;
  wire [COUNT_WIDTH-1:0] free_after_pop =
    DEPTH_COUNT - count_q + {{(COUNT_WIDTH-1){1'b0}}, pop_fire};
  wire alloc0_fire = alloc0_valid && alloc0_ready;
  wire alloc1_fire = alloc1_valid && alloc1_ready;

  assign alloc0_ready = free_after_pop != {COUNT_WIDTH{1'b0}};
  assign alloc1_ready = alloc0_valid ? (free_after_pop >= 2) :
                                      (free_after_pop != {COUNT_WIDTH{1'b0}});
  assign alloc0_buffered_ready = count_q < DEPTH_COUNT;
  assign alloc1_buffered_ready = count_q < (DEPTH_COUNT - 1'b1);
  assign alloc0_slot = tail_q;
  assign alloc1_slot = alloc0_fire ? ptr_inc(tail_q) : tail_q;
  assign complete_valid = head_done && !stale_q[head_q];
  assign complete_seq_id = seq_q[head_q];
  assign complete_epoch = epoch_q[head_q];
  assign complete_addr = addr_q[head_q];
  assign complete_size = size_q[head_q];
  assign complete_signed = signed_q[head_q];
  assign complete_word = word_q[head_q];
  assign debug_count = count_q;

  integer i;
  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      head_q <= {PTR_WIDTH{1'b0}};
      tail_q <= {PTR_WIDTH{1'b0}};
      count_q <= {COUNT_WIDTH{1'b0}};
      for (i = 0; i < DEPTH; i = i + 1) begin
        seq_q[i] <= {SEQ_ID_WIDTH{1'b0}};
        epoch_q[i] <= {EPOCH_WIDTH{1'b0}};
        addr_q[i] <= {VALUE_WIDTH{1'b0}};
        size_q[i] <= 2'b00;
        signed_q[i] <= 1'b0;
        stale_q[i] <= 1'b0;
        data_valid_q[i] <= 1'b0;
        word_q[i] <= {VALUE_WIDTH{1'b0}};
        latency_q[i] <= {LATENCY_WIDTH{1'b0}};
      end
    end else begin
      for (i = 0; i < DEPTH; i = i + 1) begin
        if (latency_q[i] != {LATENCY_WIDTH{1'b0}})
          latency_q[i] <= latency_q[i] -
                          {{(LATENCY_WIDTH-1){1'b0}}, 1'b1};
        if (redirect_valid && epoch_q[i] == redirect_epoch &&
            seq_is_younger(seq_q[i], redirect_seq_id))
          stale_q[i] <= 1'b1;
      end

      if (capture0_valid) begin
        data_valid_q[capture0_slot] <= 1'b1;
        word_q[capture0_slot] <= capture0_word;
      end
      if (capture1_valid) begin
        data_valid_q[capture1_slot] <= 1'b1;
        word_q[capture1_slot] <= capture1_word;
      end

      if (pop_fire)
        head_q <= ptr_inc(head_q);

      if (alloc0_fire) begin
        seq_q[alloc0_slot] <= alloc0_seq_id;
        epoch_q[alloc0_slot] <= alloc0_epoch;
        addr_q[alloc0_slot] <= alloc0_addr;
        size_q[alloc0_slot] <= alloc0_size;
        signed_q[alloc0_slot] <= alloc0_signed;
        stale_q[alloc0_slot] <= redirect_valid &&
          (alloc0_epoch == redirect_epoch) &&
          seq_is_younger(alloc0_seq_id, redirect_seq_id);
        data_valid_q[alloc0_slot] <= 1'b0;
        latency_q[alloc0_slot] <= LOAD_LATENCY[LATENCY_WIDTH-1:0];
      end
      if (alloc1_fire) begin
        seq_q[alloc1_slot] <= alloc1_seq_id;
        epoch_q[alloc1_slot] <= alloc1_epoch;
        addr_q[alloc1_slot] <= alloc1_addr;
        size_q[alloc1_slot] <= alloc1_size;
        signed_q[alloc1_slot] <= alloc1_signed;
        stale_q[alloc1_slot] <= redirect_valid &&
          (alloc1_epoch == redirect_epoch) &&
          seq_is_younger(alloc1_seq_id, redirect_seq_id);
        data_valid_q[alloc1_slot] <= 1'b0;
        latency_q[alloc1_slot] <= LOAD_LATENCY[LATENCY_WIDTH-1:0];
      end

      if (alloc0_fire || alloc1_fire)
        tail_q <= alloc1_fire ? ptr_inc(alloc1_slot) : ptr_inc(alloc0_slot);
      count_q <= count_q +
                 {{(COUNT_WIDTH-1){1'b0}}, alloc0_fire} +
                 {{(COUNT_WIDTH-1){1'b0}}, alloc1_fire} -
                 {{(COUNT_WIDTH-1){1'b0}}, pop_fire};
    end
  end
endmodule
