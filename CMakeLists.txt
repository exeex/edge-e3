cmake_minimum_required(VERSION 3.20)
project(edge_e3 LANGUAGES NONE)

set(EDGE_E3_SCALAR_CORE "rv64-lite" CACHE STRING
  "Scalar core for the E3 lite product wrapper: rv64-lite or edge32")
set_property(CACHE EDGE_E3_SCALAR_CORE PROPERTY STRINGS rv64-lite edge32)
if(EDGE_E3_SCALAR_CORE STREQUAL "edge32")
  set(EDGE_E3_LITE_FILELIST
    "${CMAKE_CURRENT_LIST_DIR}/edge_core/filelists/edge_core_edge32_top_verilator.fl")
  set(EDGE_E3_SCALAR_TOP_MODULE "edge_core_edge32_top")
elseif(EDGE_E3_SCALAR_CORE STREQUAL "rv64-lite")
  set(EDGE_E3_LITE_FILELIST
    "${CMAKE_CURRENT_LIST_DIR}/edge_core/filelists/edge_core_lite_top_verilator.fl")
  set(EDGE_E3_SCALAR_TOP_MODULE "edge_core_lite_top")
else()
  message(FATAL_ERROR "EDGE_E3_SCALAR_CORE must be rv64-lite or edge32")
endif()

find_program(EDGE_E3_VERILATOR verilator)
if(EDGE_E3_VERILATOR)
  add_custom_target(edge_e3_scalar_top_lint
    COMMAND "${EDGE_E3_VERILATOR}" --lint-only -Wno-fatal
            --top-module "${EDGE_E3_SCALAR_TOP_MODULE}"
            -f "$<SHELL_PATH:${EDGE_E3_LITE_FILELIST}>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    COMMENT "Linting E3 ${EDGE_E3_SCALAR_CORE} scalar product top"
    VERBATIM)
endif()

set(EDGE_E3_TOP_MODULE "edge_core_top" CACHE STRING
  "Production edge-e3 top module")
set(EDGE_E3_PRODUCTION_FILELIST
  "${CMAKE_CURRENT_LIST_DIR}/edge_core/filelists/edge_core_top_verilator_prod.fl"
  CACHE FILEPATH "Production edge-e3 RTL filelist")
set(EDGE_E3_DEBUG_FILELIST
  "${CMAKE_CURRENT_LIST_DIR}/edge_core/filelists/edge_core_top_verilator_debug.fl"
  CACHE FILEPATH "Debug edge-e3 RTL filelist")
