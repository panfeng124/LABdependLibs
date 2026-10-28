# LABdependLibs：Windows 构建实验

本仓库维护 LAB 平台的第三方依赖。本轮实验保留 `baseLibs` 中的源码及原有手工产物，新增依赖清单、构建脚本、独立产物目录和离线分发包。

**不要递归扫描整个仓库或 `baseLibs`。** 依赖以 `dependencies.json` 为准；只读取选定库的构建入口。`createAndroidLibs` 暂不参与本流程。

## 一键编译

需要 Windows x64、Visual Studio 的“使用 C++ 的桌面开发”（或对应 Build Tools、Windows SDK），以及 CMake 3.22+。脚本使用 `vswhere` 发现 VS 2019/2022/2026，并检查 CMake 是否支持相应生成器。CMake 可以在 PATH 中，也可以使用 VS 自带版本。无需打开开发者命令行；Windows 自带 PowerShell 5.1 即可。

```powershell
# 查看清单、预览顺序；预览不会开始编译或写入构建目录
.\build.ps1 -List
.\build.ps1 -Plan

# 默认：所有 CMake 库，x64、Release、动态库、/MD
.\build.cmd

# 编译后生成 ZIP + SHA256 校验文件
.\build.cmd -Package

# 只编译指定库；自动补齐依赖，不必手动排序
.\build.ps1 -Library freetype,harfbuzz -Jobs 6

# Debug 独立存放，使用 /MDd
.\build.cmd -Configuration Debug

# 如需匹配原有 vc142 工具链，显式选择 VS 2019
.\build.cmd -VisualStudioVersion 2019

# 自定义 CMake 路径
.\build.ps1 -CMakePath 'C:\Tools\CMake\bin\cmake.exe'
```

自动模式选择 CMake 支持的最新已安装 VS。默认使用该 VS 的默认工具集。暂不支持 x86、ARM64、MinGW、静态 CRT 或统一切换静态库；zlib 本身构建为静态支持库，GLM 只安装头文件。**工具链、配置或链接方式变化后，LAB 主工程也必须使用相匹配的设置重新编译。** 新 DLL 的名字可能与原来 vc142 的手工版本不同，不应直接覆盖旧目录。

