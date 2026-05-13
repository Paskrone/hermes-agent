# Railway-Deploy für Hermes-Agent

Dieser Fork wird auf [Railway](https://railway.com) im Service `hermes` deployed (Project `charismatic-energy`/production).

## Was dieses Verzeichnis enthält

- `init.sh` — Wird vor `gateway run` ausgeführt. Templated `${HERMES_HOME}/config.yaml` aus ENVs (CEELIS-MCP-Server-Eintrag). Idempotent — kann bei jedem Start laufen.

## Required ENV-Vars

| Name | Zweck |
|---|---|
| `ANTHROPIC_API_KEY` | Claude-API (Provider in config.yaml steht auf anthropic) |
| `TELEGRAM_BOT_TOKEN` | BotFather-Token |
| `TELEGRAM_ALLOWED_USERS` | Comma-separated User-IDs |
| `CEELIS_MCP_BEARER` | Bearer für CEELIS-MCP-Server |
| `GITHUB_TOKEN` | Atlas-PAT für gh-Tools (read+write auf launchpad + vault) |

## Optional

| Name | Default |
|---|---|
| `CEELIS_MCP_URL` | `https://api.kundenportal.ceelis.com/functions/v1/mcp` |
| `HERMES_DEFAULT_MODEL` | unset — wenn gesetzt: überschreibt `model.default` in `/opt/data/config.yaml` bei jedem Boot. Aktuell: `anthropic/claude-sonnet-4` |
| `HERMES_DELEGATION_MODEL` | unset — wenn gesetzt: `delegation.model` für sub-agent task offload. Aktuell: `deepseek/deepseek-chat-v3-0324` |
| `HERMES_DASHBOARD` | unset (1 = expose dashboard auf 0.0.0.0:9119) |
| `GROQ_API_KEY` | unset — wenn gesetzt: STT-Provider auf `groq` (Whisper) |
| `OPENROUTER_API_KEY` | unset — wenn gesetzt: Auxiliary-Tasks (vision/web/search/title/approval/triage/compression) auf OpenRouter/Gemini-Flash umgeleitet (~50-70% Cost-Reduction) |
| `HERMES_AUX_MODEL` | `google/gemini-2.5-flash` — Modell für die meisten Auxiliary-Tasks |
| `HERMES_AUX_COMPRESSION_MODEL` | `google/gemini-2.5-pro` — Compression braucht Context-Window ≥ Main-Model |

## Volume

Railway-Volume an `/opt/data` mounten (Hermes' `HERMES_HOME`). Größe ~2GB. Persistiert sessions, memories, skills, config.yaml.

## Upstream-Sync

```bash
git fetch upstream
git checkout railway-deploy
git merge upstream/main
# Conflict-Resolution typisch nur in Dockerfile (unsere extra-Steps am Ende)
git push origin railway-deploy
```
