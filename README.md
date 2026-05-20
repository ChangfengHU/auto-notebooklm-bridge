# auto-notebooklm-bridge

Independent producer/consumer suite for NotebookLM Bridge.

The fixed producer entry installs `notebooklm-bridge-release`. A deployment machine runs that skill to:

1. install or locate the `notebooklm` CLI
2. guide the operator through NotebookLM browser login
3. start a local HTTP bridge
4. expose the bridge with auto-domain
5. publish a consumer skill for other machines

No IP address is stored in this repository. Public access is discovered at release time from auto-domain.

## Fixed Producer Install Command

```bash
bash <(curl -fsSL https://skill.vyibc.com/install-notebooklm-bridge-release.sh)
```

## Machine Namespace

Every deployment machine gets a stable local machine id:

```text
~/.notebooklm-bridge/machine-id
```

Uploaded artifacts use this path shape:

```text
notebooklm-bridge/<machine-id>/<kind>/<name>
```

Examples:

```text
notebooklm-bridge/nbb-7f3c2a91/domain/current.json
notebooklm-bridge/nbb-7f3c2a91/release/install-notebooklm-bridge.sh
notebooklm-bridge/nbb-7f3c2a91/release/notebooklm-bridge.zip
```

## Producer Flow

```bash
skills/notebooklm-bridge-release/scripts/deploy.sh
```

The script prints the final consumer install command.

