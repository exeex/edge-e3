module edge_tensor_input_window_lane #(
  parameter LANE_WIDTH = 16,
  parameter SLOT_COUNT = 4,
  parameter SLOT_WIDTH = 2
) (
  input  wire                  clk,
  input  wire                  bank_write,
  input  wire                  write_bank,
  input  wire [SLOT_WIDTH-1:0] write_slot,
  input  wire [LANE_WIDTH-1:0] write_data,
  input  wire                  active_bank,
  input  wire [SLOT_WIDTH-1:0] active_read_slot,
  output wire [LANE_WIDTH-1:0] active_read_data
);

reg [LANE_WIDTH-1:0] bank0_data_q [0:SLOT_COUNT-1];
reg [LANE_WIDTH-1:0] bank1_data_q [0:SLOT_COUNT-1];

assign active_read_data = active_bank
                        ? bank1_data_q[active_read_slot]
                        : bank0_data_q[active_read_slot];

always @(posedge clk) begin
  if (bank_write) begin
    if (write_bank)
      bank1_data_q[write_slot] <= write_data;
    else
      bank0_data_q[write_slot] <= write_data;
  end
end

endmodule

module edge_tensor_input_window #(
  parameter LANE_WIDTH = 16,
  parameter LANE_COUNT = 8,
  parameter SLOT_COUNT = 4,
  parameter SLOT_WIDTH = 2
) (
  input  wire                               clk,
  input  wire                               resetn,
  input  wire                               start,
  input  wire                               start_from_prefetch,
  input  wire                               active_issue,
  input  wire [SLOT_WIDTH-1:0]              active_issue_slot,
  input  wire                               prefetch_issue,
  input  wire [SLOT_WIDTH-1:0]              prefetch_issue_slot,
  input  wire                               response_write,
  input  wire                               response_prefetch,
  input  wire [SLOT_WIDTH-1:0]              response_slot,
  input  wire [(LANE_WIDTH*LANE_COUNT)-1:0] response_data,
  input  wire                               active_consume,
  input  wire [SLOT_WIDTH-1:0]              active_consume_slot,
  input  wire [SLOT_WIDTH-1:0]              active_read_slot,
  output wire [(LANE_WIDTH*LANE_COUNT)-1:0] active_read_data,
  output wire [SLOT_COUNT-1:0]              active_issued,
  output wire [SLOT_COUNT-1:0]              active_valid,
  output wire [SLOT_COUNT-1:0]              prefetch_issued,
  output wire [SLOT_COUNT-1:0]              prefetch_valid
);

reg active_bank_q;
reg [SLOT_COUNT-1:0] bank0_issued_q;
reg [SLOT_COUNT-1:0] bank0_valid_q;
reg [SLOT_COUNT-1:0] bank1_issued_q;
reg [SLOT_COUNT-1:0] bank1_valid_q;
wire response_bank = response_prefetch ? ~active_bank_q : active_bank_q;

assign active_issued = active_bank_q ? bank1_issued_q : bank0_issued_q;
assign active_valid = active_bank_q ? bank1_valid_q : bank0_valid_q;
assign prefetch_issued = active_bank_q ? bank0_issued_q : bank1_issued_q;
assign prefetch_valid = active_bank_q ? bank0_valid_q : bank1_valid_q;

genvar lane;
generate
  for (lane = 0; lane < LANE_COUNT; lane = lane + 1) begin : gen_lane
    edge_tensor_input_window_lane #(
      .LANE_WIDTH(LANE_WIDTH),
      .SLOT_COUNT(SLOT_COUNT),
      .SLOT_WIDTH(SLOT_WIDTH)
    ) lane_window (
      .clk(clk),
      .bank_write(response_write),
      .write_bank(response_bank),
      .write_slot(response_slot),
      .write_data(response_data[(lane*LANE_WIDTH) +: LANE_WIDTH]),
      .active_bank(active_bank_q),
      .active_read_slot(active_read_slot),
      .active_read_data(
          active_read_data[(lane*LANE_WIDTH) +: LANE_WIDTH])
    );
  end
endgenerate

always @(posedge clk or negedge resetn) begin
  if (!resetn) begin
    active_bank_q <= 1'b0;
    bank0_issued_q <= {SLOT_COUNT{1'b0}};
    bank0_valid_q <= {SLOT_COUNT{1'b0}};
    bank1_issued_q <= {SLOT_COUNT{1'b0}};
    bank1_valid_q <= {SLOT_COUNT{1'b0}};
  end else begin
    if (active_issue) begin
      if (active_bank_q)
        bank1_issued_q[active_issue_slot] <= 1'b1;
      else
        bank0_issued_q[active_issue_slot] <= 1'b1;
    end
    if (prefetch_issue) begin
      if (active_bank_q)
        bank0_issued_q[prefetch_issue_slot] <= 1'b1;
      else
        bank1_issued_q[prefetch_issue_slot] <= 1'b1;
    end
    if (response_write) begin
      if (response_bank)
        bank1_valid_q[response_slot] <= 1'b1;
      else
        bank0_valid_q[response_slot] <= 1'b1;
    end
    if (active_consume) begin
      if (active_bank_q) begin
        bank1_issued_q[active_consume_slot] <= 1'b0;
        bank1_valid_q[active_consume_slot] <= 1'b0;
      end else begin
        bank0_issued_q[active_consume_slot] <= 1'b0;
        bank0_valid_q[active_consume_slot] <= 1'b0;
      end
    end
    if (start) begin
      if (start_from_prefetch) begin
        active_bank_q <= ~active_bank_q;
        if (active_bank_q) begin
          bank1_issued_q <= {SLOT_COUNT{1'b0}};
          bank1_valid_q <= {SLOT_COUNT{1'b0}};
        end else begin
          bank0_issued_q <= {SLOT_COUNT{1'b0}};
          bank0_valid_q <= {SLOT_COUNT{1'b0}};
        end
      end else begin
        bank0_issued_q <= {SLOT_COUNT{1'b0}};
        bank0_valid_q <= {SLOT_COUNT{1'b0}};
        bank1_issued_q <= {SLOT_COUNT{1'b0}};
        bank1_valid_q <= {SLOT_COUNT{1'b0}};
      end
    end
  end
end

endmodule
