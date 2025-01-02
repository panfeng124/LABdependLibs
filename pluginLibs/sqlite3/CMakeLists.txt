cmake_minimum_required(VERSION 3.10)

# 设置项目名称和版本
project(sqlite3 VERSION 3.0)

# 设置C++标准
set(CMAKE_CXX_STANDARD 11)

option(BUILD_SHARED "build shared library" ON)
option(BUILD_EXECUTABLE "build executable" ON)

if(BUILD_SHARED)

    # 选择SQLite源代码目录
    set(SQLITE_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/sqlite3")

    # 包含SQLite源文件
    set(SOURCE_FILES
            ${SQLITE_SRC_DIR}/sqlite3.c
    )

    # 设置动态库名称
    set(LIBRARY_OUTPUT_PATH ${CMAKE_CURRENT_SOURCE_DIR}/lib)

    # 定义动态库的输出目标
    add_library(sqlite3 SHARED ${SOURCE_FILES})

    # 设置SQLite编译选项
    target_compile_definitions(sqlite3 PRIVATE SQLITE_OMIT_LOAD_EXTENSION)
    target_compile_definitions(sqlite3 PRIVATE SQLITE_ENABLE_JSON1)

    # 设置SQLite的头文件搜索路径
    target_include_directories(${PROJECT_NAME} PUBLIC
            ${SQLITE_SRC_DIR}
    )
    install(FILES ${SQLITE_SRC_DIR}/sqlite3.h DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/include)


    # 如果需要CMake支持SQLite的其他配置，可以启用如下选项
    # target_compile_definitions(sqlite3 PRIVATE SQLITE_ENABLE_JSON1)
    # target_compile_definitions(sqlite3 PRIVATE SQLITE_ENABLE_FTS5)

    # 安装动态库到系统目录（可选）
    # install(TARGETS sqlite3 DESTINATION lib)
    # install(FILES ${SQLITE_SRC_DIR}/sqlite3.h DESTINATION include)
endif ()

if(BUILD_EXECUTABLE)
    include_directories(${CMAKE_CURRENT_SOURCE_DIR}/sqlite3)

    add_executable(${PROJECT_NAME}_APP
            main.cpp
    )
    target_link_libraries(${PROJECT_NAME}_APP
            ${CMAKE_CURRENT_SOURCE_DIR}/lib/libsqlite3.dll
    )
endif ()
