# HarfBuzz sets Windows FreeType paths before calling include(FindFreetype).
# Let CMake find the headers and library in the macOS SDK built by build-macos.sh.
unset(FREETYPE_INCLUDE_DIRS)
unset(FREETYPE_INCLUDE_DIR_ft2build)
unset(FREETYPE_INCLUDE_DIR_freetype2)
unset(FREETYPE_LIBRARY)
include("${CMAKE_ROOT}/Modules/FindFreetype.cmake")
