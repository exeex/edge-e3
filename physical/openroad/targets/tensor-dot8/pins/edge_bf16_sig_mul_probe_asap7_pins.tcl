proc edge_sigmul_set_pin_region {region patterns} {
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

edge_sigmul_set_pin_region "top:*"   {in_valid lhs_sig_i*}
edge_sigmul_set_pin_region "right:*" {rhs_sig_i*}
edge_sigmul_set_pin_region "left:*"  {out_valid product_o*}
edge_sigmul_set_pin_region "bottom:*" {clk rst_b}
