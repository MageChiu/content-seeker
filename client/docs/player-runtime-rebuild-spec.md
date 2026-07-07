# 播放后端重构方案（Seeker Player Runtime）

## 目标

- 以 `seeker player` 为唯一媒体后端，统一承载播放、缓存、下载、录制能力。
- UI 层只保留展示与交互，不再直接承担播放控制、缓存策略、下载实现、录制拼接等后端职责。
- 允许在必要时直接替换当前 `media_kit + player_page.dart + HttpDownloadEngine + legacy bridge` 这一整套实现，不以兼容旧链路为前提设计新架构。
- 对任意媒体输入统一处理：
  - 已知直链 URL
  - 站点页面 URL
  - 解析后的多轨媒体
  - 需要鉴权 Header/Cookie 的网络流
  - 可缓存、可完整下载、可部分保留的流媒体资源

## 非目标

- 不设计渐进迁移方案。
- 不为 legacy `PlayRequest`、`PlaybackDescriptor`、`HttpDownloadEngine` 保留长期兼容层。
- 不在本方案内讨论服务端改造；范围限定在 `client/`。
- 不把“先小修旧链路”作为落地前提。

## 当前问题

### 1. 运行时职责分散

- Dart UI 页面直接承担播放器初始化、header 注入、缓存配置、录制控制、音视频 mux、目录权限处理。
- 下载能力由独立 `HttpDownloadEngine` 单独发起 HTTP 请求，与播放缓存链路割裂。
- “播放缓存”和“下载文件”没有统一资产模型，导致重复下载、重复存储。

### 2. 后端能力模型过薄

- 当前播放输入仍偏向 `url + headers + secondaryAudioUrl` 的轻量结构，无法完整表达：
  - 多轨
  - 分段流
  - 码率变体
  - 字幕
  - 生命周期 / 过期时间
  - 下载策略
  - 缓存策略

### 3. seeker player 只存在接口壳

- `seeker_player_*` API 目前没有真实实现。
- 当前客户端实际上仍以 Dart 侧播放器页面为运行时核心，而不是 native runtime。

## 总体设计原则

- **单后端原则**：播放、缓存、下载、录制共享同一份 native runtime，不允许各自独立下载同一资源。
- **资产统一原则**：所有网络媒体都先抽象成可物化的媒体资产，再由播放或下载消费。
- **UI 去后端化**：Flutter 只负责视图、手势、命令派发、状态订阅。
- **协议显式建模**：不再依赖 URL 后缀猜测全部能力，媒体能力由解析结果明确声明。
- **大替换优先**：允许成片删除旧桥接与旧实现，不为减少短期 diff 牺牲长期结构。

## 目标架构

```text
Flutter UI
  └── SeekerPlayerFacade (Dart)
        └── dart:ffi
              └── libseeker
                    ├── ResolverService
                    ├── RuntimeSessionManager
                    ├── TransferManager
                    ├── CacheStore
                    ├── AssetCatalog
                    ├── DownloadPlanner
                    └── BackendAdapter
                          └── mpv backend
```

## 核心模块

### 1. ResolverService

职责：

- 把输入 URL 或媒体描述解析为统一 `ResolvedMediaGraph`
- 识别直链、站点页、HLS、DASH、多轨、字幕、鉴权需求
- 返回明确能力而不是让上层猜测

输入：

- 页面 URL
- 直链 URL
- 手工指定 headers/cookies
- 来源 hint

输出：

- `ResolvedMediaGraph`
  - 主资源
  - 变体流
  - 音轨
  - 字幕
  - 下载计划线索
  - 过期时间
  - 回退策略

### 2. RuntimeSessionManager

职责：

- 创建、销毁、恢复播放器会话
- 管理会话状态与事件分发
- 统一控制播放、暂停、seek、切换轨道、切换质量
- 协调播放端与传输端

核心要求：

- 一个会话只绑定一个 `ResolvedMediaGraph`
- 会话状态必须可序列化为 JSON 事件
- 所有播放事件从 native 侧发出，Dart 不再自行拼状态

### 3. TransferManager

职责：

- 统一管理媒体数据的获取、缓存、继续下载、完整保留
- 所有播放流都经由该层获取数据，而不是播放器直接裸拉 URL
- 对同一资源进行去重传输

支持模式：

- `streaming`
  - 按播放进度拉取并缓存
- `prefetch`
  - 激进预取，用于弱网场景
- `download`
  - 以完整保留为目标，复用已有缓存
- `record`
  - 保留当前会话数据，必要时补齐剩余分段

核心约束：

- 同一媒体分段只能下载一次
- 已缓存数据必须可被下载任务复用
- 下载中途切回播放不能重新建一份新缓存

### 4. CacheStore

职责：

- 管理落盘缓存目录与分段文件
- 提供内容寻址与索引
- 区分：
  - 临时缓存
  - 可恢复缓存
  - 已完成离线资产

设计要求：

- 缓存不能只是 mpv 私有黑盒目录
- 必须能被 runtime 查询、复用、晋升、清理

### 5. AssetCatalog

