cmake_minimum_required(VERSION 3.20)
project(edge_e3 LANGUAGES NONE)

set(EDGE_E3_SCALAR_FILELIST
  "${CMAKE_CURRENT_LIST_DIR}/edge_core/filelists/edge_core_edge32_top_verilator.fl")

find_program(EDGE_E3_VERILATOR verilator)
if(EDGE_E3_VERILATOR)
  add_custom_target(edge_e3_scalar_top_lint
    COMMAND "${EDGE_E3_VERILATOR}" --lint-only -Wno-fatal
            --top-module edge_core_edge32_top
            -f "$<SHELL_PATH:${EDGE_E3_SCALAR_FILELIST}>"
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    COMMENT "Linting E3 Edge-32 scalar product top"
    VERBATIM)
endif()

# Product software validation is owned by the maintained Edge-32 harnesses.
# E3 supplies ASIC configuration, accelerator composition and the include/ SDK.
