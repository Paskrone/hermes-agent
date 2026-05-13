#!/bin/bash
# Railway-Init: Injects CEELIS-MCP + Anthropic-Provider + STT/Auxiliary settings
# into hermes config.yaml.
#
# Runs every container start as the hermes user (after docker/entrypoint.sh
# has bootstrapped defaults). Idempotent: overwrites our managed sections,
# preserves everything else the user may have set via `hermes config set`.
#
# Required ENVs:
#   CEELIS_MCP_BEARER
# Optional ENVs:
#   CEELIS_MCP_URL          (default: https://api.kundenportal.ceelis.com/functions/v1/mcp)
#   HERMES_DEFAULT_MODEL    (presence → overrides model.default in config.yaml on every boot)
#   HERMES_DELEGATION_MODEL (presence → sets delegation.model for cheap sub-agent task offload)
#   GROQ_API_KEY            (presence → STT-Provider switched to groq)
#   OPENROUTER_API_KEY      (presence → auxiliary side-tasks routed to OpenRouter/Gemini-Flash)
#   HERMES_AUX_MODEL        (default: google/gemini-2.5-flash — used for vision/web/search/titles/approval/triage)
#   HERMES_AUX_COMPRESSION_MODEL (default: google/gemini-2.5-pro — needs >= main-model context window)
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"

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

changes = []

# --- Main model — IMMER aus ENV setzen wenn vorhanden (überschreibt existing) ---
# Frühere Versionen haben hier nur ein fallback gesetzt (`if not …`), was dazu führte
# dass ein einmal in first-boot gewähltes Modell (z.B. Opus) niemals via Railway-ENV
# wieder runter-konfiguriert werden konnte. Jetzt: ENV gewinnt, jedes Boot.
config.setdefault("model", {})
if os.environ.get("HERMES_DEFAULT_MODEL"):
    config["model"]["default"] = os.environ["HERMES_DEFAULT_MODEL"]
    changes.append(f"model.default={config['model']['default']}")

# --- Delegation model — für sub-agent task offload auf günstigerem Modell ---
if os.environ.get("HERMES_DELEGATION_MODEL"):
    config.setdefault("delegation", {})
    config["delegation"]["model"] = os.environ["HERMES_DELEGATION_MODEL"]
    changes.append(f"delegation.model={config['delegation']['model']}")

# --- CEELIS-Portal-MCP (immer aus ENV neu setzen — Bearer kann rotieren) ---
if os.environ.get("CEELIS_MCP_BEARER"):
    config.setdefault("mcp_servers", {})
    config["mcp_servers"]["ceelis-portal"] = {
        "url": os.environ.get("CEELIS_MCP_URL", "https://api.kundenportal.ceelis.com/functions/v1/mcp"),
        "headers": {"Authorization": f"Bearer {os.environ['CEELIS_MCP_BEARER']}"},
        "enabled": True,
    }
    changes.append("mcp_servers.ceelis-portal")
else:
    print("[railway-init] CEELIS_MCP_BEARER missing — skipping MCP injection.")

# --- STT: switch to groq if API-Key present (Default 'local' needs faster-whisper, not installed) ---
if os.environ.get("GROQ_API_KEY"):
    config.setdefault("stt", {})
    config["stt"]["enabled"] = True
    config["stt"]["provider"] = "groq"
    changes.append("stt.provider=groq")

# --- Auxiliary models: route side-tasks to OpenRouter/Gemini-Flash if key present ---
# Side-tasks (vision, web_extract, session_search, title_generation, compression,
# approval, triage_specifier) default to the main chat model — expensive on
# Sonnet/Opus. Re-route them to a cheap fast model via OpenRouter.
if os.environ.get("OPENROUTER_API_KEY"):
    aux_model = os.environ.get("HERMES_AUX_MODEL", "google/gemini-2.5-flash")
    aux_compression_model = os.environ.get("HERMES_AUX_COMPRESSION_MODEL", "google/gemini-2.5-pro")
    config.setdefault("auxiliary", {})
    for task in ("vision", "web_extract", "session_search", "title_generation", "approval", "triage_specifier"):
        config["auxiliary"][task] = {"provider": "openrouter", "model": aux_model}
    # Compression needs context window >= main model; use Gemini 2.5 Pro (2M context) by default.
    config["auxiliary"]["compression"] = {"provider": "openrouter", "model": aux_compression_model}
    changes.append(f"auxiliary.*=openrouter/{aux_model} (compression={aux_compression_model})")

path.write_text(yaml.safe_dump(config, sort_keys=False, default_flow_style=False))
print(f"[railway-init] config.yaml updated at {path}: {', '.join(changes) if changes else 'no changes'}")
PYEOF

# Final: execute hermes with the args we were called with
exec hermes "$@"
