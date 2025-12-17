cmake_minimum_required(VERSION 3.20)
project(mud16 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Project settings
set(TOP_MODULE ppu)
set(VERILOG_SOURCE ${CMAKE_SOURCE_DIR}/ppu.sv)
set(OBJ_DIR ${CMAKE_BINARY_DIR}/verilated)

# Find Verilator
find_program(VERILATOR_EXECUTABLE verilator HINTS ENV VERILATOR_ROOT PATH_SUFFIXES bin)
if(NOT VERILATOR_EXECUTABLE)
    message(FATAL_ERROR "Verilator not found. Please ensure 'verilator' is in your PATH or set VERILATOR_ROOT.")
endif()

# Determine VERILATOR_ROOT
if(NOT DEFINED VERILATOR_ROOT)
    execute_process(COMMAND ${VERILATOR_EXECUTABLE} --getenv VERILATOR_ROOT
                    OUTPUT_VARIABLE VERILATOR_ROOT
                    OUTPUT_STRIP_TRAILING_WHITESPACE)
endif()

message(STATUS "Verilator Executable: ${VERILATOR_EXECUTABLE}")
message(STATUS "Verilator Root: ${VERILATOR_ROOT}")

# Fetch Raylib
include(FetchContent)
FetchContent_Declare(raylib GIT_REPOSITORY https://github.com/raysan5/raylib.git GIT_TAG 5.0 GIT_SHALLOW TRUE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_GAMES OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(raylib)

# Create output directory
file(MAKE_DIRECTORY ${OBJ_DIR})

# Helper to run verilator
function(run_verilator)
    execute_process(
        COMMAND ${VERILATOR_EXECUTABLE}
            --cc ${VERILOG_SOURCE}
            --top-module ${TOP_MODULE}
            --Mdir ${OBJ_DIR}
            --trace
            -Wno-fatal
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        RESULT_VARIABLE VERILATOR_RESULT
    )
    if(NOT VERILATOR_RESULT EQUAL 0)
        message(FATAL_ERROR "Verilator failed during configuration phase.")
    endif()
endfunction()

# Run Verilator at configure time if sources are missing to populate the file list
if(NOT EXISTS "${OBJ_DIR}/V${TOP_MODULE}.cpp")
    message(STATUS "Generating initial Verilator files...")
    run_verilator()
endif()

# Glob the generated files
file(GLOB VERILATOR_GENERATED_SOURCES "${OBJ_DIR}/V${TOP_MODULE}*.cpp")
file(GLOB VERILATOR_GENERATED_HEADERS "${OBJ_DIR}/V${TOP_MODULE}*.h")

# Add a custom command to re-run Verilator at build time if ppu.sv changes
add_custom_command(
    OUTPUT ${VERILATOR_GENERATED_SOURCES} ${VERILATOR_GENERATED_HEADERS}
    COMMAND ${VERILATOR_EXECUTABLE}
        --cc ${VERILOG_SOURCE}
        --top-module ${TOP_MODULE}
        --Mdir ${OBJ_DIR}
        --trace
        -Wno-fatal
    DEPENDS ${VERILOG_SOURCE}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Re-running Verilator..."
)

# Verilator runtime library sources
set(VERILATOR_RUNTIME_SOURCES
    ${VERILATOR_ROOT}/include/verilated.cpp
    ${VERILATOR_ROOT}/include/verilated_vcd_c.cpp
    ${VERILATOR_ROOT}/include/verilated_threads.cpp
)

add_executable(mud16
    ${CMAKE_SOURCE_DIR}/main.cpp
    ${CMAKE_SOURCE_DIR}/vram_init_data.cpp
    ${VERILATOR_GENERATED_SOURCES}
    ${VERILATOR_RUNTIME_SOURCES}
)

target_include_directories(mud16 PRIVATE
    ${OBJ_DIR}
    include
    ${VERILATOR_ROOT}/include
    ${VERILATOR_ROOT}/include/vltstd
)

# Suppress warnings common in Verilated code
if(MSVC)
    target_compile_options(mud16 PRIVATE /wd4244 /wd4267 /wd4100)
else()
    target_compile_options(mud16 PRIVATE -Wno-aligned-new -Wno-parentheses-equality -Wno-sign-compare)
endif()

target_link_libraries(mud16 PRIVATE raylib)

if(WIN32)
    target_link_libraries(mud16 PRIVATE winmm)
elseif(UNIX AND NOT APPLE)
    target_link_libraries(mud16 PRIVATE m pthread dl GL X11)
endif()
