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

file(GLOB_RECURSE EDGE_E3_OBFUSCATE_RTL CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_LIST_DIR}/*.v"
  "${CMAKE_CURRENT_LIST_DIR}/../edge-rv/*.v")
set(EDGE_E3_OBFUSCATE_TOOL "${STAREDGE_ROOT}/tools/obfuscate_edge_e3.py")
set(EDGE_E3_OBFUSCATE_DIR "${STAREDGE_ROOT}/src/edge-e3enc")
set(EDGE_E3_OBFUSCATE_OUTPUTS
  "${EDGE_E3_OBFUSCATE_DIR}/edge_e3enc.v"
  "${EDGE_E3_OBFUSCATE_DIR}/edge_e3enc_sram.v"
  "${EDGE_E3_OBFUSCATE_DIR}/LICENSE.md"
  "${EDGE_E3_OBFUSCATE_DIR}/edge_rv_public.fl"
  "${EDGE_E3_OBFUSCATE_DIR}/edge_e3enc_nosram.fl"
  "${EDGE_E3_OBFUSCATE_DIR}/edge_e3enc_sram.fl"
  "${EDGE_E3_OBFUSCATE_DIR}/edge_e3enc_mixed.fl"
  "${EDGE_E3_OBFUSCATE_DIR}/manifest.json"
  "${EDGE_E3_OBFUSCATE_DIR}/README.md")

add_custom_command(
  OUTPUT ${EDGE_E3_OBFUSCATE_OUTPUTS}
  COMMAND "${Python3_EXECUTABLE}" "$<SHELL_PATH:${EDGE_E3_OBFUSCATE_TOOL}>"
    --private-root "$<SHELL_PATH:${CMAKE_CURRENT_LIST_DIR}>"
    --public-root "$<SHELL_PATH:${CMAKE_CURRENT_LIST_DIR}/../edge-rv>"
    --verilator "$<SHELL_PATH:${STAREDGE_VERILATOR}>"
  WORKING_DIRECTORY "${STAREDGE_ROOT}"
  DEPENDS
    ${EDGE_E3_OBFUSCATE_RTL}
    "${EDGE_E3_PRODUCTION_FILELIST}"
    "${STAREDGE_ROOT}/src/soc/logical/common/edge_soc_top.v"
    "${EDGE_E3_OBFUSCATE_TOOL}"
  COMMENT "Generating and validating obfuscated edge-e3 RTL"
  VERBATIM)

add_custom_target(edge_e3_obfuscate DEPENDS ${EDGE_E3_OBFUSCATE_OUTPUTS})
