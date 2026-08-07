// Two-candidate classified lookup launch policy for edge_dcache.
module edge_dcache_lookup_scheduler (
  input  wire oldest_index,
  input  wire candidate0_valid,
  input  wire candidate0_classified,
  input  wire candidate0_hit,
  input  wire candidate0_phase_match,
  input  wire candidate1_valid,
  input  wire candidate1_classified,
  input  wire candidate1_hit,
  input  wire candidate1_phase_match,
  input  wire hit_ready,
  input  wire miss_ready,
  output wire select_valid,
  output wire select_index,
  output wire select_hit,
  output wire park_candidate0
);
  wire candidate0_hit_launchable = candidate0_valid &&
    candidate0_classified && candidate0_hit && candidate0_phase_match &&
    hit_ready;
  wire candidate0_miss_launchable = candidate0_valid &&
    candidate0_classified && !candidate0_hit && miss_ready;
  wire candidate0_miss_blocked = candidate0_valid &&
    candidate0_classified && !candidate0_hit && !miss_ready;
  wire candidate1_hit_launchable = candidate1_valid &&
    candidate1_classified && candidate1_hit && candidate1_phase_match &&
    hit_ready;
  wire candidate1_miss_launchable = candidate1_valid &&
    candidate1_classified && !candidate1_hit && miss_ready;
  wire candidate1_miss_blocked = candidate1_valid &&
    candidate1_classified && !candidate1_hit && !miss_ready;
  wire oldest0 = candidate0_valid && (!candidate1_valid || !oldest_index);
  wire oldest1 = candidate1_valid && (!candidate0_valid || oldest_index);
  wire select0 = (oldest0 &&
      (candidate0_hit_launchable || candidate0_miss_launchable)) ||
    (oldest1 && candidate1_miss_blocked && candidate0_hit_launchable);
  wire select1 = (oldest1 &&
      (candidate1_hit_launchable || candidate1_miss_launchable)) ||
    (oldest0 && candidate0_miss_blocked && candidate1_hit_launchable);

  assign select_valid = select0 || select1;
  assign select_index = select1;
  assign select_hit = select_index ? candidate1_hit : candidate0_hit;
  assign park_candidate0 = (oldest0 && candidate0_miss_blocked) ||
                           (oldest1 && candidate1_miss_blocked);
endmodule
