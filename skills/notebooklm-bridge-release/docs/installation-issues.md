# NotebookLM Bridge — 安装问题记录

> 记录时间：2026-05-22
> 目标：新机器部署一遍过，不再重复踩坑

---

## 一、环境依赖问题

| # | 问题 | 原因 | 解决 |
|---|------|------|------|
| 1 | `zip: command not found` | 系统没装 zip | `apt-get install -y zip` |
| 2 | 所有脚本缺少执行权限 | 没有 `chmod +x` | 手动 chmod 修复（deploy.sh 开头已加自动 chmod） |
| 3 | Python 脚本 `NoneType has no attribute 'get'` | JSON 解析逻辑错误 | 修正脚本逻辑 |

---

## 二、Cloudflare API / wrangler 问题

| # | 问题 | 原因 | 解决 |
|---|------|------|------|
| 4 | wrangler 报 "no stored wrangler auth" | wrangler 未登录 | 改用环境变量方式认证 |
| 5 | wrangler 报 "CLOUDFLARE_API_TOKEN required" | 非交互环境无法 wrangler login | 用 `CLOUDFLARE_API_KEY` + `CLOUDFLARE_EMAIL` 代替 |
| 6 | CF API 返回 10000 Authentication error | 用了 `Authorization: Bearer` 格式 | 改为 `X-Auth-Key` + `X-Auth-Email` |
| 7 | CF API 返回 9109 Invalid access token | token 无效或过期 | 换正确 token |
| 8 | CF API 返回 10007 entitlements.not_available | 账号未开通 Workers 付费计划 | 开通 Workers Standard（$5/月） |
| 9 | wrangler deploy 报 10013 unknown error | 未设置 `CLOUDFLARE_ACCOUNT_ID` | 部署时必须 export 该变量（见下方命令） |

**wrangler 正确部署命令：**
```bash
CLOUDFLARE_ACCOUNT_ID=9dee73ebf489bc2d507f7a3991c2c401 \
CLOUDFLARE_API_KEY=<cfk_...> \
CLOUDFLARE_EMAIL=go20260310@outlook.com \
npx wrangler deploy --config wrangler.toml
```

---

## 三、隧道稳定性问题

| # | 问题 | 原因 | 解决 |
|---|------|------|------|
| 10 | 连接后立即 1006 断开 | `await sendTg` 阻塞 101 握手响应（Telegram 请求 1-5s）| 改为 fire-and-forget：`sendTg(...).catch(() => {})` |
| 11 | 1006 后循环 409 | CF 延迟 10-30s 通知 DO 断开，期间旧 socket 仍有效，重连被拒 | 重连时先强制关闭所有旧 socket |
| 12 | 架构缺陷：`newUniqueId()` + KV 路由竞态 | 每次连接新建 DO，KV 有竞态，gateway 找不到正确 DO | 全改用 `idFromName(subdomain)`，永久绑定 |
| 13 | 公网返回 "Tunnel not found" 但 agent 显示 live | KV 条目过期或写入竞态 | `idFromName` 架构消除 KV 依赖，从根本解决 |
| 14 | 隧道自动下线 | DO Alarm + KV 清理竞态 | 新架构无需 Alarm，DO 直接管理连接状态 |

**核心架构修复（tunnel-do.js）：**
```js
// 重连时先关闭旧 socket
for (const ws of this.state.getWebSockets()) {
  try { ws.close(4000, 'Replaced by new connection'); } catch (_) {}
}
// TG 通知不阻塞 101 响应
sendTg(this.env, tgMsg(...)).catch(() => {});
return new Response(null, { status: 101, webSocket: client });
```

**核心架构修复（index.js）：**
```js
// idFromName 替代 newUniqueId — 同 subdomain 永远映射同一 DO
const doStub = env.TUNNEL_DO.get(env.TUNNEL_DO.idFromName(subdomain));
```

---

## 四、本地 Bridge 启动问题

