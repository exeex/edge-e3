// Split 128-bit I-cache responses into compact 64-bit fetch chunks.
module edge_fetch_packet_fifo #(
  parameter PC_WIDTH = 40,
  parameter EPOCH_WIDTH = 4,
  parameter DEPTH = 4,
  parameter PTR_WIDTH = 2,
  parameter COUNT_WIDTH = 3
) (
  input  wire                    forever_cpuclk,
  input  wire                    cpurst_b,
  input  wire                    flush_valid,

  input  wire                    in_valid,
  output wire                    in_ready,
  input  wire [PC_WIDTH-1:0]     in_block_pc,
  input  wire [1:0]              in_start_word,
  input  wire [127:0]            in_bits,
  input  wire [EPOCH_WIDTH-1:0]  in_epoch,

  output wire                    out_valid,
  input  wire                    out_ready,
  output wire [PC_WIDTH-1:0]     out_block_pc,
  // 0: both 32-bit parcels valid; 1: only bits[63:32] is valid.
  output wire                    out_first_word,
  output wire [63:0]             out_bits,
  output wire [EPOCH_WIDTH-1:0]  out_epoch,
  output wire [COUNT_WIDTH-1:0]  debug_count
);

  localparam [COUNT_WIDTH-1:0] DEPTH_COUNT = DEPTH[COUNT_WIDTH-1:0];
  localparam [PTR_WIDTH-1:0] LAST_PTR =
    DEPTH[PTR_WIDTH-1:0] - {{(PTR_WIDTH-1){1'b0}}, 1'b1};

  reg [PC_WIDTH-1:0] block_pc_q [0:DEPTH-1];
  reg first_word_q [0:DEPTH-1];
  reg [63:0] bits_q [0:DEPTH-1];
  reg [EPOCH_WIDTH-1:0] epoch_q [0:DEPTH-1];
  reg [PTR_WIDTH-1:0] head_q;
  reg [PTR_WIDTH-1:0] tail_q;
  reg [COUNT_WIDTH-1:0] count_q;

  // A 128-bit IFU packet always contains every parcel at or after its start.
  // The low 64-bit chunk is absent only for starts at word 2 or 3.
  wire low_valid = in_start_word < 2'd2;
  wire high_valid = 1'b1;
  wire [1:0] input_chunk_count = {1'b0, low_valid} + {1'b0, high_valid};
  wire stored_valid = count_q != {COUNT_WIDTH{1'b0}};
  wire bypass_valid = !flush_valid && !stored_valid && in_valid;
  wire stored_dequeue_fire = stored_valid && out_ready;
  wire bypass_dequeue_fire = bypass_valid && out_ready;
  wire [COUNT_WIDTH-1:0] free_slots = DEPTH_COUNT - count_q;
  wire enqueue_fire = in_valid && in_ready;
  wire [1:0] stored_input_count =
    input_chunk_count - {1'b0, bypass_dequeue_fire};
  wire [PTR_WIDTH-1:0] tail_plus_one =
    (tail_q == LAST_PTR) ? {PTR_WIDTH{1'b0}} :
                           tail_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
  wire [PTR_WIDTH-1:0] head_plus_one =
    (head_q == LAST_PTR) ? {PTR_WIDTH{1'b0}} :
                           head_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1};

  assign out_valid = stored_valid || bypass_valid;
  assign in_ready = !flush_valid &&
                    (free_slots >= {{(COUNT_WIDTH-2){1'b0}}, input_chunk_count});
  assign out_block_pc = stored_valid ? block_pc_q[head_q] :
                        (low_valid ? in_block_pc :
                         in_block_pc + {{(PC_WIDTH-4){1'b0}}, 4'd8});
  assign out_first_word = stored_valid ? first_word_q[head_q] :
                          (low_valid ? in_start_word[0] :
                                       (in_start_word == 2'd3));
  assign out_bits = stored_valid ? bits_q[head_q] :
                    (low_valid ? in_bits[63:0] : in_bits[127:64]);
  assign out_epoch = stored_valid ? epoch_q[head_q] : in_epoch;
  assign debug_count = count_q;

  integer i;
  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      head_q <= {PTR_WIDTH{1'b0}};
      tail_q <= {PTR_WIDTH{1'b0}};
      count_q <= {COUNT_WIDTH{1'b0}};
      for (i = 0; i < DEPTH; i = i + 1) begin
        block_pc_q[i] <= {PC_WIDTH{1'b0}};
        first_word_q[i] <= 1'b0;
        bits_q[i] <= 64'd0;
        epoch_q[i] <= {EPOCH_WIDTH{1'b0}};
      end
    end else if (flush_valid) begin
      head_q <= {PTR_WIDTH{1'b0}};
      tail_q <= {PTR_WIDTH{1'b0}};
      count_q <= {COUNT_WIDTH{1'b0}};
    end else begin
      if (stored_dequeue_fire)
        head_q <= head_plus_one;

      if (enqueue_fire) begin
        if (low_valid && !bypass_dequeue_fire) begin
          block_pc_q[tail_q] <= in_block_pc;
          first_word_q[tail_q] <= in_start_word[0];
          bits_q[tail_q] <= in_bits[63:0];
          epoch_q[tail_q] <= in_epoch;
        end
        if (high_valid && !(bypass_dequeue_fire && !low_valid)) begin
          block_pc_q[(low_valid && !bypass_dequeue_fire) ? tail_plus_one : tail_q] <=
            in_block_pc + {{(PC_WIDTH-4){1'b0}}, 4'd8};
          first_word_q[(low_valid && !bypass_dequeue_fire) ? tail_plus_one : tail_q] <=
            in_start_word == 2'd3;
          bits_q[(low_valid && !bypass_dequeue_fire) ? tail_plus_one : tail_q] <=
            in_bits[127:64];
          epoch_q[(low_valid && !bypass_dequeue_fire) ? tail_plus_one : tail_q] <=
            in_epoch;
        end
        case (stored_input_count)
          2'd2: tail_q <= (tail_plus_one == LAST_PTR) ? {PTR_WIDTH{1'b0}} :
                                                        tail_plus_one + 1'b1;
          2'd1: tail_q <= tail_plus_one;
          default: tail_q <= tail_q;
        endcase
      end

      case ({enqueue_fire, stored_dequeue_fire})
        2'b10: count_q <= count_q + stored_input_count;
        2'b01: count_q <= count_q - {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        2'b11: count_q <= count_q + stored_input_count -
                            {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
        default: count_q <= count_q;
      endcase
    end
  end

`ifdef IVERILOG_SIM
  initial begin
    if (DEPTH != (1 << PTR_WIDTH)) begin
      $display("edge_fetch_packet_fifo: DEPTH must equal 2**PTR_WIDTH");
      $finish;
    end
  end
`endif

endmodule
