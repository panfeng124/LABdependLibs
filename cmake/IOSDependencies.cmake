# Static dependencies for one iOS device or simulator build.
include_guard(GLOBAL)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "IOSDependencies requires CMAKE_SYSTEM_NAME=iOS")
endif()

set(_base "${CMAKE_CURRENT_LIST_DIR}/../baseLibs")
set(_build "${CMAKE_CURRENT_BINARY_DIR}/ios-deps")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
add_subdirectory("${_base}/SDL-release-3.4.20" "${_build}/sdl" EXCLUDE_FROM_ALL)

# libhv writes platform-specific hconfig.h and include/hv into its source tree.
# Isolate this copy from the macOS build and from builds using another SDK.
file(COPY "${_base}/libhv-master/" DESTINATION "${_build}/hv-src"
     PATTERN "hconfig.h" EXCLUDE PATTERN "include/hv" EXCLUDE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC ON CACHE BOOL "" FORCE)
add_subdirectory("${_build}/hv-src" "${_build}/hv" EXCLUDE_FROM_ALL)

# Preserve WOFF2 and embedded PNG glyph support using the bundled decoders.
set(BROTLI_DISABLE_TESTS ON CACHE BOOL "" FORCE)
add_subdirectory("${_base}/brotli-master" "${_build}/brotli" EXCLUDE_FROM_ALL)
set(PNG_SHARED OFF CACHE BOOL "" FORCE)
set(PNG_EXECUTABLES OFF CACHE BOOL "" FORCE)
set(PNG_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory("${_base}/libpng-1.6.40" "${_build}/png" EXCLUDE_FROM_ALL)

# Supply target libraries directly to FreeType's generated feature config
# and skip package searches that could resolve to a macOS installation.
set(PNG_FOUND TRUE)
set(PNG_LIBRARIES "$<BUILD_INTERFACE:png_static>")
set(PNG_INCLUDE_DIRS "${_base}/libpng-1.6.40" "${_build}/png")
set(BROTLIDEC_FOUND TRUE)
set(BROTLIDEC_LIBRARIES "$<BUILD_INTERFACE:brotlidec>")
foreach(feature IN ITEMS HARFBUZZ BZIP2 PNG BROTLI)
    set(FT_DISABLE_${feature} ON CACHE BOOL "" FORCE)
endforeach()
add_subdirectory("${_base}/freetype-master" "${_build}/freetype" EXCLUDE_FROM_ALL)
add_library(harfbuzz STATIC "${_base}/harfbuzz-main/src/harfbuzz.cc")
target_compile_features(harfbuzz PRIVATE cxx_std_17)

add_subdirectory("${_base}/yoga-main/yoga" "${_build}/yoga" EXCLUDE_FROM_ALL)
set(LUNASVG_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
add_subdirectory("${_base}/lunasvg" "${_build}/lunasvg" EXCLUDE_FROM_ALL)

set(ASSIMP_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ASSIMP_INSTALL OFF CACHE BOOL "" FORCE)
set(ASSIMP_WARNINGS_AS_ERRORS OFF CACHE BOOL "" FORCE)
set(ASSIMP_NO_EXPORT ON CACHE BOOL "" FORCE)
add_subdirectory("${_base}/assimp-master" "${_build}/assimp" EXCLUDE_FROM_ALL)

add_library(lab_ios_deps INTERFACE)
target_link_libraries(lab_ios_deps INTERFACE SDL3::SDL3-static hv_static freetype harfbuzz
    yogacore lunasvg::lunasvg assimp::assimp "-framework OpenGLES")
