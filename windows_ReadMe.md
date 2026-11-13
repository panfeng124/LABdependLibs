# libFFI编译
 
在windows编译libffi需要使用msys2  
msys2下载页面https://www.msys2.org/ 下载后安装

打开MSYS2 MINGW64
```MINGW64
pacman -S base-devel mingw-w64-x86_64-toolchain autoconf automake libtool
```
base-devel：提供基本开发工具（如 make）。
mingw-w64-x86_64-toolchain：安装 MinGW 编译工具链。
autoconf、automake、libtool：构建 libffi 所需

cd 进入libffi的文件加目录，如
```MINGW64
cd E:/code/LAB/LABdependLibs/baseLibs/libffi-master
```

生成configure等需要的文件等
```MINGW64
./autogen.sh
```

生成配置文件
```MINGW64
./configure prefix=E:/code/LAB/LABdependLibs/baseLibs/libffi-master/buildResult --enable-debug --disable-docs
```
--prefix：设置编译结果的安装路径。例如：--prefix=E:/code/LAB/LABdependLibs/baseLibs/libffi-master/buildResult
--host：指定目标平台，Windows 64 位为 x86_64-w64-mingw32，32 位为 i686-w64-mingw32

注意路劲分割符号，使用/

```MINGW64
make
make install
```
在指定的buildResult目录中，有编译结果。
在编译时可能有报错，忽略不管，我这边也编译成功了。


#sqlLite
例子程序不能运行，极大概率是因为动态库没有放在程序文件夹中。

# Windows x64 项目迁移

将 `LABdependLibs`、`LABScript`、`LABEngine` 放在同一父目录。迁移已有环境时应一并复制完整的 `LABdependLibs/result`，Git 会忽略其中的编译产物。先编译 LABScript，生成 `LABScript.lib` 和 `LABScript.dll`，再配置和编译 LABEngine。

以下命令在 Visual Studio 2022 的 x64 Developer PowerShell 中运行，工作目录为 `LABdependLibs`。项目依赖的头文件放在 `result/libHeaders`，依赖的 x64 导入库和 DLL 分别放在 `result/libs/win_MSVC/lib` 与 `result/libs/win_MSVC/bin`。

### FFmpeg

项目使用自编译的 MSVC x64 动态库，SDK 文件名为 `ffmpeg-windows-x64-sdk.zip`，SHA256 为 `89c1422fbc2c96d845abb6837e9b84cf1e82eb6994c47066a40f4c080d5211b2`。构建版本字符串为 `8.0.git`。对应组件版本为 avcodec 63.11.101、avformat 63.6.100、avutil 61.7.100、swresample 7.3.100、swscale 10.2.100。源码构建步骤见[Windows + MSVC 编译 FFmpeg 备忘](<document/Windows + MSVC 编译 FFmpeg 备忘.md>)。

在新机器上把该压缩包放在 `LABdependLibs` 根目录，然后运行以下命令。包内已按 `result` 目录布局放好公共头文件、五个导入库、五个 DLL 和许可证。已有其他 FFmpeg 版本时，先将该版本的五个头文件目录、导入库、DLL 和许可证移到备份目录，再解压。保留同一套 SDK 的所有文件，随后在新构建目录中重新配置并编译 LABEngine。

```powershell
$sdk = 'ffmpeg-windows-x64-sdk.zip'
$expected = '89c1422fbc2c96d845abb6837e9b84cf1e82eb6994c47066a40f4c080d5211b2'
if ((Get-FileHash -LiteralPath $sdk).Hash -ne $expected) { throw 'FFmpeg SDK 校验失败' }
Expand-Archive -LiteralPath $sdk -DestinationPath . -Force
```

### libffi

如果已经有与 `result/libHeaders/FFI` 匹配的 x64 `libffi-8.dll`（本机为 libffi 3.4.6），可从它的导出表生成 MSVC 导入库。`ffi_type_*` 是数据符号，必须在导出定义中标注 `DATA`。下面使用上文 MSYS2 步骤生成的 DLL。

```powershell
$ffiDll = 'baseLibs/libffi-master/buildResult/bin/libffi-8.dll'
$work = 'build/ffi'
$winDeps = 'result/libs/win_MSVC'
New-Item -ItemType Directory -Force $work | Out-Null
$symbols = dumpbin /nologo /exports $ffiDll | ForEach-Object {
    if ($_ -match '^\s*\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+(ffi_\w+)\s*$') {
        $name = $Matches[1]
        if ($name.StartsWith('ffi_type_')) { "$name DATA" } else { $name }
    }
}
if (!$symbols) { throw '未读取到 libffi 的导出表' }
@('LIBRARY ffi-8.dll', 'EXPORTS') + $symbols | Set-Content -Encoding ascii "$work/ffi.def"
lib /nologo /machine:x64 "/def:$work/ffi.def" "/out:$work/FFI.lib"
if ($LASTEXITCODE) { throw '生成 FFI.lib 失败' }
Copy-Item "$work/FFI.lib" "$winDeps/lib/" -Force
Copy-Item $ffiDll "$winDeps/bin/ffi-8.dll" -Force
```

### LunaSVG

```powershell
$work = 'build/lunasvg-win64'
$winDeps = 'result/libs/win_MSVC'
cmake -S baseLibs/lunasvg -B $work -G "Visual Studio 17 2022" -A x64 -DBUILD_SHARED_LIBS=ON -DLUNASVG_BUILD_EXAMPLES=OFF
cmake --build $work --config Release --parallel
Copy-Item "$work/Release/lunasvg.lib" "$winDeps/lib/" -Force
Copy-Item "$work/Release/lunasvg.dll", "$work/plutovg/Release/plutovg.dll" "$winDeps/bin/" -Force
```
