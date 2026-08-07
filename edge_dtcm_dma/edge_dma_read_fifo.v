// SRAM-friendly AXI-read response FIFO for the DTCM DMA write path.
module edge_dma_read_fifo #(
  parameter DEPTH = 16,
  parameter PTR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH),
  parameter ROW_COUNT = DEPTH / 2,
  parameter ROW_WIDTH = (ROW_COUNT <= 2) ? 1 : $clog2(ROW_COUNT)
) (
  input  wire         clk,
  input  wire         reset_b,
  input  wire         push_valid,
  output wire         push_ready,
  input  wire [127:0] push_data,
  input  wire [15:0]  push_wstrb,
  input  wire [15:0]  push_meta,
  output wire         pop_valid,
  input  wire         pop_ready,
  output wire [127:0] pop_data,
  output wire [15:0]  pop_wstrb,
  output wire [15:0]  pop_meta,
  output wire [PTR_WIDTH:0] occupancy
);

  // Even beats use banks 0/1; odd beats use banks 2/3. This matches the
  // macro-friendly 4x64 organization used by the D-cache data array.
  reg [63:0] bank0_q [0:ROW_COUNT-1];
  reg [63:0] bank1_q [0:ROW_COUNT-1];
  reg [63:0] bank2_q [0:ROW_COUNT-1];
  reg [63:0] bank3_q [0:ROW_COUNT-1];
  reg [15:0] strb_even_q [0:ROW_COUNT-1];
  reg [15:0] strb_odd_q [0:ROW_COUNT-1];
  reg [15:0] meta_even_q [0:ROW_COUNT-1];
  reg [15:0] meta_odd_q [0:ROW_COUNT-1];

  reg         input_valid_q;
  reg [127:0] input_data_q;
  reg [15:0]  input_wstrb_q;
  reg [15:0]  input_meta_q;
  reg         output_valid_q;
  reg [127:0] output_data_q;
  reg [15:0]  output_wstrb_q;
  reg [15:0]  output_meta_q;
  reg [PTR_WIDTH-1:0] write_ptr_q;
  reg [PTR_WIDTH-1:0] read_ptr_q;
  reg [PTR_WIDTH:0] memory_count_q;

  wire output_take = output_valid_q && pop_ready;
  wire output_slot_open = !output_valid_q || output_take;
  wire memory_full = memory_count_q == DEPTH[PTR_WIDTH:0];
  wire write_half = write_ptr_q[0];
  wire read_half = read_ptr_q[0];
  wire write_fire_pre = input_valid_q && !memory_full;
  wire read_bank_conflict = write_fire_pre && (write_half == read_half);
  wire read_fire = output_slot_open && (memory_count_q != 0) &&
                   !read_bank_conflict;
  wire write_fire = write_fire_pre;
  wire input_take = push_valid && push_ready;
  wire [ROW_WIDTH-1:0] write_row = write_ptr_q[PTR_WIDTH-1:1];
  wire [ROW_WIDTH-1:0] read_row = read_ptr_q[PTR_WIDTH-1:1];

  assign push_ready = !input_valid_q || write_fire;
  assign pop_valid = output_valid_q;
  assign pop_data = output_data_q;
  assign pop_wstrb = output_wstrb_q;
  assign pop_meta = output_meta_q;
  assign occupancy = memory_count_q + input_valid_q + output_valid_q;

  always @(posedge clk or negedge reset_b) begin
    if (!reset_b) begin
      input_valid_q <= 1'b0;
      input_data_q <= 128'b0;
      input_wstrb_q <= 16'b0;
      input_meta_q <= 16'b0;
      output_valid_q <= 1'b0;
      output_data_q <= 128'b0;
      output_wstrb_q <= 16'b0;
      output_meta_q <= 16'b0;
      write_ptr_q <= {PTR_WIDTH{1'b0}};
      read_ptr_q <= {PTR_WIDTH{1'b0}};
      memory_count_q <= {(PTR_WIDTH+1){1'b0}};
    end else begin
      if (input_take) begin
        input_valid_q <= 1'b1;
        input_data_q <= push_data;
        input_wstrb_q <= push_wstrb;
        input_meta_q <= push_meta;
      end else if (write_fire) begin
        input_valid_q <= 1'b0;
      end

      if (output_take)
        output_valid_q <= 1'b0;
      if (read_fire) begin
        output_valid_q <= 1'b1;
        if (read_half) begin
          output_data_q <= {bank3_q[read_row], bank2_q[read_row]};
          output_wstrb_q <= strb_odd_q[read_row];
          output_meta_q <= meta_odd_q[read_row];
        end else begin
          output_data_q <= {bank1_q[read_row], bank0_q[read_row]};
          output_wstrb_q <= strb_even_q[read_row];
          output_meta_q <= meta_even_q[read_row];
        end
        read_ptr_q <= read_ptr_q + {{PTR_WIDTH-1{1'b0}}, 1'b1};
      end

      if (write_fire) begin
        if (write_half) begin
          bank2_q[write_row] <= input_data_q[63:0];
          bank3_q[write_row] <= input_data_q[127:64];
          strb_odd_q[write_row] <= input_wstrb_q;
          meta_odd_q[write_row] <= input_meta_q;
        end else begin
          bank0_q[write_row] <= input_data_q[63:0];
          bank1_q[write_row] <= input_data_q[127:64];
          strb_even_q[write_row] <= input_wstrb_q;
          meta_even_q[write_row] <= input_meta_q;
        end
        write_ptr_q <= write_ptr_q + {{PTR_WIDTH-1{1'b0}}, 1'b1};
      end

      case ({write_fire, read_fire})
        2'b10: memory_count_q <= memory_count_q + 1'b1;
        2'b01: memory_count_q <= memory_count_q - 1'b1;
        default: memory_count_q <= memory_count_q;
      endcase
    end
  end

endmodule
