---
name: notebooklm-bridge
description: "通过远程 NotebookLM HTTP Bridge 调用 NotebookLM 能力；消费端无需安装 notebooklm，只需配置访问 token。支持笔记本管理、添加内容源、AI 对话、生成产物（脑图/报告/音频/视频）、下载文件到本地。"
---

# NotebookLM Bridge

## Connection

Read connection values from `bridge.env` in this skill directory:

```bash
NOTEBOOKLM_BRIDGE_URL=__PUBLIC_URL__
HERMES_WEBHOOK_TOKEN=__HERMES_WEBHOOK_TOKEN__
```

All requests require header: `X-Token: $HERMES_WEBHOOK_TOKEN`

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/run` | POST | 同步执行（≤60s，适合 list/create/ask 等） |
| `/run/async` | POST | 异步执行，返回 job_id（适合 generate/download 等耗时命令） |
| `/jobs/{id}` | GET | 查询 job 状态和结果 |
| `/files` | GET | 列出远端可下载文件 |
| `/file/{filename}` | GET | 下载文件到本地（mp3/mp4/pdf 等二进制文件走此接口） |
| `/health` | GET | 健康检查（无需 token） |

## Common Commands

**List notebooks:**
```json
{"args": ["list", "--json"]}
```

**Create notebook:**
```json
{"args": ["create", "笔记本名称", "--json"]}
```

**Add source (YouTube / URL / paper):**
```json
{"args": ["source", "add", "https://...", "-n", "NB_ID", "--json"]}
```

**Wait for source to finish processing:**
```json
{"args": ["source", "wait", "SOURCE_ID", "-n", "NB_ID", "--timeout", "300", "--json"]}
```

**Ask a question:**
```json
{"args": ["ask", "核心观点是什么？", "-n", "NB_ID", "--json"]}
```

**Generate artifacts (use /run/async):**
```json
{"args": ["generate", "mind-map",   "-n", "NB_ID", "--json"]}
{"args": ["generate", "report",     "-n", "NB_ID", "--language", "zh_Hans", "--json"]}
{"args": ["generate", "audio",      "-n", "NB_ID", "--json"]}
{"args": ["generate", "flashcards", "-n", "NB_ID", "--json"]}
{"args": ["generate", "quiz",       "-n", "NB_ID", "--json"]}
{"args": ["generate", "slide-deck", "-n", "NB_ID", "--json"]}
```

**Wait for artifact generation (use /run/async):**
```json
{"args": ["artifact", "wait", "ARTIFACT_ID", "-n", "NB_ID", "--timeout", "900", "--json"]}
```

**Download binary file (mp3/mp4/pdf) to remote downloads dir:**
```json
{"args": ["download", "audio", "ARTIFACT_ID", "-n", "NB_ID",
          "--output-dir", "/home/USER/.notebooklm-bridge/downloads", "--json"]}
```

**Then fetch file to local machine:**
```bash
curl "$NOTEBOOKLM_BRIDGE_URL/file/FILENAME" \
  -H "X-Token: $HERMES_WEBHOOK_TOKEN" \
  -o ~/Desktop/FILENAME
```

## Full Flow: Download Audio to Desktop

```bash
# 1. Generate audio (async)
JOB=$(curl -s -X POST "$BRIDGE/run/async" -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args":["generate","audio","-n","NB_ID","--json"]}')
JOB_ID=$(echo $JOB | python3 -c "import json,sys; print(json.load(sys.stdin)['job_id'])")

# 2. Poll until done, get artifact_id
# 3. Download to remote downloads dir (async)
curl -s -X POST "$BRIDGE/run/async" -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"args\":[\"download\",\"audio\",\"ARTIFACT_ID\",\"-n\",\"NB_ID\",
      \"--output-dir\",\"/home/USER/.notebooklm-bridge/downloads\",\"--json\"]}"

# 4. List files to get filename
curl -s "$BRIDGE/files" -H "X-Token: $TOKEN"

# 5. Download file to local desktop
curl -s "$BRIDGE/file/FILENAME" -H "X-Token: $TOKEN" -o ~/Desktop/FILENAME
```

## Notes

- Consumers do NOT need a NotebookLM account or Google login — auth lives on the producer machine.
- Use `/run` for fast commands (list, create, ask, source add). Use `/run/async` + poll for slow commands (generate, download).
- Binary files (mp3, mp4, pdf) must be downloaded via `GET /file/{filename}`, not via stdout.
- Downloads dir on producer: `~/.notebooklm-bridge/downloads/`
