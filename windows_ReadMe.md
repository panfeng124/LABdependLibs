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