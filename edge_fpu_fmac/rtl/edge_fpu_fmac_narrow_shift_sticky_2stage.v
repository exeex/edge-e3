module edge_fpu_fmac_narrow_shift_sticky_2stage(
  shift_in,
  shift_amt,
  shift_out
);

input   [26:0]  shift_in;
input   [12:0]  shift_amt;
output  [26:0]  shift_out;

reg     [26:0]  coarse_data;
reg     [26:0]  fine_data;
wire            shift_saturate;
wire    [2 :0]  coarse_amt;
wire    [2 :0]  fine_amt;
wire    [26:0]  shift_in;
wire    [12:0]  shift_amt;
wire    [26:0]  shift_out;

assign shift_saturate = shift_amt[12:0] >= 13'd27;
assign coarse_amt[2:0] = shift_amt[5:3];
assign fine_amt[2:0] = shift_amt[2:0];

always @(coarse_amt[2:0]
      or shift_in[26:0]
      or shift_saturate)
begin
  if(shift_saturate) begin
    coarse_data[26:0] = {26'b0, |shift_in[26:0]};
  end
  else begin
    case(coarse_amt[2:0])
      3'd0:    coarse_data[26:0] = shift_in[26:0];
      3'd1:    coarse_data[26:0] = {8'b0,  shift_in[26:9],
                                    shift_in[8]  || (|shift_in[7:0])};
      3'd2:    coarse_data[26:0] = {16'b0, shift_in[26:17],
                                    shift_in[16] || (|shift_in[15:0])};
      3'd3:    coarse_data[26:0] = {24'b0, shift_in[26:25],
                                    shift_in[24] || (|shift_in[23:0])};
      default: coarse_data[26:0] = {26'b0, |shift_in[26:0]};
    endcase
  end
end

always @(coarse_data[26:0]
      or fine_amt[2:0]
      or shift_saturate)
begin
  if(shift_saturate) begin
    fine_data[26:0] = coarse_data[26:0];
  end
  else begin
    case(fine_amt[2:0])
      3'd0:    fine_data[26:0] = coarse_data[26:0];
      3'd1:    fine_data[26:0] = {1'b0, coarse_data[26:2],
                                  coarse_data[1] || coarse_data[0]};
      3'd2:    fine_data[26:0] = {2'b0, coarse_data[26:3],
                                  coarse_data[2] || (|coarse_data[1:0])};
      3'd3:    fine_data[26:0] = {3'b0, coarse_data[26:4],
                                  coarse_data[3] || (|coarse_data[2:0])};
      3'd4:    fine_data[26:0] = {4'b0, coarse_data[26:5],
                                  coarse_data[4] || (|coarse_data[3:0])};
      3'd5:    fine_data[26:0] = {5'b0, coarse_data[26:6],
                                  coarse_data[5] || (|coarse_data[4:0])};
      3'd6:    fine_data[26:0] = {6'b0, coarse_data[26:7],
                                  coarse_data[6] || (|coarse_data[5:0])};
      3'd7:    fine_data[26:0] = {7'b0, coarse_data[26:8],
                                  coarse_data[7] || (|coarse_data[6:0])};
      default: fine_data[26:0] = {27{1'bx}};
    endcase
  end
end

assign shift_out[26:0] = fine_data[26:0];

endmodule
