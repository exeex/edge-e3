proc edge_dot8_set_pin_region {region patterns} {
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

# Tensor input stream enters from the north.
edge_dot8_set_pin_region "top:*" {
  in_valid
  bf16_vec_i*
}

# WLD-owned weight wires enter from the east.
edge_dot8_set_pin_region "right:*" {
  weight_bf16_mode_i
  int8_vec_i*
  bf16_weight_vec_i*
}

# Result stream leaves toward the west-side consumer.
edge_dot8_set_pin_region "left:*" {
  out_valid
  bf16_o*
}

# Clock/reset and RSUM sequence controls use the remaining south face.
edge_dot8_set_pin_region "bottom:*" {
  clk
  rst_b
  rsum_enable_i
  rsum_first_i
  rsum_last_i
}
