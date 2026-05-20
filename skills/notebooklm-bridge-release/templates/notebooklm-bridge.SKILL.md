---
name: notebooklm-bridge
description: "通过远程 NotebookLM HTTP Bridge 调用 NotebookLM 能力；消费端无需安装 notebooklm，只需配置访问 token。"
---

# NotebookLM Bridge

## Connection

```text
BASE_URL: __PUBLIC_URL__
Auth: Header X-Token: <HERMES_WEBHOOK_TOKEN>
```

Set the bridge token before use:

```bash
export HERMES_WEBHOOK_TOKEN="<bridge token>"
```

## Calls

Synchronous:

```bash
curl -X POST "__PUBLIC_URL__/run" \
  -H "X-Token: $HERMES_WEBHOOK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["list", "--json"]}'
```

Asynchronous:

```bash
curl -X POST "__PUBLIC_URL__/run/async" \
  -H "X-Token: $HERMES_WEBHOOK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["generate", "report", "深度分析", "-n", "NB_ID", "--json"]}'
```

Poll:

```bash
curl "__PUBLIC_URL__/jobs/JOB_ID" -H "X-Token: $HERMES_WEBHOOK_TOKEN"
```

## Common Commands

List notebooks:

```json
{"args": ["list", "--json"]}
```

Add source:

```json
{"args": ["source", "add", "https://example.com", "-n", "NB_ID", "--json"]}
```

Ask:

```json
{"args": ["ask", "核心观点是什么？", "-n", "NB_ID", "--json"]}
```

Generate report:

```json
{"args": ["generate", "report", "深度分析", "-n", "NB_ID", "--language", "zh_Hans", "--json"]}
```

## Notes

The NotebookLM login session lives on the producer machine that runs the bridge. Consumers only call the published HTTP endpoint.

