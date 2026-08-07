// Accelerator-to-scalar completed-value snapshot table.
module edge_reverse_snapshot #(
  parameter DEPTH = 2,
  parameter ID_WIDTH = 1,
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter VALUE_WIDTH = 64
) (
  input  wire                       forever_cpuclk,
  input  wire                       cpurst_b,

  input  wire                       alloc_valid,
  output wire                       alloc_ready,
  output wire [ID_WIDTH-1:0]        alloc_id,
  input  wire [SEQ_ID_WIDTH-1:0]    alloc_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     alloc_epoch,

  input  wire                       write_valid,
  output wire                       write_ready,
  input  wire [ID_WIDTH-1:0]        write_id,
  input  wire [VALUE_WIDTH-1:0]     write_value,

  input  wire [ID_WIDTH-1:0]        read_id,
  output wire                       read_ready,
  output wire [VALUE_WIDTH-1:0]     read_value,
  input  wire                       consume_valid,
  input  wire [ID_WIDTH-1:0]        consume_id,

  input  wire                       redirect_kill_valid,
  input  wire [SEQ_ID_WIDTH-1:0]    redirect_kill_seq_id,
  input  wire [EPOCH_WIDTH-1:0]     redirect_kill_epoch,

  output wire [DEPTH-1:0]           debug_owned,
  output wire [DEPTH-1:0]           debug_value_valid
);

reg [DEPTH-1:0] owned_q;
reg [DEPTH-1:0] value_valid_q;
reg [SEQ_ID_WIDTH-1:0] owner_seq_id_q [0:DEPTH-1];
reg [EPOCH_WIDTH-1:0] owner_epoch_q [0:DEPTH-1];
reg [VALUE_WIDTH-1:0] value_q [0:DEPTH-1];

reg free_found;
reg [ID_WIDTH-1:0] free_id;
integer scan_i;
always @* begin
  free_found = 1'b0;
  free_id = {ID_WIDTH{1'b0}};
  for (scan_i = 0; scan_i < DEPTH; scan_i = scan_i + 1) begin
    if (!owned_q[scan_i] && !free_found) begin
      free_found = 1'b1;
      free_id = scan_i[ID_WIDTH-1:0];
    end
  end
end

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

assign alloc_ready = free_found;
assign alloc_id = free_id;
assign write_ready = owned_q[write_id];
assign read_ready = owned_q[read_id] && value_valid_q[read_id];
assign read_value = value_q[read_id];
assign debug_owned = owned_q;
assign debug_value_valid = value_valid_q;

integer i;
always @(posedge forever_cpuclk or negedge cpurst_b) begin
  if (!cpurst_b) begin
    owned_q <= {DEPTH{1'b0}};
    value_valid_q <= {DEPTH{1'b0}};
    for (i = 0; i < DEPTH; i = i + 1) begin
      owner_seq_id_q[i] <= {SEQ_ID_WIDTH{1'b0}};
      owner_epoch_q[i] <= {EPOCH_WIDTH{1'b0}};
      value_q[i] <= {VALUE_WIDTH{1'b0}};
    end
  end else begin
    if (alloc_valid && alloc_ready) begin
      owned_q[alloc_id] <= 1'b1;
      value_valid_q[alloc_id] <= 1'b0;
      owner_seq_id_q[alloc_id] <= alloc_seq_id;
      owner_epoch_q[alloc_id] <= alloc_epoch;
    end

    if (write_valid && write_ready) begin
      value_q[write_id] <= write_value;
      value_valid_q[write_id] <= 1'b1;
    end

    if (consume_valid && owned_q[consume_id]) begin
      owned_q[consume_id] <= 1'b0;
      value_valid_q[consume_id] <= 1'b0;
    end

    if (redirect_kill_valid) begin
      for (i = 0; i < DEPTH; i = i + 1) begin
        if (owned_q[i] &&
            (owner_epoch_q[i] == redirect_kill_epoch) &&
            seq_is_younger(owner_seq_id_q[i], redirect_kill_seq_id)) begin
          owned_q[i] <= 1'b0;
          value_valid_q[i] <= 1'b0;
        end
      end
    end
  end
end

endmodule
