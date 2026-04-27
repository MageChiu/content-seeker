# 扩展国内外视频检索源设计

## 目标

- 在不突破当前 `client/` 边界的前提下，设计一套可持续扩展的视频检索源接入方案。
- 兼容现有两条路径：
  - 本地搜索：客户端直连公开接口或开放平台接口。
  - 远程搜索：客户端将查询交给服务端统一聚合。
- 优先增加稳定、低风控、可直接打开或嵌入播放的视频源。

## 现状

当前客户端已经具备比较清晰的搜索源接入骨架：

- `lib/core/source_catalog.dart`
  - 维护内容源目录、能力声明和默认开关。
- `lib/features/settings/settings_provider.dart`
  - 维护源配置、启用状态、就绪态判断和持久化。
- `lib/features/settings/settings_page.dart`
  - 自动根据目录展示配置 UI。
- `lib/features/search/search_provider.dart`
  - 根据设置分发到本地源实现或远程服务端聚合。
- `lib/features/search/sources/*.dart`
  - 每个搜索源一个独立实现，负责请求、错误处理和 `SearchResult` 映射。

当前问题不在于“能不能再接源”，而在于“继续加源后是否还可维护”。

主要瓶颈：

- `SearchProvider` 里用 `switch` 做实例化，新增源需要改动中心路由。
- `SourceConfig` 只有 `apiKey` 一个字段，不足以表达 `clientId`、`accessToken`、实例地址、Cookie 等不同凭证模型。
- 内容源目录缺少区域、稳定性、接入模式等维度，设置页只能平铺展示。
- 多个本地源已经开始出现相似的超时、重试、限流处理，后续会继续重复。

## 设计原则

- 最小改动优先：先顺着现有 `catalog -> settings -> provider -> source` 结构扩展。
- 稳定性优先：优先接入开放 API 或公共实例搜索接口，避免一开始就依赖高风控网页抓取。
- 播放能力优先：优先选择可外部打开、可网页嵌入、或可提供稳定播放链接的源。
- 渐进式接入：把候选源拆成低风险本地源、需要凭证的本地源、建议远程聚合的高风险源三层。
- 客户端边界清晰：本次只设计 `client/`，对必须改 `server/` 的内容仅做预留说明，不直接落地。

## 候选源分层

### 第一批：建议优先接入

这些源最适合当前客户端架构，改造收益高、风险相对低。

| Source Key | 平台 | 区域 | 建议模式 | 原因 |
| --- | --- | --- | --- | --- |
| `vimeo` | Vimeo | 国外 | 本地搜索 | 开放接口成熟，结果结构清晰，适合映射到现有 `SearchResult` |
| `peertube` | PeerTube | 国外 | 本地搜索 | 可基于公共实例或聚合实例检索，适合外链或内嵌播放 |
| `acfun` | AcFun | 国内 | 本地搜索 | 与 Bilibili 用户心智接近，视频检索价值高，可先做外部打开 |
| `youku` | 优酷 | 国内 | 本地搜索 | 适合作为长视频补充源，但需要更灵活的凭证配置 |

### 第二批：需要额外凭证或实例配置

这些源可接入，但需要在配置模型上先做升级。

| Source Key | 平台 | 区域 | 建议模式 | 关键前提 |
| --- | --- | --- | --- | --- |
| `twitch` | Twitch VOD / Clips | 国外 | 本地搜索 | 需要 `clientId` 和 `accessToken`，更适合外部打开 |
| `rutube` | RuTube | 国外 | 本地搜索 | 需先验证搜索稳定性和结果字段完整度 |
| `youku_open` | 优酷开放平台 | 国内 | 本地搜索 | 需要 `clientId` 类字段，不能再只靠 `apiKey` |

### 第三批：建议只预留，不在客户端直接做

这些平台检索价值高，但更适合服务端代理、风控隔离、Cookie 管理或网页补充。

| Source Key | 平台 | 区域 | 建议模式 | 原因 |
| --- | --- | --- | --- | --- |
| `qq_video` | 腾讯视频 | 国内 | 远程搜索 | 网页链路复杂，风控和签名成本高，不适合直接在客户端做 |
| `iqiyi` | 爱奇艺 | 国内 | 远程搜索 | 搜索与播放链路耦合，客户端直连稳定性风险高 |
| `mgtv` | 芒果 TV | 国内 | 远程搜索 | 接口稳定性和授权模型不适合先在客户端硬编码 |
| `douyin_video` | 抖音视频 | 国内 | 远程搜索 | 风控强，网页补充或服务端聚合更合理 |
| `xigua` | 西瓜视频 | 国内 | 远程搜索 | 播放链接和搜索链路演变快，建议后置 |

