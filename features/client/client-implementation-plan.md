# Client 播放器能力改造 Implementation Plan

## 1. 文档目标

本文基于前一份调研文档，进一步拆解出一个可执行的 `Implementation Plan`，用于指导 `client` 从当前的“搜索 + 轻量播放”状态，逐步演进为：

- 可稳定播放
- 可下载
- 可离线播放
- 可按平台分级启用高级能力
- 可保证 `macOS`、`Windows`、`iOS`、`Android` 都能编译运行

本文重点解决三类问题：

1. 具体怎么分阶段推进
2. 代码目录和模块怎么落
3. 如果某些能力只有 `desktop` 才具备，如何做到不与移动端冲突

## 2. 总体实施原则

### 2.1 核心原则

- 保留 `Flutter` 作为跨平台 UI 和应用编排层
- 将播放、下载、缓存、来源解析、平台增强能力从页面层剥离
- 所有 `desktop-only` 能力都必须通过“适配层 + feature gate”接入
- `desktop` 与 `mobile` 允许能力不同，但不能让代码互相污染
- 构建策略必须优先保证：
  - `macOS` 可编译
  - `Windows` 可编译
  - `iOS` 可编译运行
  - `Android` 可编译运行

### 2.2 阶段交付原则

- 第一阶段只做“架构重构 + 稳定播放”
- 第二阶段做“普通下载闭环”
- 第三阶段做“离线库与缓存增强”
- 第四阶段才考虑“边下边播”
- 第五阶段才考虑“桌面本地工具链 / torrent / 更强 resolver”

### 2.3 平台策略原则

- `desktop` 优先承接复杂能力
- `mobile` 优先承接稳定能力
- 每项能力必须显式声明支持平台
- 每项能力必须定义：
  - 功能是否启用
  - 运行时是否可用
  - 编译期是否允许依赖该实现

## 3. 目标交付范围

## 3.1 Phase 1 目标

- 抽离播放器应用层
- 建立 resolver 策略层
- 建立统一播放状态模型
- 保证当前核心播放链路更稳定
- 建立平台能力和 feature gate 的基础设施

## 3.2 Phase 2 目标

- 支持直链文件下载
- 支持下载任务列表
- 支持断点续传、暂停恢复
- 支持下载状态持久化
- 支持下载完成后的离线播放

## 3.3 Phase 3 目标

- 建立离线媒体库
- 建立缓存管理与清理策略
- 记录播放历史与离线资源索引

## 3.4 Phase 4 目标

- 建立本地缓存代理
- 支持部分资源边下边播
- 支持 seek 场景下的优先下载

## 3.5 Phase 5 目标

- 桌面端增强来源解析能力
- 接入本地工具链
- 评估 `torrent` / `magnet` 能力

## 4. 非目标

以下内容不建议在第一轮实现中承诺：

- 所有平台同时具备完全一致的高级功能
- `iOS` 立刻支持与桌面同等的本地工具链增强
- 第一期就支持 `torrent`
- 第一期就支持完整 `m3u8` / DASH 离线化
- 第一期就支持通用站点边下边播

## 5. 推荐代码目录结构

建议在 `client/lib/` 下逐步演进到如下结构：

