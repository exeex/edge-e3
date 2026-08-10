// Four 128-bit circular lanes with six integer-width routing modes.
module edge_weight_circular4_mux6(
  clk, rst_b, start_i, start_ready_o, mode_i, busy_o, done_o,
  load_valid_i, load_ready_o, load_data_i,
  drain_valid_o, drain_ready_i, drain_data_o,
  drain_target_dot_o, drain_fill_slot_o
);
input clk, rst_b, start_i;
output start_ready_o, busy_o, done_o;
input [2:0] mode_i;
input load_valid_i;
output load_ready_o;
input [127:0] load_data_i;
output [3:0] drain_valid_o;
input [3:0] drain_ready_i;
output [127:0] drain_data_o;
output [11:0] drain_target_dot_o;
output [7:0] drain_fill_slot_o;

localparam MODE_N16=3'd0, MODE_T16=3'd1;
localparam MODE_N8 =3'd2, MODE_T8 =3'd3;
localparam MODE_N4 =3'd4, MODE_T4 =3'd5;

reg busy_q, done_q, load_complete_q, trans_half_q;
reg [2:0] mode_q, load_count_q, trans_group_q;
reg [31:0] data_mem [0:3][0:3];
reg [2:0] dot_mem [0:3][0:3];
reg [1:0] slot_mem [0:3][0:3];
reg [1:0] head_q [0:3], tail_q [0:3];
reg [2:0] count_q [0:3];
reg [3:0] select_comb;
reg [7:0] used_dot_comb;
reg [2:0] head_dot;
wire [3:0] dequeue = select_comb & drain_ready_i;
wire transpose_mode = mode_q[0];
wire load_accept = load_valid_i && load_ready_o;
integer lane_i;

function [3:0] expected_beats;
  input [2:0] mode;
  begin
    case (mode)
      MODE_N16,MODE_T16: expected_beats=4'd8;
      MODE_N8, MODE_T8:  expected_beats=4'd4;
      default:            expected_beats=4'd2;
    endcase
  end
endfunction

function [31:0] transpose_chunk;
  input [2:0] mode;
  input [2:0] target;
  input [127:0] beat0;
  input [127:0] beat1;
  integer row;
  begin
    transpose_chunk=0;
    case (mode)
      MODE_T16:
        transpose_chunk={beat1[target*16 +: 16],beat0[target*16 +: 16]};
      MODE_T8: begin
        for (row=0;row<2;row=row+1) begin
          transpose_chunk[row*8 +: 8]=beat0[(row*8+target)*8 +: 8];
          transpose_chunk[(row+2)*8 +: 8]=beat1[(row*8+target)*8 +: 8];
        end
      end
      MODE_T4: begin
        for (row=0;row<4;row=row+1) begin
          transpose_chunk[row*4 +: 4]=beat0[(row*8+target)*4 +: 4];
          transpose_chunk[(row+4)*4 +: 4]=beat1[(row*8+target)*4 +: 4];
        end
      end
      default: transpose_chunk=0;
    endcase
  end
endfunction

wire [127:0] trans_beat0 = {
  data_mem[3][tail_q[3]], data_mem[2][tail_q[2]],
  data_mem[1][tail_q[1]], data_mem[0][tail_q[0]]};
wire [3:0] beat_limit = expected_beats(mode_q);
wire [2:0] enqueue_count = transpose_mode ? (trans_half_q ? 3'd2 : 3'd0)
                                          : 3'd1;

always @(*) begin
  select_comb=0;
  used_dot_comb=0;
  for (lane_i=0;lane_i<4;lane_i=lane_i+1) begin
    head_dot=dot_mem[lane_i][head_q[lane_i]];
    if (count_q[lane_i] != 0 && !used_dot_comb[head_dot]) begin
      select_comb[lane_i]=1'b1;
      used_dot_comb[head_dot]=1'b1;
    end
  end
end

generate
  genvar lane_g;
  for (lane_g=0;lane_g<4;lane_g=lane_g+1) begin : GEN_DRAIN
    assign drain_valid_o[lane_g]=select_comb[lane_g];
    assign drain_data_o[lane_g*32 +: 32]=data_mem[lane_g][head_q[lane_g]];
    assign drain_target_dot_o[lane_g*3 +: 3]=dot_mem[lane_g][head_q[lane_g]];
    assign drain_fill_slot_o[lane_g*2 +: 2]=slot_mem[lane_g][head_q[lane_g]];
  end
endgenerate

