# AGENTS.md

Tobars — macOS 菜单栏（status bar）应用，汇总 OpenCode Go / Command Code / Open Design 的订阅额度。
SwiftPM + SwiftUI `MenuBarExtra`，macOS 14+，`swift-tools-version: 6.0`，**没有 `.xcodeproj`**。

## 常用命令

```bash
./scripts/build.sh                 # 调试构建（自动用 xcode-select -p 设 DEVELOPER_DIR）
./scripts/build.sh run             # 启动，仅菜单栏图标（AppDelegate 设为 .accessory）
./scripts/build.sh test            # 全量测试
./scripts/build.sh test --filter TobarsCoreTests.CommandCodeProviderTests
./scripts/make_app.sh              # 打包 build/Tobars.app（ad-hoc 签名）
```

- 改完菜单 UI 必须离屏检查（菜单栏弹窗没法常规截图）：
  `.build/debug/Tobars --render-snapshot /tmp/tobars-snap` → 生成菜单与设置的浅色/深色 PNG。
- 设置窗口打不开时用 `.build/debug/Tobars --show-settings` 直接定位。
- 不启动 UI 验证真实接口：`.build/debug/Tobars --print-usage`；无凭据时加 `--demo`。
- 只装 CommandLineTools 编译不了：SwiftUI 宏依赖完整 Xcode 的 `libSwiftUIMacros`。
- `make_app.sh` 优先用本机 `Apple Development` 身份签名，找不到才退回 ad-hoc；稳定签名能避免系统把每次构建当成新应用。

## 结构

- `Sources/TobarsCore/`：模型、三家 provider、凭据存储、缓存、格式化。**不依赖 SwiftUI**。
- `Sources/Tobars/`：`MenuBarExtra`、设置窗口、`AppState`、离屏渲染、`main.swift` 参数分发。
- 供应商 logo 在 `Sources/Tobars/Resources/ProviderLogos/`，用 `Bundle.module` 读取；
  `make_app.sh` 必须把 SwiftPM 生成的 `Tobars_Tobars.bundle` 一起拷进 `Contents/Resources`，
  否则打包后 logo 会变空白。
- 数据源是 **`Account` 列表**，不是「每个服务商一个配置」：同一 provider 可以添加多个账号。
  `accounts.json` 只存 UUID/服务商/显示名；密钥按账号 UUID 存在
  `credentials.json`（权限 0600）。
  菜单、设置、`--print-usage` 全部按账号遍历，新增/删除账号不涉及 provider 代码。
- 新增服务商：实现 `UsageProviding` → 在 `ProviderRegistry` 注册 → `ProviderID` 加 case
  （「添加账号」菜单会自动枚举）。解析逻辑放进 `TobarsCore` 并有 fixture 测试。
- `MenuContentView` 只接收 `MenuContentData`，与 `AppState` 解耦，专为渲染与测试服务。
- 测试统一用 `MockTransport` + 真实响应样本；不要为测试引入网络。

## UI 原则

- **不要添加多余的解释性文本，让 UI 自己表达含义。** 标题、状态 chip、按钮文案已经说明的事情不要再写一段话；
  只有安全语义或供应商特有的陷阱无法从控件推断时，才保留一行短提示（例如 Open Design 的 Control Key 与推理密钥的区别）。
- 改 UI 后必须看 `--render-snapshot` 的实际渲染结果，不要凭 SwiftUI 代码想象布局。

## 数据与安全

- 凭据存 `~/Library/Application Support/Tobars/credentials.json`，权限 0600；绝不进 git、日志或对话。
  **不要改回 Keychain**：ad-hoc 签名每次重建都会让它弹钥匙串密码。旧 Keychain 条目只用于
  一次性迁移（`--migrate-credentials`），运行期不再访问。
- `Tobars/accounts.json` 只有账号元数据；`usage-cache.json` 以账号 UUID 为 key，只有百分比与时间。
- 菜单栏数字 = 所有账号、所有窗口中最高的已用百分比；未知值显示 `—`，不要伪造成 0%。

## 接口坑位（详细契约见 `docs/providers/`）

- 三家都**没有完整公开的 usage API**，字段会漂移；解析前先读对应 doc，修改时保留宽松兼容。
- OpenCode Go：`GET opencode.ai/zen/go/v1/usage`，`percent` 是**已用**百分比；
  `rolling/weekly/monthly` 要逐窗口容错，字段曾在上线后一小时内改版。
- Command Code：先 `/alpha/whoami` 取 `org.id`，再并发请求 credits/subscriptions/summary。
  `windowLimits` 在 credits 响应的**顶层**（与 `credits` 同级），不在 `credits` 内部；
  本月额度用 `totalCost / (totalCost + 剩余)` 反推；**不要硬编码套餐月度额度**（官方两处数字不一致）。
- Open Design：账号身份取 `GET /api/v1/me` 的 `email`（`workspaces/current` 只有工作区名）；
  控制面 `amr-api.open-design.ai` 只认 Control Key（`vela_ctrl_…`）或会话 Cookie，
  `sk-amr-…` 推理密钥不行；`coding-plan-usage` 返回 401/403 时才回退 `billing/preflight`
  （窗口嵌在 `codingPlan` 下）；workspaceId 必须取 `/workspaces/current` 或 `items[]`，
  不能拿 `~/.amr/config.json` 的 user id。
- JSON 解析统一走 `JSON` + `Optional<JSON>` 扩展；credits 可能是字符串、时间可能是 epoch/ISO。

## 已知取舍

- `MenuContentView` **不使用 `ScrollView`**：菜单窗口按内容增高，不做滚动；`ImageRenderer`
  也渲染不出 ScrollView 内容。账号多时让弹窗变高，不要改回滚动。
- 设置窗口是手写的 `NSWindow`（`SettingsWindowController`），**不要换回 SwiftUI `Settings` scene**：
  `.accessory` + `MenuBarExtra` 下 `openSettings` 会无反应。设置页截图也必须走真实窗口
  `cacheDisplay`（`ImageRenderer` 会把 TextField/Picker 画成黄色占位）。
- 凭据流程是「先验证、成功才写凭据文件」（`AppState.test(_:for:)`），失败的 key 不落盘。
- Swift 语言模式固定 `.v5`（`Package.swift`），避免 Swift 6 严格并发拖慢 provider 迭代。
- OpenCode 2.x 凭据在 `opencode.db`，目前只自动导入 1.x 的 `auth.json` 与 `~/.commandcode/auth.json`。
- Open Design 的 Control Key 不在网页上，来自 `~/.amr/config.json` 的
  `profiles.prod.controlKey`（桌面版或 `vela login` 写入）；`sk-amr-…` 推理 key 不能查额度。