```text
client/lib/
├── app/
│   ├── bootstrap/
│   │   ├── app_bootstrap.dart
│   │   ├── dependency_container.dart
│   │   └── app_environment.dart
│   ├── playback/
│   │   ├── playback_coordinator.dart
│   │   ├── playback_session_controller.dart
│   │   ├── playback_state.dart
│   │   └── playback_commands.dart
│   ├── download/
│   │   ├── download_coordinator.dart
│   │   ├── download_queue_controller.dart
│   │   ├── download_state.dart
│   │   └── download_commands.dart
│   ├── offline/
│   │   ├── offline_library_coordinator.dart
│   │   ├── offline_library_state.dart
│   │   └── playback_history_service.dart
│   └── feature_flags/
│       ├── app_feature.dart
│       ├── feature_gate.dart
│       ├── feature_registry.dart
│       └── feature_policy.dart
├── domain/
│   ├── media/
│   │   ├── resolved_media.dart
│   │   ├── playable_source.dart
│   │   ├── playback_session.dart
│   │   └── source_capability.dart
│   ├── download/
│   │   ├── download_task_entity.dart
│   │   ├── download_status.dart
│   │   ├── download_request.dart
│   │   ├── offline_asset.dart
│   │   └── cache_entry.dart
│   ├── storage/
│   │   ├── storage_location.dart
│   │   └── storage_policy.dart
│   └── errors/
│       ├── app_error.dart
│       ├── playback_error.dart
│       ├── download_error.dart
│       └── resolver_error.dart
├── infra/
│   ├── resolver/
│   │   ├── resolver_orchestrator.dart
│   │   ├── resolver_strategy.dart
│   │   ├── direct_media_resolver.dart
│   │   ├── bilibili_resolver.dart
│   │   ├── web_embed_resolver.dart
│   │   ├── external_open_resolver.dart
│   │   └── desktop_tools/
│   │       ├── desktop_tool_resolver.dart
│   │       ├── desktop_tool_resolver_io.dart
│   │       └── desktop_tool_resolver_stub.dart
│   ├── playback/
│   │   ├── player_adapter.dart
│   │   ├── media_kit_player_adapter.dart
│   │   └── player_adapter_factory.dart
│   ├── download/
│   │   ├── download_engine.dart
│   │   ├── background_download_engine.dart
│   │   ├── progressive_download_engine.dart
│   │   ├── download_repository_impl.dart
│   │   └── download_storage_manager.dart
│   ├── storage/
│   │   ├── app_database.dart
│   │   ├── download_dao.dart
│   │   ├── offline_asset_dao.dart
│   │   ├── resolver_cache_dao.dart
│   │   └── file_store.dart
│   ├── cache_proxy/
│   │   ├── media_cache_proxy.dart
│   │   ├── media_cache_proxy_stub.dart
│   │   └── chunk_scheduler.dart
│   └── telemetry/
│       ├── app_logger.dart
│       ├── playback_metrics.dart
│       └── resolver_metrics.dart
├── platform/
│   ├── capabilities/
│   │   ├── platform_capabilities.dart
│   │   ├── platform_capability_service.dart
│   │   ├── platform_capability_service_io.dart
│   │   └── platform_capability_service_stub.dart
│   ├── desktop_tools/
│   │   ├── desktop_tools_bridge.dart
│   │   ├── desktop_tools_bridge_io.dart
│   │   └── desktop_tools_bridge_stub.dart
│   ├── background_tasks/
│   │   ├── background_task_bridge.dart
│   │   ├── background_task_bridge_io.dart
│   │   └── background_task_bridge_stub.dart
│   └── notifications/
│       ├── notification_bridge.dart
│       ├── notification_bridge_io.dart
│       └── notification_bridge_stub.dart
├── ui/
│   ├── player/
│   ├── downloads/
│   ├── offline/
│   └── settings/
├── features/
│   ├── search/
│   └── settings/
├── models/
└── main.dart
```

## 6. 模块职责说明

### 6.1 `app/`

职责：

- 应用流程编排
- UI 与领域层之间的状态聚合
- feature gate 读取
- 协调播放、下载、离线库

不负责：

- 直接访问平台 API
- 直接写文件
- 直接调用本地工具链

### 6.2 `domain/`

职责：

- 纯业务模型
- 枚举、实体、错误类型、能力描述

要求：

- 不依赖 Flutter Widget
- 尽量不依赖第三方平台插件

### 6.3 `infra/`

职责：

- 具体实现层
- resolver 实现
- 下载引擎实现
- 文件存储
- 数据库
- cache proxy

### 6.4 `platform/`

职责：

- 平台专属能力封装
- 通过 conditional import 提供不同实现
- 让上层永远只依赖抽象接口

### 6.5 `ui/`

职责：

- 页面、组件、交互
- 不直接决定某个能力是否支持
- 从 `app/feature_flags` 和 `app/*_coordinator` 获取状态

## 7. Feature 控制与平台适配设计

这是本次 Implementation Plan 的关键部分。

### 7.1 为什么必须单独设计

因为后续一定会出现以下情况：