职责：

- 统一记录所有本地媒体资产与下载任务元数据
- 替代当前下载任务库与离线资产库的割裂模型

统一资产状态：

- `ephemeral`
- `cached_partial`
- `cached_reusable`
- `downloading`
- `completed`
- `failed`
- `expired`

### 6. DownloadPlanner

职责：

- 根据 `ResolvedMediaGraph` 生成下载计划
- 区分：
  - 单文件直链下载
  - HLS 分段保留
  - DASH 音视频分轨下载与合并
  - 字幕与封面伴随下载

输出：

- `DownloadPlan`
  - 资源清单
  - 分段策略
  - 合并策略
  - 目标文件名
  - 复用已有缓存的规则

### 7. BackendAdapter

职责：

- 封装实际播放内核
- 首版后端仍可使用 mpv，但 mpv 只作为 backend，不再暴露到 Dart UI

原则：

- 上层不直接调用 mpv property
- mpv 的 `cache`、`stream-record` 等概念不直接泄漏到 UI
- 所有 backend 特性都通过 seeker player 统一语义包装

## 核心领域模型

### 1. ResolvedMediaGraph

用于描述“可消费媒体”，替代当前轻量 `PlaybackDescriptor`。

建议字段：

- `media_id`
- `source_id`
- `title`
- `kind`
  - `file`
  - `hls`
  - `dash`
  - `progressive`
  - `live`
- `container`
- `mime_type`
- `duration_ms`
- `is_live`
- `expires_at`
- `auth`
  - headers
  - cookies
- `variants`
- `tracks`
  - video
  - audio
  - subtitle
- `download_profile`
- `cache_profile`
- `fallbacks`

### 2. MaterializedAsset

用于描述“本地已掌握的数据资产”。

建议字段：

- `asset_id`
- `media_id`
- `storage_kind`
  - temp
  - cache
  - offline
- `completeness`
  - partial
  - full
- `local_manifest_path`
- `primary_file_path`
- `auxiliary_files`
- `bytes_total`
- `bytes_ready`
- `segment_coverage`
- `created_at`
- `updated_at`

### 3. PlaybackSessionState

- `session_id`
- `status`
  - idle
  - resolving
  - buffering
  - ready
  - playing
  - paused
  - ended
  - failed
- `position_ms`
- `buffered_position_ms`
- `duration_ms`
- `selected_variant_id`
- `selected_audio_track_id`
- `selected_subtitle_track_id`
- `download_status`
- `cache_status`
- `error`

## 新的 C API 设计

当前 `player.h` 不够，需要扩成完整 runtime contract。

### 生命周期

```c
SEEKER_API int32_t seeker_runtime_create(const char* config_json);
SEEKER_API void seeker_runtime_destroy(int32_t runtime_id);
```

### 会话管理

```c
typedef void (*seeker_runtime_event_callback)(
    int32_t runtime_id,
    int32_t session_id,
    const char* event_json
);

SEEKER_API int32_t seeker_session_create(
    int32_t runtime_id,
    seeker_runtime_event_callback callback
);
SEEKER_API int seeker_session_dispose(int32_t runtime_id, int32_t session_id);
```

### 媒体准备

```c
SEEKER_API char* seeker_resolve_media(
    int32_t runtime_id,
    const char* request_json
);

SEEKER_API int seeker_session_open(
    int32_t runtime_id,
    int32_t session_id,
    const char* resolved_media_json
);
```

### 播放控制

```c
SEEKER_API int seeker_session_play(int32_t runtime_id, int32_t session_id);
SEEKER_API int seeker_session_pause(int32_t runtime_id, int32_t session_id);
SEEKER_API int seeker_session_seek(
    int32_t runtime_id,
    int32_t session_id,
    int64_t position_ms
);
SEEKER_API int seeker_session_set_rate(
    int32_t runtime_id,
    int32_t session_id,
    double rate
);
SEEKER_API int seeker_session_set_volume(
    int32_t runtime_id,
    int32_t session_id,
    double volume
);
SEEKER_API int seeker_session_select_track(
    int32_t runtime_id,
    int32_t session_id,
    const char* track_id
);
SEEKER_API int seeker_session_select_variant(
    int32_t runtime_id,
    int32_t session_id,
    const char* variant_id
);
```

### 传输与下载

```c
SEEKER_API char* seeker_build_download_plan(
    int32_t runtime_id,
    const char* resolved_media_json,
    const char* options_json
);

SEEKER_API int32_t seeker_download_start(
    int32_t runtime_id,
    const char* download_plan_json
);
SEEKER_API int seeker_download_pause(int32_t runtime_id, int32_t download_id);
SEEKER_API int seeker_download_resume(int32_t runtime_id, int32_t download_id);
SEEKER_API int seeker_download_cancel(int32_t runtime_id, int32_t download_id);
```

### 资产与缓存

```c
SEEKER_API char* seeker_query_asset(
    int32_t runtime_id,
    const char* media_id
);
SEEKER_API char* seeker_list_assets(int32_t runtime_id, const char* filter_json);
SEEKER_API int seeker_evict_asset(int32_t runtime_id, const char* asset_id);
```

