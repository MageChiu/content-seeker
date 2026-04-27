# Content Seeker

跨平台音视频搜索播放应用，支持通过自然语言搜索视频、音乐和播客内容。服务端会结合意图识别、LLM Query 改写、多源并行搜索、网页补充搜索和结果重排，返回统一结构化结果供客户端播放或跳转。

## 架构

```
┌──────────────────────┐          ┌──────────────────────────┐
│   Flutter 客户端      │  HTTPS   │    Python 服务端          │
│                      │◄────────►│                          │
│  - UI + 搜索交互      │          │  - LLM Query 改写        │
│  - 双通道搜索路由     │          │  - 多源并行搜索           │
│  - 播放器 (url_launcher)│        │  - 结果重排 + 摘要生成    │
│  - Key 安全存储       │          │  - API Key 安全管理       │
└──────────────────────┘          └──────────────────────────┘
```

### 双通道搜索

- **通道 1（客户端直调）**：用户自己配置 API Key 或 OAuth 授权，客户端直接调搜索 API
- **通道 2（服务端代理）**：走统一后端，后端持有 Key，提供 LLM 增强搜索

用户可在设置页面为每个搜索源独立选择通道。

### 当前服务端搜索源

- **YouTube**：官方 API，适合视频与部分音频关键词
- **Bilibili**：公开搜索接口，适合中文视频内容
- **iTunes**：公开 API，适合歌曲预览搜索
- **Jamendo**：官方 API，适合可直接播放的音乐曲目
- **Podcast**：基于 iTunes Podcast Search，返回播客节目与单集
- **Google 补充搜索**：可选网页索引补充，仅在显式开启 `enable_web_supplement` 时参与

### 网页补充搜索

- 网页补充搜索当前由 **Google Programmable Search Engine** 提供
- 仅在请求中传入 `enable_web_supplement: true` 时启用
- 结果会过滤成可识别的媒体页面，例如 YouTube、Bilibili、Jamendo、Apple Podcasts、Spotify 等
- 这类结果的 `source_tier` 为 `web_supplement`，通常用于补充发现，排序优先级低于官方 API / 公开 API
- 若结果仅为索引页而非直接可播放资源，`availability` 可能为 `indexed_only`

---

## 快速开始

### 1. 启动服务端

```bash
cd server

# 安装依赖
pip install -r requirements.txt

# 配置环境变量
cp .env.example .env
# 编辑 .env 填入你的 Key：
#   OPENAI_API_KEY=sk-xxx            (可选，不填则跳过 LLM 增强)
#   YOUTUBE_API_KEY=xxx              (可选，不填则 YouTube 源不可用)
#   JAMENDO_CLIENT_ID=xxx            (可选，不填则 Jamendo 源不可用)
#   GOOGLE_SEARCH_API_KEY=xxx        (可选，不填则网页补充搜索不可用)
#   GOOGLE_SEARCH_CX=xxx             (可选，需与 Google Search API Key 配套)

# 启动
python main.py
# 服务运行在 http://localhost:8000
```

验证服务端：
```bash
# 健康检查
curl http://localhost:8000/health

# 搜索测试
curl -X POST http://localhost:8000/api/v1/search \
  -H "Content-Type: application/json" \
  -d '{"query": "Kubernetes 教程", "enhance_with_llm": false}'
```

启用网页补充搜索并限制搜索源：

```bash
curl -X POST http://localhost:8000/api/v1/search \
  -H "Content-Type: application/json" \
  -d '{
    "query": "lofi focus music",
    "enhance_with_llm": true,
    "media_type_preference": "audio",
    "enable_web_supplement": true,
    "sources": ["itunes", "jamendo", "youtube", "google"],
    "limit": 10
  }'
```

### 2. 启动 Flutter 客户端

```bash
cd client

# 获取依赖
flutter pub get

# 运行（选择目标平台）
flutter run -d macos     # macOS
flutter run -d windows   # Windows
flutter run -d chrome     # Web（调试用）
flutter run               # 默认设备（手机/模拟器）
```

