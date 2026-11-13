# Windows + MSVC 编译 FFmpeg 备忘

## 日常增量编译

适用于已有 `ffmpeg-build`、沿用上次配置、只改了源码的情况。首次搭建先看[安装构建工具](#安装构建工具)，首次编译或更换配置看[配置并编译](#配置并编译)。

**1.** 打开 Visual Studio 的 **x64 Native Tools Command Prompt**，执行以下 CMD 命令，让 MSYS2 继承 x64 编译环境。

```cmd
C:\msys64\msys2_shell.cmd -use-full-path
```

**2.** 在新打开的 **MSYS2 Bash** 中执行以下命令。每次打开新终端都要设置一次。换工作目录时，只需改 `ROOT`。

```bash
ROOT=/f/PF/FFMpegBuild
SRC="$ROOT/FFmpeg"
BUILD="$ROOT/ffmpeg-build"
PREFIX="$ROOT/ffmpeg-install"

MSVC_CL="$(command -v cl.exe)" && export PATH="$(dirname "$MSVC_CL"):$PATH"
hash -r
type -P cl.exe link.exe lib.exe
```

三行路径都应指向 Visual Studio 的 x64 工具目录。如果缺少工具或出现 `/usr/bin/link.exe`，先看下方的[工具链排错](#工具链排错)。

**3.** 编译并安装。命令会在出错的步骤停下。

```bash
cd "$BUILD" && make -j"$(nproc)" && make install
```

## 安装构建工具

安装 Visual Studio 的 x64 C++ 工具和 Windows SDK。将 MSYS2 安装到 `C:\msys64`，在 MSYS2 Bash 中更新软件包。

```bash
pacman -Syu
```

如果更新提示关闭终端，重新打开 MSYS2，再运行一次 `pacman -Syu`。然后安装构建工具。

```bash
pacman -S --needed make diffutils nasm pkgconf
```

## 配置并编译

将 FFmpeg 源码放在 `F:\PF\FFMpegBuild\FFmpeg`。先完成“日常增量编译”的第 1、2 步，在同一个 Bash 中执行下面的命令。源码、编译和安装各用一个目录。

更换 FFmpeg 版本、工具链或构建选项时，可先把 `BUILD` 和 `PREFIX` 改为新的目录名，保留旧产物，同时避免混入上一版的头文件或 DLL。

```bash
mkdir -p "$BUILD" && cd "$BUILD" &&
"$SRC/configure" \
    --toolchain=msvc \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    --disable-programs \
    --disable-doc \
    --disable-avdevice \
    --disable-avfilter &&
make -j"$(nproc)" && make install
```

本配置为 C++ 项目构建五个动态库：`avformat`、`avcodec`、`avutil`、`swresample`、`swscale`。`--disable-programs` 会跳过 `ffmpeg.exe`、`ffprobe.exe` 和 `ffplay.exe`。旧笔记中的 `--disable-postproc` 已从本配置移除。切换源码版本时，可用 `"$SRC/configure" --help` 核对可用选项。

## 安装产物与 C++ 接入

默认安装目录为 `F:\PF\FFMpegBuild\ffmpeg-install`。本机这次 MSVC 构建的布局如下。

| 用途 | 安装位置 | C++ 项目如何使用 |
| --- | --- | --- |
| 编译 | `include/libavcodec/`、`include/libavformat/` 等 | 将 `include/` 加入头文件搜索路径 |
| 链接 | `bin/avcodec.lib`、`bin/avformat.lib` 等 | 将导入库所在目录加入库搜索路径，链接项目使用的 `.lib` |
| 运行 | `bin/avcodec-*.dll`、`bin/avformat-*.dll` 等 | 部署时可将同一批构建的五个 DLL 放到应用程序的 `.exe` 旁 |
| 辅助文件 | `lib/*.def`、`lib/pkgconfig/` | 模块定义和 pkg-config 元数据 |

升级或更换安装包后，用下面的命令确认导入库和 DLL 的实际位置。DLL 文件名中的版本号会随库版本变化。

```bash
find "$PREFIX" -type f \( -name '*.lib' -o -name '*.dll' \) | sort
```

## 工具链排错

**找不到 cl.exe，或 link.exe 指向 /usr/bin。** 从 x64 Native Tools Command Prompt 运行 `where cl` 确认 MSVC 已加载，再按日常流程启动 MSYS2 并设置 PATH。如果编译器能启动但找不到头文件或系统库，执行 `echo "$INCLUDE"` 和 `echo "$LIB"`，检查两者是否包含 MSVC 和 Windows SDK 的对应目录。

**configure 报 C compiler test failed。** 先在当前编译目录查看失败的编译、链接命令和错误信息。

```bash
grep -n -B 10 -A 30 'C compiler test' "$BUILD/ffbuild/config.log"
```

用最小程序单独验证当前终端能否编译、链接和运行。输出 `0` 表示成功。

```bash
(
    cd "$(mktemp -d)" &&
    printf 'int main(void) { return 0; }\n' > test.c &&
    cl.exe test.c && ./test.exe
)
echo $?
```

**最小程序成功，但 configure 使用 -o 并报 LNK1136。** 检查日志里的 MSVC 标识。中文输出可能以“用于 x64 的 Microsoft”开头，部分版本的 `configure` 使用 `^Microsoft` 匹配行首，导致探测失败。本机源码已放宽匹配。换用新源码后，可先定位相关判断。

```bash
grep -n 'VSLANG=1033.*Microsoft' "$SRC/configure"
```

如果仍有行首限制且日志符合上述症状，只调整 `cl.exe`、编译器标识 `_ident` 和 `lib.exe` 探测处的匹配：将 `grep -q ^Microsoft` 改为 `grep -q Microsoft`，将提取标识的 `grep ^Microsoft` 改为 `grep Microsoft`。保留原有 `VSLANG=1033` 和其余判断。然后选一个空的 `BUILD` 目录，重新执行“配置并编译”，在日志中确认对象文件输出参数为 `-Fo`。
