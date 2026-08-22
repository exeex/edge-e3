proc edge_weight_exp_lane_set_pin_region {region patterns} {
  set pins {}
  foreach pattern $patterns {
    set found [get_ports -quiet $pattern]
    if {[llength $found] > 0} {
      set pins [concat $pins $found]
    }
  }
  if {[llength $pins] > 0} {
    set_io_pin_constraint -region $region -pin_names $pins
  }
}

edge_weight_exp_lane_set_pin_region "top:*"    {in_valid_i activation_bf16_i*}
edge_weight_exp_lane_set_pin_region "right:*"  {wld_en_i wld_bank_i wld_weight_i*}
edge_weight_exp_lane_set_pin_region "left:*"   {out_valid_o product_sig_o* product_exp_o* product_sign_o product_nonzero_o}
edge_weight_exp_lane_set_pin_region "bottom:*" {clk rst_b active_bank_i}