## 架构改造

### 1. 把本地源实例化从 `switch` 改成注册表

当前 `SearchProvider` 中的 `switch (source)` 可用，但继续扩源后会变成主文件热点。

建议新增一个本地源注册表，例如：

```dart
typedef SearchSourceFactory = SearchSource Function(SourceRuntimeConfig config);

class SourceRuntimeConfig {
  final String sourceKey;
  final Map<String, String> credentials;
  final String? customBaseUrl;
  final Map<String, String> extra;

  const SourceRuntimeConfig({
    required this.sourceKey,
    this.credentials = const {},
    this.customBaseUrl,
    this.extra = const {},
  });
}

final Map<String, SearchSourceFactory> kLocalSourceRegistry = {
  'youtube': (config) => YouTubeLocalSource(
        apiKey: config.credentials['apiKey'] ?? '',
      ),
  'bilibili': (_) => BilibiliLocalSource(),
};
```

收益：

- 新增源只需要“注册”而不是改 `SearchProvider` 主流程。
- 更容易做按源能力过滤和灰度发布。
- 未来可以把源实现独立为更清晰的模块。

### 2. 升级 `SourceConfig`

当前：

```dart
class SourceConfig {
  bool enabled;
  String apiKey;
}
```

建议升级为：

```dart
class SourceConfig {
  bool enabled;
  Map<String, String> credentials;
  String customBaseUrl;
  Map<String, String> extra;
}
```

字段含义：

- `credentials`
  - 统一承载 `apiKey`、`clientId`、`accessToken`、`cookie` 等。
- `customBaseUrl`
  - 适合 PeerTube 这类“实例可配置”的源。
- `extra`
  - 承载实例名、地域、语言、排序偏好等轻量配置。

兼容策略：

- 保留旧版 `api_key` 的读取兼容。
- 迁移时把旧值写入 `credentials['apiKey']`。

### 3. 扩展内容源目录元数据

建议给 `ContentSourceDescriptor` 新增以下字段：

- `region`
  - `domestic` / `international`
- `accessMode`
  - `publicApi` / `officialApi` / `remoteOnly`
- `stabilityTier`
  - `stable` / `experimental` / `fragile`
- `defaultPlaybackKind`
  - `externalOpen` / `embeddedWeb` / `nativeStream`
- `credentialHints`
  - 用于设置页动态展示不同字段名

这能解决两个问题：

- 设置页可以按“国内 / 国外 / 实验性”分组，而不是长列表平铺。
- 搜索页可以更自然地做默认源提示和启用建议。

## 搜索源实现规范

建议新增一个统一约定，所有新视频源都遵循以下实现模板：

1. 输入
   - `query`
   - `page`
   - `limit`
2. 请求层
   - 统一超时
   - 统一重试
   - 统一限流降级
3. 解析层
   - 先把原始响应映射为平台内部 DTO
   - 再映射到 `SearchResult`
4. 播放层
   - 先保证 `canonicalUrl`
   - 播放优先级先做 `externalOpen`
   - 能稳定嵌入再做 `embeddedWeb`

建议补一个抽象基类，例如 `HttpJsonSearchSourceBase`，沉淀这些公共能力：

- `getJsonWithRetry()`
- `parseList()`
- `mapToSearchResult()`
- 统一 `LocalSourceHttpException`
- 统一 `LocalSourceRateLimitState`

这样可以避免每接一个源就复制一套 `timeout + retry + debug` 逻辑。

## 各源设计建议

### Vimeo

- `sourceKey`: `vimeo`
- 区域：国外
- 接入方式：本地搜索
- 凭证：建议支持 `accessToken`
- 播放：
  - 第一阶段：外部打开
  - 第二阶段：如果嵌入稳定，再接 `embeddedWeb`
- 排序权重：
  - `sourceTier = officialApi`
  - 视频搜索时权重可与 `dailymotion` 同层

### PeerTube

- `sourceKey`: `peertube`
- 区域：国外
- 接入方式：本地搜索
- 配置：
  - `customBaseUrl` 表示实例地址
  - 若用户未配置，默认使用公共聚合实例
- 播放：
  - 第一阶段优先 `externalOpen`
  - 若返回 iframe / embed 链接稳定，可升级为 `embeddedWeb`
- 特别价值：
  - 可补足去中心化技术、开源社区、教育类内容检索