assign start_ready_o=!busy_q;
assign busy_o=busy_q;
assign done_o=done_q;
assign load_ready_o=busy_q && !load_complete_q
  && ((!transpose_mode
       && ((count_q[0] < 4 || dequeue[0])
           && (count_q[1] < 4 || dequeue[1])
           && (count_q[2] < 4 || dequeue[2])
           && (count_q[3] < 4 || dequeue[3])))
      || (transpose_mode && !trans_half_q
          && count_q[0] < 4 && count_q[1] < 4
          && count_q[2] < 4 && count_q[3] < 4)
      || (transpose_mode && trans_half_q
          && ((count_q[0] <= 2 || (count_q[0] == 3 && dequeue[0]))
              && (count_q[1] <= 2 || (count_q[1] == 3 && dequeue[1]))
              && (count_q[2] <= 2 || (count_q[2] == 3 && dequeue[2]))
              && (count_q[3] <= 2 || (count_q[3] == 3 && dequeue[3])))));

always @(posedge clk or negedge rst_b) begin
  if (!rst_b) begin
    busy_q<=0; done_q<=0; load_complete_q<=0; trans_half_q<=0;
    mode_q<=0; load_count_q<=0; trans_group_q<=0;
    for (lane_i=0;lane_i<4;lane_i=lane_i+1) begin
      head_q[lane_i]<=0; tail_q[lane_i]<=0; count_q[lane_i]<=0;
    end
  end else begin
    done_q<=0;
    if (start_i && start_ready_o) begin
      busy_q<=1; load_complete_q<=0; trans_half_q<=0;
      mode_q<=mode_i; load_count_q<=0; trans_group_q<=0;
      for (lane_i=0;lane_i<4;lane_i=lane_i+1) begin
        head_q[lane_i]<=0; tail_q[lane_i]<=0; count_q[lane_i]<=0;
      end
    end else if (busy_q) begin
      for (lane_i=0;lane_i<4;lane_i=lane_i+1) begin
        if (dequeue[lane_i]) head_q[lane_i]<=head_q[lane_i]+2'd1;
        case ({load_accept && enqueue_count!=0,dequeue[lane_i]})
          2'b10: count_q[lane_i]<=count_q[lane_i]+enqueue_count;
          2'b01: count_q[lane_i]<=count_q[lane_i]-3'd1;
          2'b11: count_q[lane_i]<=count_q[lane_i]+enqueue_count-3'd1;
          default: begin end
        endcase
      end

      if (load_accept) begin
        load_count_q<=load_count_q+3'd1;
        if (load_count_q+1 >= beat_limit) load_complete_q<=1'b1;
        if (!transpose_mode) begin
          for (lane_i=0;lane_i<4;lane_i=lane_i+1) begin
            data_mem[lane_i][tail_q[lane_i]]<=load_data_i[lane_i*32 +: 32];
            if (mode_q==MODE_N16) begin
              dot_mem[lane_i][tail_q[lane_i]]<=load_count_q;
              slot_mem[lane_i][tail_q[lane_i]]<=lane_i[1:0];
            end else if (mode_q==MODE_N8) begin
              dot_mem[lane_i][tail_q[lane_i]]<={load_count_q[1:0],1'b0}+lane_i[1];
              slot_mem[lane_i][tail_q[lane_i]]<={1'b0,lane_i[0]};
            end else begin
              dot_mem[lane_i][tail_q[lane_i]]<={load_count_q[0],2'b00}+lane_i[1:0];
              slot_mem[lane_i][tail_q[lane_i]]<=0;
            end
            tail_q[lane_i]<=tail_q[lane_i]+2'd1;
          end
        end else if (!trans_half_q) begin
          for (lane_i=0;lane_i<4;lane_i=lane_i+1)
            data_mem[lane_i][tail_q[lane_i]]<=load_data_i[lane_i*32 +: 32];
          trans_half_q<=1'b1;
        end else begin
          for (lane_i=0;lane_i<4;lane_i=lane_i+1) begin
            data_mem[lane_i][tail_q[lane_i]]<=
                transpose_chunk(mode_q,lane_i*2,trans_beat0,load_data_i);
            dot_mem[lane_i][tail_q[lane_i]]<=lane_i*2;
            slot_mem[lane_i][tail_q[lane_i]]<=trans_group_q[1:0];
            data_mem[lane_i][tail_q[lane_i]+2'd1]<=
                transpose_chunk(mode_q,lane_i*2+1,trans_beat0,load_data_i);
            dot_mem[lane_i][tail_q[lane_i]+2'd1]<=lane_i*2+1;
            slot_mem[lane_i][tail_q[lane_i]+2'd1]<=trans_group_q[1:0];
            tail_q[lane_i]<=tail_q[lane_i]+2'd2;
          end
          trans_group_q<=trans_group_q+3'd1;
          trans_half_q<=1'b0;
        end
      end

      if (load_complete_q && !trans_half_q
          && count_q[0]==dequeue[0] && count_q[1]==dequeue[1]
          && count_q[2]==dequeue[2] && count_q[3]==dequeue[3]) begin
        busy_q<=0; done_q<=1;
      end
    end
  end
end
endmodule
