#include <iostream>
#include <cstring>
#ifdef LAB_HAVE_ZLIB
#include <zlib.h>
#endif
#ifdef LAB_HAVE_BROTLI
#include <brotli/decode.h>
#endif
#ifdef LAB_HAVE_LIBPNG
#include <png.h>
#endif
#ifdef LAB_HAVE_FREETYPE
#include <ft2build.h>
#include FT_FREETYPE_H
#endif
#ifdef LAB_HAVE_HARFBUZZ
#include <hb.h>
#include <hb-ft.h>
#endif
#ifdef LAB_HAVE_GLFW
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>
#endif
#ifdef LAB_HAVE_GLM
#include <glm/glm.hpp>
#endif
#ifdef LAB_HAVE_LIBHV
#include <hv/hbase.h>
#endif
#ifdef LAB_HAVE_LUNASVG
#include <lunasvg.h>
#endif
#ifdef LAB_HAVE_NFD
#include <nfd.h>
#endif
#ifdef LAB_HAVE_OPENAL
#include <AL/al.h>
#endif
#ifdef LAB_HAVE_YOGA
#include <yoga/Yoga.h>
#endif
#ifdef LAB_HAVE_ASSIMP
#include <assimp/version.h>
#include <assimp/config.h>
#include <assimp/revision.h>
#endif
#ifdef LAB_HAVE_SQLITE3
#include <sqlite3.h>
#endif
#ifdef LAB_HAVE_LIBFFI
#include <ffi.h>
static int add_values(int a, int b) { return a + b; }
#endif

int main() {
#ifdef LAB_HAVE_ZLIB
    const char input[] = "LAB dependency package";
    unsigned char compressed[128]{};
    char output[128]{};
    uLongf compressed_size = sizeof(compressed), output_size = sizeof(output);
    if (compress(compressed, &compressed_size, reinterpret_cast<const Bytef*>(input), sizeof(input)) != Z_OK) return 1;
    if (uncompress(reinterpret_cast<Bytef*>(output), &output_size, compressed, compressed_size) != Z_OK || std::strcmp(input, output)) return 2;
    std::cout << "zlib " << zlibVersion() << '\n';
#endif
#ifdef LAB_HAVE_BROTLI
    if (!BrotliDecoderVersion()) return 3;
#endif
#ifdef LAB_HAVE_LIBPNG
    std::cout << "png " << png_get_libpng_ver(nullptr) << '\n';
#endif
#ifdef LAB_HAVE_FREETYPE
    FT_Library ft = nullptr;
    if (FT_Init_FreeType(&ft)) return 4;
    FT_Done_FreeType(ft);
#endif
#ifdef LAB_HAVE_HARFBUZZ
    hb_buffer_t* buffer = hb_buffer_create();
    if (!hb_buffer_allocation_successful(buffer)) return 5;
    hb_buffer_destroy(buffer);
    // Exercise the exported FreeType bridge without requiring a font fixture.
    if (hb_ft_font_get_face(hb_font_get_empty()) != nullptr) return 6;
    std::cout << "harfbuzz " << hb_version_string() << '\n';
#endif
#ifdef LAB_HAVE_GLFW
    int major = 0, minor = 0, revision = 0;
    glfwGetVersion(&major, &minor, &revision);
    if (major < 3) return 7;
#endif
#ifdef LAB_HAVE_GLM
    if (glm::vec3(1.0f).x != 1.0f) return 8;
#endif
#ifdef LAB_HAVE_LIBHV
    void* allocation = hv_malloc(16);
    if (!allocation) return 9;
    hv_free(allocation);
#endif
#ifdef LAB_HAVE_LUNASVG
    auto document = lunasvg::Document::loadFromData("<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4'><rect width='4' height='4' fill='red'/></svg>");
    if (!document || document->renderToBitmap().isNull()) return 10;
#endif
#ifdef LAB_HAVE_NFD
    NFD_ClearError();
#endif
#ifdef LAB_HAVE_OPENAL
    (void)alGetError(); // Does not open an audio device.
#endif
#ifdef LAB_HAVE_YOGA
    auto node = YGNodeNew();
    YGNodeStyleSetWidth(node, 20);
    YGNodeStyleSetHeight(node, 10);
    YGNodeCalculateLayout(node, 20, 10, YGDirectionLTR);
    if (YGNodeLayoutGetWidth(node) != 20) return 11;
    YGNodeFree(node);
#endif
#ifdef LAB_HAVE_ASSIMP
    std::cout << "assimp " << aiGetVersionMajor() << '.' << aiGetVersionMinor() << '\n';
#endif
#ifdef LAB_HAVE_SQLITE3
    sqlite3* db = nullptr;
    if (sqlite3_open(":memory:", &db) != SQLITE_OK) return 12;
    if (sqlite3_exec(db, "CREATE TABLE smoke (id INTEGER)", nullptr, nullptr, nullptr) != SQLITE_OK) return 13;
    sqlite3_close(db);
#endif
#ifdef LAB_HAVE_LIBFFI
    ffi_cif cif;
    ffi_type* types[] = {&ffi_type_sint, &ffi_type_sint};
    int a = 20, b = 22;
    void* values[] = {&a, &b};
    ffi_arg result = 0;
    if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 2, &ffi_type_sint, types) != FFI_OK) return 14;
    ffi_call(&cif, FFI_FN(add_values), &result, values);
    if (result != 42) return 15;
#endif
    std::cout << "LAB dependency smoke test passed\n";
    return 0;
}
