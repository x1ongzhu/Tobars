# OpenCode Go

## 认证

普通 API key（`opencode.ai/console` 生成），请求头：

```
Authorization: Bearer <key>
```

密钥来源优先级（本机）：`~/.local/share/opencode/auth.json` 的 `opencode-go` 条目（OpenCode 1.x）。
OpenCode 2.x 把凭据移进 `~/.local/share/opencode/opencode*.db`，当前未自动读取。

## 用量接口

```
GET https://opencode.ai/zen/go/v1/usage
```

响应（实测字段，2026-08）：

```json
{
  "usage": {
    "rolling": { "status": "ok", "percent": 4, "resetsAt": "2026-08-13T16:27:38.287Z" },
    "weekly":  { "status": "ok", "percent": 3, "resetsAt": "2026-08-17T00:00:00.287Z" },
    "monthly": { "status": "ok", "percent": 1, "resetsAt": "2026-09-13T06:06:01.287Z" }
  }
}
```

- 三个窗口对应 5 小时 / 每周 / 每月；`percent` 是已用百分比，不是剩余。
- 接口返回的是**额度百分比**，没有 token 明细，也没有金额。
- 上线一小时内改过一次响应结构，官方也承认控制台 SSR 解析易碎；因此 code 里逐窗口容错。

## 错误

- `401 {"type":"error","error":{"type":"AuthError",...}}` → key 错误/失效。
- `403` + `EntitlementError` → 该 key 没有 Go 订阅。
- 官方控制台另有 `GET /api/experimental/usage/limits`（网页登录态），应用不依赖它。

## 其他

- 订阅档位：Go $10/月、Go Plus $40/月；限额按模型月额度拆分到 5 小时（20%）/每周（50%）。
- 控制台：https://opencode.ai/console/go
