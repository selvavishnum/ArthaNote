cmake_minimum_required(VERSION 3.22.1)

project("arthanote")

# Stub shared library — compiled only to enforce 16KB ELF page alignment.
# Android 15+ devices require all native .so files to be aligned to 16KB
# memory page boundaries. These linker flags set both the max and common
# page sizes to 16384 bytes, satisfying the Play Store compatibility check.
add_library(${CMAKE_PROJECT_NAME} SHARED stub.cpp)

target_link_options(${CMAKE_PROJECT_NAME} PRIVATE
    "-Wl,-z,max-page-size=16384"
    "-Wl,-z,common-page-size=16384"
)

find_library(log-lib log)
target_link_libraries(${CMAKE_PROJECT_NAME} ${log-lib})
