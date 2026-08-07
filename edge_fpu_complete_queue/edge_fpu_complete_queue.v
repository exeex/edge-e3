module edge_fpu_complete_queue #(
  parameter DEPTH = 8,
  parameter MAX_PUSH = 5,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter REG_INDEX_WIDTH = 5,
  parameter VALUE_WIDTH = 64
) (
  input  wire                         forever_cpuclk,
  input  wire                         cpurst_b,
  input  wire                         flush,
  input  wire [SEQ_ID_WIDTH-1:0]      flush_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       flush_epoch,
  input  wire                         in0_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      in0_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       in0_epoch,
  input  wire                         in0_domain,
  input  wire [REG_INDEX_WIDTH-1:0]   in0_reg,
  input  wire                         in0_bank,
  input  wire [VALUE_WIDTH-1:0]       in0_value,
  input  wire [4:0]                   in0_fflags,
  input  wire                         in1_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      in1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       in1_epoch,
  input  wire                         in1_domain,
  input  wire [REG_INDEX_WIDTH-1:0]   in1_reg,
  input  wire                         in1_bank,
  input  wire [VALUE_WIDTH-1:0]       in1_value,
  input  wire [4:0]                   in1_fflags,
  input  wire                         in2_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      in2_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       in2_epoch,
  input  wire                         in2_domain,
  input  wire [REG_INDEX_WIDTH-1:0]   in2_reg,
  input  wire                         in2_bank,
  input  wire [VALUE_WIDTH-1:0]       in2_value,
  input  wire [4:0]                   in2_fflags,
  input  wire                         in3_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      in3_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       in3_epoch,
  input  wire                         in3_domain,
  input  wire [REG_INDEX_WIDTH-1:0]   in3_reg,
  input  wire                         in3_bank,
  input  wire [VALUE_WIDTH-1:0]       in3_value,
  input  wire [4:0]                   in3_fflags,
  input  wire                         in4_valid,
  input  wire [SEQ_ID_WIDTH-1:0]      in4_seq_id,
  input  wire [EPOCH_WIDTH-1:0]       in4_epoch,
  input  wire                         in4_domain,
  input  wire [REG_INDEX_WIDTH-1:0]   in4_reg,
  input  wire                         in4_bank,
  input  wire [VALUE_WIDTH-1:0]       in4_value,
  input  wire [4:0]                   in4_fflags,
  output wire                         ingress_ready,
  output wire                         out_valid,
  input  wire                         out_ready,
  output wire [SEQ_ID_WIDTH-1:0]      out_seq_id,
  output wire [EPOCH_WIDTH-1:0]       out_epoch,
  output wire                         out_domain,
  output wire [REG_INDEX_WIDTH-1:0]   out_reg,
  output wire                         out_bank,
  output wire [VALUE_WIDTH-1:0]       out_value,
  output wire [4:0]                   out_fflags
);
  localparam PTR_WIDTH = $clog2(DEPTH);
  localparam COUNT_WIDTH = $clog2(DEPTH + 1);

  reg [SEQ_ID_WIDTH-1:0] seq_mem [0:DEPTH-1];
  reg [EPOCH_WIDTH-1:0] epoch_mem [0:DEPTH-1];
  reg domain_mem [0:DEPTH-1];
  reg [REG_INDEX_WIDTH-1:0] reg_mem [0:DEPTH-1];
  reg bank_mem [0:DEPTH-1];
  reg [VALUE_WIDTH-1:0] value_mem [0:DEPTH-1];
  reg [4:0] fflags_mem [0:DEPTH-1];
  reg [PTR_WIDTH-1:0] head_r;
  reg [PTR_WIDTH-1:0] tail_r;
  reg [COUNT_WIDTH-1:0] count_r;
`ifdef IVERILOG_SIM
  reg [COUNT_WIDTH-1:0] max_count_r;
`endif

  wire pop;
  wire [2:0] push_count;
  assign pop = out_valid && out_ready;
  assign push_count = in0_valid + in1_valid + in2_valid + in3_valid + in4_valid;
  assign ingress_ready = (DEPTH - count_r + pop) >= MAX_PUSH;
  assign out_valid = count_r != 0;
  assign out_seq_id = seq_mem[head_r];
  assign out_epoch = epoch_mem[head_r];
  assign out_domain = domain_mem[head_r];
  assign out_reg = reg_mem[head_r];
  assign out_bank = bank_mem[head_r];
  assign out_value = value_mem[head_r];
  assign out_fflags = fflags_mem[head_r];

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

  function flush_kills_entry;
    input [SEQ_ID_WIDTH-1:0] candidate_seq;
    input [EPOCH_WIDTH-1:0] candidate_epoch;
    begin
      flush_kills_entry = flush &&
                          (candidate_epoch == flush_epoch) &&
                          seq_is_younger(candidate_seq, flush_seq_id);
    end
  endfunction

  integer offset;
  integer scan;
  integer compact_count;
  reg [PTR_WIDTH-1:0] write_ptr;
  reg [PTR_WIDTH-1:0] read_ptr;
  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      head_r <= 0;
      tail_r <= 0;
      count_r <= 0;