- `desktop` 支持本地工具链解析
- `mobile` 不支持本地工具链解析
- `desktop` 可能支持更强下载与缓存能力
- `mobile` 只能支持普通 HTTP 下载
- `torrent` 很可能只适合桌面

如果没有 feature 控制和平台适配层，结果通常会是：

- `Platform.isMacOS` 判断散落全项目
- `dart:io` 误进移动端或 Web 编译链路
- UI 显示了当前平台根本不支持的入口
- 某个平台构建通过，另一个平台编译失败

### 7.2 两层控制模型

建议采用“两层控制”：

#### 第一层：编译期适配

作用：

- 确保不同平台能编译通过
- 隔离 `dart:io`、本地进程、桌面工具链等实现

方式：

- conditional import
- `*_stub.dart`
- `*_io.dart`

#### 第二层：运行时 feature gate

作用：

- 控制功能入口是否展示
- 控制能力是否启用
- 控制实验特性是否灰度打开

方式：

- `FeatureGate`
- `FeatureRegistry`
- `PlatformCapabilities`

### 7.3 推荐的 Feature 定义

建议统一枚举：

```dart
enum AppFeature {
  stablePlayback,
  basicDownload,
  offlineLibrary,
  progressiveCachePlayback,
  desktopEnhancedResolver,
  desktopLocalToolchain,
  desktopTorrent,
  mobileBackgroundDownload,
  externalSubtitleSupport,
}
```

### 7.4 推荐的能力描述对象

```dart
class PlatformCapabilities {
  final bool isDesktop;
  final bool isMobile;
  final bool supportsBackgroundDownload;
  final bool supportsDesktopLocalToolchain;
  final bool supportsProgressiveCachePlayback;
  final bool supportsTorrent;
}
```

### 7.5 推荐的 FeatureGate 接口

```dart
abstract class FeatureGate {
  bool isEnabled(AppFeature feature);
  bool isVisible(AppFeature feature);
}
```

建议判断逻辑由三部分组成：

- 平台能力：这个平台理论上支不支持
- 构建配置：这个版本是否打开
- 运行环境：当前依赖是否就绪

例如：

- `desktopLocalToolchain`
  - `macOS` / `Windows` 可见
  - `iOS` / `Android` 不可见
  - 即使在桌面，也只有本地依赖存在时才启用

### 7.6 推荐的目录落点

建议放在：

- `client/lib/app/feature_flags/`
- `client/lib/platform/capabilities/`

#### 推荐文件

- `app_feature.dart`
- `feature_gate.dart`
- `feature_registry.dart`
- `feature_policy.dart`
- `platform_capabilities.dart`
- `platform_capability_service.dart`

### 7.7 编译安全规则

这是必须执行的工程规范。

#### 规则一

凡是涉及以下能力的代码，不允许直接从 UI 或 Coordinator 引用具体实现：

- `dart:io`
- `Process.run`
- 文件系统平台特性
- 本地工具链
- 平台通道
- 本地代理服务

必须先经过接口层。

#### 规则二

凡是 `desktop-only` 的具体实现，都必须同时提供：

- `xxx.dart`
- `xxx_io.dart`
- `xxx_stub.dart`

例如：

```dart
import 'desktop_tools_bridge_stub.dart'
    if (dart.library.io) 'desktop_tools_bridge_io.dart';
```

#### 规则三

如果某项能力仅桌面可用，UI 不能只靠 `Platform.isMacOS` 控制按钮显示，必须走：

- `FeatureGate.isVisible`

这样可以统一管理产品行为。

#### 规则四

即使某 feature 在桌面开启，移动端也必须有 stub 实现，保证：

- 类型可解析
- 编译可通过
- 运行可安全降级

#### 规则五

所有平台专属类名都必须表达清楚语义，例如：

- `DesktopToolResolver`
- `BackgroundTaskBridge`
- `CacheProxyServer`

不要让页面层直接感知平台差异。

## 8. 推荐的适配模式

建议统一采用以下模式。

### 8.1 模式 A：Bridge + Stub

适用于：

- 本地工具链
- 通知
- 平台后台任务

结构：

