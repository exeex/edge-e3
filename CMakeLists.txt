cmake_minimum_required(VERSION 3.20)
project(edge_e3 LANGUAGES NONE)

set(EDGE_E3_TOP_MODULE "edge_core_top" CACHE STRING
  "Production edge-e3 top module")
set(EDGE_E3_PRODUCTION_FILELIST
  "${CMAKE_CURRENT_LIST_DIR}/edge_core/filelists/edge_core_top_verilator_prod.fl"
  CACHE FILEPATH "Production edge-e3 RTL filelist")
set(EDGE_E3_DEBUG_FILELIST
  "${CMAKE_CURRENT_LIST_DIR}/edge_core/filelists/edge_core_top_verilator_debug.fl"
  CACHE FILEPATH "Debug edge-e3 RTL filelist")
