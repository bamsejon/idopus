cmake_minimum_required(VERSION 3.20)
project(idopus VERSION 1.8.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# macOS ARM target
if(APPLE)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Build for Apple Silicon")
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "macOS 13+")
endif()

# Include paths
include_directories(${CMAKE_SOURCE_DIR}/include)

# --- Platform Abstraction Layer (PAL) ---
set(PAL_SOURCES
    src/pal/pal_memory.c
    src/pal/pal_lists.c
    src/pal/pal_ipc.c
    src/pal/pal_strings.c
)
if(WIN32)
    list(APPEND PAL_SOURCES
        src/pal/pal_sync_win32.c
        src/pal/pal_file_win32.c)
else()
    list(APPEND PAL_SOURCES
        src/pal/pal_sync.c
        src/pal/pal_file.c)
endif()

add_library(pal STATIC ${PAL_SOURCES})
if(WIN32)
    # shell32 for SHFileOperation (only if used); advapi32 default-linked in MSVC
    target_link_libraries(pal PRIVATE shell32)
else()
    target_link_libraries(pal PRIVATE pthread)
endif()

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
    # Localization resources — Base (English) + Swedish + whatever else is in resources/
    file(GLOB LOCALIZATION_DIRS RELATIVE ${CMAKE_SOURCE_DIR}/resources
         ${CMAKE_SOURCE_DIR}/resources/*.lproj)
    set(LOCALIZATION_FILES "")
    foreach(lproj ${LOCALIZATION_DIRS})
        set(src ${CMAKE_SOURCE_DIR}/resources/${lproj}/Localizable.strings)
        list(APPEND LOCALIZATION_FILES ${src})
        set_source_files_properties(${src} PROPERTIES
            MACOSX_PACKAGE_LOCATION Resources/${lproj})
    endforeach()

    set(ICON_FILE "${CMAKE_SOURCE_DIR}/resources/iDOpus.icns")
    set_source_files_properties(${ICON_FILE} PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources)

    add_executable(idopus MACOSX_BUNDLE
        src/gui/AppDelegate.m
        ${ICON_FILE}
        ${LOCALIZATION_FILES}
    )
    target_compile_options(idopus PRIVATE "-fobjc-arc")
    target_link_libraries(idopus PRIVATE core pal
        "-framework Cocoa"
        "-framework Quartz"
        "-framework QuickLookThumbnailing"
        "-framework UniformTypeIdentifiers"
        pthread
    )
    set_target_properties(idopus PROPERTIES
        OUTPUT_NAME "iDOpus"
        MACOSX_BUNDLE_GUI_IDENTIFIER "se.bamsejon.idopus"
        MACOSX_BUNDLE_BUNDLE_NAME "iDOpus"
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
        MACOSX_BUNDLE_COPYRIGHT "Copyright 2026 Jon Bylund. Original (c) GP Software / Jonathan Potter."
        MACOSX_BUNDLE_EXECUTABLE_NAME "iDOpus"
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/resources/Info.plist.in"
    )

    # Bundle rclone helper binary if it's been fetched into third_party/rclone/.
    # scripts/fetch-rclone.sh downloads and pins the official build.
    set(RCLONE_BIN "${CMAKE_SOURCE_DIR}/third_party/rclone/rclone")
    set(RCLONE_LIC "${CMAKE_SOURCE_DIR}/third_party/rclone/LICENSE")
    if(EXISTS "${RCLONE_BIN}")
        add_custom_command(TARGET idopus POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory
                "$<TARGET_BUNDLE_DIR:idopus>/Contents/MacOS"
            COMMAND ${CMAKE_COMMAND} -E copy
                "${RCLONE_BIN}"
                "$<TARGET_BUNDLE_DIR:idopus>/Contents/MacOS/rclone"
            COMMAND chmod +x "$<TARGET_BUNDLE_DIR:idopus>/Contents/MacOS/rclone"
            COMMENT "Bundling rclone helper")
        if(EXISTS "${RCLONE_LIC}")
            add_custom_command(TARGET idopus POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory
                    "$<TARGET_BUNDLE_DIR:idopus>/Contents/Resources"
                COMMAND ${CMAKE_COMMAND} -E copy
                    "${RCLONE_LIC}"
                    "$<TARGET_BUNDLE_DIR:idopus>/Contents/Resources/rclone-LICENSE.txt"
                COMMENT "Bundling rclone LICENSE")
        endif()
    else()
        message(STATUS "rclone binary not found at ${RCLONE_BIN} — run scripts/fetch-rclone.sh to bundle it")
    endif()
endif()

# --- Qt6 GUI app (Linux / non-Apple) ---
if(NOT APPLE)
    option(BUILD_QT_GUI "Build Qt6 GUI on non-Apple platforms" ON)
    if(BUILD_QT_GUI)
        find_package(Qt6 6.5 COMPONENTS Core Widgets)
        if(Qt6_FOUND)
            qt_standard_project_setup()
            qt_add_executable(idopus-qt
                src/gui/qt/main.cpp
                src/gui/qt/MainWindow.cpp
                src/gui/qt/MainWindow.h
                src/gui/qt/ListerWidget.cpp
                src/gui/qt/ListerWidget.h
                src/gui/qt/DirBufferModel.cpp
                src/gui/qt/DirBufferModel.h
                src/gui/qt/ButtonBank.cpp
                src/gui/qt/ButtonBank.h
                src/gui/qt/FileTypeActions.cpp
                src/gui/qt/FileTypeActions.h
                src/gui/qt/FileJob.cpp
                src/gui/qt/FileJob.h
                src/gui/qt/JobsPanel.cpp
                src/gui/qt/JobsPanel.h
                src/gui/qt/ConflictDialog.cpp
                src/gui/qt/ConflictDialog.h
                src/gui/qt/PreferencesDialog.cpp
                src/gui/qt/PreferencesDialog.h
                src/gui/qt/BreadcrumbBar.cpp
                src/gui/qt/BreadcrumbBar.h
                src/gui/qt/PreviewPane.cpp
                src/gui/qt/PreviewPane.h
                src/gui/qt/Archiver.cpp
                src/gui/qt/Archiver.h
            )
            if(WIN32)
                set(IDOPUS_QT_WIN32 ON)
            else()
                set(IDOPUS_QT_WIN32 OFF)
            endif()
            set_target_properties(idopus-qt PROPERTIES
                AUTOMOC ON
                WIN32_EXECUTABLE ${IDOPUS_QT_WIN32}
                MACOSX_BUNDLE OFF
            )
            target_link_libraries(idopus-qt PRIVATE
                core pal Qt6::Widgets)
            if(NOT WIN32)
                target_link_libraries(idopus-qt PRIVATE pthread)
            endif()
        else()
            message(STATUS "Qt6 not found — skipping idopus-qt target")
        endif()
    endif()
endif()
