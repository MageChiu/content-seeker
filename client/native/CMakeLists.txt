cmake_minimum_required(VERSION 3.14)
project(seeker LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

# 构建选项
option(SEEKER_BUILD_SHARED "构建动态库" ON)
option(SEEKER_BUILD_TESTS "构建测试" OFF)

# 源文件
set(SEEKER_SOURCES
    src/core/seeker_context.cpp
    src/core/thread_pool.cpp
    src/core/callback_dispatcher.cpp
    src/extractor/extractor_registry.cpp
    src/extractor/plugins/bilibili_plugin.cpp
    src/extractor/plugins/youtube_plugin.cpp
    src/extractor/plugins/youtube_cipher.cpp
    src/utils/json_utils.cpp
    src/utils/js_engine.cpp
    src/utils/wbi_sign.cpp
    src/utils/muxer_fmp4.cpp
    src/seeker_api.cpp
)

# Apple 平台使用 Objective-C++ HTTP 客户端 + AVFoundation muxer
# 其他平台使用 fMP4 muxer 作为 seeker_mux_av_to_mp4 实现
if(APPLE)
    list(APPEND SEEKER_SOURCES
        src/utils/http_client_apple.mm
        src/utils/muxer_apple.mm
    )
else()
    list(APPEND SEEKER_SOURCES
        src/utils/http_client_stub.cpp
        src/utils/muxer_default.cpp
    )
endif()

# QuickJS 集成（如果源文件存在）
set(QUICKJS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/quickjs)
set(SEEKER_ENABLE_QUICKJS OFF)
if(EXISTS "${QUICKJS_DIR}/quickjs.c" AND NOT WIN32)
    set(SEEKER_ENABLE_QUICKJS ON)
    message(STATUS "QuickJS found, enabling JS engine")
    set(QUICKJS_VERSION "embedded")
    if(EXISTS "${QUICKJS_DIR}/VERSION")
        file(STRINGS "${QUICKJS_DIR}/VERSION" QUICKJS_VERSION LIMIT_COUNT 1)
    endif()
    list(APPEND SEEKER_SOURCES
        ${QUICKJS_DIR}/quickjs.c
        ${QUICKJS_DIR}/libregexp.c
        ${QUICKJS_DIR}/libunicode.c
        ${QUICKJS_DIR}/cutils.c
        ${QUICKJS_DIR}/libbf.c
    )
    set(SEEKER_INCLUDE_DIRS
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party
        ${QUICKJS_DIR}
    )
elseif(EXISTS "${QUICKJS_DIR}/quickjs.c" AND WIN32)
    message(STATUS "QuickJS found, but disabled on Windows; JS engine will be stubbed")
    set(SEEKER_INCLUDE_DIRS
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party
    )
else()
    message(STATUS "QuickJS not found, JS engine will be stubbed")
    set(SEEKER_INCLUDE_DIRS
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party
    )
endif()

# 库目标
if(SEEKER_BUILD_SHARED)
    add_library(seeker SHARED ${SEEKER_SOURCES})
    target_compile_definitions(seeker PRIVATE SEEKER_BUILDING_DLL)
else()
    add_library(seeker STATIC ${SEEKER_SOURCES})
endif()

target_include_directories(seeker PUBLIC ${SEEKER_INCLUDE_DIRS})

if(SEEKER_ENABLE_QUICKJS)
    # Mirror the upstream QuickJS Makefile so embedded sources compile
    # correctly outside of its native build system.
    target_compile_definitions(seeker PRIVATE
        _GNU_SOURCE
        CONFIG_VERSION="${QUICKJS_VERSION}"
    )
endif()

# 平台特定配置
if(ANDROID)
    # QuickJS uses libm symbols such as pow/sin/cos/fmod on Android.
    # Link libm explicitly to avoid arm64 release link failures.
    target_link_libraries(seeker PRIVATE
        log
        m
    )
elseif(APPLE)
    # 链接 Foundation 框架（NSURLSession HTTP 客户端需要）
    find_library(FOUNDATION_FRAMEWORK Foundation)
    find_library(AVFOUNDATION_FRAMEWORK AVFoundation)
    find_library(COREMEDIA_FRAMEWORK CoreMedia)
    target_link_libraries(seeker PRIVATE
        ${FOUNDATION_FRAMEWORK}
        ${AVFOUNDATION_FRAMEWORK}
        ${COREMEDIA_FRAMEWORK}
    )
    set_target_properties(seeker PROPERTIES
        FRAMEWORK FALSE
        MACOSX_RPATH ON
    )
    # 允许 .mm 文件编译为 Objective-C++
    set_source_files_properties(
        src/utils/http_client_apple.mm
        src/utils/muxer_apple.mm
        PROPERTIES COMPILE_FLAGS "-fobjc-arc"
    )
elseif(WIN32)
    target_compile_definitions(seeker PRIVATE WIN32_LEAN_AND_MEAN)
    # QuickJS headers use designated initializers in C++ context on MSVC.
    # Build the native target as C++20 on Windows to keep third_party sources untouched.
    target_compile_features(seeker PRIVATE cxx_std_20)
endif()

# 导出符号
set_target_properties(seeker PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)