### 3. 配置搜索源

在客户端「设置」页面：

1. **服务端地址**：默认 `http://localhost:8000`，部署后改为你的服务端地址
2. **YouTube**：选择「使用平台服务」或「使用自有 Key」
3. **Bilibili**：默认客户端直调（公开 API，无需 Key）
4. **音频 / 播客结果**：优先由服务端统一聚合 `iTunes`、`Jamendo`、`Podcast`
5. **AI 增强**：可选使用自有 OpenAI Key 或平台 AI 服务

### 4. 环境变量

服务端启动时会通过 `python-dotenv` 自动加载 `server/.env`。当前实际使用的环境变量如下：

| 变量名 | 必填 | 作用 |
|------|------|------|
| `OPENAI_API_KEY` | 否 | 启用 LLM Query 改写与结果重排 |
| `YOUTUBE_API_KEY` | 否 | 启用 YouTube 官方搜索 |
| `JAMENDO_CLIENT_ID` | 否 | 启用 Jamendo 音乐搜索 |
| `GOOGLE_SEARCH_API_KEY` | 否 | 启用 Google 网页补充搜索 |
| `GOOGLE_SEARCH_CX` | 否 | Google Programmable Search Engine 的搜索引擎 ID |

说明：

- 未配置某个搜索源所需变量时，该搜索源会自动跳过，不影响其他源工作
- `GOOGLE_SEARCH_API_KEY` 和 `GOOGLE_SEARCH_CX` 需要同时配置，网页补充搜索才会生效
- 未配置 `OPENAI_API_KEY` 时，请求仍可执行，只是不做 LLM 增强

---

## 项目结构

```
content-seeker/
├── server/                         # Python 服务端 (FastAPI)
│   ├── main.py                     # 入口
│   ├── routers/
│   │   └── search.py               # 搜索路由（编排多源 + LLM）
│   ├── services/
│   │   ├── llm_service.py          # LLM 编排（Query 改写 + 重排）
│   │   ├── youtube_service.py      # YouTube Data API v3
│   │   ├── bilibili_service.py     # Bilibili 搜索
│   │   ├── itunes_service.py       # iTunes 音乐搜索
│   │   ├── jamendo_service.py      # Jamendo 音乐搜索
│   │   ├── podcast_service.py      # Podcast 搜索
│   │   ├── google_search_service.py# Google 网页补充搜索
│   │   └── search_orchestrator.py  # 意图识别、选源、排序、去重
│   ├── models/
│   │   └── schemas.py              # 数据模型
│   ├── requirements.txt
│   └── .env.example
│
├── client/                         # Flutter 客户端
│   ├── lib/
│   │   ├── main.dart               # 入口
│   │   ├── core/
│   │   │   └── search_source.dart  # 搜索源抽象接口
│   │   ├── models/
│   │   │   └── search_result.dart  # 数据模型
│   │   └── features/
│   │       ├── search/
│   │       │   ├── search_page.dart      # 搜索 UI
│   │       │   ├── search_provider.dart  # 搜索状态管理 + 编排
│   │       │   └── sources/
│   │       │       ├── youtube_local_source.dart  # 通道1: YouTube 直调
│   │       │       ├── bilibili_local_source.dart # 通道1: Bilibili 直调
│   │       │       └── server_source.dart         # 通道2: 服务端统一搜索
│   │       └── settings/
│   │           ├── settings_page.dart     # 设置 UI
│   │           └── settings_provider.dart # 设置状态管理
│   └── pubspec.yaml
│
└── README.md
```

---

## 扩展指南

### 添加新搜索源

1. **服务端**：在 `server/services/` 下新建 `xxx_service.py`，实现 `search()` 方法
2. **客户端通道1**：在 `client/lib/features/search/sources/` 下新建 `xxx_local_source.dart`，实现 `SearchSource` 接口
3. **注册**：在 `search_provider.dart` 和 `server/routers/search.py` 中注册新源

