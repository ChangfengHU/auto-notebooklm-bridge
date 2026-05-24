---
name: notebooklm-bridge
description: "通过远程 NotebookLM HTTP Bridge 调用 NotebookLM 能力。支持笔记本管理、添加内容源（YouTube/论文/网页）、AI 对话、生成产物（脑图/报告/音频/视频/闪卡/测验）。音视频等二进制产物自动上传 R2，job 结果直接返回下载链接，消费端无需登录 NotebookLM。"
---

# NotebookLM Bridge

## 连接配置

skill 目录下的 `bridge.env` 已内置，无需手动配置：

```
NOTEBOOKLM_BRIDGE_URL=__PUBLIC_URL__
HERMES_WEBHOOK_TOKEN=__HERMES_WEBHOOK_TOKEN__
```

所有请求需要 header：`X-Token: __HERMES_WEBHOOK_TOKEN__`

## 接口说明

| 接口 | 方法 | 说明 |
|------|------|------|
| `/run` | POST | 同步执行（≤60s）适合 list/create/ask 等快速命令 |
| `/run/async` | POST | 异步执行，返回 job_id，适合 generate/download 等耗时命令 |
| `/jobs/{id}` | GET | 查询 job 状态；download 完成后含 `r2_urls` 直接下载链接 |
| `/health` | GET | 健康检查（无需 token） |

## 文件传输说明

**音频、视频、PDF 等二进制产物走 R2，不经过隧道：**

1. `/run/async` 执行 `download` 命令
2. Bridge 自动上传文件到 R2
3. `GET /jobs/{id}` 结果中包含 `r2_urls: {"filename.mp3": "https://skill.vyibc.com/..."}`
4. 消费者直接 `curl` R2 地址下载到本地，无大小限制

## 常用命令

**列出笔记本：**
```json
{"args": ["list", "--json"]}
```

**创建笔记本：**
```json
{"args": ["create", "笔记本名称", "--json"]}
```

**添加内容源（YouTube / 论文 / 网页）：**
```json
{"args": ["source", "add", "https://...", "-n", "NB_ID", "--json"]}
```

**等待内容源处理完成（/run/async）：**
```json
{"args": ["source", "wait", "SOURCE_ID", "-n", "NB_ID", "--timeout", "300", "--json"]}
```

**向笔记本提问：**
```json
{"args": ["ask", "核心观点是什么？", "-n", "NB_ID", "--json"]}
```

**生成产物（均用 /run/async）：**
```json
{"args": ["generate", "mind-map",   "-n", "NB_ID", "--json"]}
{"args": ["generate", "report",     "-n", "NB_ID", "--language", "zh_Hans", "--json"]}
{"args": ["generate", "audio",      "-n", "NB_ID", "--json"]}
{"args": ["generate", "flashcards", "-n", "NB_ID", "--json"]}
{"args": ["generate", "quiz",       "-n", "NB_ID", "--json"]}
{"args": ["generate", "slide-deck", "-n", "NB_ID", "--json"]}
```

**等待产物生成完成（/run/async）：**
```json
{"args": ["artifact", "wait", "ARTIFACT_ID", "-n", "NB_ID", "--timeout", "900", "--json"]}
```

**下载音频/视频到本地（完整流程）：**
```json
// Step 1: 提交 download 任务（Bridge 自动补 --output-dir）
{"args": ["download", "audio", "ARTIFACT_ID", "-n", "NB_ID", "--json"]}

// Step 2: 轮询 GET /jobs/{job_id}，done 后结果含：
// {"r2_urls": {"podcast.mp3": "https://skill.vyibc.com/notebooklm/downloads/podcast.mp3"}}

// Step 3: 消费者直接下载
// curl "https://skill.vyibc.com/notebooklm/downloads/podcast.mp3" -o ~/Desktop/podcast.mp3
```

## 完整示例：从添加论文到下载音频

```
用户说：帮我创建关于 LoRA 微调的笔记本，添加论文，生成中文播客音频，下载到桌面

Agent 执行步骤：
1. POST /run     {"args": ["create", "LoRA微调研究", "--json"]}
2. POST /run     {"args": ["source", "add", "https://arxiv.org/abs/2106.09685", "-n", "NB_ID", "--json"]}
3. POST /run/async {"args": ["source", "wait", "SRC_ID", "-n", "NB_ID", "--timeout", "300"]}
4. POST /run/async {"args": ["generate", "audio", "-n", "NB_ID", "--json"]}
   → 轮询直到 done，拿到 ARTIFACT_ID
5. POST /run/async {"args": ["artifact", "wait", "ARTIFACT_ID", "-n", "NB_ID", "--timeout", "900"]}
6. POST /run/async {"args": ["download", "audio", "ARTIFACT_ID", "-n", "NB_ID", "--json"]}
   → 轮询 done，结果含 r2_urls: {"lora-podcast.mp3": "https://skill.vyibc.com/..."}
7. curl R2 URL -o ~/Desktop/lora-podcast.mp3
```

## 注意事项

- 消费者**无需** NotebookLM 账号或 Google 登录，认证在生产者机器上
- 快速命令用 `/run`，耗时命令用 `/run/async` + 轮询 `/jobs/{id}`
- 所有命令加 `--json` 获得结构化输出
- `-n NB_ID` 指定笔记本 ID（从 list 命令获取）