## Dart 层改造原则

### 保留

- 页面布局
- 控件交互
- Provider / ChangeNotifier 或等价状态容器
- 搜索结果到播放请求的页面级组装

### 删除或重写

- `features/player/playback_resolver.dart`
- `app/playback/playback_coordinator.dart` 现有基于 legacy request 的实现
- `infra/download/http_download_engine.dart`
- `player_page.dart` 中所有后端逻辑
- `legacy_content_ports.dart` 中回桥到旧播放/下载模型的链路

### 新的 Dart 侧结构

建议新增：

- `lib/native_bridge/seeker_runtime_bridge.dart`
- `lib/domain/media/media_graph.dart`
- `lib/domain/media/materialized_asset.dart`
- `lib/app/runtime/runtime_coordinator.dart`
- `lib/app/runtime/runtime_state.dart`

### UI 与 runtime 的关系

- `PlayerPage` 只消费 `RuntimeSessionViewModel`
- “下载当前媒体”变成向 runtime 发命令
- “缓存目录”“录制目录”不再由页面自己探测和写入

## 下载与缓存统一设计

这是本次重构的关键，不允许再拆成两套。

### 基本规则

- 所有播放流都必须经过 `TransferManager`
- `TransferManager` 落盘的数据默认进入 `CacheStore`
- 用户点击下载时：
  - 先查询现有缓存覆盖率
  - 已有部分直接复用
  - 缺失部分继续拉取
  - 完成后将资产状态从 `cache` 晋升为 `offline`

### 对不同媒体类型的策略

#### 单文件直链

- 直接 Range 下载
- 播放与下载共享同一个文件句柄或相同目标文件

#### HLS

- 保存播放列表、分段、密钥信息
- 下载完成后可选择：
  - 保留原始 HLS 目录
  - 输出合并文件

#### DASH

- 视频轨、音轨分别缓存
- 下载完成后统一封装为离线资产
- 合并逻辑由 native muxer 负责，不由 UI 协调

#### Live

- 默认只缓存滑动窗口，不支持“完整下载”
- 若支持录制，则录制走 runtime 的 record job，而不是页面旁路写文件

## 存储设计

建议将存储拆为三层：

- `cache/blobs/`
  - 分段数据
- `cache/manifests/`
  - 媒体清单、轨道、segment 索引
- `offline/assets/`
  - 用户可见导出产物

元数据统一记录在：

- `runtime_assets.json`
- `runtime_jobs.json`

不再区分“下载库”和“离线资产库”两套逻辑仓储。

## 事件模型

所有状态统一以 runtime event 上报，Dart 不再拼接零散状态。

事件类型建议包括：

- `session.resolving`
- `session.ready`
- `session.buffering`
- `session.playing`
- `session.paused`
- `session.ended`
- `session.failed`
- `download.started`
- `download.progress`
- `download.paused`
- `download.completed`
- `download.failed`
- `asset.promoted`
- `cache.evicted`

## 平台实现策略

### 首版 backend

- 继续使用 mpv 作为实际播放后端
- 但 mpv 被封装在 native 内部，不再由 Dart 直接操作 property

### Apple 平台

- 继续复用现有 `muxer_apple.mm`
- 目录授权、bookmark、导出行为由 runtime 统一管理

### 非 Apple 平台

- 保留跨平台 muxer
- 下载/缓存资产模型保持一致

## 风险与约束

### 风险

- 原有 `media_kit` 直接控制链路删除后，需要 native event/view bridge 一次性补齐
- 若 mpv backend 无法稳定提供某些缓存复用能力，可能需要 runtime 自建上游拉流和本地代理层
- 统一缓存与下载后，存储元数据的一致性要求明显提高

### 约束

- 本次重构允许大面积删除旧实现
- 但最终仍需保证 `client/` 内自洽，不把关键能力外推到 `server/`

## 验收标准

满足以下条件，才算完成重构：

1. UI 层不再直接调用 `media_kit` / mpv property。
2. UI 层不存在独立下载实现或录制旁路下载实现。
3. `seeker player` 能统一处理站点 URL 与指定直链 URL。
4. 对同一媒体执行“先播放后下载”时，不会重复下载已缓存数据。
5. 下载任务支持暂停、恢复、取消，并可复用现有缓存。
6. DASH/HLS/单文件直链三类媒体都能进入统一 runtime。
7. 下载、缓存、离线资产由统一资产模型管理。
8. 旧的 playback/download legacy bridge 被删除或降为非核心兼容层。

## 建议废弃清单

重构完成后，应删除或重写以下模块：

- `client/lib/features/player/playback_resolver.dart`
- `client/lib/app/playback/playback_coordinator.dart`
- `client/lib/infra/download/http_download_engine.dart`
- `client/lib/app/content/legacy_content_ports.dart`
- `client/lib/models/media_playback.dart`
- `client/lib/models/play_request.dart` 中与旧播放链路强绑定的部分
- `client/lib/features/player/player_page.dart` 内所有后端控制逻辑
