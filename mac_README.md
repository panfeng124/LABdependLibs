# macOS 桌面依赖

在装有 Xcode 命令行工具、CMake 3.24+ 的 Mac 上，从本仓库根目录运行以下命令。脚本按当前终端架构构建 Release 动态库，并将匹配的头文件一起安装到工作区。

```sh
./build-macos.sh
```

Apple Silicon 原生终端的输出为 `result/macos-arm64/{include,lib,licenses}`。编译目录为 `build/macos-arm64/`。CPU 并行数可通过 `CMAKE_BUILD_PARALLEL_LEVEL` 指定，最低部署版本通过 `MACOSX_DEPLOYMENT_TARGET` 指定，默认值为 `11.5`。

| 功能 | 动态库来源 |
| --- | --- |
| 网络和桌面窗口 | 仓库内的 libhv、SDL 3.4.20 |
| 字体和 SVG | 仓库内的 Brotli、libpng、FreeType、HarfBuzz、LunaSVG、plutovg |
| 布局和模型导入 | 仓库内的 Yoga、Assimp 6.0.5 |
| 音视频 | FFmpeg 9.0.2 的 avformat、avcodec、avutil、swresample、swscale |
| FFI 和系统压缩库 | Xcode SDK 的 libffi、zlib、bzip2，运行时由 macOS 提供 |

macOS 构建 libpng 1.6.40 时，脚本让编译器预先包含系统的 `math.h`。该版本的 `pngpriv.h` 会据此跳过旧版 Mac 的 `fp.h`。Brotli 动态库的 `@rpath` 和 HarfBuzz 查找 FreeType 的设置也仅由 macOS 构建脚本加载。

Assimp 的 OBJ 导入和导出源码随仓库跟踪，版本对应 [Assimp v6.0.5](https://github.com/assimp/assimp/tree/v6.0.5/code/AssetLib/Obj)。Intel Mac 原生构建 FFmpeg 还需要 NASM。本次验证使用 Apple Silicon。

首次构建会下载并校验 FFmpeg 源码。离线构建时可预先放置 `build/macos-downloads/ffmpeg-9.0.2.tar.xz`。如需使用镜像，可设置 `FFMPEG_RELEASE_URL` 为存放该压缩包的目录 URL；脚本校验同一个 SHA-256。[FFmpeg 官方发布目录](https://ffmpeg.org/releases/)

将本仓库与 `LABScript`、`LABEngine` 放在同一父目录，在 `LABEngine` 中执行 `./packaging/macos/build.sh` 即可完成依赖、脚本运行库和桌面应用的整套构建。日常修改 C++ 后可直接增量构建对应的 CMake 目标。
