`timescale 1ns/1ps

module edge_core_strided_dma_ctrl #(
  parameter ADDR_WIDTH = 40,
  parameter VALUE_WIDTH = 64
) (
  input  wire                    forever_cpuclk,
  input  wire                    cpurst_b,

  input  wire                    start_req,
  input  wire [VALUE_WIDTH-1:0]  start_src,
  input  wire [VALUE_WIDTH-1:0]  start_dst,
  input  wire [31:0]             start_len,
  input  wire [31:0]             start_x_stride,
  input  wire [31:0]             start_y_stride,
  input  wire [31:0]             start_x_count,
  input  wire [31:0]             start_y_count,
  input  wire [31:0]             start_total,

  input  wire                    dma_busy,
  input  wire                    edge_start_pending,
  input  wire                    tensor_start_pending,
  input  wire                    circular_launch,

  output wire                    launch,
  output wire [ADDR_WIDTH-1:0]   launch_src,
  output wire [ADDR_WIDTH-1:0]   launch_dst,
  output wire [31:0]             launch_len,
  output wire                    busy
);

  reg                    active_q;
  reg                    inflight_q;
  reg                    dma_busy_q;
  reg [VALUE_WIDTH-1:0]  src_q;
  reg [VALUE_WIDTH-1:0]  group_base_q;
  reg [VALUE_WIDTH-1:0]  dst_q;
  reg [31:0]             len_q;
  reg [31:0]             x_stride_q;
  reg [31:0]             y_stride_q;
  reg [31:0]             x_count_q;
  reg [31:0]             inner_q;
  reg [31:0]             total_q;
  reg [31:0]             issued_q;

  wire done_pulse = inflight_q && dma_busy_q && !dma_busy;

  assign launch = active_q && !inflight_q && (issued_q < total_q) &&
                  !dma_busy && !edge_start_pending &&
                  !tensor_start_pending && !circular_launch;
  assign launch_src[ADDR_WIDTH-1:0] = src_q[ADDR_WIDTH-1:0];
  assign launch_dst[ADDR_WIDTH-1:0] = dst_q[ADDR_WIDTH-1:0];
  assign launch_len[31:0] = len_q[31:0];
  assign busy = active_q || inflight_q;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      active_q <= 1'b0;
      inflight_q <= 1'b0;
      dma_busy_q <= 1'b0;
      src_q[VALUE_WIDTH-1:0] <= {VALUE_WIDTH{1'b0}};
      group_base_q[VALUE_WIDTH-1:0] <= {VALUE_WIDTH{1'b0}};
      dst_q[VALUE_WIDTH-1:0] <= {VALUE_WIDTH{1'b0}};
      len_q[31:0] <= 32'b0;
      x_stride_q[31:0] <= 32'b0;
      y_stride_q[31:0] <= 32'b0;
      x_count_q[31:0] <= 32'b0;
      inner_q[31:0] <= 32'b0;
      total_q[31:0] <= 32'b0;
      issued_q[31:0] <= 32'b0;
    end else begin
      dma_busy_q <= dma_busy;

      if (start_req) begin
        active_q <= (start_len != 32'b0) &&
                    (start_x_count != 32'b0) &&
                    (start_y_count != 32'b0);
        inflight_q <= 1'b0;
        src_q[VALUE_WIDTH-1:0] <= start_src[VALUE_WIDTH-1:0];
        group_base_q[VALUE_WIDTH-1:0] <= start_src[VALUE_WIDTH-1:0];
        dst_q[VALUE_WIDTH-1:0] <= start_dst[VALUE_WIDTH-1:0];
        len_q[31:0] <= start_len[31:0];
        x_stride_q[31:0] <= start_x_stride[31:0];
        y_stride_q[31:0] <= start_y_stride[31:0];
        x_count_q[31:0] <= start_x_count[31:0];
        inner_q[31:0] <= 32'b0;
        total_q[31:0] <= start_total[31:0];
        issued_q[31:0] <= 32'b0;
      end

      if (launch) begin
        inflight_q <= 1'b1;
        issued_q[31:0] <= issued_q[31:0] + 32'd1;
        if (inner_q[31:0] == (x_count_q[31:0] - 32'd1)) begin
          inner_q[31:0] <= 32'b0;
          group_base_q[VALUE_WIDTH-1:0] <=
            group_base_q[VALUE_WIDTH-1:0] +
            {{(VALUE_WIDTH-32){1'b0}}, y_stride_q[31:0]};
          src_q[VALUE_WIDTH-1:0] <=
            group_base_q[VALUE_WIDTH-1:0] +
            {{(VALUE_WIDTH-32){1'b0}}, y_stride_q[31:0]};
        end else begin
          inner_q[31:0] <= inner_q[31:0] + 32'd1;
          src_q[VALUE_WIDTH-1:0] <=
            src_q[VALUE_WIDTH-1:0] +
            {{(VALUE_WIDTH-32){1'b0}}, x_stride_q[31:0]};
        end
        dst_q[VALUE_WIDTH-1:0] <=
          dst_q[VALUE_WIDTH-1:0] +
          {{(VALUE_WIDTH-32){1'b0}}, len_q[31:0]};
      end

      if (done_pulse) begin
        inflight_q <= 1'b0;
        if (issued_q[31:0] >= total_q[31:0])
          active_q <= 1'b0;
      end
    end
  end

endmodule