### AcFun

- `sourceKey`: `acfun`
- 区域：国内
- 接入方式：本地搜索
- 凭证：默认无凭证
- 播放：
  - 第一阶段：外部打开
  - 第二阶段：验证是否存在稳定嵌入页
- 风险：
  - 需要单独验证搜索接口稳定性和反爬特征
- 排序建议：
  - 与 `bilibili` 同属国内 UGC 视频源，但初始权重略低于 `bilibili`

### 优酷

- `sourceKey`: `youku`
- 区域：国内
- 接入方式：本地搜索
- 凭证：
  - 不建议继续复用单一 `apiKey`
  - 需支持 `clientId` 或等价开放平台字段
- 播放：
  - 第一阶段：外部打开
  - 第二阶段：视开放平台能力决定是否支持内嵌
- 风险：
  - 平台开放能力和接口连续性需要单独验收

### 腾讯视频 / 爱奇艺 / 芒果 TV

- 本次只在目录层做“远程能力预留”，不做本地实现。
- 原因：
  - 这类源更可能需要服务端代理、请求头伪装、Cookie 或网页补充。
  - 直接在客户端维护容易造成版本脆弱和排障成本过高。

## UI 设计

### 设置页

将当前“内容源平铺列表”改为分组展示：

- 国内视频
- 国外视频
- 音频
- 实验性 / 高风险源

每个源卡片增加以下信息：

- 区域标签
- 接入方式标签
- 播放方式标签
- 状态标签
  - 已就绪
  - 需凭证
  - 实验性

凭证输入也改为动态字段，而不是只显示一个 “API Key”：

- Vimeo: `Access Token`
- Youku: `Client ID`
- Twitch: `Client ID` + `Access Token`
- PeerTube: `实例地址`

### 搜索页

保留当前“可用本地源提示”，但建议增加两点：

- 当搜索类型为视频时，优先展示视频源列表，不混入音频源。
- 当已启用的国内 / 国外视频源很多时，按区域分组显示可用源标签。

## 排序与召回策略

当前排序逻辑主要依赖：

- `sourceTier`
- `availability`
- `playbackKind`
- 媒体类型匹配

建议新增两条轻量策略，不需要大改模型：

### 1. 区域偏好加权

根据查询语言做轻量加权：

- 中文查询：国内源加小幅权重
- 非中文查询：国外源加小幅权重

注意：

- 这是排序增强，不是硬过滤。
- 不应覆盖用户显式启用的源。

### 2. 实验性源降权

对于 `stabilityTier = experimental` 的源，即使有结果也略微降权，减少不稳定源顶到前排。

## 推荐落地顺序

### Phase 0：先做可扩展性改造

- 升级 `SourceConfig`
- 引入本地源注册表
- 扩展 `ContentSourceDescriptor`
- 设置页支持动态凭证字段

### Phase 1：接入低风险国外视频源

- `vimeo`
- `peertube`

原因：

- 能验证新注册表和新配置模型是否合理。
- 风险低于先做国内高风控平台。

### Phase 2：接入国内补充视频源

- `acfun`
- `youku`

原因：

- 能显著提升中文视频检索覆盖度。
- 但需要先完成 Phase 0 的配置模型升级。

### Phase 3：仅预留高风险远程源

- `qq_video`
- `iqiyi`
- `mgtv`
- `douyin_video`
- `xigua`

说明：

- 这一阶段需要服务端设计配合，本次客户端仅预留 catalog 和 UI 展示策略。

## 验收标准

完成 Phase 2 后，客户端应满足：

- 新增至少 4 个视频源时，`SearchProvider` 不再继续膨胀 `switch`。
- 设置页可表达多种凭证类型，而不局限于单个 `apiKey`。
- 视频搜索时能够稳定展示国内 + 国外多源结果。
- 结果卡片仍复用现有 `SearchResult`，不需要重写搜索页 UI。
- 对不稳定源具备超时、重试、限流降级能力。

## 本次设计结论

最合适的路线不是“直接再加一串 case”，而是：

1. 先把本地源工厂和配置模型升级。
2. 先落地 `vimeo` 和 `peertube`，验证国际视频扩展路径。
3. 再落地 `acfun` 和 `youku`，补国内视频检索覆盖。
4. 对腾讯视频、爱奇艺、芒果 TV、抖音、西瓜视频仅做远程预留，不在当前客户端直接实现。

这样可以在不破坏现有结构的前提下，把视频检索源从“少量特例接入”升级为“可持续扩展的能力”。
