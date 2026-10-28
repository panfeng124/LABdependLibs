cmake_minimum_required(VERSION 3.22)
project(LABDependencyAdapter LANGUAGES C CXX)
include(GNUInstallDirs)

if(NOT DEFINED LAB_SOURCE OR NOT DEFINED LAB_LIBRARY)
    message(FATAL_ERROR "Use build.ps1 to select LAB_SOURCE and LAB_LIBRARY")
endif()

if(LAB_LIBRARY STREQUAL "glm")
    # This vendored GLM predates modern CMake. It is header-only.
    install(DIRECTORY "${LAB_SOURCE}/glm" DESTINATION include
        FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp" PATTERN "*.inl")
elseif(LAB_LIBRARY STREQUAL "zlib")
    # The upstream build renames zconf.h in its source directory. Generate our
    # header in the binary directory and compile the explicit upstream sources.
    configure_file("${LAB_SOURCE}/zconf.h.cmakein" "${CMAKE_CURRENT_BINARY_DIR}/zconf.h" @ONLY)
    set(zlib_sources adler32.c compress.c crc32.c deflate.c gzclose.c gzlib.c
        gzread.c gzwrite.c inflate.c infback.c inftrees.c inffast.c trees.c uncompr.c zutil.c)
    list(TRANSFORM zlib_sources PREPEND "${LAB_SOURCE}/")
    add_library(zlibstatic STATIC ${zlib_sources})
    target_include_directories(zlibstatic PUBLIC "${LAB_SOURCE}" "${CMAKE_CURRENT_BINARY_DIR}")
    target_compile_definitions(zlibstatic PRIVATE _CRT_SECURE_NO_DEPRECATE _CRT_NONSTDC_NO_DEPRECATE)
    install(TARGETS zlibstatic ARCHIVE DESTINATION lib)
    install(FILES "${LAB_SOURCE}/zlib.h" "${CMAKE_CURRENT_BINARY_DIR}/zconf.h" DESTINATION include)
elseif(LAB_LIBRARY STREQUAL "harfbuzz")
    # An imported target bypasses the vendored hard-coded freetype build path.
    find_package(Freetype REQUIRED)
    add_library(freetype INTERFACE IMPORTED)
    set_target_properties(freetype PROPERTIES INTERFACE_LINK_LIBRARIES Freetype::Freetype)
    add_subdirectory("${LAB_SOURCE}" upstream)
    install(FILES "${LAB_SOURCE}/src/hb-ft.h" DESTINATION include/harfbuzz)
elseif(LAB_LIBRARY STREQUAL "yoga")
    # The root project unconditionally downloads googletest; build only yogacore.
    add_subdirectory("${LAB_SOURCE}/yoga" upstream)
    if(MSVC)
        # The vendored shared build exports classes containing STL members.
        # Keep /WX, but do not promote the expected DLL-interface warning.
        target_compile_options(yogacore PRIVATE /wd4251)
    endif()
    install(TARGETS yogacore RUNTIME DESTINATION bin ARCHIVE DESTINATION lib)
    install(DIRECTORY "${LAB_SOURCE}/yoga" DESTINATION include FILES_MATCHING PATTERN "*.h")
elseif(LAB_LIBRARY STREQUAL "sqlite3")
    add_library(sqlite3 SHARED "${LAB_SOURCE}/sqlite3.c")
    target_compile_definitions(sqlite3 PRIVATE SQLITE_OMIT_LOAD_EXTENSION SQLITE_ENABLE_JSON1)
    set_target_properties(sqlite3 PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
    install(TARGETS sqlite3 RUNTIME DESTINATION bin ARCHIVE DESTINATION lib)
    install(FILES "${LAB_SOURCE}/sqlite3.h" "${LAB_SOURCE}/sqlite3ext.h" DESTINATION include)
else()
    message(FATAL_ERROR "Unknown adapter: ${LAB_LIBRARY}")
endif()
