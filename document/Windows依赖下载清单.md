# Windows 依赖下载清单

按 dependencies.json，常规构建有 14 项，准备 13 份源码即可。建议 ZIP 文件名带版本或提交号；master/main 只是分支名。

| 下载项目 | 选包说明 |
| --- | --- |
| Assimp | 完整源码，保留 contrib/zlib。同一包提供 zlib 和 Assimp |
| Brotli | google/brotli |
| libpng | 当前使用目录标为 1.6.40，依赖 zlib |
| FreeType | 依赖 zlib、libpng、Brotli |
| HarfBuzz | 依赖 FreeType |
| GLFW | glfw/glfw |
| GLM | g-truc/glm，只安装头文件 |
| libhv | ithewei/libhv |
| LunaSVG | 确认包含完整 plutovg 源码和许可证 |
| Native File Dialog Extended | btzy/nativefiledialog-extended，对应 nfd |
| OpenAL Soft | kcat/openal-soft，对应 openal |
| Yoga | facebook/yoga |
| SQLite | 选 sqlite-amalgamation 源码包，包含 sqlite3.c 和 sqlite3.h |

另外单独处理三项：

- libffi 源码。使用 scripts/Build-Libffi.ps1 和 MSYS2 单独构建。
- FFmpeg 的 Windows x64 SDK。现有流程从 prebuilt/windows-x64 复制；如需重编，参考本目录的 FFmpeg 备忘。
- legacy-headers。沿用 prebuilt/windows-x64/include 中手工维护的头文件，包括 utfcpp 和 zip。

## 从源码到交付包

1. 集中保存源码 ZIP，记录上游版本或提交号。要复现现有版本，可直接归档清单中对应的源码目录。
2. 当前入口读取已解压的目录。先将各包解压到 dependencies.json 对应的 source 路径，去掉多余的外层目录。后续从 ZIP 一键开始时，再给入口补上校验和解压步骤。
3. 在仓库根目录运行 .\build.cmd -Package。需要 Windows x64、VS C++ 工具链、Windows SDK 和 CMake 3.22+。脚本按依赖顺序编译，在 result 下按工具链、配置和库名整理头文件、LIB、DLL 和许可证，再把分发 ZIP 和 SHA256 写入 packages。
