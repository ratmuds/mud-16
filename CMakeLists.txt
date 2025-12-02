cmake_minimum_required(VERSION 3.20)
project(mud16 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Project settings
set(TOP_MODULE ppu)
set(VERILOG_SOURCES ${CMAKE_SOURCE_DIR}/ppu.sv)
set(OBJ_DIR ${CMAKE_BINARY_DIR}/verilated)

# Find Verilator
find_program(VERILATOR_EXECUTABLE verilator
    HINTS ENV VERILATOR_ROOT
    PATH_SUFFIXES bin
)
if(NOT VERILATOR_EXECUTABLE)
    message(FATAL_ERROR "Verilator not found. Please install Verilator.")
endif()

# Get Verilator root for includes
execute_process(
    COMMAND ${VERILATOR_EXECUTABLE} --getenv VERILATOR_ROOT
    OUTPUT_VARIABLE VERILATOR_ROOT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
message(STATUS "Verilator root: ${VERILATOR_ROOT}")

# Fetch Raylib
include(FetchContent)
FetchContent_Declare(
    raylib
    GIT_REPOSITORY https://github.com/raysan5/raylib.git
    GIT_TAG 5.0
    GIT_SHALLOW TRUE
)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_GAMES OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(raylib)

# Run Verilator at configure time to generate sources
message(STATUS "Running Verilator...")
file(MAKE_DIRECTORY ${OBJ_DIR})
execute_process(
    COMMAND ${VERILATOR_EXECUTABLE}
        --cc ${VERILOG_SOURCES}
        --top-module ${TOP_MODULE}
        --Mdir ${OBJ_DIR}
        --trace
        -Wno-fatal
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    RESULT_VARIABLE VERILATOR_RESULT
)
if(NOT VERILATOR_RESULT EQUAL 0)
    message(FATAL_ERROR "Verilator failed!")
endif()

# Gather generated Verilator sources
file(GLOB VERILATOR_SOURCES
    ${OBJ_DIR}/V${TOP_MODULE}.cpp
    ${OBJ_DIR}/V${TOP_MODULE}___024root*.cpp
    ${OBJ_DIR}/V${TOP_MODULE}__Syms.cpp
    ${OBJ_DIR}/V${TOP_MODULE}__Trace*.cpp
)

# Create executable
add_executable(mud16
    ${CMAKE_SOURCE_DIR}/main.cpp
    ${VERILATOR_SOURCES}
    ${VERILATOR_ROOT}/include/verilated.cpp
    ${VERILATOR_ROOT}/include/verilated_vcd_c.cpp
    ${VERILATOR_ROOT}/include/verilated_threads.cpp
)

target_include_directories(mud16 PRIVATE
    ${OBJ_DIR}
    ${VERILATOR_ROOT}/include
    ${VERILATOR_ROOT}/include/vltstd
)

target_link_libraries(mud16 PRIVATE raylib)

# Platform-specific
if(WIN32)
    target_link_libraries(mud16 PRIVATE winmm)
elseif(APPLE)
    target_link_libraries(mud16 PRIVATE "-framework IOKit" "-framework Cocoa" "-framework OpenGL")
elseif(UNIX)
    target_link_libraries(mud16 PRIVATE m pthread dl GL X11)
endif()

# Custom target to re-run Verilator when Verilog changes
add_custom_target(verilate
    COMMAND ${VERILATOR_EXECUTABLE}
        --cc ${VERILOG_SOURCES}
        --top-module ${TOP_MODULE}
        --Mdir ${OBJ_DIR}
        --trace
        -Wno-fatal
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Re-running Verilator on ${VERILOG_SOURCES}"
)

# Run target
add_custom_target(run
    COMMAND mud16
    DEPENDS mud16
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Running mud-16"
)