| # | 问题 | 原因 | 解决 |
|---|------|------|------|
| 15 | bridge 启动后 `curl localhost:18800` 连接拒绝 | 服务未完全就绪 | 增加启动等待时间 |
| 16 | auto-domain skill 未找到 | 未提前安装 auto-domain | 先安装 auto-domain skill |
| 17 | auto-domain 未打印公网 URL | agent 连接失败或 token 无效 | 修复 token + 等待重试 |
| 18 | `vendor/auto-domain/run.sh` 缺少 `--daemon` 参数 | deploy 脚本一直阻塞不返回 | 添加 `--daemon` 参数 |

---

## 五、Token / 配置错误

| # | 问题 | 原因 | 解决 |
|---|------|------|------|
| 19 | auto-domain token 无效 | 配置写错 token | 正确 token：`myproxy-token-2026` |
| 20 | R2 upload token 无效（用了默认 `123456`）| 配置未更新 | 正确 token：`yt-research-token-2026` |
| 21 | bridge 调用返回 401 | token 配置或 header 不对 | 修正 token 传递方式 |

---

## 六、VNC 登录问题

| # | 问题 | 原因 | 解决 |
|---|------|------|------|
| 22 | websockify `PermissionError: [Errno 13]` | 尝试绑定 1006 特权端口 | 改用 7080 端口 |
| 23 | VNC 外网无法访问（port 1006）| 防火墙封锁 + 特权端口 | 改为高位端口 7080 |
| 24 | `notebooklm login` 无 PTY 错误 | 后台 `&` 方式运行，没有终端 | 改用 `screen -dmS` 创建 PTY |
| 25 | 新机器每次部署都要重新 VNC 登录 | auth（storage_state.json）不跨机器 | 实现 R2 auth 同步，自动跳过登录 |

**R2 auth 同步机制：**
- `scripts/sync-auth.sh`：验证 auth 有效后上传 `storage_state.json` 到 R2
- `scripts/download-auth.sh`：从 R2 下载并验证，写入本地 profile
- `start-bridge.sh`：启动时立即同步一次，之后每 30 分钟同步
- `deploy.sh`：部署前先验证本地 auth；本地无效才从 R2 恢复 auth，成功则跳过 VNC 登录
- R2 地址：`https://skill.vyibc.com/notebooklm/storage_state.json`

**Bridge token 规则：**
- `start-bridge.sh` 只在 `~/.notebooklm-bridge/env` 缺少 token 时生成新 token
- consumer skill 发布时会把当前 token 写入 `bridge.env`
- 不要为排障临时改 token；如确实轮换 token，必须重新运行 `publish-consumer-skill.sh` 并让消费者重新安装 skill
- 重启 bridge / domain 不应改变 `NOTEBOOKLM_BRIDGE_TOKEN` 或 `HERMES_WEBHOOK_TOKEN`

---

## 七、其他问题

| # | 问题 | 原因 | 解决 |
|---|------|------|------|
| 26 | `pkill` 返回 exit 144 导致脚本中断 | `pkill` 找不到进程返回非零，`set -e` 中止 | 加 `\|\| true` 忽略 |
| 27 | `sleep` 命令被 Claude Code 拦截 | Claude Code 禁止长 sleep 轮询 | 改用 `until` 循环 |
| 28 | bridge `/run` 接口缺少 `exit_code` 字段 | 返回结构与预期不符 | 修正解析逻辑 |

---

## 新机器部署 Checklist

- [ ] CF 账号已开通 **Workers Standard**（$5/月）
- [ ] 部署 Worker 时 export `CLOUDFLARE_ACCOUNT_ID=9dee73ebf489bc2d507f7a3991c2c401`
- [ ] 系统已安装 `zip`、`Xvfb`、`x11vnc`、`websockify`
- [ ] config.env 中 token 配置正确（auto-domain、R2、TG）
- [ ] 首次部署先复用本地 auth；本地无效再从 R2 下载 auth → 无需 VNC
- [ ] 如 R2 auth 过期 → 自动走 VNC 流程（7080 端口）
- [ ] Bridge 运行后每 30 分钟自动同步 auth 到 R2
- [ ] consumer skill 中的 `bridge.env` token 与生产端 `~/.notebooklm-bridge/env` 一致

---

## CF API 正确认证格式

```bash
# ✅ 正确
curl -H "X-Auth-Key: cfk_..." -H "X-Auth-Email: go20260310@outlook.com" ...

# ❌ 错误
curl -H "Authorization: Bearer cfk_..." ...
```
