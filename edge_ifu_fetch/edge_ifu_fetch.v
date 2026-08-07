// Minimal 128-bit instruction fetch packet source.
module edge_ifu_fetch #(
  parameter PC_WIDTH    = 40,
  parameter EPOCH_WIDTH = 4
) (
  input  wire                    forever_cpuclk,
  input  wire                    cpurst_b,

  input  wire [PC_WIDTH-1:0]     boot_pc,
  input  wire                    fetch_start,
  input  wire                    fetch_stop,

  input  wire                    redirect_valid,
  input  wire [PC_WIDTH-1:0]     redirect_pc,
  input  wire [EPOCH_WIDTH-1:0]  redirect_epoch,

  output wire                    imem_req_valid,
  input  wire                    imem_req_ready,
  output wire [PC_WIDTH-1:0]     imem_req_addr,

  input  wire                    imem_resp_valid,
  output wire                    imem_resp_ready,
  input  wire [127:0]            imem_resp_bits,

  output wire                    fetch_valid,
  input  wire                    fetch_ready,
  output wire [PC_WIDTH-1:0]     fetch_block_pc,
  // First valid 32-bit parcel within the naturally aligned 128-bit response.
  output wire [1:0]              fetch_start_word,
  output wire [127:0]            fetch_bits,
  output wire [EPOCH_WIDTH-1:0]  fetch_epoch
);

  reg                    req_valid_r;
  reg [PC_WIDTH-1:0]     req_addr_r;
  reg [1:0]              req_start_word_r;
  reg [EPOCH_WIDTH-1:0]  req_epoch_r;

  reg                    outstanding_valid_r;
  reg                    outstanding_stale_r;
  reg [PC_WIDTH-1:0]     outstanding_block_pc_r;
  reg [1:0]              outstanding_start_word_r;
  reg [EPOCH_WIDTH-1:0]  outstanding_epoch_r;

  reg                    fetch_valid_r;
  reg [PC_WIDTH-1:0]     fetch_block_pc_r;
  reg [1:0]              fetch_start_word_r;
  reg [127:0]            fetch_bits_r;
  reg [EPOCH_WIDTH-1:0]  fetch_epoch_r;

  reg                    skid_valid_r;
  reg [PC_WIDTH-1:0]     skid_block_pc_r;
  reg [1:0]              skid_start_word_r;
  reg [127:0]            skid_bits_r;
  reg [EPOCH_WIDTH-1:0]  skid_epoch_r;

  wire [PC_WIDTH-1:0] boot_block_pc;
  wire [PC_WIDTH-1:0] redirect_block_pc;
  wire [PC_WIDTH-1:0] sequential_block_pc;
  wire req_fire;
  wire redirect_req_fire;
  wire resp_fire;
  wire fetch_fire;
  wire fetch_bypass_valid;
  wire fetch_bypass_fire;
  wire can_accept_response;
  wire can_drain_response;
  wire response_is_stale;
  wire resp_to_primary;
  wire resp_to_skid;
  wire skid_promote;
  wire [PC_WIDTH-1:0] response_sequential_block_pc;

  assign boot_block_pc = {boot_pc[PC_WIDTH-1:4], 4'b0000};
  assign redirect_block_pc = {redirect_pc[PC_WIDTH-1:4], 4'b0000};
  assign sequential_block_pc = fetch_block_pc_r + {{(PC_WIDTH-5){1'b0}}, 5'd16};

  assign req_fire = imem_req_valid && imem_req_ready;
  assign redirect_req_fire = redirect_valid && req_fire;
  assign response_is_stale = outstanding_stale_r || redirect_valid;
  assign can_accept_response = outstanding_stale_r || redirect_valid ||
                               !fetch_valid_r || fetch_ready;
  assign can_drain_response = response_is_stale || can_accept_response ||
                              !skid_valid_r;
  assign resp_fire = outstanding_valid_r && imem_resp_valid &&
                     can_drain_response;
  assign fetch_fire = fetch_valid_r && fetch_ready;
  assign fetch_bypass_valid = resp_fire && !response_is_stale && !fetch_valid_r;
  assign fetch_bypass_fire = fetch_bypass_valid && fetch_ready;
  assign resp_to_primary = resp_fire && !response_is_stale &&
                           can_accept_response;
  assign resp_to_skid = resp_fire && !response_is_stale &&
                        !can_accept_response;
  assign skid_promote = skid_valid_r && (!fetch_valid_r || fetch_ready) &&
                        !resp_to_primary;
  assign response_sequential_block_pc =
    outstanding_block_pc_r + {{(PC_WIDTH-5){1'b0}}, 5'd16};

  assign imem_req_valid = redirect_valid ?
                          (!outstanding_valid_r || resp_fire) :
                          (req_valid_r && !outstanding_valid_r &&
                           can_accept_response && !skid_valid_r);
  assign imem_req_addr = redirect_valid ? redirect_block_pc : req_addr_r;
  assign imem_resp_ready = outstanding_valid_r && can_drain_response;

  assign fetch_valid = fetch_valid_r || fetch_bypass_valid;
  assign fetch_block_pc = fetch_valid_r ? fetch_block_pc_r : outstanding_block_pc_r;
  assign fetch_start_word = fetch_valid_r ? fetch_start_word_r :
                                             outstanding_start_word_r;
  assign fetch_bits = fetch_valid_r ? fetch_bits_r : imem_resp_bits;
  assign fetch_epoch = fetch_valid_r ? fetch_epoch_r : outstanding_epoch_r;

  always @(posedge forever_cpuclk or negedge cpurst_b) begin
    if (!cpurst_b) begin
      req_valid_r <= 1'b0;
      req_addr_r <= {PC_WIDTH{1'b0}};
      req_start_word_r <= 2'd0;
      req_epoch_r <= {EPOCH_WIDTH{1'b0}};
      outstanding_valid_r <= 1'b0;
      outstanding_stale_r <= 1'b0;
      outstanding_block_pc_r <= {PC_WIDTH{1'b0}};
      outstanding_start_word_r <= 2'd0;
      outstanding_epoch_r <= {EPOCH_WIDTH{1'b0}};
      fetch_valid_r <= 1'b0;
      fetch_block_pc_r <= {PC_WIDTH{1'b0}};
      fetch_start_word_r <= 2'd0;
      fetch_bits_r <= 128'd0;
      fetch_epoch_r <= {EPOCH_WIDTH{1'b0}};
      skid_valid_r <= 1'b0;
      skid_block_pc_r <= {PC_WIDTH{1'b0}};
      skid_start_word_r <= 2'd0;
      skid_bits_r <= 128'd0;
      skid_epoch_r <= {EPOCH_WIDTH{1'b0}};
    end else if (fetch_stop) begin
      req_valid_r <= 1'b0;
      outstanding_valid_r <= 1'b0;
      outstanding_stale_r <= 1'b0;
      fetch_valid_r <= 1'b0;
      skid_valid_r <= 1'b0;
    end else if (fetch_start) begin
      req_valid_r <= 1'b1;
      req_addr_r <= boot_block_pc;
      req_start_word_r <= boot_pc[3:2];
      req_epoch_r <= {EPOCH_WIDTH{1'b0}};
      outstanding_valid_r <= 1'b0;
      outstanding_stale_r <= 1'b0;
      fetch_valid_r <= 1'b0;
      skid_valid_r <= 1'b0;
    end else begin
      if (redirect_valid) begin
        req_addr_r <= redirect_block_pc;
        req_start_word_r <= redirect_pc[3:2];
        req_epoch_r <= redirect_epoch;
        fetch_valid_r <= 1'b0;
        skid_valid_r <= 1'b0;

        if (redirect_req_fire) begin
          req_valid_r <= 1'b0;
          outstanding_valid_r <= 1'b1;
          outstanding_stale_r <= 1'b0;
          outstanding_block_pc_r <= redirect_block_pc;
          outstanding_start_word_r <= redirect_pc[3:2];
          outstanding_epoch_r <= redirect_epoch;
        end else begin
          req_valid_r <= 1'b1;
        end

        if (outstanding_valid_r && resp_fire && !redirect_req_fire) begin
          outstanding_valid_r <= 1'b0;
          outstanding_stale_r <= 1'b0;
        end else if (outstanding_valid_r && !redirect_req_fire) begin
          outstanding_stale_r <= 1'b1;
        end
      end else if (req_fire) begin
        req_valid_r <= 1'b0;
        outstanding_valid_r <= 1'b1;
        outstanding_stale_r <= 1'b0;
        outstanding_block_pc_r <= req_addr_r;
        outstanding_start_word_r <= req_start_word_r;
        outstanding_epoch_r <= req_epoch_r;
      end else if (fetch_fire && !req_valid_r && !outstanding_valid_r) begin
        req_valid_r <= 1'b1;
        req_addr_r <= sequential_block_pc;
        req_start_word_r <= 2'd0;
        req_epoch_r <= fetch_epoch_r;
      end

      if (resp_fire && !redirect_req_fire) begin
        outstanding_valid_r <= 1'b0;
        outstanding_stale_r <= 1'b0;
        if (resp_to_primary) begin
          if (fetch_bypass_fire) begin
            fetch_valid_r <= 1'b0;
            req_valid_r <= 1'b1;
            req_addr_r <= response_sequential_block_pc;
            req_start_word_r <= 2'd0;
            req_epoch_r <= outstanding_epoch_r;
          end else begin
            fetch_valid_r <= 1'b1;
            fetch_block_pc_r <= outstanding_block_pc_r;
            fetch_start_word_r <= outstanding_start_word_r;
            fetch_bits_r <= imem_resp_bits;
            fetch_epoch_r <= outstanding_epoch_r;
          end
        end else if (resp_to_skid) begin
          skid_valid_r <= 1'b1;
          skid_block_pc_r <= outstanding_block_pc_r;
          skid_start_word_r <= outstanding_start_word_r;
          skid_bits_r <= imem_resp_bits;
          skid_epoch_r <= outstanding_epoch_r;
        end
      end else if (skid_promote) begin
        fetch_valid_r <= 1'b1;
        fetch_block_pc_r <= skid_block_pc_r;
        fetch_start_word_r <= skid_start_word_r;
        fetch_bits_r <= skid_bits_r;
        fetch_epoch_r <= skid_epoch_r;
        skid_valid_r <= 1'b0;
      end else if (fetch_fire) begin
        fetch_valid_r <= 1'b0;
      end
    end
  end

endmodule
