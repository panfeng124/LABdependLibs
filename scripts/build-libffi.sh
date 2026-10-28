#!/usr/bin/env bash
set -euo pipefail

export PATH="$PATH:/usr/bin"
for tool in autoreconf autoconf automake libtoolize make tar cygpath; do
    command -v "$tool" >/dev/null || { echo "Missing MSYS2 tool: $tool" >&2; exit 2; }
done
if [[ ${1:-} == --check ]]; then
    echo "MSYS2 prerequisites found."
    exit 0
fi

source_dir=$(cygpath -u "$1")
build_dir=$(cygpath -u "$2")
install_dir=$(cygpath -m "$3")
configuration=$4
jobs=$5
command -v cl.exe >/dev/null
command -v ml64.exe >/dev/null

cd "$source_dir"
# The checked-in Windows files may have CRLF. Only normalize the disposable copy.
for file in autogen.sh msvcc.sh configure.ac Makefile.am configure.host config.guess config.sub libtool-version libtool-ldflags; do
    sed -i 's/\r$//' "$file"
done
autoreconf -vfi
cd "$build_dir"
flags='-O2 -FS'
debug=--disable-debug
if [[ $configuration == Debug ]]; then
    flags='-O0 -g -FS -DUSE_DEBUG_RTL'
    debug=--enable-debug
fi
# Explicit MSVC tools avoid accidentally selecting MSYS /usr/bin/link.exe.
msvc_bin=$(dirname "$(command -v cl.exe)")
export PATH="$msvc_bin:$source_dir:$PATH"
# Use a command name on PATH: Autoconf splits CC and does not remove embedded quotes.
export CC='msvcc.sh -m64'
export CXX="$CC"
export LD=link
export CPP='cl -nologo -EP'
export CXXCPP="$CPP"
export CPPFLAGS='-DFFI_BUILDING_DLL'
export CFLAGS="$flags"
export CXXFLAGS="$flags"
export NM='dumpbin -symbols'
export STRIP=:
# Automake supplies ar-lib for translating ar flags to MSVC lib.exe.
ar_wrapper="$(automake --print-libdir)/ar-lib"
test -f "$ar_wrapper"
export PATH="$(dirname "$ar_wrapper"):$PATH"
export AR='ar-lib lib'
bash "$source_dir/configure" --prefix="$install_dir" \
    --build=x86_64-pc-msys --host=x86_64-w64-cygwin \
    --enable-shared --disable-static --disable-docs "$debug"
make -j"$jobs"
install_unix=$(cygpath -u "$install_dir")
# Libtool's MSVC installer expects libffi.lib while link.exe creates libffi-8.lib,
# and can even copy a DLL to a .lib filename. Install the actual linker outputs.
test -f .libs/libffi-8.dll
test -f .libs/libffi-8.lib
make -C include install
install -d "$install_unix/bin" "$install_unix/lib"
install -m 755 .libs/libffi-8.dll "$install_unix/bin/libffi-8.dll"
install -m 644 .libs/libffi-8.lib "$install_unix/lib/ffi.lib"
