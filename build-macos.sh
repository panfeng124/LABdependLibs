#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
root=$PWD
arch=$(uname -m)
sdk="$root/result/macos-$arch"
work="$root/build/macos-$arch"
sources="$root/baseLibs"
jobs=${CMAKE_BUILD_PARALLEL_LEVEL:-$(sysctl -n hw.ncpu)}
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-11.5}
export PKG_CONFIG_LIBDIR="$sdk/lib/pkgconfig"
mkdir -p "$work" "$sdk/lib" "$sdk/include"
mkdir -p "$sdk/include/utfcpp"
cp -R "$root/result/libHeaders/utfcpp/source" "$sdk/include/utfcpp/"
cp -R "$root/result/libHeaders/zip" "$sdk/include/"

configure() {
    local name=$1 source=$2
    shift 2
    cmake -S "$source" -B "$work/$name" \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
        -DCMAKE_INSTALL_PREFIX="$sdk" -DCMAKE_PREFIX_PATH="$sdk" \
        '-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local' \
        -DCMAKE_MACOSX_RPATH=ON -DCMAKE_INSTALL_NAME_DIR=@rpath "$@"
    cmake --build "$work/$name" --config Release --parallel "$jobs"
}

install_cmake() {
    configure "$@"
    cmake --install "$work/$1" --config Release
}

install_cmake hv "$sources/libhv-master" -DBUILD_STATIC=OFF -DBUILD_EXAMPLES=OFF
install_cmake sdl "$sources/SDL-release-3.4.20" -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST_LIBRARY=OFF
install_cmake brotli "$sources/brotli-master" -DBROTLI_DISABLE_TESTS=ON \
    -DCMAKE_PROJECT_brotli_INCLUDE="$root/cmake/macos/BrotliInstallName.cmake"
# libpng 1.6.40 skips the classic Mac fp.h when math.h has already been included.
# CMAKE_C_FLAGS also reaches its standalone header generator.
install_cmake png "$sources/libpng-1.6.40" -DPNG_STATIC=OFF -DPNG_TESTS=OFF -DPNG_EXECUTABLES=OFF \
    -DCMAKE_C_FLAGS="${CFLAGS:+$CFLAGS }-include math.h"
install_cmake freetype "$sources/freetype-master" -DFT_DISABLE_HARFBUZZ=ON -DFT_REQUIRE_PNG=ON -DFT_REQUIRE_BROTLI=ON
install_cmake harfbuzz "$sources/harfbuzz-main" -DHB_BUILD_SUBSET=OFF \
    -DCMAKE_MODULE_PATH="$root/cmake/macos"
install_cmake lunasvg "$sources/lunasvg" -DLUNASVG_BUILD_EXAMPLES=OFF -DPLUTOVG_BUILD_EXAMPLES=OFF \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
install_cmake assimp "$sources/assimp-master" -DASSIMP_BUILD_TESTS=OFF -DASSIMP_WARNINGS_AS_ERRORS=OFF

# Yoga's top-level project also downloads GoogleTest. Build its library target directly.
configure yoga "$sources/yoga-main/yoga"
cp "$work/yoga/libyogacore.dylib" "$sdk/lib/"
rsync -a --include='*/' --include='*.h' --exclude='*' "$sources/yoga-main/yoga/" "$sdk/include/yoga/"

# FFmpeg is the one desktop dependency whose sources are not in this repository.
version=9.0.2
downloads="$root/build/macos-downloads"
archive="ffmpeg-$version.tar.xz"
mkdir -p "$downloads" "$work/ffmpeg"
(
    cd "$downloads"
    verify() {
        echo "8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e  $1" | shasum -a 256 --check
    }
    if [[ ! -f "$archive" ]] || ! verify "$archive"; then
        part=$(mktemp "$archive.XXXXXX")
        trap 'rm -f "$part"' EXIT
        curl -fL --retry 2 "${FFMPEG_RELEASE_URL:-https://ffmpeg.org/releases}/$archive" -o "$part"
        verify "$part"
        mv "$part" "$archive"
    fi
    if [[ ! -f "ffmpeg-$version/.lab-unpacked" ]]; then
        tar xf "$archive"
        touch "ffmpeg-$version/.lab-unpacked"
    fi
)
(
    cd "$work/ffmpeg"
    "$downloads/ffmpeg-$version/configure" --prefix="$sdk" --install-name-dir=@rpath \
        --enable-shared --disable-static --disable-programs --disable-doc --disable-avdevice --disable-avfilter \
        --disable-autodetect --enable-securetransport --enable-zlib --enable-bzlib --enable-iconv --extra-libs=-liconv
    make -j"$jobs"
    make install
)

licenses="$sdk/licenses"
mkdir -p "$licenses"
for file in SDL-release-3.4.20/LICENSE.txt assimp-master/LICENSE brotli-master/LICENSE \
        freetype-master/docs/FTL.TXT harfbuzz-main/COPYING libhv-master/LICENSE libpng-1.6.40/LICENSE \
        lunasvg/LICENSE lunasvg/plutovg/LICENSE yoga-main/LICENSE; do
    name=$(basename "$(dirname "$file")")
    cp "$sources/$file" "$licenses/$name-$(basename "$file")"
done
cp "$downloads/ffmpeg-$version/COPYING.LGPLv2.1" "$licenses/FFmpeg-LGPL-2.1.txt"
echo "macOS SDK: $sdk"