`ifdef IVERILOG_SIM
      max_count_r <= 0;
`endif
    end else begin
      compact_count = 0;
      if (flush) begin
        for (scan = 0; scan < DEPTH; scan = scan + 1) begin
          if (scan < (count_r - pop)) begin
            read_ptr = head_r + scan[PTR_WIDTH-1:0] + pop;
            if (!flush_kills_entry(seq_mem[read_ptr], epoch_mem[read_ptr])) begin
              seq_mem[compact_count[PTR_WIDTH-1:0]] <= seq_mem[read_ptr];
              epoch_mem[compact_count[PTR_WIDTH-1:0]] <= epoch_mem[read_ptr];
              domain_mem[compact_count[PTR_WIDTH-1:0]] <= domain_mem[read_ptr];
              reg_mem[compact_count[PTR_WIDTH-1:0]] <= reg_mem[read_ptr];
              bank_mem[compact_count[PTR_WIDTH-1:0]] <= bank_mem[read_ptr];
              value_mem[compact_count[PTR_WIDTH-1:0]] <= value_mem[read_ptr];
              fflags_mem[compact_count[PTR_WIDTH-1:0]] <= fflags_mem[read_ptr];
              compact_count = compact_count + 1;
            end
          end
        end
        write_ptr = compact_count[PTR_WIDTH-1:0];
      end else begin
        if (pop) head_r <= head_r + 1'b1;
        write_ptr = tail_r;
        compact_count = count_r - pop;
      end
      offset = 0;
      if (in0_valid && !flush_kills_entry(in0_seq_id, in0_epoch)) begin
        seq_mem[write_ptr] <= in0_seq_id; epoch_mem[write_ptr] <= in0_epoch;
        domain_mem[write_ptr] <= in0_domain; reg_mem[write_ptr] <= in0_reg;
        bank_mem[write_ptr] <= in0_bank; value_mem[write_ptr] <= in0_value;
        fflags_mem[write_ptr] <= in0_fflags;
        write_ptr = write_ptr + 1'b1; offset = offset + 1;
      end
      if (in1_valid && !flush_kills_entry(in1_seq_id, in1_epoch)) begin
        seq_mem[write_ptr] <= in1_seq_id; epoch_mem[write_ptr] <= in1_epoch;
        domain_mem[write_ptr] <= in1_domain; reg_mem[write_ptr] <= in1_reg;
        bank_mem[write_ptr] <= in1_bank; value_mem[write_ptr] <= in1_value;
        fflags_mem[write_ptr] <= in1_fflags;
        write_ptr = write_ptr + 1'b1; offset = offset + 1;
      end
      if (in2_valid && !flush_kills_entry(in2_seq_id, in2_epoch)) begin
        seq_mem[write_ptr] <= in2_seq_id; epoch_mem[write_ptr] <= in2_epoch;
        domain_mem[write_ptr] <= in2_domain; reg_mem[write_ptr] <= in2_reg;
        bank_mem[write_ptr] <= in2_bank; value_mem[write_ptr] <= in2_value;
        fflags_mem[write_ptr] <= in2_fflags;
        write_ptr = write_ptr + 1'b1; offset = offset + 1;
      end
      if (in3_valid && !flush_kills_entry(in3_seq_id, in3_epoch)) begin
        seq_mem[write_ptr] <= in3_seq_id; epoch_mem[write_ptr] <= in3_epoch;
        domain_mem[write_ptr] <= in3_domain; reg_mem[write_ptr] <= in3_reg;
        bank_mem[write_ptr] <= in3_bank; value_mem[write_ptr] <= in3_value;
        fflags_mem[write_ptr] <= in3_fflags;
        write_ptr = write_ptr + 1'b1; offset = offset + 1;
      end
      if (in4_valid && !flush_kills_entry(in4_seq_id, in4_epoch)) begin
        seq_mem[write_ptr] <= in4_seq_id; epoch_mem[write_ptr] <= in4_epoch;
        domain_mem[write_ptr] <= in4_domain; reg_mem[write_ptr] <= in4_reg;
        bank_mem[write_ptr] <= in4_bank; value_mem[write_ptr] <= in4_value;
        fflags_mem[write_ptr] <= in4_fflags;
        write_ptr = write_ptr + 1'b1; offset = offset + 1;
      end
      if (flush)
        head_r <= 0;
      tail_r <= write_ptr;
      count_r <= compact_count + offset;
`ifdef IVERILOG_SIM
      if ((compact_count + offset) > max_count_r) begin
        max_count_r <= compact_count + offset;
        $display("EDGE_FPU_COMPLETE_QUEUE_MAX_OCCUPANCY %0d", compact_count + offset);
      end
      if ((compact_count + offset) > DEPTH) begin
        $display("EDGE_FPU_COMPLETE_QUEUE_OVERFLOW");
        $finish;
      end
`endif
    end
  end
endmodule
