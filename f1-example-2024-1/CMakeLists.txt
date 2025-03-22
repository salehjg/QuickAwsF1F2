cmake_minimum_required(VERSION 3.20)

#print PATH env variable
message(STATUS "PATH = $ENV{PATH}")

# This is absolutely necessary to use the Vitis CMake functions
set(PROGRAM_PLATFORM_PART "xcvu9p-flga2104-2-e" CACHE INTERNAL "F1 part number")

# for clangd
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(HelloWorld)

message("${CMAKE_MODULE_PATH}")
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CMAKE_SOURCE_DIR}/hlslib/cmake)
find_package(Vitis REQUIRED)

add_executable(MyHostExecutable main.cpp)
include_directories(${Vitis_INCLUDE_DIRS} ${CMAKE_SOURCE_DIR}/hlslib/include)
target_link_libraries(MyHostExecutable ${Vitis_LIBRARIES})

# Will populate the "hw", "hw_emu", and "synthesis" targets
add_vitis_kernel(MyKernel FILES kernel.cpp)

# You cannot use the path to the xpfm file. It should be the name.
# The name can be obtained by running: `paltforminfo --list`
add_vitis_program(MyKernel "xilinx_aws-vu9p-f1_shell-v04261818_201920_4")

