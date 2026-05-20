---
name: notebooklm-bridge-release
description: "生产者部署 NotebookLM Bridge：安装 CLI、引导 NotebookLM 登录、启动 HTTP 服务、申请公网域名并发布消费端 skill。"
---

# NotebookLM Bridge Release

## Purpose

Use this skill on a producer machine. It prepares that machine to serve NotebookLM over HTTP and publishes a consumer skill for other machines.

The fixed install command for this producer skill is:

```bash
bash <(curl -fsSL "https://skill.vyibc.com/install-notebooklm-bridge-release.sh?v=$(date +%s)")
```

## Artifact Path

All uploaded artifacts are isolated by stable machine id:

```text
notebooklm-bridge/<machine-id>/<kind>/<name>
```

The machine id is created once and stored at:

```text
~/.notebooklm-bridge/machine-id
```

## Deploy

Run:

```bash
__SKILL_DIR__/scripts/deploy.sh
```

The script performs:

1. generate or read `machine-id`
2. install or locate `notebooklm`
3. guide the operator through browser login
4. start local HTTP bridge on `18800`
5. expose the bridge with auto-domain
6. publish the consumer `notebooklm-bridge` skill under the machine path
7. print the consumer install command

Deploy is considered successful only after NotebookLM auth passes and `/run` can execute `list --json` through both the local bridge and the public tunnel with the bridge token.

## Linux Headless

If Linux has no `$DISPLAY`, run:

```bash
__SKILL_DIR__/scripts/deploy-linux-vnc.sh
```

Open the printed VNC URL, then run:

```bash
DISPLAY=:99 notebooklm login
```

After login succeeds, rerun:

```bash
__SKILL_DIR__/scripts/deploy.sh --skip-login
```

`--skip-login` still requires existing NotebookLM auth to pass. It will not publish a consumer skill if auth is invalid.

## Output

The final output contains:

```text
MACHINE_ID=...
PUBLIC_URL=...
AUTH_STATUS=pass
BRIDGE_TOKEN_FILE=~/.notebooklm-bridge/env
CONSUMER_INSTALL_COMMAND=...
```