### 搜索请求参数

服务端 `POST /api/v1/search` 当前支持以下核心参数：

| 字段 | 类型 | 默认值 | 说明 |
|------|------|------|------|
| `query` | `string` | - | 用户搜索词 |
| `page` | `int` | `1` | 分页页码 |
| `limit` | `int` | `20` | 单页结果数 |
| `enhance_with_llm` | `bool` | `true` | 是否启用 LLM 改写与重排 |
| `media_type_preference` | `video \| audio \| podcast \| null` | `null` | 手动指定搜索意图 |
| `enable_web_supplement` | `bool` | `false` | 是否启用 Google 网页补充搜索 |
| `sources` | `string[] \| null` | `null` | 指定参与搜索的源，`null` 表示按意图自动选择 |

按意图自动选择的默认搜索源如下：

- `video`：`youtube`、`bilibili`
- `audio`：`itunes`、`jamendo`、`youtube`
- `podcast`：`podcast`、`itunes`、`youtube`
- `mixed`：`youtube`、`bilibili`、`itunes`、`jamendo`、`podcast`
- 当 `enable_web_supplement=true` 时，会额外追加 `google`

### 部署服务端

服务端可部署到任何支持 Python 的平台：
- **Cloudflare Workers / Vercel**：Serverless，适合轻量使用
- **Railway / Fly.io / Render**：一键部署，免费额度可用
- **Docker**：`cd server && docker build -t content-seeker-server .`
- **K8s**：按需扩展

### 后续功能

- [ ] Spotify / Apple Podcast / 更多完整曲库音频搜索
- [ ] 内嵌播放器（media_kit）替代外部浏览器跳转
- [ ] 字幕时间戳定位（搜到某句话 → 跳到视频对应时刻）
- [ ] 搜索历史 + 收藏
- [ ] 离线缓存
- [ ] 本地 LLM（Ollama）支持

---

## 技术栈

| 层次 | 技术 |
|------|------|
| 客户端 | Flutter 3.x + Dart |
| 状态管理 | Provider |
| 服务端 | Python + FastAPI |
| LLM | OpenAI API (gpt-4o-mini) |
| 搜索源 | YouTube Data API v3, Bilibili, iTunes Search API, Jamendo, iTunes Podcast Search, Google Programmable Search |
| 部署 | Docker / Serverless |

## License

MIT

---

## GitHub Actions

- 推送到 `ci-sandbox/dev-*` 分支时，会触发客户端多平台构建校验
- 推送 `release-*` tag 时，会执行正式签名构建，并自动创建 GitHub Release
- 当前流水线覆盖的平台为：`Android`、`iOS`、`macOS`、`Windows`

### 发布方式

```bash
git tag release-0.1.0
git push origin release-0.1.0
```

### Release 产物

- `content-seeker-android-release.apk`
- `content-seeker-android-release.aab`
- `content-seeker-ios-release.ipa`
- `content-seeker-macos.app.zip`
- `content-seeker-windows-release.zip`

说明：

- `ci-sandbox/dev-*` 分支校验时，`iOS` 仍会产出未签名的 `content-seeker-ios-runner.app.zip` 用于编译验证
- `release-*` tag 发布时，`Android` 会使用 keystore 正式签名，并额外产出 `AAB`
- `release-*` tag 发布时，`iOS` 会导入 `.p12` 证书和 provisioning profile，产出正式签名的 `.ipa`
- `Windows` 产物为运行目录压缩包，解压后可直接运行其中的可执行文件

### GitHub Secrets

正式签名发布前，请在仓库 `Settings > Secrets and variables > Actions` 中配置以下 secrets：

