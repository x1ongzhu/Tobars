# Tobars

macOS 菜单栏（status bar）里的 LLM 订阅用量查看器。点击图标即可看到每个服务的
5 小时 / 每周 / 每月额度、重置倒计时和错误信息；不打开浏览器也能知道还剩多少。

当前支持：

**按账号管理**：同一家服务可以添加多个账号，菜单里逐个展示。

| 服务 | 认证 | 数据来源 |
| --- | --- | --- |
| OpenCode Go | API key | `opencode.ai/zen/go/v1/usage`（官方额度接口） |
| Command Code | API key | Studio 的 `/alpha/billing/*`、`/alpha/usage/summary` |
| Open Design | Control Key（`vela_ctrl_…`）或会话 Cookie | `amr-api.open-design.ai` 的工作区额度接口 |

接口字段与控制台行为记录在 [`docs/providers/`](docs/providers/)。

## 环境要求

- macOS 14 (Sonoma) 及以上
- **完整 Xcode**（只装 CommandLineTools 无法编译：SwiftUI 宏需要 Xcode 内的 `libSwiftUIMacros`）

## 构建与运行

```bash
./scripts/build.sh          # 调试构建
./scripts/build.sh run      # 构建并运行（菜单栏出现图标，无 Dock 图标）
./scripts/build.sh test     # 全部测试
./scripts/build.sh test --filter TobarsCoreTests.CommandCodeProviderTests
./scripts/make_app.sh       # 打包 build/Tobars.app
open build/Tobars.app
```

`scripts/build.sh` 会用 `xcode-select -p` 自动设置 `DEVELOPER_DIR`；Xcode 装在别处时：

```bash
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer ./scripts/build.sh build
```

## 配置

菜单栏图标 →「设置…」，或启动时加 `--show-settings`。点「添加账号」选择服务，
同一家可以添加多个账号（个人 / 工作 / 团队），各自独立配置；每个账号走
「未配置 → 填写 → 保存并连接 → 摘要」流程，连接成功才会写入本地凭据文件。

- **OpenCode Go**：`opencode.ai/console` 的 API key
- **Command Code**：Studio 的 API key（与 CLI 共用）
- **Open Design**：Control Key；若额度接口只认浏览器会话，展开「粘贴 Cookie」，
  从控制台额度请求里复制 `Cookie` 请求头。Workspace ID 可留空自动发现。

凭据保存在 `~/Library/Application Support/Tobars/credentials.json`，权限 `0600`，
与 command-code / vela 等 CLI 的登录文件同级；不进 git、不打印、不写日志。
旧版本存在钥匙串里的凭据可用 `.build/debug/Tobars --migrate-credentials` 一次性迁移。
本机已登录对应 CLI 时，设置页会出现「从本机导入」。

## 无 UI 调试

```bash
# 离屏渲染菜单（浅色 + 深色 PNG），改 UI 后先看这里
.build/debug/Tobars --render-snapshot /tmp/tobars-snap

# 直接打开设置窗口（菜单栏图标不好点时的备用入口）
.build/debug/Tobars --show-settings

# 把旧 Keychain 凭据迁移到 0600 文件（只需一次）
.build/debug/Tobars --migrate-credentials

# 用真实凭据拉一次并打印 JSON；不启动菜单栏
.build/debug/Tobars --print-usage

# 用演示数据检查输出格式
.build/debug/Tobars --print-usage --demo
```

## 项目结构

```
Sources/TobarsCore/        # 可测试核心：模型、三家 provider、凭据存储、缓存、格式化
Sources/Tobars/            # SwiftUI MenuBarExtra、设置窗口、离屏渲染
Tests/TobarsCoreTests/     # 用 MockTransport + 真实响应样本做解析测试
docs/providers/            # 各服务接口契约与坑位
scripts/                   # build.sh / make_app.sh
```

`TobarsCore` 不依赖 SwiftUI；新增服务商实现 `UsageProviding` 并在 `ProviderRegistry`
注册即可。菜单内容与 `AppState` 解耦，便于 `--render-snapshot` 渲染。

## 已知限制

- 三家的用量接口都未完全公开（Command Code、Open Design 为控制台自用接口），
  字段变更时以服务商控制台为准；解析层已做宽松兼容，但无法保证永久有效。
- OpenCode 2.x 把登录凭据存入 `opencode.db`，目前只自动导入 1.x 的 `auth.json`。
- 未做 Developer ID 签名 / 公证；`make_app.sh` 使用 ad-hoc 签名，仅本机使用。
