cmake_minimum_required(VERSION 3.10.2)

project(pancyo_sweph)

# Android 15/16の16KBページサイズ端末でもロードできるELF配置にする。
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")

set(SWISSEPH_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/swisseph")

add_library(
    pancyo_sweph
    SHARED
    pancyo_sweph_bridge.c
    "${SWISSEPH_DIR}/swedate.c"
    "${SWISSEPH_DIR}/swehouse.c"
    "${SWISSEPH_DIR}/swejpl.c"
    "${SWISSEPH_DIR}/swemmoon.c"
    "${SWISSEPH_DIR}/swemplan.c"
    "${SWISSEPH_DIR}/sweph.c"
    "${SWISSEPH_DIR}/swephlib.c"
    "${SWISSEPH_DIR}/swecl.c"
    "${SWISSEPH_DIR}/swehel.c"
)

target_include_directories(pancyo_sweph PRIVATE "${SWISSEPH_DIR}")
target_compile_options(pancyo_sweph PRIVATE -fvisibility=hidden)
target_link_libraries(pancyo_sweph m)
