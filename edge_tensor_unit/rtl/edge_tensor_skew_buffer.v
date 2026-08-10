module edge_tensor_skew_lane #(
  parameter LANE_WIDTH = 16,
  parameter SLOT_COUNT = 4,
  parameter CFG_WIDTH  = 3
) (
  input  wire                  clk,
  input  wire                  resetn,
  input  wire [CFG_WIDTH-1:0]  tap_select,
  input  wire                  in_valid,
  input  wire [LANE_WIDTH-1:0] in_data,
  output wire                  out_valid,
  output wire [LANE_WIDTH-1:0] out_data
);

reg [SLOT_COUNT-1:0] slot_valid_q;
reg [LANE_WIDTH-1:0] slot_data_q [0:SLOT_COUNT-1];
integer slot;
localparam TAP_WIDTH = (SLOT_COUNT <= 2) ? 1 : $clog2(SLOT_COUNT);
wire [TAP_WIDTH-1:0] tap_index = tap_select[TAP_WIDTH-1:0];

assign out_valid = slot_valid_q[tap_index];
assign out_data  = slot_data_q[tap_index];

always @(posedge clk or negedge resetn) begin
  if (!resetn) begin
    slot_valid_q <= {SLOT_COUNT{1'b0}};
  end else begin
    slot_valid_q[0] <= in_valid;
    slot_data_q[0]  <= in_data;
    for (slot = 1; slot < SLOT_COUNT; slot = slot + 1) begin
      slot_valid_q[slot] <= slot_valid_q[slot-1];
      slot_data_q[slot]  <= slot_data_q[slot-1];
    end
  end
end

endmodule

module edge_tensor_skew_buffer #(
  parameter LANE_WIDTH = 16,
  parameter LANE_COUNT = 4,
  parameter SLOT_COUNT = 4,
  parameter CFG_WIDTH  = 3
) (
  input  wire                               clk,
  input  wire                               resetn,
  input  wire                               cfg_valid_i,
  input  wire [CFG_WIDTH-1:0]               cfg_extra_i,
  output reg                                cfg_valid_o,
  output reg  [CFG_WIDTH-1:0]               cfg_extra_o,
  input  wire                               in_valid,
  input  wire [(LANE_WIDTH*LANE_COUNT)-1:0] in_data,
  output wire                               out_valid,
  output wire [(LANE_WIDTH*LANE_COUNT)-1:0] out_data
);

localparam [CFG_WIDTH-1:0] EXTRA_CAPACITY = SLOT_COUNT - 1;

reg [CFG_WIDTH-1:0] tap_select_q;
wire [LANE_COUNT-1:0] lane_out_valid;

always @(posedge clk or negedge resetn) begin
  if (!resetn) begin
    tap_select_q <= {CFG_WIDTH{1'b0}};
    cfg_valid_o <= 1'b0;
    cfg_extra_o <= {CFG_WIDTH{1'b0}};
  end else begin
    cfg_valid_o <= cfg_valid_i;
    if (cfg_valid_i) begin
      if (cfg_extra_i > EXTRA_CAPACITY) begin
        tap_select_q <= EXTRA_CAPACITY;
        cfg_extra_o <= cfg_extra_i - EXTRA_CAPACITY;
      end else begin
        tap_select_q <= cfg_extra_i;
        cfg_extra_o <= {CFG_WIDTH{1'b0}};
      end
    end
  end
end

genvar lane;
generate
  for (lane = 0; lane < LANE_COUNT; lane = lane + 1) begin : gen_lane
    edge_tensor_skew_lane #(
      .LANE_WIDTH(LANE_WIDTH),
      .SLOT_COUNT(SLOT_COUNT),
      .CFG_WIDTH(CFG_WIDTH)
    ) lane_buffer (
      .clk      (clk),
      .resetn   (resetn),
      .tap_select(tap_select_q),
      .in_valid (in_valid),
      .in_data  (in_data[(lane*LANE_WIDTH) +: LANE_WIDTH]),
      .out_valid(lane_out_valid[lane]),
      .out_data (out_data[(lane*LANE_WIDTH) +: LANE_WIDTH])
    );
  end
endgenerate

assign out_valid = lane_out_valid[0];

endmodule
