# Command Code

## 认证

API key（Studio → API keys），与 CLI 共用。请求头：

```
Authorization: Bearer <key>
```

本机来源：`~/.commandcode/auth.json` 的 `apiKey` 字段，或环境变量 `COMMAND_CODE_API_KEY`。

## 用量接口

CLI 的 `/usage` 面板用的就是这组 alpha 接口（非公开文档，字段可能变）：

```
GET https://api.commandcode.ai/alpha/whoami?limits=1
GET https://api.commandcode.ai/alpha/billing/credits?orgId=<org>
GET https://api.commandcode.ai/alpha/billing/subscriptions?orgId=<org>
GET https://api.commandcode.ai/alpha/usage/summary?orgId=<org>
```

`whoami` 先拿 `org.id`，其余请求都带 `orgId`。

### 关键字段

```jsonc
// whoami
{ "org": { "id": "org_...", "login": "name" }, "user": { "userName": "name" } }

// billing/credits
{
  "credits": {
    "planId": "individual-goat",   // 有时只在 subscriptions 里
    "monthlyCredits": 1.66,        // 剩余（不是总额）
    "purchasedCredits": 0,
    "freeCredits": 0
  },
  "windowLimits": {                // 顶层！不在 credits 内
    "limited": true,
    "fiveHour": { "used": 0, "cap": 14, "resetAt": 0 },
    "weekly":   { "used": 0.72, "cap": 35, "resetAt": 1795198760635 }
  }
}

// billing/subscriptions
{ "data": { "planId": "...", "status": "active",
            "currentPeriodStart": "...", "currentPeriodEnd": "..." } }

// usage/summary
{ "totalCost": 56.8 }
```

## 计算方式

- 5 小时 / 每周：`used / cap`，取 **顶层** `windowLimits`（旧样本里可能在 `credits` 内，
  解析器两种都接受）。`resetAt: 0` 表示该窗口还没开始，不显示倒计时。
- 本月：`totalCost / (totalCost + remaining)`，其中
  `remaining = monthlyCredits + purchasedCredits + freeCredits`。
  这样不依赖各套餐的硬编码月度额度（CLI 里的套餐表已经与定价页出现过不一致）。
- `windowLimits.limited == true` → 菜单里显示「已触发窗口限额」。
- 额外额度（purchased + free）单独显示，不混进 5h/周窗口。

## 其他

- 只有 `/alpha/*` 用量接口；Provider API（`/provider/v1/*`）只用于模型调用，不返回账号额度。
- GOAT 的窗口按 credit 价值计算：5h = 14 credits、每周 = 35 credits，与 `used/cap` 的金额口径一致。
- 控制台：https://commandcode.ai/usage
