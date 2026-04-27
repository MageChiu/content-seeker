# Content Seeker 客户端架构文档

## 1. 架构总览

Content Seeker 客户端采用 **Flutter + C++ Native Core** 分层架构，将 UI 交互保留在 Dart/Flutter 层，将音视频的流提取、协议处理、播放控制下沉到 C++ 原生层（`libseeker`）。

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter UI Layer (Dart)                    │
│        播放控件 / 搜索 / 列表 / 设置 / 状态管理               │
└──────────────────────────┬──────────────────────────────────┘
                           │ dart:ffi (同步 + 异步回调)
┌──────────────────────────▼──────────────────────────────────┐
│                C++ Native Core (libseeker)                    │
│                                                              │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────────┐  │
│  │StreamExtractor│  │ProtocolEngine │  │PlayerController │  │
│  │              │  │               │  │                 │  │
│  │- 站点插件     │  │- HLS (AES)   │  │- 统一播放接口    │  │
│  │- URL→流映射  │  │- DASH MPD    │  │- 多轨管理       │  │
│  │- 签名/加密   │  │- HTTP-FLV    │  │- 缓冲策略       │  │
│  │- Cookie管理  │  │- RTMP/RTSP   │  │- 自适应码率     │  │
│  │- 反爬对抗    │  │- WebSocket   │  │- 硬件加速调度    │  │
│  └──────────────┘  └───────────────┘  └─────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           FFmpeg / libmpv (底层解码与渲染引擎)          │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

## 2. 设计原则

- **Dart 只做 UI**：所有音视频相关的网络请求、协议解析、播放控制逻辑归入 C++ 层
- **C API 边界**：C++ 层对外暴露纯 C 接口（`extern "C"`），确保 dart:ffi 兼容
- **异步优先**：流提取等耗时操作在 C++ 内部线程池执行，通过回调通知 Dart
- **插件化扩展**：站点提取器以插件形式注册，新增站点不修改框架代码
- **跨平台一致**：一份 C++ 代码编译到 Android/iOS/macOS/Windows/Linux，行为完全一致
- **复用 FFmpeg**：不单独引入 FFmpeg 副本，复用 media_kit_libs 已提供的预编译库

## 3. 核心模块设计

### 3.1 StreamExtractor（流提取器）

**职责**：将任意内容 URL 转换为可直接播放的流地址。

| 组件 | 说明 |
|------|------|
| ExtractorRegistry | 插件注册中心，管理所有站点提取器 |
| SitePlugin | 站点插件接口，每个支持的站点实现一个 |
| HttpClient | 内置 HTTP 客户端（基于 curl 或自研），支持 Cookie/Header 管理 |
| CryptoUtils | 签名算法库（HMAC、RSA、自定义 cipher） |

**已规划的站点插件**：
- Bilibili（wbi 签名、DASH 流提取）
- YouTube（sig cipher 解密、adaptive formats）
- 通用提取器（从 HTML 页面探测 video/source 标签）

### 3.2 ProtocolEngine（协议引擎）

**职责**：处理各种流媒体传输协议，输出标准化数据流。

| 协议 | 能力 |
|------|------|
| HLS | M3U8 多级解析、AES-128/SAMPLE-AES 解密、多码率自适应切换 |
| DASH | MPD 解析、SegmentTemplate/SegmentList、Period 切换 |
| HTTP-FLV | 直播长连接、自动重连 |
| RTMP/RTSP | 实时流支持 |
| HTTP Progressive | 标准 HTTP Range 下载 |

### 3.3 PlayerController（播放控制器）

**职责**：在 libmpv 之上提供统一播放控制接口。

| 能力 | 说明 |
|------|------|
| 统一播放接口 | 屏蔽底层协议差异，上层只需 play(url) |
| 自适应码率 | 实时带宽估算 + 无缝质量切换 |
| 智能缓冲 | 根据网络状况动态调整缓冲策略 |
| 多轨同步 | DASH 分离流的 audio+video 精确同步 |
| 硬件加速 | 按平台/编码自动选择最优解码器 (VideoToolbox/MediaCodec/DXVA2/VAAPI) |

## 4. 目录结构

