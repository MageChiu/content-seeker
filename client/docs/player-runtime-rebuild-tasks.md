# 播放后端重构落地任务

## 原则

- 按终局架构直接实施，不做“旧链路渐进保活”。
- 任务以最终可替换旧实现为目标，不以降低短期改动量为优先。
- 除必要的临时编译过渡外，不为 legacy 结构增加长期维护代码。

## Task 1: 定义 seeker runtime 协议

目标：

- 重写 `client/native/include/seeker/player.h`
- 明确 runtime、session、download、asset、event 的 C API

产出：

- 新版 `player.h`
- 配套 JSON contract 文档
- 错误码与事件类型枚举

验收：

- 可以完整表达播放、下载、缓存、资产查询能力
- 不再局限于 `create/open/play/pause/seek/set_rate`

## Task 2: 建立 native runtime 骨架

目标：

- 在 `client/native/src/` 下新增 runtime 模块

建议目录：

- `src/runtime/runtime_manager.*`
- `src/runtime/session_manager.*`
- `src/runtime/event_bus.*`
- `src/runtime/runtime_models.*`

产出：

- runtime 生命周期管理
- session 注册与销毁
- 事件分发总线

验收：

- Dart 可创建 runtime、创建 session、接收事件

## Task 3: 重构 ResolverService

目标：

- 将当前 extractor 和直链判断整合成统一 `ResolvedMediaGraph` 输出

产出：

- `ResolvedMediaGraph` native 数据模型
- 解析请求 JSON -> graph JSON 的服务
- 站点 URL / 直链 URL 统一解析入口

验收：

- 直链、Bilibili、YouTube 至少能输出统一 graph
- graph 中显式包含轨道、headers、fallback、下载能力

## Task 4: 实现 TransferManager

目标：

- 统一播放数据获取、缓存、下载、恢复能力

产出：

- `src/runtime/transfer_manager.*`
- 统一 job 模型
- 缓存命中与复用逻辑

验收：

- 对同一媒体请求播放和下载时，传输层不会重复建立两份下载任务
- 支持 pause / resume / cancel

## Task 5: 实现 CacheStore 与 AssetCatalog

目标：

- 建立统一缓存和离线资产模型

产出：

- `src/runtime/cache_store.*`
- `src/runtime/asset_catalog.*`
- 统一元数据文件格式

验收：

- 可查询某媒体是否已有可复用缓存
- 可将 partial cache 晋升为 full offline asset

## Task 6: 实现 DownloadPlanner

目标：

- 根据媒体 graph 生成下载计划

产出：

- `src/runtime/download_planner.*`
- 单文件 / HLS / DASH 三类计划生成逻辑

验收：

- 输入统一 graph，输出结构化 download plan
- 计划中包含缓存复用信息、目标文件信息、后处理信息

## Task 7: 实现 backend adapter

目标：

- 将 mpv 封装为 native backend

产出：

- `src/player/backend_adapter_mpv.*` 或等价目录
- session 到 backend 的统一控制桥

验收：

- Dart 不再直接接触 mpv property
- 播放、暂停、seek、切轨、切码率通过 seeker runtime API 完成

## Task 8: 将录制能力并入 runtime

目标：

- 删除 UI 旁路录制 / 旁路下载 / 页面内 mux 控制

产出：

- `record job` 模型
- runtime 内部的录制与后处理逻辑

验收：

- 录制由 runtime 发起与结束
- DASH 录制不再由页面层额外下载音轨

## Task 9: 建立 Dart runtime bridge

目标：

- 在 Dart 侧提供类型安全的 runtime facade

产出：

- `lib/native_bridge/seeker_runtime_bridge.dart`
- `lib/native_bridge/seeker_runtime_models.dart`
- runtime event stream 封装

验收：

- Flutter 代码只依赖 runtime facade，不直接拼底层 JSON

## Task 10: 重建 Dart 领域模型

目标：

- 用新媒体模型替换旧播放请求模型

产出：

- `lib/domain/media/media_graph.dart`
- `lib/domain/media/materialized_asset.dart`
- `lib/domain/runtime/runtime_session_state.dart`

验收：

- 新模型能覆盖播放、缓存、下载、资产状态
- `PlaybackDescriptor` 不再是核心模型

## Task 11: 重建应用层 runtime coordinator

目标：

- 以 runtime 为中心重写应用层协调器

产出：

- `lib/app/runtime/runtime_coordinator.dart`
- `lib/app/runtime/runtime_state.dart`

验收：

- prepare/open/play/download/query asset 走统一 coordinator
- 不再拆成旧的 playback coordinator 和 download coordinator 核心链路

## Task 12: 重写 ContentEngine 接口

目标：

- 让 `ContentEngine` 直接对接 runtime，而不是回桥 legacy 模型

产出：

- 新的 `ContentPlaybackPort`
- 新的 `ContentDownloadPort`
- 新的 content request -> runtime request 转换

验收：

- `legacy_content_ports.dart` 退出主链路

## Task 13: 重写 PlayerPage

目标：

- 让 `PlayerPage` 退化为纯 UI 壳

必须删除的页面职责：

- 解析播放地址
- 直接配置缓存目录
- 直接调用 mpv property
- 旁路下载音轨
- 直接执行 mux
- 录制文件导出控制

验收：

- 页面只做事件订阅、用户命令、渲染

## Task 14: 重写下载页与下载入口

目标：

- 所有下载入口统一走 runtime download job

产出：

- 搜索页下载入口改造
- 阅读页下载入口改造
- 下载页展示 runtime job 和 asset 状态

验收：

- UI 侧不再构造 `HttpDownloadEngine` 风格的裸 HTTP 下载请求

## Task 15: 删除旧下载实现

目标：

- 移除旧下载链路

删除或降级对象：

- `lib/infra/download/http_download_engine.dart`
- `lib/app/download/download_coordinator.dart`
- `lib/domain/download/*` 中仅服务旧链路的模型

验收：

- 主链路不再依赖旧下载实现

## Task 16: 删除旧播放实现

目标：

- 移除旧播放链路

删除或降级对象：

- `lib/features/player/playback_resolver.dart`
- `lib/app/playback/playback_coordinator.dart`
- `lib/models/media_playback.dart`
- `legacy play request` 主链路

验收：

- 主链路中不再依赖 `PlaybackDescriptor`

## Task 17: 存储与设置重构

目标：

- 将播放缓存目录、下载目录、录制目录收敛成 runtime 可理解的存储配置

产出：

- 新设置模型
- 存储策略枚举
- 目录权限与 bookmark 的统一处理

验收：

- 页面不再自己判定目录可写性
- runtime 能统一读取和执行存储策略

## Task 18: 测试与验收

目标：

- 为新 runtime 主链路建立验证矩阵

必须覆盖：

- 直链 URL 播放
- Bilibili 页面 URL 播放
- YouTube 页面 URL 播放
- HLS 播放 + 下载
- DASH 播放 + 下载 + 复用缓存
- 下载暂停 / 恢复 / 取消
- 播放后再下载不重复拉取已缓存数据
- 会话恢复与状态同步

验收：

- 新主链路通过后，旧链路可以整体删除

## 建议执行顺序

1. Task 1-3
2. Task 4-6
3. Task 7-8
4. Task 9-12
5. Task 13-17
6. Task 18

## 交付完成标准

满足以下条件后，可以认为本次重构完成：

- seeker runtime 成为唯一播放后端入口
- seeker runtime 成为唯一下载与缓存后端入口
- UI 层不再直接操纵底层播放器和下载器
- 缓存与下载统一为一套资产系统
- 旧播放链路与旧下载链路已退出主路径
