---
name: notebooklm-bridge
description: "通过远程 NotebookLM HTTP Bridge 调用 NotebookLM 能力；消费端无需安装 notebooklm，只需配置访问 token。"
---

# NotebookLM Bridge

## Connection

This consumer skill is preconfigured by the producer deployment.

Read connection values from `bridge.env` in this skill directory:

```bash
set -a
source "$(dirname "$0")/bridge.env"
set +a
```

Values:

```text
NOTEBOOKLM_BRIDGE_URL=__PUBLIC_URL__
HERMES_WEBHOOK_TOKEN=__HERMES_WEBHOOK_TOKEN__
```

Use `NOTEBOOKLM_BRIDGE_URL` as the base URL and send `HERMES_WEBHOOK_TOKEN` in the `X-Token` header.

## Calls

Synchronous:

```bash
source ./bridge.env
curl -X POST "$NOTEBOOKLM_BRIDGE_URL/run" \
  -H "X-Token: $HERMES_WEBHOOK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["list", "--json"]}'
```

Asynchronous:

```bash
source ./bridge.env
curl -X POST "$NOTEBOOKLM_BRIDGE_URL/run/async" \
  -H "X-Token: $HERMES_WEBHOOK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["generate", "report", "深度分析", "-n", "NB_ID", "--json"]}'
```

Poll:

```bash
source ./bridge.env
curl "$NOTEBOOKLM_BRIDGE_URL/jobs/JOB_ID" -H "X-Token: $HERMES_WEBHOOK_TOKEN"
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
Consumers do not need to install `notebooklm` or login to Google.
