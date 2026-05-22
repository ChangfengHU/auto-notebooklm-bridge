# NotebookLM Bridge — 消费者使用指南

消费者不需要本地安装 NotebookLM，也不需要登录 Google 账号。
生产者机器提供公网 Bridge，消费者通过 HTTP 调用所有 NotebookLM 能力。

---

## 前置准备

安装消费者 skill 后，`~/.claude/skills/notebooklm-bridge/bridge.env` 中已内置：

```bash
NOTEBOOKLM_BRIDGE_URL="https://notebooklm-bridge-nbb-a2321d3c9a.chxyka.ccwu.cc"
HERMES_WEBHOOK_TOKEN="<token>"
```

后续所有示例中：
- `$BRIDGE` = `NOTEBOOKLM_BRIDGE_URL`
- `$TOKEN` = `HERMES_WEBHOOK_TOKEN`

---

## Bridge 端点概览

| 端点 | 说明 | 适用场景 |
|------|------|---------|
| `POST /run` | 同步执行，阻塞等待结果（60s 超时）| list、create、ask、source add 等快速命令 |
| `POST /run/async` | 异步执行，立即返回 job_id | 生成产物、等待任务、下载文件等耗时命令 |
| `GET /jobs/{job_id}` | 查询 job 状态和结果 | 轮询异步任务 |
| `GET /jobs` | 列出最近所有 jobs | 调试、监控 |
| `DELETE /jobs/{job_id}` | 取消正在运行的 job | 中断耗时任务 |
| `GET /health` | 健康检查（无需 token）| 监控 |

---

## 一、笔记本管理

### 列出所有笔记本
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["list", "--json"]}'
```

### 创建笔记本
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["create", "我的研究笔记", "--json"]}'
```

### 重命名笔记本
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["rename", "<notebook_id>", "新名称", "--json"]}'
```

### 删除笔记本
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["delete", "<notebook_id>", "--json"]}'
```

### 获取笔记本 AI 摘要
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["summary", "-n", "<notebook_id>", "--json"]}'
```

---

## 二、添加内容源

### 添加 YouTube 视频
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["source", "add", "https://www.youtube.com/watch?v=VIDEO_ID", "-n", "<notebook_id>", "--json"]}'
```

### 添加网页
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["source", "add", "https://example.com/article", "-n", "<notebook_id>", "--json"]}'
```

### 等待内容源处理完成（异步）
```bash
# 先拿到 source_id，再等待
curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["source", "wait", "<source_id>", "-n", "<notebook_id>", "--timeout", "300", "--json"]}'
# 返回 job_id，然后轮询 /jobs/{job_id}
```

### 列出笔记本的所有内容源
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["source", "list", "-n", "<notebook_id>", "--json"]}'
```

### 删除内容源
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["source", "delete", "<source_id>", "-n", "<notebook_id>", "--json"]}'
```

---

## 三、AI 对话

### 向笔记本提问（同步）
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["ask", "这个视频的核心观点是什么？", "-n", "<notebook_id>", "--json"]}'
```

### 获取对话历史
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["history", "-n", "<notebook_id>", "--json"]}'
```

### 把对话历史保存为笔记
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["history", "save", "-n", "<notebook_id>", "--json"]}'
```

---

## 四、生成 AI 产物

> 生成类命令耗时较长（30s - 15min），全部用 `/run/async` + 轮询。

### 生成音频概览（Audio Overview）
```bash
JOB=$(curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["generate", "audio", "-n", "<notebook_id>", "--json"]}')
echo $JOB  # 拿到 job_id
```

### 生成思维导图（Mind Map）
```bash
curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["generate", "mind-map", "-n", "<notebook_id>", "--json"]}'
```

### 生成测验（Quiz）
```bash
curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["generate", "quiz", "-n", "<notebook_id>", "--json"]}'
```

### 生成闪卡（Flashcards）
```bash
curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["generate", "flashcards", "-n", "<notebook_id>", "--json"]}'
```

### 生成学习报告（Report）
```bash
curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["generate", "report", "-n", "<notebook_id>", "--json"]}'
```

### 生成幻灯片（Slide Deck）
```bash
curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["generate", "slide-deck", "-n", "<notebook_id>", "--json"]}'
```

### 生成信息图（Infographic）
```bash
curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["generate", "infographic", "-n", "<notebook_id>", "--json"]}'
```

### 等待产物生成完成
```bash
curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["artifact", "wait", "<artifact_id>", "-n", "<notebook_id>", "--timeout", "900", "--json"]}'
```

---

## 五、下载产物

### 下载音频文件
```bash
curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["download", "audio", "<artifact_id>", "-n", "<notebook_id>", "--json"]}'
```

### 列出所有产物
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["artifact", "list", "-n", "<notebook_id>", "--json"]}'
```

### 获取产物详情（含下载链接）
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["artifact", "get", "<artifact_id>", "-n", "<notebook_id>", "--json"]}'
```

---

## 六、笔记管理

### 创建笔记
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["note", "create", "笔记标题", "笔记内容", "-n", "<notebook_id>", "--json"]}'
```

### 列出所有笔记
```bash
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["note", "list", "-n", "<notebook_id>", "--json"]}'
```

---

## 七、异步任务轮询模式

所有耗时操作的标准流程：

```bash
# Step 1: 提交异步任务
RESPONSE=$(curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["generate", "audio", "-n", "<notebook_id>", "--json"]}')

JOB_ID=$(echo $RESPONSE | python3 -c "import json,sys; print(json.load(sys.stdin)['job_id'])")

# Step 2: 轮询结果
while true; do
  STATUS=$(curl -s "$BRIDGE/jobs/$JOB_ID" -H "X-Token: $TOKEN")
  STATE=$(echo $STATUS | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
  echo "状态: $STATE"
  if [[ "$STATE" == "done" || "$STATE" == "failed" ]]; then
    echo "$STATUS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('stdout',''))"
    break
  fi
  sleep 10
done
```

---

## 八、典型完整流程 — YouTube 视频分析

```bash
# 1. 创建笔记本
NB=$(curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" -H "Content-Type: application/json" \
  -d '{"args":["create","YouTube分析","--json"]}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['stdout'])" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# 2. 添加 YouTube 视频源
SRC=$(curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"args\":[\"source\",\"add\",\"https://youtube.com/watch?v=VIDEO_ID\",\"-n\",\"$NB\",\"--json\"]}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['stdout'])" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# 3. 等待处理完成
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"args\":[\"source\",\"wait\",\"$SRC\",\"-n\",\"$NB\",\"--timeout\",\"300\",\"--json\"]}"

# 4. 提问
curl -s -X POST "$BRIDGE/run" \
  -H "X-Token: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"args\":[\"ask\",\"视频的核心观点是什么？\",\"-n\",\"$NB\",\"--json\"]}"

# 5. 异步生成思维导图
JOB=$(curl -s -X POST "$BRIDGE/run/async" \
  -H "X-Token: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"args\":[\"generate\",\"mind-map\",\"-n\",\"$NB\",\"--json\"]}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['job_id'])")

# 6. 等待完成
curl -s "$BRIDGE/jobs/$JOB" -H "X-Token: $TOKEN"
```

---

## 注意事项

- `/run` 同步超时 **60s**，耗时命令必须用 `/run/async`
- 所有写操作都需要 `X-Token` header，`/health` 无需认证
- `--json` 参数让 CLI 输出结构化 JSON，建议所有调用都加上
- `-n <notebook_id>` 指定笔记本，不加则使用当前上下文笔记本
