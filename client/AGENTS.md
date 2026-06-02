# Client Rules

## 目录约束

- Flutter 客户端修改仅在本目录内完成。
- 平台侧改动仅在确有必要时触达 `android/`、`ios/`、`macos/`、`windows/`。

## 代码约束

- UI 改动优先放在 `lib/features/`
- 领域模型放在 `lib/domain/`
- 基础能力和平台能力优先复用 `lib/app/`、`lib/infra/`、`lib/platform/`