- `abstract class XxxBridge`
- `xxx_bridge_io.dart`
- `xxx_bridge_stub.dart`

### 8.2 模式 B：Capability Service

适用于：

- 判断当前平台支持哪些能力

结构：

- `PlatformCapabilityService`
- `PlatformCapabilities`

由它统一提供：

- `isDesktop`
- `supportsDesktopLocalToolchain`
- `supportsBackgroundDownload`
- `supportsTorrent`

### 8.3 模式 C：Feature Registry

适用于：

- 产品策略和灰度控制

结构：

- `FeatureRegistry`
- `FeaturePolicy`
- `FeatureGate`

它把：

- 平台能力
- 实验开关
- 构建配置

合并成最终结论。

## 9. Implementation Roadmap

下面是建议的执行路线，按依赖关系排列。

## Phase 0: 基础重构准备

目标：

- 为后续能力建设准备稳定架构骨架

产出：

- 新目录结构骨架
- `FeatureGate` 基础实现
- `PlatformCapabilities` 基础实现
- `PlaybackCoordinator` 初始壳
- `ResolverOrchestrator` 初始壳

任务清单：

1. 新建 `app/`、`domain/`、`infra/`、`platform/`、`ui/` 目录骨架
2. 定义核心实体：
   - `ResolvedMedia`
   - `PlaybackSession`
   - `DownloadTaskEntity`
   - `OfflineAsset`
3. 定义统一错误模型：
   - `PlaybackError`
   - `ResolverError`
   - `DownloadError`
4. 建立 `PlatformCapabilities` 接口和默认实现
5. 建立 `FeatureGate`、`FeatureRegistry`、`FeaturePolicy`
6. 把现有 `desktop_yt_dlp_resolver` 模式沉淀为统一工程规范

验收标准：

- 项目目录骨架建立
- 所有平台仍能编译
- `desktop-only` 逻辑开始从页面中剥离

## Phase 1: 稳定播放改造

目标：

- 将播放链路从页面驱动升级为应用层驱动

产出：

- `PlaybackCoordinator`
- `PlaybackSessionController`
- `PlayerAdapter`
- `ResolverOrchestrator`

任务清单：

1. 抽离 `PlaybackResolver` 为 `ResolverOrchestrator`
2. 把 resolver 拆成策略：
   - 直链 resolver
   - Bilibili resolver
   - desktop tool resolver
   - web embed resolver
   - external fallback resolver
3. 引入统一 `ResolvedMedia`
4. 将 `player_page.dart` 中的播放初始化逻辑迁移到 `PlaybackCoordinator`
5. 建立统一播放状态：
   - loading
   - ready
   - buffering
   - failed
   - completed
6. 建立统一回退链
7. 建立统一错误展示文案和日志上报字段

验收标准：

- `player_page.dart` 不再直接承担复杂解析和回退策略
- 同一套播放状态可用于不同来源
- `macOS`、`Windows`、`iOS`、`Android` 仍可运行

## Phase 2: 普通下载系统

目标：

- 支持基础下载闭环

产出：

- `DownloadCoordinator`
- `DownloadEngine`
- `DownloadRepository`
- 下载任务页面

任务清单：

1. 定义 `DownloadTaskEntity` 与状态机
2. 选择并接入下载基础设施
3. 实现 `DownloadRepository`
4. 实现 `DownloadStorageManager`
5. 建立下载列表页和下载详情状态
6. 建立下载任务与媒体资源的关联关系
7. 支持下载完成后的本地播放
8. 支持失败重试、暂停、恢复、取消

验收标准：

- 直链媒体可加入下载列表
- 下载状态持久化
- 重启应用后仍能看到任务状态
- 下载完成文件可离线播放

## Phase 3: 离线库和数据层

目标：

- 构建可管理的本地媒体库

产出：

- `OfflineLibraryCoordinator`
- 本地数据库
- 离线媒体列表

任务清单：

1. 引入数据库层
2. 设计表结构：
   - downloads
   - offline_assets
   - playback_history
   - resolver_cache
3. 实现 DAO / repository
4. 建立离线资源列表 UI
5. 支持删除、清理、重建索引
6. 支持播放历史恢复

