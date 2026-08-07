// Two-entry elastic load lookup boundary for edge_dcache.
module edge_dcache_lookup_buffer #(
  parameter SEQ_ID_WIDTH = 8,
  parameter EPOCH_WIDTH = 4,
  parameter VALUE_WIDTH = 64
) (
  input  wire                    clk,
  input  wire                    reset_b,
  input  wire                    redirect_valid,
  input  wire [SEQ_ID_WIDTH-1:0] redirect_seq_id,
  input  wire [EPOCH_WIDTH-1:0]  redirect_epoch,

  input  wire                    push_valid,
  output wire                    push_ready,
  input  wire [SEQ_ID_WIDTH-1:0] push_seq_id,
  input  wire [EPOCH_WIDTH-1:0]  push_epoch,
  input  wire [VALUE_WIDTH-1:0]  push_addr,
  input  wire [1:0]              push_size,
  input  wire                    push_signed,
  input  wire                    push1_valid,
  input  wire [SEQ_ID_WIDTH-1:0] push1_seq_id,
  input  wire [EPOCH_WIDTH-1:0]  push1_epoch,
  input  wire [VALUE_WIDTH-1:0]  push1_addr,
  input  wire [1:0]              push1_size,
  input  wire                    push1_signed,

  output wire                    lookup_valid,
  output wire [SEQ_ID_WIDTH-1:0] lookup_seq_id,
  output wire [EPOCH_WIDTH-1:0]  lookup_epoch,
  output wire [VALUE_WIDTH-1:0]  lookup_addr,
  output wire [1:0]              lookup_size,
  output wire                    lookup_signed,
  output wire                    lookup1_valid,
  output wire [SEQ_ID_WIDTH-1:0] lookup1_seq_id,
  output wire [EPOCH_WIDTH-1:0]  lookup1_epoch,
  output wire [VALUE_WIDTH-1:0]  lookup1_addr,
  output wire [1:0]              lookup1_size,
  output wire                    lookup1_signed,
  input  wire                    lookup_pop,
  input  wire                    lookup1_pop,
  input  wire                    lookup_park,
  input  wire                    retry_parked,
  output wire                    empty,
  output wire [1:0]              count
);
  reg valid_q [0:1];
  reg parked_q [0:1];
  reg lane1_valid_q [0:1];
  reg [SEQ_ID_WIDTH-1:0] seq_q [0:1];
  reg [EPOCH_WIDTH-1:0] epoch_q [0:1];
  reg [VALUE_WIDTH-1:0] addr_q [0:1];
  reg [1:0] size_q [0:1];
  reg signed_q [0:1];
  reg [SEQ_ID_WIDTH-1:0] seq1_q [0:1];
  reg [EPOCH_WIDTH-1:0] epoch1_q [0:1];
  reg [VALUE_WIDTH-1:0] addr1_q [0:1];
  reg [1:0] size1_q [0:1];
  reg signed1_q [0:1];
  wire bypass = !valid_q[0] && push_valid;
  wire select1 = valid_q[0] && parked_q[0] && valid_q[1] && !parked_q[1];
  wire push_fire = push_valid && push_ready;
  wire kill0 = redirect_valid && valid_q[0] &&
    epoch_q[0] == redirect_epoch && seq_is_younger(seq_q[0], redirect_seq_id);
  wire kill1 = redirect_valid && valid_q[1] &&
    epoch_q[1] == redirect_epoch && seq_is_younger(seq_q[1], redirect_seq_id);
  wire kill0_lane1 = redirect_valid && lane1_valid_q[0] &&
    epoch1_q[0] == redirect_epoch && seq_is_younger(seq1_q[0], redirect_seq_id);
  wire kill1_lane1 = redirect_valid && lane1_valid_q[1] &&
    epoch1_q[1] == redirect_epoch && seq_is_younger(seq1_q[1], redirect_seq_id);
  wire push_kill_lane0 = redirect_valid && push_valid &&
    push_epoch == redirect_epoch &&
    seq_is_younger(push_seq_id, redirect_seq_id);
  wire push_kill_lane1 = redirect_valid && push1_valid &&
    push1_epoch == redirect_epoch &&
    seq_is_younger(push1_seq_id, redirect_seq_id);
  wire selected_kill_lane0 = bypass ? push_kill_lane0 :
                             (select1 ? kill1 : kill0);
  wire selected_kill_lane1 = bypass ? push_kill_lane1 :
                             (select1 ? kill1_lane1 : kill0_lane1);

  assign count = {1'b0, valid_q[0]} + {1'b0, valid_q[1]};
  assign empty = count == 2'd0;
  assign push_ready = !valid_q[1];
  assign lookup_valid = (bypass ? push_valid :
                         (select1 ? valid_q[1] : valid_q[0])) &&
                        !selected_kill_lane0;
  assign lookup_seq_id = bypass ? push_seq_id :
                         (select1 ? seq_q[1] : seq_q[0]);
  assign lookup_epoch = bypass ? push_epoch :
                        (select1 ? epoch_q[1] : epoch_q[0]);
  assign lookup_addr = bypass ? push_addr :
                       (select1 ? addr_q[1] : addr_q[0]);
  assign lookup_size = bypass ? push_size :
                       (select1 ? size_q[1] : size_q[0]);
  assign lookup_signed = bypass ? push_signed :
                         (select1 ? signed_q[1] : signed_q[0]);
  assign lookup1_valid = (bypass ? push1_valid :
                          (select1 ? lane1_valid_q[1] : lane1_valid_q[0])) &&
                         !selected_kill_lane0 && !selected_kill_lane1;
  assign lookup1_seq_id = bypass ? push1_seq_id :
                          (select1 ? seq1_q[1] : seq1_q[0]);
  assign lookup1_epoch = bypass ? push1_epoch :
                         (select1 ? epoch1_q[1] : epoch1_q[0]);
  assign lookup1_addr = bypass ? push1_addr :
                        (select1 ? addr1_q[1] : addr1_q[0]);
  assign lookup1_size = bypass ? push1_size :
                        (select1 ? size1_q[1] : size1_q[0]);
  assign lookup1_signed = bypass ? push1_signed :
                          (select1 ? signed1_q[1] : signed1_q[0]);

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

  task capture_entry;
    input integer slot;
    begin
      valid_q[slot] <= 1'b1;
      parked_q[slot] <= 1'b0;
      seq_q[slot] <= push_seq_id;
      epoch_q[slot] <= push_epoch;
      addr_q[slot] <= push_addr;
      size_q[slot] <= push_size;
      signed_q[slot] <= push_signed;
      lane1_valid_q[slot] <= push1_valid && !push_kill_lane1;
      seq1_q[slot] <= push1_seq_id;
      epoch1_q[slot] <= push1_epoch;
      addr1_q[slot] <= push1_addr;
      size1_q[slot] <= push1_size;
      signed1_q[slot] <= push1_signed;
    end
  endtask

  integer i;
  always @(posedge clk or negedge reset_b) begin
    if (!reset_b) begin
      for (i = 0; i < 2; i = i + 1) begin
        valid_q[i] <= 1'b0;
        parked_q[i] <= 1'b0;
        lane1_valid_q[i] <= 1'b0;
      end
    end else begin
      if (retry_parked) begin
        parked_q[0] <= 1'b0;
        parked_q[1] <= 1'b0;
      end
      if (lookup_park)
        parked_q[select1] <= 1'b1;
      if (lookup_pop && lookup1_valid && !lookup1_pop) begin
        if (select1) begin
          seq_q[1] <= seq1_q[1]; epoch_q[1] <= epoch1_q[1];
          addr_q[1] <= addr1_q[1]; size_q[1] <= size1_q[1];
          signed_q[1] <= signed1_q[1]; lane1_valid_q[1] <= 1'b0;
          parked_q[1] <= 1'b0;
        end else begin
          seq_q[0] <= seq1_q[0]; epoch_q[0] <= epoch1_q[0];
          addr_q[0] <= addr1_q[0]; size_q[0] <= size1_q[0];
          signed_q[0] <= signed1_q[0]; lane1_valid_q[0] <= 1'b0;
          parked_q[0] <= 1'b0;
        end
      end else if (lookup_pop) begin
        if (select1) begin
          valid_q[1] <= 1'b0;
          parked_q[1] <= 1'b0;
        end else begin
          valid_q[0] <= valid_q[1];
          parked_q[0] <= parked_q[1];
          lane1_valid_q[0] <= lane1_valid_q[1];
          seq_q[0] <= seq_q[1]; epoch_q[0] <= epoch_q[1];
          addr_q[0] <= addr_q[1]; size_q[0] <= size_q[1];
          signed_q[0] <= signed_q[1];
          seq1_q[0] <= seq1_q[1]; epoch1_q[0] <= epoch1_q[1];
          addr1_q[0] <= addr1_q[1]; size1_q[0] <= size1_q[1];
          signed1_q[0] <= signed1_q[1];
          valid_q[1] <= 1'b0;
          parked_q[1] <= 1'b0;
        end
      end
      if (push_fire && !push_kill_lane0 && !(bypass && lookup_pop)) begin
        if (!valid_q[0] || (lookup_pop && !select1 && !valid_q[1]))
          capture_entry(0);
        else if (lookup_pop && !select1)
          capture_entry(1);
        else
          capture_entry(1);
      end
      if (bypass && lookup_pop && lookup1_valid && !lookup1_pop) begin
        valid_q[0] <= 1'b1;
        parked_q[0] <= 1'b0;
        lane1_valid_q[0] <= 1'b0;
        seq_q[0] <= push1_seq_id;
        epoch_q[0] <= push1_epoch;
        addr_q[0] <= push1_addr;
        size_q[0] <= push1_size;
        signed_q[0] <= push1_signed;
      end
      if (kill0) begin valid_q[0] <= 1'b0; parked_q[0] <= 1'b0; end
      else if (kill0_lane1) lane1_valid_q[0] <= 1'b0;
      if (kill1) begin valid_q[1] <= 1'b0; parked_q[1] <= 1'b0; end
      else if (kill1_lane1) lane1_valid_q[1] <= 1'b0;
      if (!valid_q[0] && valid_q[1] && !kill1) begin
        valid_q[0] <= 1'b1; parked_q[0] <= parked_q[1];
        lane1_valid_q[0] <= lane1_valid_q[1];
        seq_q[0] <= seq_q[1]; epoch_q[0] <= epoch_q[1];
        addr_q[0] <= addr_q[1]; size_q[0] <= size_q[1];
        signed_q[0] <= signed_q[1];
        seq1_q[0] <= seq1_q[1]; epoch1_q[0] <= epoch1_q[1];
        addr1_q[0] <= addr1_q[1]; size1_q[0] <= size1_q[1];
        signed1_q[0] <= signed1_q[1]; valid_q[1] <= 1'b0;
      end
      if (!valid_q[0] && !valid_q[1] && push_fire && !push_kill_lane0 &&
          !(bypass && lookup_pop))
        capture_entry(0);
    end
  end
endmodule
