module edge_dtcm_addr_hit(
  dtcm_base,
  dtcm_enable,
  dtcm_hit,
  dtcm_mask,
  pa
);

parameter PA_WIDTH = 40;

input  [PA_WIDTH-1:0] dtcm_base;
input                 dtcm_enable;
input  [PA_WIDTH-1:0] dtcm_mask;
input  [PA_WIDTH-1:0] pa;
output                dtcm_hit;

assign dtcm_hit = dtcm_enable
               && ((pa[PA_WIDTH-1:0] & dtcm_mask[PA_WIDTH-1:0])
                == dtcm_base[PA_WIDTH-1:0]);

endmodule
