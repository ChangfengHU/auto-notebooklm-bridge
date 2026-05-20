# auto-notebooklm-bridge

这是一个独立的 NotebookLM Bridge 生产者部署仓库。

它解决的问题是：在任意一台部署机器上完成 NotebookLM 登录、本地 HTTP Bridge 启动、公网域名分配，然后自动发布一个“消费者 skill”，让其他人的 Cursor/Codex/Claude 等工具可以通过这个公网 Bridge 使用 NotebookLM 能力。

仓库里不会写死任何机器 IP。公网访问地址由部署机器运行时通过 auto-domain 自动获取。

## 一键安装 Producer Skill

在需要部署 NotebookLM Bridge 的机器上执行：

```bash
bash <(curl -fsSL "https://skill.vyibc.com/install-notebooklm-bridge-release.sh?v=$(date +%s)")
```

`?v=$(date +%s)` 用来绕过 CDN 或本机缓存，确保拿到最新安装脚本。URL 必须加双引号，避免 zsh 把 `?` 当作通配符。

执行后会让你选择安装到哪个 AI 工具：

```text
1) Codex
2) Cursor
3) Claude
4) Gemini
5) Antigravity
6) Copilot
7) OpenClaw
8) Agents
9) Hermes
10) All
```

比如安装到 Cursor，就选 `2`。

## 安装后怎么用

上面的命令只是安装 `notebooklm-bridge-release` 这个 producer skill，不是直接完成部署。

安装完成后，在对应工具里对 agent 说：

```text
使用 notebooklm-bridge-release 部署 NotebookLM Bridge
```

或者：

```text
运行 notebooklm-bridge-release 的 deploy
```

producer skill 会执行完整部署流程：

1. 安装或定位 `notebooklm` CLI
2. 引导用户完成 NotebookLM 登录
3. 启动本地 HTTP Bridge
4. 使用 auto-domain 获取公网域名
5. 发布消费者 skill
6. 输出消费者一键安装命令

## NotebookLM 登录说明

NotebookLM 登录是必须的，因为 Bridge 需要使用部署机器上的 NotebookLM 登录态。

当前使用的是 `notebooklm-py` 的登录逻辑：

```bash
notebooklm login
```

它使用 Playwright 管理的 Chromium 浏览器，不是系统默认浏览器。

如果机器上还没有 Playwright Chromium，部署脚本会提示你可以执行类似命令：

```bash
~/.venvs/notebooklm-py/bin/python -m playwright install chromium
```

下载完成后，重新让 agent 运行 deploy 即可。当前脚本不会强制自动下载 Chromium。

如果你在 macOS 或 Windows 已经用 Chrome 登录过 Google，也可以让部署脚本走备用登录路径：

```bash
notebooklm login --browser-cookies chrome
```

这个方式默认读取 Chrome 的 Default Profile。它不会自动扫描所有 Chrome Profile；如果你有多个 Google 账号，需要确认 Default Profile 对应的账号就是你想给 Bridge 使用的 NotebookLM 账号。

Linux 服务器如果没有桌面环境，需要通过 VNC 完成浏览器登录；macOS 和 Windows 通常会直接弹出本机浏览器窗口。

## 公网域名

部署时会自动启动本地 Bridge，并通过 auto-domain 申请公网域名。

域名不是写死在仓库里的。每台机器部署时会根据运行结果生成自己的公网访问地址。

如果 tunnel 失败，脚本会提示查看：

```bash
~/.notebooklm-bridge/domain.log
~/.tunneling/machine-agent/agent.log
```

本地 Bridge 正常但公网 404 时，通常是 tunnel agent 没连到正确的 gateway，需要按日志提示重启 agent。

## 机器 ID 和发布路径

每台部署机器会生成一个稳定的机器 ID：

```text
~/.notebooklm-bridge/machine-id
```

发布产物会带机器 ID，避免多台机器互相覆盖：

```text
notebooklm-bridge/<machine-id>/<kind>/<name>
```

示例：

```text
notebooklm-bridge/nbb-7f3c2a91/domain/current.json
notebooklm-bridge/nbb-7f3c2a91/release/install-notebooklm-bridge.sh
notebooklm-bridge/nbb-7f3c2a91/release/notebooklm-bridge.zip
```

## 消费者怎么使用

producer 部署成功后，会输出消费者安装命令，类似：

```bash
bash <(curl -fsSL "https://skill.vyibc.com/notebooklm-bridge/<machine-id>/release/install-notebooklm-bridge.sh?v=$(date +%s)")
```

把这个命令发给别人，对方安装后就能通过你的公网 Bridge 调用 NotebookLM。

消费者机器不需要自己登录 NotebookLM，也不需要本地部署 Bridge；登录和 Bridge 都在生产者机器上。消费者 skill 包里会内置 `bridge.env`，包含公网 URL 和 `HERMES_WEBHOOK_TOKEN`，所以消费端安装后不需要再手动猜 token。

## 常用命令

重新运行部署：

```bash
~/.cursor/skills/notebooklm-bridge-release/scripts/deploy.sh
```

如果已经登录过，只想跳过登录重新检查 Bridge 和公网域名：

```bash
~/.cursor/skills/notebooklm-bridge-release/scripts/deploy.sh --skip-login
```

查看本地状态：

```bash
ls ~/.notebooklm-bridge
```

检查本地 Bridge：

```bash
curl http://127.0.0.1:18800/health
```

## 仓库职责

这个仓库主要面向部署机器，也就是 producer。

它负责：

- 安装 producer skill
- 引导 NotebookLM 登录
- 启动本地 Bridge
- 获取公网域名
- 发布 consumer skill

最终分享给别人使用的是 producer 部署成功后生成的 consumer skill 安装命令。

## 部署成功判据

部署脚本不会只依赖 `/health`。完整成功需要同时满足：

- NotebookLM Auth 检查通过
- 本地 Bridge `/run` 可以带 token 执行 `list --json`
- 公网 Bridge `/run` 可以带 token 执行 `list --json`
- consumer skill 发布成功

如果使用 `--skip-login`，脚本也会先检查 NotebookLM Auth；Auth 不通过时不会继续发布。
