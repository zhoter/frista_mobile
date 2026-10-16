cmake_minimum_required(VERSION 3.10.2)
project("frista_dlib" CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(-O3 -fexceptions -frtti)
add_definitions(-DDLIB_NO_GUI_SUPPORT)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/dlib
)

add_library(frista_dlib SHARED
    native_dlib.cpp
    dlib/dlib/all/source.cpp
)

target_link_libraries(frista_dlib
    android
    jnigraphics
    log
)