- `ANDROID_APPLICATION_ID`：Android 正式包名，例如 `com.yourcompany.contentseeker`
- 默认 Android 包名已设置为 `com.magechiu.contentseeker`
- `ANDROID_KEYSTORE_BASE64`：Android keystore 文件的 Base64 内容
- `ANDROID_KEYSTORE_PASSWORD`：keystore 密码
- `ANDROID_KEY_ALIAS`：签名别名
- `ANDROID_KEY_PASSWORD`：签名 key 密码
- `IOS_BUNDLE_IDENTIFIER`：iOS 正式 bundle id，默认值为 `com.magechiu.contentseeker`
- `IOS_DEVELOPMENT_TEAM`：Apple Developer Team ID
- `IOS_CERTIFICATE_P12_BASE64`：导出的发布证书 `.p12` 的 Base64 内容
- `IOS_CERTIFICATE_PASSWORD`：`.p12` 密码
- `IOS_PROVISIONING_PROFILE_BASE64`：发布用 `.mobileprovision` 的 Base64 内容
- `IOS_PROVISIONING_PROFILE_SPECIFIER`：Xcode 中显示的 provisioning profile 名称
- `IOS_CODE_SIGN_IDENTITY`：可选，默认 `Apple Distribution`
- `IOS_EXPORT_METHOD`：可选，默认 `app-store`，也可按需要改为 `ad-hoc` 等

### 本地签名模板

- Android keystore 模板见 [key.properties.example](file:///Users/zhaopeng.charles/code/magechiu/content-seeker/client/android/key.properties.example)
- iOS 默认签名变量见 [AppConfig.xcconfig](file:///Users/zhaopeng.charles/code/magechiu/content-seeker/client/ios/Flutter/AppConfig.xcconfig)

### Base64 转换脚本

- 脚本位置：[print-signing-secrets-base64.sh](file:///Users/zhaopeng.charles/code/magechiu/content-seeker/scripts/print-signing-secrets-base64.sh)
- 用法：

```bash
scripts/print-signing-secrets-base64.sh \
  --p12 /path/to/dist-cert.p12 \
  --mobileprovision /path/to/profile.mobileprovision \
  --jks /path/to/upload-keystore.jks
```

- 脚本默认会把结果写入仓库根目录的 `.env.github-secrets`，也会同时打印到终端
- 脚本会交互录入密码与签名相关配置，并额外生成 `.gh-set-github-secrets.sh`
- 可选参数：`--output /custom/path/.env.github-secrets`、`--gh-output /custom/path/set-secrets.sh`、`--repo owner/repo`
- 输出包含以下 3 个可复制到 GitHub Secrets 的键值：
  `IOS_CERTIFICATE_P12_BASE64`、`IOS_PROVISIONING_PROFILE_BASE64`、`ANDROID_KEYSTORE_BASE64`
- 生成的 `.gh-set-github-secrets.sh` 可直接执行，把 `.env.github-secrets` 中的值写入 GitHub Secrets

### 生成签名文件

#### Android `.jks`

可以直接在本机生成 upload keystore：

```bash
keytool -genkeypair \
  -v \
  -keystore upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload
```

生成后请记录：

- keystore 文件路径
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

#### iOS `.p12`

`iOS` 发布证书不能像 `Android` 一样本地随意生成，必须依赖 Apple Developer 账号：

1. 在 Apple Developer 创建 `Certificates, Identifiers & Profiles`
2. 创建或确认 App ID：`com.magechiu.contentseeker`
3. 创建 `Apple Distribution` 证书
4. 在本机钥匙串安装证书后，导出为 `.p12`
5. 导出时设置一个密码，对应 `IOS_CERTIFICATE_PASSWORD`

#### iOS `.mobileprovision`

1. 在 Apple Developer 创建与 `com.magechiu.contentseeker` 匹配的 `Provisioning Profile`
2. 绑定同一张 `Apple Distribution` 证书
3. 下载得到 `.mobileprovision`
4. 记录 Profile 名称，填到 `IOS_PROVISIONING_PROFILE_SPECIFIER`
