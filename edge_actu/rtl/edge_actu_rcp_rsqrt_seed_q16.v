`timescale 1ns/1ps

module edge_actu_rcp_rsqrt_seed_q16 (
  input  wire [4:0]  mant_idx,
  input  wire        rsqrt_mode,
  input  wire        exponent_odd,
  output reg  [16:0] seed_q16
);

always @* begin
  case ({rsqrt_mode, rsqrt_mode && exponent_odd, mant_idx})
    7'h00: seed_q16 = 17'h0fc10; 7'h01: seed_q16 = 17'h0f490;
    7'h02: seed_q16 = 17'h0ed70; 7'h03: seed_q16 = 17'h0e6c0;
    7'h04: seed_q16 = 17'h0e070; 7'h05: seed_q16 = 17'h0da70;
    7'h06: seed_q16 = 17'h0d4c0; 7'h07: seed_q16 = 17'h0cf60;
    7'h08: seed_q16 = 17'h0ca40; 7'h09: seed_q16 = 17'h0c560;
    7'h0a: seed_q16 = 17'h0c0c0; 7'h0b: seed_q16 = 17'h0bc50;
    7'h0c: seed_q16 = 17'h0b810; 7'h0d: seed_q16 = 17'h0b410;
    7'h0e: seed_q16 = 17'h0b030; 7'h0f: seed_q16 = 17'h0ac70;
    7'h10: seed_q16 = 17'h0a8f0; 7'h11: seed_q16 = 17'h0a580;
    7'h12: seed_q16 = 17'h0a230; 7'h13: seed_q16 = 17'h09f10;
    7'h14: seed_q16 = 17'h09c10; 7'h15: seed_q16 = 17'h09920;
    7'h16: seed_q16 = 17'h09650; 7'h17: seed_q16 = 17'h093a0;
    7'h18: seed_q16 = 17'h09100; 7'h19: seed_q16 = 17'h08e80;
    7'h1a: seed_q16 = 17'h08c10; 7'h1b: seed_q16 = 17'h089b0;
    7'h1c: seed_q16 = 17'h08760; 7'h1d: seed_q16 = 17'h08530;
    7'h1e: seed_q16 = 17'h08310; 7'h1f: seed_q16 = 17'h08100;

    7'h40: seed_q16 = 17'h0fe00; 7'h41: seed_q16 = 17'h0fa30;
    7'h42: seed_q16 = 17'h0f690; 7'h43: seed_q16 = 17'h0f310;
    7'h44: seed_q16 = 17'h0efb0; 7'h45: seed_q16 = 17'h0ec80;
    7'h46: seed_q16 = 17'h0e960; 7'h47: seed_q16 = 17'h0e670;
    7'h48: seed_q16 = 17'h0e390; 7'h49: seed_q16 = 17'h0e0d0;
    7'h4a: seed_q16 = 17'h0de20; 7'h4b: seed_q16 = 17'h0db90;
    7'h4c: seed_q16 = 17'h0d910; 7'h4d: seed_q16 = 17'h0d6b0;
    7'h4e: seed_q16 = 17'h0d460; 7'h4f: seed_q16 = 17'h0d220;
    7'h50: seed_q16 = 17'h0cff0; 7'h51: seed_q16 = 17'h0cdd0;
    7'h52: seed_q16 = 17'h0cbd0; 7'h53: seed_q16 = 17'h0c9d0;
    7'h54: seed_q16 = 17'h0c7e0; 7'h55: seed_q16 = 17'h0c600;
    7'h56: seed_q16 = 17'h0c430; 7'h57: seed_q16 = 17'h0c260;
    7'h58: seed_q16 = 17'h0c0b0; 7'h59: seed_q16 = 17'h0bf00;
    7'h5a: seed_q16 = 17'h0bd50; 7'h5b: seed_q16 = 17'h0bbc0;
    7'h5c: seed_q16 = 17'h0ba30; 7'h5d: seed_q16 = 17'h0b8b0;
    7'h5e: seed_q16 = 17'h0b730; 7'h5f: seed_q16 = 17'h0b5c0;

    7'h60: seed_q16 = 17'h0b3a0; 7'h61: seed_q16 = 17'h0b0f0;
    7'h62: seed_q16 = 17'h0ae50; 7'h63: seed_q16 = 17'h0abe0;
    7'h64: seed_q16 = 17'h0a980; 7'h65: seed_q16 = 17'h0a730;
    7'h66: seed_q16 = 17'h0a510; 7'h67: seed_q16 = 17'h0a2f0;
    7'h68: seed_q16 = 17'h0a0e0; 7'h69: seed_q16 = 17'h09ef0;
    7'h6a: seed_q16 = 17'h09d10; 7'h6b: seed_q16 = 17'h09b40;
    7'h6c: seed_q16 = 17'h09980; 7'h6d: seed_q16 = 17'h097d0;
    7'h6e: seed_q16 = 17'h09630; 7'h6f: seed_q16 = 17'h09490;
    7'h70: seed_q16 = 17'h09310; 7'h71: seed_q16 = 17'h09190;
    7'h72: seed_q16 = 17'h09020; 7'h73: seed_q16 = 17'h08eb0;
    7'h74: seed_q16 = 17'h08d50; 7'h75: seed_q16 = 17'h08c00;
    7'h76: seed_q16 = 17'h08ab0; 7'h77: seed_q16 = 17'h08970;
    7'h78: seed_q16 = 17'h08840; 7'h79: seed_q16 = 17'h08710;
    7'h7a: seed_q16 = 17'h085e0; 7'h7b: seed_q16 = 17'h084c0;
    7'h7c: seed_q16 = 17'h083a0; 7'h7d: seed_q16 = 17'h08290;
    7'h7e: seed_q16 = 17'h08180; 7'h7f: seed_q16 = 17'h08080;
    default: seed_q16 = 17'h10000;
  endcase
end

endmodule
