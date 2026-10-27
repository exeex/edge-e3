// BF22 dot x BF20 scale: 14x12 unsigned product, then normalize/BF22 RNE.
// Two register cuts, II=1. Payload is unreset; validity owns observation.
module edge_tensor_scale_mul(
 input wire clk,rst_b,in_valid,
 input wire [31:0] dot_i,input wire [19:0] scale_i,
 output reg out_valid,output reg [31:0] result_o
);
wire [13:0] am={dot_i[30:23]!=0,dot_i[22:10]};
wire [11:0] bm={scale_i[18:11]!=0,scale_i[10:0]};
reg [25:0] product;
reg signed [11:0] exponent_q;
reg sign_q,nan_q,valid_q;
reg [4:0] msb;
reg [26:0] normalized;
reg [14:0] rounded;
reg signed [12:0] exponent;
reg [31:0] result;
integer j;
always @* begin
 msb=0;
 for(j=0;j<26;j=j+1)if(product[j])msb=5'(j);
 normalized={1'b0,product} << (26-msb);
 rounded={1'b0,normalized[26:13]} +
         {14'b0,(normalized[12] && ((|normalized[11:0]) || normalized[13]))};
 exponent=13'(exponent_q)+13'({1'b0,msb})+13'd127+13'(rounded[14]);
 result={sign_q,31'b0};
 if(nan_q)result=32'h7fc00000;
 else if(product!=0 && exponent>0)begin
  if(exponent>=255)result={sign_q,8'hff,23'b0};
  else result={sign_q,exponent[7:0],rounded[14]?rounded[13:1]:rounded[12:0],10'b0};
 end
end
always @(posedge clk)begin
 product<=am*bm;
 exponent_q<=(dot_i[30:23]==0?-12'sd126:$signed({4'b0,dot_i[30:23]})-12'sd127)
            +(scale_i[18:11]==0?-12'sd126:$signed({4'b0,scale_i[18:11]})-12'sd127)-12'sd24;
 sign_q<=dot_i[31]^scale_i[19];nan_q<=dot_i[30:23]==255 || scale_i[18:11]==255;
 result_o<=result;
end
always @(posedge clk or negedge rst_b)
 if(!rst_b)begin valid_q<=0;out_valid<=0;end
 else begin valid_q<=in_valid;out_valid<=valid_q;end
endmodule
