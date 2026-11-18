# Open Design

## 认证

额度接口在**控制面** `amr-api.open-design.ai`，只接受：

- **Control Key**（`vela_ctrl_…`），`Authorization: Bearer …`；或
- 浏览器会话 Cookie（`__Secure-better-auth.session_token` 等）。

`sk-amr-…` 推理密钥**不能**查询额度（401/403）。应用优先使用 Control Key，
也支持直接粘贴从控制台额度请求里复制的 Cookie 头。

## 如何获取 Control Key

Control Key（`vela_ctrl_…`）**不会显示在任何网页上**，由设备授权签发：

1. 安装 OpenDesign 桌面版并登录（<https://open-design.ai/download>），
   或安装官方 vela CLI（<https://open-design.ai/amr>）后运行 `vela login`；
2. 在浏览器里批准设备授权；
3. 登录状态保存到 `~/.amr/config.json`，`profiles.prod.controlKey` 就是 Control Key；
4. Tobars 设置页的「从本机读取并连接」会自动读这个字段。

注意：

- Cloud 控制台 API Keys 页生成的是 `sk-amr-…` **推理密钥**，只能调用模型，查额度会 401。
- 不装桌面版 / CLI 也可以：在浏览器控制台的额度请求里复制 Cookie 请求头，
  Tobars 里把认证方式切到「浏览器 Cookie」。

## 接口

```
GET https://amr-api.open-design.ai/api/v1/workspaces/current
GET https://amr-api.open-design.ai/api/v1/workspaces/{id}/billing/coding-plan-usage
    X-Vela-Workspace-Id: {id}
GET https://amr-api.open-design.ai/api/v1/workspaces/{id}/wallet/balance
GET https://amr-api.open-design.ai/api/v1/me
```

`/api/v1/me` 返回 `{ email, name, plan, balanceUsd, ... }`，菜单里的「账号」用它；
`workspaces/current` 只有 `workspaceName`（工作区名，不等于账号）。

工作区 ID 也可以手动填写；自动发现失败时回退到 `GET /api/v1/workspaces`
取 `items[].workspaceId`。注意不能用 `~/.amr/config.json` 里的 user id。

### coding-plan-usage

```json
{
  "eligible": true,
  "tier": "go",
  "windows": [
    { "durationSeconds": 18000,  "usedCredits": "16000", "limitCredits": "50000", "resetsAt": "..." },
    { "durationSeconds": 604800, "usedCredits": "78000", "limitCredits": "150000", "resetsAt": "..." }
  ]
}
```

- `18000` = 5 小时，`604800` = 7 天；Go 两个窗口都有，Plus/Pro/Max 只有 7 天窗口。
- `usedCredits` / `limitCredits` 可能超出 2^53，且可能是字符串 → 一律按宽松数值解析。
- 百分比 = `usedCredits / limitCredits`；不要相加多个窗口，也不要当美元。

### preflight 回退

部分账号的 `coding-plan-usage` 只认浏览器 Cookie，Control Key 会得到 401/403。
此时用同一凭据请求：

```
GET .../billing/preflight
```

窗口数据嵌在 `codingPlan` 下（形状同上），另有 `workspaceMemberId`、`balanceUsd`。
只在 401/403 时回退一次；200 但结构异常不回退。

### 钱包

`wallet/balance` 独立读取；字段可能是 `balanceUsd` / `balance` / `amount`。
失败不影响额度展示。

## 其他

- 这些是官网控制台自己在用的未公开接口，官方 issue 仍要求提供公开 usage API。
- 控制台：https://open-design.ai/cloud/dashboard
- 文档：https://open-design.ai/help/billing/
