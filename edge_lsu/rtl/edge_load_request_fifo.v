// Dual-allocation, dual-dequeue buffer between LSU scheduling and D-cache.
module edge_load_request_fifo #(
  parameter DEPTH = 2,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter VALUE_WIDTH = 64,
  parameter COUNT_WIDTH = $clog2(DEPTH + 1)
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,
  input  wire                       flush,
  input  wire [SEQ_ID_WIDTH-1:0]    flush_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     flush_epoch,

  input  wire                       in0_valid,
  output wire                       in0_ready,
  input  wire [SEQ_ID_WIDTH-1:0]    in0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     in0_epoch,
  input  wire [VALUE_WIDTH-1:0]     in0_addr,
  input  wire [1:0]                 in0_size,
  input  wire                       in0_signed,

  input  wire                       in1_valid,
  output wire                       in1_ready,
  input  wire [SEQ_ID_WIDTH-1:0]    in1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     in1_epoch,
  input  wire [VALUE_WIDTH-1:0]     in1_addr,
  input  wire [1:0]                 in1_size,
  input  wire                       in1_signed,

  output wire                       out_valid,
  input  wire                       out_ready,
  output wire [SEQ_ID_WIDTH-1:0]    out_seq_id,
  output wire [EPOCH_WIDTH-1:0]     out_epoch,
  output wire [VALUE_WIDTH-1:0]     out_addr,
  output wire [1:0]                 out_size,
  output wire                       out_signed,
  output wire                       out1_valid,
  input  wire                       out1_ready,
  output wire [SEQ_ID_WIDTH-1:0]    out1_seq_id,
  output wire [EPOCH_WIDTH-1:0]     out1_epoch,
  output wire [VALUE_WIDTH-1:0]     out1_addr,
  output wire [1:0]                 out1_size,
  output wire                       out1_signed,
  output wire [COUNT_WIDTH-1:0]     debug_count
);

  localparam [COUNT_WIDTH-1:0] DEPTH_COUNT = DEPTH[COUNT_WIDTH-1:0];
  reg [SEQ_ID_WIDTH-1:0] seq_q [0:DEPTH-1];
  reg [EPOCH_WIDTH-1:0] epoch_q [0:DEPTH-1];
  reg [VALUE_WIDTH-1:0] addr_q [0:DEPTH-1];
  reg [1:0] size_q [0:DEPTH-1];
  reg signed_q [0:DEPTH-1];
  reg [COUNT_WIDTH-1:0] count_q;
  integer keep_count;

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

  wire out_fire = out_valid && out_ready;
  wire out1_fire = out_fire && out1_valid && out1_ready;
  wire [1:0] pop_count = {1'b0, out_fire} + {1'b0, out1_fire};
  wire [COUNT_WIDTH-1:0] free_after_pop =
    DEPTH_COUNT - count_q +
    {{(COUNT_WIDTH-2){1'b0}}, pop_count};
  wire in0_fire = in0_valid && in0_ready;
  wire in1_fire = in1_valid && in1_ready;
  wire [COUNT_WIDTH-1:0] base_count =
    count_q - {{(COUNT_WIDTH-2){1'b0}}, pop_count};

  assign in0_ready = free_after_pop != {COUNT_WIDTH{1'b0}};
  assign in1_ready = in0_valid ? (free_after_pop >= 2) :
                                 (free_after_pop != {COUNT_WIDTH{1'b0}});
  assign out_valid = count_q != {COUNT_WIDTH{1'b0}};
  assign out_seq_id = seq_q[0];
  assign out_epoch = epoch_q[0];
  assign out_addr = addr_q[0];
  assign out_size = size_q[0];
  assign out_signed = signed_q[0];
  assign out1_valid = count_q >= 2;
  assign out1_seq_id = seq_q[1];
  assign out1_epoch = epoch_q[1];
  assign out1_addr = addr_q[1];
  assign out1_size = size_q[1];
  assign out1_signed = signed_q[1];
  assign debug_count = count_q;

  integer i;
  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      count_q <= {COUNT_WIDTH{1'b0}};
      for (i = 0; i < DEPTH; i = i + 1) begin
        seq_q[i] <= {SEQ_ID_WIDTH{1'b0}};
        epoch_q[i] <= {EPOCH_WIDTH{1'b0}};
        addr_q[i] <= {VALUE_WIDTH{1'b0}};
        size_q[i] <= 2'b00;
        signed_q[i] <= 1'b0;
      end
    end else if (flush) begin
      if (flush_seq_id == {SEQ_ID_WIDTH{1'b0}}) begin
        count_q <= {COUNT_WIDTH{1'b0}};
      end else begin
        keep_count = 0;
        for (i = 0; i < DEPTH; i = i + 1) begin
          if ((i < count_q) &&
              !((epoch_q[i] == flush_epoch) &&
                seq_is_younger(seq_q[i], flush_seq_id))) begin
            seq_q[keep_count] <= seq_q[i];
            epoch_q[keep_count] <= epoch_q[i];
            addr_q[keep_count] <= addr_q[i];
            size_q[keep_count] <= size_q[i];
            signed_q[keep_count] <= signed_q[i];
            keep_count = keep_count + 1;
          end
        end
        count_q <= keep_count[COUNT_WIDTH-1:0];
      end
    end else begin
      if (out1_fire) begin
        for (i = 0; i < DEPTH-2; i = i + 1) begin
          seq_q[i] <= seq_q[i+2];
          epoch_q[i] <= epoch_q[i+2];
          addr_q[i] <= addr_q[i+2];
          size_q[i] <= size_q[i+2];
          signed_q[i] <= signed_q[i+2];
        end
      end else if (out_fire) begin
        for (i = 0; i < DEPTH-1; i = i + 1) begin
          seq_q[i] <= seq_q[i+1];
          epoch_q[i] <= epoch_q[i+1];
          addr_q[i] <= addr_q[i+1];
          size_q[i] <= size_q[i+1];
          signed_q[i] <= signed_q[i+1];
        end
      end
      if (in0_fire) begin
        seq_q[base_count] <= in0_seq_id;
        epoch_q[base_count] <= in0_epoch;
        addr_q[base_count] <= in0_addr;
        size_q[base_count] <= in0_size;
        signed_q[base_count] <= in0_signed;
      end
      if (in1_fire) begin
        seq_q[base_count + {{(COUNT_WIDTH-1){1'b0}}, in0_fire}] <= in1_seq_id;
        epoch_q[base_count + {{(COUNT_WIDTH-1){1'b0}}, in0_fire}] <= in1_epoch;
        addr_q[base_count + {{(COUNT_WIDTH-1){1'b0}}, in0_fire}] <= in1_addr;
        size_q[base_count + {{(COUNT_WIDTH-1){1'b0}}, in0_fire}] <= in1_size;
        signed_q[base_count + {{(COUNT_WIDTH-1){1'b0}}, in0_fire}] <= in1_signed;
      end
      count_q <= count_q +
                 {{(COUNT_WIDTH-1){1'b0}}, in0_fire} +
                 {{(COUNT_WIDTH-1){1'b0}}, in1_fire} -
                 {{(COUNT_WIDTH-1){1'b0}}, out_fire} -
                 {{(COUNT_WIDTH-1){1'b0}}, out1_fire};
    end
  end
endmodule
