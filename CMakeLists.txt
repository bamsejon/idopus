cmake_minimum_required(VERSION 3.20)
project(idopus VERSION 0.7.1 LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# macOS ARM target
if(APPLE)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Build for Apple Silicon")
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "macOS 13+")
endif()

# Include paths
include_directories(${CMAKE_SOURCE_DIR}/include)

# --- Platform Abstraction Layer (PAL) ---
add_library(pal STATIC
    src/pal/pal_memory.c
    src/pal/pal_lists.c
    src/pal/pal_sync.c
    src/pal/pal_ipc.c
    src/pal/pal_strings.c
    src/pal/pal_file.c
)
target_link_libraries(pal PRIVATE pthread)

# --- Core library ---
add_library(core STATIC
    src/core/dir_entry.c
    src/core/dir_buffer.c
)
target_link_libraries(core PRIVATE pal)

# --- Test programs ---
add_executable(pal_test tests/pal_test.c)
target_link_libraries(pal_test PRIVATE pal)

add_executable(core_test tests/core_test.c)
target_link_libraries(core_test PRIVATE core pal)

# --- GUI app (macOS only) ---
if(APPLE)
    add_executable(idopus MACOSX_BUNDLE src/gui/AppDelegate.m)
    target_compile_options(idopus PRIVATE "-fobjc-arc")
    target_link_libraries(idopus PRIVATE core pal
        "-framework Cocoa"
        pthread
    )
    set_target_properties(idopus PROPERTIES
        OUTPUT_NAME "iDOpus"
        MACOSX_BUNDLE_GUI_IDENTIFIER "se.bamsejon.idopus"
        MACOSX_BUNDLE_BUNDLE_NAME "iDOpus"
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
        MACOSX_BUNDLE_COPYRIGHT "Copyright 2026 Jon Bylund. Original (c) GP Software / Jonathan Potter."
    )
endif()