验收标准：

- 离线文件可检索
- 删除下载可同步清理索引
- 离线播放路径稳定

## Phase 4: Progressive Cache / 边下边播

目标：

- 在不影响移动端稳定性的前提下，逐步引入缓存代理能力

产出：

- `MediaCacheProxy`
- `ChunkScheduler`
- `ProgressiveDownloadEngine`

任务清单：

1. 设计缓存块模型
2. 实现 chunk 下载调度
3. 实现本地代理服务接口
4. 将播放器接入本地代理 URL
5. 建立 seek 优先下载策略
6. 建立缓存清理规则
7. 将此能力接入 `FeatureGate`

验收标准：

- feature 关闭时不影响普通播放
- feature 开启时可在支持平台工作
- 非支持平台自动退回普通播放/下载

## Phase 5: Desktop Enhanced 能力

目标：

- 让桌面端接近目标播放器体验

产出：

- `DesktopToolResolver`
- 桌面增强能力页
- 可选高级来源支持

任务清单：

1. 抽象桌面工具桥接接口
2. 把 `yt-dlp` 解析纳入统一 bridge
3. 增加本地依赖检测
4. 将桌面增强能力接入 `FeatureGate`
5. 为桌面单独提供设置项和诊断页
6. 评估 `torrent` 的独立插件化方案

验收标准：

- 桌面增强 feature 不影响移动端构建
- 桌面缺少依赖时有清晰提示
- 移动端不显示不可用入口

## 10. 详细任务清单

下面按工程包拆分为更细任务。

### 10.1 架构任务

- 建立新目录骨架
- 建立依赖注入入口
- 建立统一错误模型
- 建立统一日志接口
- 建立跨模块命名规范

### 10.2 播放任务

- 抽离播放会话控制器
- 建立播放器适配器接口
- 拆分 resolver 策略
- 实现平台差异回退
- 建立播放失败自动降级链

### 10.3 下载任务

- 建立下载实体和状态机
- 接入下载引擎
- 实现任务持久化
- 实现任务恢复
- 构建下载页面

### 10.4 离线任务

- 建立离线资产模型
- 建立离线索引
- 建立本地文件删除规则
- 建立播放历史记录
- 构建离线媒体库页面

### 10.5 平台适配任务

- 建立 `PlatformCapabilities`
- 建立 `FeatureGate`
- 为桌面增强实现 bridge/stub
- 为背景任务实现 bridge/stub
- 为通知实现 bridge/stub

### 10.6 测试与验证任务

- 为各平台建立最小 smoke test
- 验证 `macOS` 构建
- 验证 `Windows` 构建
- 验证 `iOS` 构建
- 验证 `Android` 构建
- 验证 feature 开关在不同平台下的显示和运行行为

## 11. 平台编译与运行兼容策略

这是必须落实到工程规范里的部分。

### 11.1 兼容目标

#### `macOS`

- 可编译
- 支持桌面增强能力

#### `Windows`

- 可编译
- 支持桌面增强能力

#### `iOS`

- 可编译运行
- 自动降级为移动端支持能力

#### `Android`

- 可编译运行
- 自动降级为移动端支持能力

### 11.2 具体策略

#### 策略一：编译期隔离

任何使用以下内容的代码都必须放到 `*_io.dart` 中：

- `dart:io`
- `Process.run`
- 本地可执行程序探测
- 桌面专属文件访问逻辑

#### 策略二：运行时显式降级

即使编译期已隔离，上层仍然必须通过 `FeatureGate` 判断：

- 是否展示功能入口
- 是否允许执行

#### 策略三：依赖注入时按平台注册

建议在 `app/bootstrap/dependency_container.dart` 中根据 capability 注册实现。

例如：

- 桌面注册 `DesktopToolResolver`
- 移动端注册 `NoopDesktopToolResolver`

#### 策略四：UI 永远只依赖抽象

例如下载页不会知道：

- 当前是桌面增强下载
- 还是普通下载

UI 只拿到：

- `DownloadCoordinator`
- `FeatureGate`

## 12. 建议的数据模型演进

### 12.1 `ResolvedMedia`

建议字段：

