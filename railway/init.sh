#!/bin/bash
# Railway-Init: Injects CEELIS-MCP + Anthropic-Provider into hermes config.yaml.
#
# Runs every container start as the hermes user (after docker/entrypoint.sh
# has bootstrapped defaults). Idempotent: overwrites our managed sections,
# preserves everything else the user may have set via `hermes config set`.
#
# Required ENVs:
#   CEELIS_MCP_BEARER
# Optional ENVs:
#   CEELIS_MCP_URL (default: https://api.kundenportal.ceelis.com/functions/v1/mcp)
#   HERMES_DEFAULT_MODEL (default: anthropic/claude-sonnet-4-5)
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"

if [ -z "$CEELIS_MCP_BEARER" ]; then
  echo "[railway-init] CEELIS_MCP_BEARER missing — skipping MCP injection."
else
  python3 <<PYEOF
import os, yaml
from pathlib import Path

path = Path(os.environ.get("HERMES_HOME", "/opt/data")) / "config.yaml"
config = {}
if path.exists():
    try:
        config = yaml.safe_load(path.read_text()) or {}
    except yaml.YAMLError as e:
        print(f"[railway-init] WARNING: existing config.yaml unparseable ({e}), starting fresh")
        config = {}

# Model-Default (nicht überschreiben falls User schon was anderes gesetzt hat)
config.setdefault("model", {})
if not config["model"].get("default"):
    config["model"]["default"] = os.environ.get("HERMES_DEFAULT_MODEL", "anthropic/claude-sonnet-4-5")

# CEELIS-Portal-MCP (immer aus ENV neu setzen — Bearer kann rotieren)
config.setdefault("mcp_servers", {})
config["mcp_servers"]["ceelis-portal"] = {
    "url": os.environ.get("CEELIS_MCP_URL", "https://api.kundenportal.ceelis.com/functions/v1/mcp"),
    "headers": {"Authorization": f"Bearer {os.environ['CEELIS_MCP_BEARER']}"},
    "enabled": True,
}

path.write_text(yaml.safe_dump(config, sort_keys=False, default_flow_style=False))
print(f"[railway-init] config.yaml updated at {path} (CEELIS-Portal-MCP injected)")
PYEOF
fi

# Final: execute hermes with the args we were called with
exec hermes "$@"
