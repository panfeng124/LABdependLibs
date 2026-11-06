# Windows + MSVC 编译 FFmpeg

目标：

```text
Windows
MSVC
MSYS2
FFmpeg shared libraries
```

主要用于给 C++ 项目提供：

```text
avformat
avcodec
avutil
swresample
swscale
```

---

## 1. 安装 MSYS2

安装到默认目录：

```text
C:\msys64
```

安装完成后更新：

```bash
pacman -Syu
```

如果提示关闭窗口，重新打开 MSYS2，再执行一次：

```bash
pacman -Syu
```

安装 FFmpeg 构建工具：

```bash
pacman -S make diffutils nasm pkgconf
```

---

## 2. 启动 MSVC + MSYS2 环境

先打开：

```text
x64 Native Tools Command Prompt for VS
```

确认：

```cmd
cl
```

可以正常找到 MSVC。

然后从该终端启动 MSYS2：

```cmd
C:\msys64\msys2_shell.cmd -use-full-path
```

这样：

```text
MSYS2 提供：
    bash
    configure
    make
    nasm

Visual Studio 提供：
    cl.exe
    link.exe
    lib.exe
```

---

## 3. 检查编译器

```bash
which cl
which link
```

正常情况下都应该指向 Visual Studio：

```text
/c/Program Files/Microsoft Visual Studio/.../cl
/c/Program Files/Microsoft Visual Studio/.../link
```

### link.exe 冲突

MSYS2 自己也存在：

```text
/usr/bin/link
```

如果：

```bash
which link
```

得到：

```text
/usr/bin/link
```

说明 MSYS2 的 `link.exe` 抢占了 MSVC linker。

可以先让 MSVC 目录优先：

```bash
MSVC_BIN="$(dirname "$(which cl)")"
export PATH="$MSVC_BIN:$PATH"
hash -r
```

再次：

```bash
which link
```

如果仍然指向 `/usr/bin/link`，可以改名：

```bash
mv /usr/bin/link.exe /usr/bin/link.exe.bak
hash -r
```

---

## 4. 验证 MSVC 是否正常

```bash
echo 'int main(void) { return 0; }' > test.c
cl.exe test.c
```

应该生成：

```text
test.obj
test.exe
```

执行：

```bash
./test.exe
echo $?
```

应该输出：

```text
0
```

同时可以检查：

```bash
echo "$INCLUDE"
echo "$LIB"
```

应该包含 MSVC 和 Windows SDK 路径。

---

## 5. 建立独立编译目录

假设：

```text
源码：
F:\PF\FFMpegBuild\FFmpeg

编译：
F:\PF\FFMpegBuild\ffmpeg-build

安装：
F:\PF\FFMpegBuild\ffmpeg-install
```

MSYS2 中对应：

```text
/f/PF/FFMpegBuild/FFmpeg
/f/PF/FFMpegBuild/ffmpeg-build
/f/PF/FFMpegBuild/ffmpeg-install
```

不要使用：

```text
F://PF//FFMpegBuild//FFmpeg
```

统一使用 MSYS2 Unix 路径格式。

进入编译目录：

```bash
cd /f/PF/FFMpegBuild/ffmpeg-build
```

---

## 6. configure

```bash
/f/PF/FFMpegBuild/FFmpeg/configure \
    --toolchain=msvc \
    --prefix=/f/PF/FFMpegBuild/ffmpeg-install \
    --enable-shared \
    --disable-static \
    --disable-programs \
    --disable-doc \
    --disable-avdevice \
    --disable-avfilter
```

这里暂时不做极限裁剪。

主要保留：

```text
libavformat
libavcodec
libavutil
libswresample
libswscale
```

不需要：

```text
ffmpeg.exe
ffprobe.exe
ffplay.exe
libavdevice
libavfilter
```

新版 FFmpeg 已经没有：

```bash
--disable-postproc
```

不要再添加这个选项。

---

## 7. MSVC 中文环境导致 configure 识别失败

如果出现：

```text
cl.exe is unable to create an executable file.
C compiler test failed.
```

先查看：

```bash
grep -n -A 30 -B 10 "C compiler test" ffbuild/config.log
```

如果发现类似：

```text
cl.exe -options:strict -c -o xxx/test.o xxx/test.c

用于 x64 的 Microsoft (R) C/C++ 优化编译器 ...

LNK1136: 无效或损坏的文件
```

问题通常是：

```text
FFmpeg 没有正确识别 cl.exe 为 MSVC。
```

正常 MSVC 编译 `.obj` 应使用：

```text
-Fo
```

但错误情况下 FFmpeg 使用了：

```text
-o
```

### 原因

FFmpeg `configure` 中存在类似：

```bash
grep -q ^Microsoft
```

而中文 MSVC 输出可能是：

```text
用于 x64 的 Microsoft (R) C/C++ 优化编译器 ...
```

因此并不是以 `Microsoft` 开头，检测失败。

### 解决

在 FFmpeg 的：

```text
configure
```

中搜索：

```bash
grep -q ^Microsoft
```

把相关判断：

```bash
grep -q ^Microsoft
```

改为：

```bash
grep -q Microsoft
```

例如：

```bash
VSLANG=1033 $_cc -nologo- 2>&1 | grep -q Microsoft
```

以及：

```bash
_ident=$(VSLANG=1033 $_cc 2>&1 | grep Microsoft | head -n1 | tr -d '\r')
```

`lib.exe` 相关检测如果也使用：

```bash
grep -q ^Microsoft
```

同样改成：

```bash
grep -q Microsoft
```

---

## 8. 修改 configure 后重新编译

清理旧 build：

```bash
cd /f/PF/FFMpegBuild/ffmpeg-build
rm -rf ./*
```

重新执行：

```bash
/f/PF/FFMpegBuild/FFmpeg/configure \
    --toolchain=msvc \
    --prefix=/f/PF/FFMpegBuild/ffmpeg-install \
    --enable-shared \
    --disable-static \
    --disable-programs \
    --disable-doc \
    --disable-avdevice \
    --disable-avfilter
```

如果 configure 成功，再编译：

```bash
make -j$(nproc)
```

然后安装：

```bash
make install
```

---

## 9. 最终产物

安装目录：

```text
F:\PF\FFMpegBuild\ffmpeg-install
```

主要内容：

```text
ffmpeg-install/
├── include/
│   ├── libavcodec/
│   ├── libavformat/
│   ├── libavutil/
│   ├── libswresample/
│   └── libswscale/
│
└── bin/                 # 本次 MSVC 安装的导入库也在 bin/
    ├── avcodec.lib
    ├── avformat.lib
    ├── avutil.lib
    ├── swresample.lib
    ├── swscale.lib
    ├── avcodec-*.dll
    ├── avformat-*.dll
    ├── avutil-*.dll
    ├── swresample-*.dll
    └── swscale-*.dll
```

---

## 10. 最短流程

以后重新编译时主要就是：

```text
1. 打开 x64 Native Tools Command Prompt
2. 启动：
   C:\msys64\msys2_shell.cmd -use-full-path

3. 检查：
   which cl
   which link

4. 进入：
   cd /f/PF/FFMpegBuild/ffmpeg-build

5. configure

6. make -j$(nproc)

7. make install
```

如果 `configure` 再次出现：

```text
C compiler test failed
```

优先检查：

```text
ffbuild/config.log
```

重点确认 FFmpeg 调用 MSVC 时是否使用：

```text
-Fo
```

而不是：

```text
-o
```