通用版 CMake 对 VS 2026 生成器的支持从 4.2 开始；部分 VS 内置版本有回移支持，脚本实际检查生成器能力，不只检查版本数字。参见 [CMake VS 2026 文档](https://cmake.org/cmake/help/latest/generator/Visual%20Studio%2018%202026.html)。CRT 选择遵循 [CMAKE_MSVC_RUNTIME_LIBRARY](https://cmake.org/cmake/help/latest/variable/CMAKE_MSVC_RUNTIME_LIBRARY.html)。

## 产物和增量构建

```text
.build/windows-x64-vs2026-md/Release/<库>/
  build/                   CMake 缓存和编译中间文件
  build.log                该库最近一次构建的完整日志
  install/                 尚未发布的临时安装结果
result/windows-x64-vs2026-md/Release/
  LABDepsConfig.cmake       可迁移的统一 CMake 入口
  <库>/include/            包含生成后的配置头
  <库>/lib/                .lib 文件
  <库>/bin/                DLL（如有）
  <库>/licenses/           对应许可证/源码声明
  <库>/build-info.json      工具链、配置、依赖、源码位置和构建时间
packages/
  LABdeps-*.zip
  LABdeps-*.zip.sha256
```

脚本按依赖顺序执行 `configure → build → install`。再次执行复用 CMake 构建缓存；安装目录每次重新生成，避免旧文件混入。一个库成功后才替换其产物目录；失败立即返回非零退出码，显示日志末尾及路径，保留此前已发布版本。多个库不是一个整体事务：失败前已完成的库会保留本次更新。相同工具链、配置有文件锁，防止两个构建或打包进程同时写入。

脚本不会向原来的 `result/libHeaders`、`result/libs/win_MSVC` 发布，也不会删除 `createAndroidLibs`。生成目录和 ZIP 不进入 Git。`build-info.json` 记录仓库 HEAD，但不递归计算源码哈希；有未提交的源码修改时，不能仅凭 HEAD 复现构建。发布正式版本前应提交所使用的源码与适配脚本。

## 依赖范围

| 名称 | 来源/处理 |
| --- | --- |
| zlib | 复用 Assimp 内附 1.2.13，外层适配生成 zconf.h，不触碰源码 |
| brotli | 独立构建编解码和 common 库 |
| libpng | 使用本次构建的 zlib |
| freetype | 使用 zlib、libpng、Brotli；关闭 BZip2 和 FreeType 内部 HarfBuzz 集成，避免循环依赖 |
| harfbuzz | 使用本次 FreeType；外层 imported target 绕过源码中写死的旧路径，保留 hb-ft 接口 |
| glfw | 关闭示例、测试和文档 |
| glm | 只安装头文件，绕过旧 CMake 入口及测试 |
| libhv | 仅把清单明确列出的构建输入复制到 `.build`，允许上游在副本中生成 hconfig.h 等文件 |
| lunasvg | 同时构建其附带的 plutovg |
| nfd | 关闭交互测试 |
| openal | 保留主库及数据，关闭示例/工具/测试 |
| yoga | 只构建 yogacore，避免根目录无条件下载 GTest；针对 DLL 导出关闭 C4251 警告，保留其他 /WX 检查 |
| assimp | 使用外部 zlib，关闭测试/示例/工具/Draco；自动安装生成的 config.h，并补上上游未安装的 revision.h |
| sqlite3 | 使用 `pluginLibs/sqlite3/sqlite3`，外层适配导出 DLL 并安装头文件，不运行原示例 |

这些选项是当前实验明确选择的功能范围，不代表与过去手工构建的全部可选功能相同。新增库时修改 `dependencies.json`；只有确有必要时才增加 `cmake/adapters` 分支。不要通过全目录扫描自动发现库。

### libffi

libffi 使用 Autotools，入口单独放在 `scripts/Build-Libffi.ps1`。它在 `.build` 副本里运行 Autotools，并通过上游 `msvcc.sh` 使用 MSVC；不会把 MinGW 产物当成 MSVC 产物。

先在现有 MSYS2 终端补齐工具（这些依赖不会由构建脚本自动安装）：

```bash
pacman -S --needed autoconf-wrapper automake-wrapper libtool make tar
```

```powershell
.\scripts\Build-Libffi.ps1 -Check
.\scripts\Build-Libffi.ps1 -MsysRoot C:\msys64
# 已具备 MSYS2 工具后，可纳入同一次构建和打包
.\build.cmd -IncludeLibffi -Package
```

脚本会保留 DLL 的实际文件名，不能随意重命名 DLL，否则导入库内记录的名字会失效。当前 Libtool 的 MSVC 安装规则对导入库名称处理有误，因此在 `make` 成功后明确安装链接器生成的 DLL 和导入库，不忽略安装错误，也不把 DLL 当成 `.lib`。

### FFmpeg 与原来的手工资源

本仓库只有 FFmpeg 产物，没有其源码；不会声称能从这里重编 FFmpeg。`result/libHeaders` 里的 utfcpp、zip 等旧资源，以及原有 `ffi.lib`/DLL，仍可通过旧产物快照迁移：

```powershell
.\scripts\Package.ps1 -Legacy
```

该快照包含原有 `libHeaders/` 和 `libs/win_MSVC/`，保留目录与文件名。包内标明其工具链、架构、配置及完整性未经过重新构建验证。原 `bin` 中的 LAB.dll/LABScript.dll 也会随快照保留。不要将它与新构建目录直接混合。

## 换一台 Windows

有两条路径：

1. **需要编译**：复制或检出仓库（保留当前 vendored 源码），安装 C++ 工具链，执行 `build.cmd -Package`。
2. **只需要编译结果**：复制 `packages` 中的 ZIP 和同名 `.sha256` 文件，再用解压脚本校验到一个全新目录；不需要 `baseLibs` 或原构建机器。

```powershell
# 构建后也可单独重新打包，不触发编译
.\scripts\Package.ps1 -InputDirectory .\result\windows-x64-vs2026-md\Release

# 目的目录必须不存在；校验失败会清理本次新建的目的目录
.\scripts\Import-Package.ps1 -Archive D:\Transfer\LABdeps-example.zip -Destination D:\SDK\LABdeps
```

ZIP 包内有文件清单及每个文件的 SHA256；解压脚本先校验整个 ZIP，再校验各文件。哈希校验用于发现传输损坏，不替代可信分发渠道。可以只复制 ZIP 和 `.sha256` 手工校验解压；自动导入需一并复制 `Import-Package.ps1` 和 `Build.Common.ps1`。

打包会收集所选产物目录中已经成功安装的所有库，包括此前单独构建的 libffi；不会额外读取旧目录中的 FFmpeg 或手工头文件。具体内容以 `package-manifest.json` 中的 `libraries` 及各库的 `build-info.json` 为准。消费者需要相匹配的 MSVC 运行时；Debug 包依赖调试运行时，主要供开发机使用。

### CMake 消费示例

```cmake
# 指向已解压目录，或 result 下对应工具链的 Release/Debug 目录
set(LABDeps_DIR "D:/SDK/LABdeps")
find_package(LABDeps CONFIG REQUIRED COMPONENTS freetype harfbuzz glfw)
target_link_libraries(MyApp PRIVATE LAB::freetype LAB::harfbuzz LAB::glfw)
lab_deps_copy_runtime(MyApp)
```

每个已构建库都有 `LAB::<清单名称>`；`LAB::all` 用于链接包内全部库。`lab_deps_copy_runtime` 会把包内的 DLL 复制到目标程序目录。此入口使用相对位置，适合迁移；上游自身安装的 CMake/pkg-config 文件可能保留原构建路径，优先使用 LAB 入口。Visual Studio 多配置工程需显式构建与所选包一致的 Debug/Release，不要共用一个包链接两种配置。

## 验证

```powershell
# 顺序、循环依赖、路径边界、发布失败回退
.\scripts\Test-Orchestration.ps1

# 编译并运行实际使用头文件、.lib 和 DLL 的 C++ 消费者
.\scripts\Test-Package.ps1 -InputDirectory .\result\windows-x64-vs2026-md\Release
# 同样可指向解压到其他位置的包
.\scripts\Test-Package.ps1 -InputDirectory D:\SDK\LABdeps
```

冒烟测试仅调用包内已经存在的库；它验证压缩往返、FreeType 初始化、HarfBuzz/FreeType 接口、SVG 渲染、Yoga 布局、SQLite 内存数据库等，不打开窗口或音频设备。它不替代各上游的完整测试或 LAB 主工程集成测试。

2026-10-28 实验验证：本机 VS 2026 18.3 / MSVC 14.50 / CMake 4.1.2-msvc8，Windows PowerShell 5.1 入口通过。清单中的 14 项 CMake 依赖及 libffi 均已产出 Release、Debug 两套结果；两套完整包分别解压到带空格的新目录，683 个文件的校验及 C++ 编译、链接、运行全部通过，包括 libffi 的 `ffi_call`。原手工产物快照的 391 个文件也通过导入校验。VS 2019/2022 的构建以及 LAB 主程序接入尚未实际验证。

## 源码存储的后续方向

本轮先保留 vendored 源码：其中已有 LAB 的定制（如 HarfBuzz 路径、Yoga 动态库设置），贸然改成包管理器或直接拉取上游版本会丢失这些差异。

后续建议逐库迁移到“**固定版本源码压缩包 + SHA256 + 独立补丁**”，把压缩包与二进制 ZIP 放在团队制品存储或发布附件中，主仓库只维护锁定清单、补丁、脚本。这样换机器可直接下载经过验证的二进制，需要重建时再按清单获取源码。迁移前逐库确认来源版本、定制差异、许可证及 LAB 功能需求；`*-master`/`*-main` 目录名不能当作版本号。

暂不增加远端下载、CI 发布、Git 历史重写、submodule 转换或源目录搬迁。先验证 Windows 工作流，再将平台参数和适配层扩展到 macOS/Android。