- `sourceId`
- `kind`
- `primaryUri`
- `secondaryAudioUri`
- `headers`
- `fallbacks`
- `supportsDownload`
- `supportsOffline`
- `supportsProgressiveCache`
- `expiresAt`

### 12.2 `DownloadTaskEntity`

建议字段：

- `taskId`
- `mediaId`
- `sourceId`
- `url`
- `filename`
- `savePath`
- `status`
- `bytesDownloaded`
- `totalBytes`
- `supportsResume`
- `createdAt`
- `updatedAt`
- `lastError`

### 12.3 `OfflineAsset`

建议字段：

- `assetId`
- `mediaId`
- `title`
- `localPath`
- `thumbnailPath`
- `mimeType`
- `durationMs`
- `createdAt`
- `lastPlayedAt`

## 13. 推荐的里程碑与顺序

## Milestone A: Architecture Skeleton

完成标志：

- 新目录搭建完成
- `FeatureGate` 与 `PlatformCapabilities` 就位
- 旧播放器逻辑开始迁移

## Milestone B: Stable Playback

完成标志：

- 播放逻辑不再绑定页面初始化
- resolver 具备清晰回退链

## Milestone C: Basic Download

完成标志：

- 直链下载闭环跑通
- 本地离线播放跑通

## Milestone D: Offline Library

完成标志：

- 下载产物被离线库接管
- 本地资源可管理

## Milestone E: Desktop Enhanced

完成标志：

- 桌面增强能力可单独开关
- 移动端不受影响

## Milestone F: Progressive Playback

完成标志：

- 本地代理方案在支持平台可用
- feature 关闭时不影响现有系统

## 14. 建议的开发顺序

推荐按以下顺序提交：

1. 目录结构与抽象层
2. `FeatureGate` 和 `PlatformCapabilities`
3. 播放协调器与 resolver 重构
4. 下载实体和 repository
5. 下载页和离线库
6. 桌面增强 bridge
7. progressive cache

## 15. 风险控制建议

### 15.1 不要一次性引入所有能力

原因：

- 范围太大
- 调试难度指数上升
- 很难定位回归问题

### 15.2 所有增强功能默认关闭

建议：

- `stablePlayback` 默认开
- `basicDownload` 在实现完成后默认开
- `offlineLibrary` 在实现完成后默认开
- `desktopEnhancedResolver` 初期默认关
- `desktopLocalToolchain` 初期默认关
- `desktopTorrent` 默认关
- `progressiveCachePlayback` 默认关

### 15.3 desktop feature 必须具备“缺依赖可降级”能力

例如：

- 找不到 `yt-dlp`
- 用户未安装依赖
- 权限不足

系统应表现为：

- 不崩溃
- 不阻塞普通播放
- 显示明确提示

## 16. 第一轮建议实施包

如果要尽快开始，建议第一轮只做以下内容：

### Package A: 架构骨架

- 新目录结构
- `FeatureGate`
- `PlatformCapabilities`
- `ResolvedMedia`
- `PlaybackSession`

### Package B: 播放改造

- `PlaybackCoordinator`
- `ResolverOrchestrator`
- 页面解耦

### Package C: 普通下载 MVP

- 下载实体
- 下载 repository
- 下载页
- 离线播放入口

这三个包完成后，系统就从“可试播客户端”升级为“具备播放器产品基础设施的客户端”。

## 17. 最终建议

建议按以下方案执行：

1. 立即开始目录重构和抽象层建设
2. 立即建立 `FeatureGate + PlatformCapabilities + Stub/IO` 规范
3. 桌面增强能力统一走 bridge，不允许页面层直接引用
4. 第一阶段只保证稳定播放和普通下载
5. 第二阶段再做离线库
6. 第三阶段再做 progressive cache
7. `torrent` 仅作为桌面增强候选能力，单独评估，不并入第一轮主计划

---

## 附：一句话执行策略

这次改造不应该再以“修播放器页”为中心，而应该以“建立跨平台可编译、可降级、可扩展的播放器系统骨架”为中心；所有桌面专属能力都必须通过 `feature gate + platform adapter + stub/io conditional import` 接入。