```
client/
├── lib/                              # Dart 层
│   ├── main.dart                     # 应用入口
│   ├── native_bridge/                # dart:ffi 桥接层
│   │   ├── seeker_bindings.dart      # C API 绑定声明
│   │   ├── seeker_native.dart        # 高层封装（异步、类型安全）
│   │   └── native_library_loader.dart # 动态库加载（各平台路径）
│   ├── app/                          # 应用层
│   │   ├── bootstrap/                # 启动初始化
│   │   ├── download/                 # 下载协调
│   │   ├── feature_flags/            # 功能开关
│   │   └── playback/                 # 播放状态协调
│   ├── core/                         # 核心抽象
│   ├── domain/                       # 领域模型
│   ├── features/                     # 功能模块 (UI)
│   │   ├── player/                   # 播放器页面
│   │   ├── search/                   # 搜索页面
│   │   └── settings/                 # 设置页面
│   ├── infra/                        # 基础设施
│   ├── models/                       # 数据模型
│   └── platform/                     # 平台能力检测
│
├── native/                           # C++ Native Core (libseeker)
│   ├── CMakeLists.txt                # 顶层构建配置
│   ├── include/seeker/               # 公共头文件 (C API)
│   │   ├── seeker.h                  # 库初始化/销毁
│   │   ├── extractor.h              # 流提取器 API
│   │   ├── protocol.h               # 协议引擎 API
│   │   ├── muxer.h                  # 音视频合并 API（边播边存后处理）
│   │   └── player.h                 # 播放控制 API
│   ├── src/                          # 内部实现 (C++)
│   │   ├── core/                     # 核心基础设施
│   │   │   ├── seeker_context.h/cpp  # 全局上下文
│   │   │   ├── thread_pool.h/cpp    # 线程池
│   │   │   └── callback_dispatcher.h/cpp # 回调分发
│   │   ├── extractor/                # 流提取器实现
│   │   │   ├── extractor_registry.h/cpp
│   │   │   ├── plugin_interface.h   # 插件接口定义
│   │   │   └── plugins/             # 站点插件
│   │   │       ├── bilibili_plugin.h/cpp
│   │   │       ├── youtube_plugin.h/cpp
│   │   │       └── generic_plugin.h/cpp
│   │   ├── protocol/                 # 协议引擎实现
│   │   │   ├── hls_engine.h/cpp
│   │   │   ├── dash_engine.h/cpp
│   │   │   └── http_client.h/cpp
│   │   ├── player/                   # 播放控制实现
│   │   │   ├── player_core.h/cpp
│   │   │   ├── adaptive_selector.h/cpp
│   │   │   └── buffer_manager.h/cpp
│   │   └── utils/                    # 工具模块
│   │       ├── crypto.h/cpp
│   │       ├── json.h/cpp
│   │       └── url_parser.h/cpp
│   └── third_party/                  # 第三方库 (header-only 或 git submodule)
│       └── nlohmann/                 # JSON 库
│
├── android/                          # Android 平台集成
│   └── app/src/main/
│       └── CMakeLists.txt            # 引入 native/ 构建
├── ios/                              # iOS 平台集成
│   └── native_seeker.podspec         # CocoaPods 集成
├── macos/                            # macOS 平台集成
│   └── native_seeker.podspec         # CocoaPods 集成
├── windows/                          # Windows 平台集成
│   └── CMakeLists.txt                # 已有, 追加 native/ 子目录
├── linux/                            # Linux 平台集成 (预留)
│
├── docs/                             # 文档
│   ├── ARCHITECTURE.md               # 本文件
│   └── video-source-expansion-design.md
├── test/                             # 测试
├── pubspec.yaml                      # Dart 依赖
└── Makefile                          # 常用命令
```

## 5. FFI 接口设计

### 5.1 C API 约定

- 所有函数以 `seeker_` 前缀命名
- 返回值使用 `int` 错误码（0 = 成功）
- 复杂数据通过 JSON 字符串传递（简化跨语言序列化）
- 异步操作通过函数指针回调通知结果
- 句柄类型使用 `void*` 不透明指针

### 5.2 核心接口

```c
// 生命周期
int seeker_init(const char* config_json);
void seeker_destroy(void);
const char* seeker_version(void);

// 流提取
typedef void (*seeker_extract_callback)(int request_id, const char* result_json, const char* error);
int seeker_extract_stream(const char* url, const char* options_json, seeker_extract_callback cb);
void seeker_cancel_extract(int request_id);

// 播放控制
typedef void (*seeker_player_event_callback)(int player_id, const char* event_json);
int seeker_player_create(seeker_player_event_callback cb);
int seeker_player_open(int player_id, const char* stream_json);
int seeker_player_play(int player_id);
int seeker_player_pause(int player_id);
int seeker_player_seek(int player_id, double position_seconds);
int seeker_player_set_rate(int player_id, double rate);
int seeker_player_destroy(int player_id);
```

## 6. 平台集成策略

| 平台 | 构建方式 | 产物 |
|------|----------|------|
| Android | CMake (NDK) 在 Gradle 中引入 | `libseeker.so` |
| iOS | podspec 引入源码，Xcode 编译 | `libseeker.a` (静态库) |
| macOS | podspec 引入源码，Xcode 编译 | `libseeker.dylib` |
| Windows | CMake 子目录 | `seeker.dll` |
| Linux | CMake 子目录 | `libseeker.so` |

## 7. 开发阶段

| 阶段 | 目标 | 验收标准 |
|------|------|----------|
| Phase 1 | 骨架搭建 | Dart 通过 FFI 调用 C++ 返回版本号 |
| Phase 2 | StreamExtractor 核心 | Bilibili/YouTube URL 在 <200ms 内返回可播放流 |
| Phase 3 | ProtocolEngine | 加密 HLS、DASH MPD 可正常播放 |
| Phase 4 | PlayerController | 自适应码率、智能缓冲、多轨同步 |
| Phase 5 | 通用提取器 + 扩展 | 任意网页 URL 尝试自动提取可播放流 |

## 8. 技术选型

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 语言 | C++17 | FFmpeg/libmpv 生态原生语言 |
| 构建 | CMake 3.14+ | Flutter plugin 标准构建系统 |
| FFI | dart:ffi | 零拷贝、低延迟 |
| JSON | nlohmann/json (header-only) | 轻量、无依赖 |
| HTTP | libcurl 或平台原生 | 成熟稳定 |
| 并发 | std::thread + 线程池 | 标准库，无外部依赖 |
| 播放引擎 | 保留 libmpv (media_kit) | 成熟稳定，硬件加速完善 |

## 9. 废弃计划

Phase 2 完成后，以下现有 Dart 代码将被 C++ 实现替代并移除：

- `lib/features/player/bilibili_playback_resolver.dart`
- `lib/features/player/desktop_yt_dlp_resolver*.dart`
- `lib/features/player/playback_resolver.dart` 中的流提取逻辑

播放页面 (`player_page.dart`) 保留，但其播放控制逻辑将改为调用 native_bridge。
