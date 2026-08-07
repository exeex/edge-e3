// Combinational bank/phase policy for paired scalar D-cache requests.
module edge_dcache_pair_predictor #(
  parameter VALUE_WIDTH = 64
) (
  input  wire                   phase,
  input  wire                   mem_active,

  input  wire                   load0_valid,
  input  wire [VALUE_WIDTH-1:0] load0_addr,
  input  wire                   load1_valid,
  input  wire [VALUE_WIDTH-1:0] load1_addr,
  input  wire                   load_metadata_hit,
  input  wire                   load_dirty_conflict,
  input  wire                   load_backend_blocked,
  input  wire                   load1_same_line,
  output wire                   load0_ready,
  output wire                   load1_ready,
  output wire                   load1_same_bank_conflict,

  input  wire                   store0_valid,
  input  wire [VALUE_WIDTH-1:0] store0_addr,
  input  wire                   store1_valid,
  input  wire [VALUE_WIDTH-1:0] store1_addr,
  input  wire                   store_backend_blocked,
  input  wire                   store1_same_line,
  output wire                   store0_ready,
  output wire                   store1_ready,
  output wire                   store1_same_bank_conflict
);

  wire load0_slot_open;
  wire load1_slot_open;
  wire store0_slot_open;
  wire store1_slot_open;
  wire [1:0] load0_bank;
  wire [1:0] load1_bank;
  wire [1:0] store0_bank;
  wire [1:0] store1_bank;

  assign load0_bank = load0_addr[4:3];
  assign load1_bank = load1_addr[4:3];
  assign store0_bank = store0_addr[4:3];
  assign store1_bank = store1_addr[4:3];

  assign load0_slot_open = !mem_active || load0_addr[4] == phase;
  assign load1_slot_open = !mem_active || load1_addr[4] == phase;
  assign store0_slot_open = !mem_active || store0_addr[4] == phase;
  assign store1_slot_open = !mem_active || store1_addr[4] == phase;

  assign load1_same_bank_conflict =
    load0_valid && load1_valid && (load0_bank == load1_bank);
  assign store1_same_bank_conflict =
    store0_valid && store1_valid && (store0_bank == store1_bank);

  assign load0_ready = !load_backend_blocked && load0_slot_open;
  assign load1_ready =
    load0_valid && load0_ready && load1_valid &&
    load_metadata_hit && !load_dirty_conflict && load1_same_line &&
    load1_slot_open && !load1_same_bank_conflict;

  assign store0_ready = !store_backend_blocked && store0_slot_open;
  assign store1_ready =
    store0_valid && store0_ready && store1_valid &&
    store1_same_line && store1_slot_open && !store1_same_bank_conflict;

endmodule
