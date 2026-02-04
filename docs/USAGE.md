# VAI Usage Guide (English)
*(Chinese version: [`docs/USAGE.zh-CN.md`](USAGE.zh-CN.md))*

This guide matches the current implementation (see `vai.v`, `config/`, `workspace/`, `bus/`, `agent/`, `web/`, `gateway/`, `llm/`).

## Quick start

### 1) Build

```bash
# in repo root
v -prod .
./vai --help
```

### 2) First-time setup (onboard)

Initialize configuration and workspace. This creates `~/.vai/config.json` and `~/.vai/workspace/` (including template files like AGENTS.md, SOUL.md, USER.md, memory/MEMORY.md):

```bash
./vai onboard
```

Aliases: `vai init`, `vai setup`. After this, edit `~/.vai/config.json` to add API keys and model settings.

### 3) Pick ONE LLM provider

VAI can run with different providers. For a minimal working setup, pick one (or configure in `config.json`):

- **OpenAI**

```bash
export OPENAI_API_KEY="..."
```

- **OpenRouter**

```bash
export OPENROUTER_API_KEY="..."
export VAI_DEFAULT_MODEL="gpt-4o-mini"   # optional
```

- **Local Ollama** (registered by default)

```bash
# make sure Ollama is running locally
ollama serve
```

## Run modes

The CLI entrypoint is `vai.v` and supports these modes:

### Commands summary

| Command        | Description                          |
|----------------|--------------------------------------|
| `vai onboard`  | Initialize config and workspace      |
| `vai chat`     | Interactive chat                     |
| `vai cli`      | CLI console                          |
| `vai web`      | Web UI server                        |
| `vai cron list`| List scheduled cron jobs             |
| `vai`          | Default service mode (gateways + Agent) |

### Web dashboard

```bash
./vai web
```

- **URL**: `http://localhost:8080`
- **What it starts** (current implementation): an `AgentHub`, a default agent (if a default LLM provider is available), and the Web UI server.

### CLI console

```bash
./vai cli
```

### Interactive chat

```bash
./vai chat
```

### Default service mode

```bash
./vai
```

This runs the default “service mode” defined in `VAIAgent.start()` (see `vai.v`).

## Environment variables

> Tip: you can use a `.env` file in your shell workflow, but VAI currently reads environment variables directly via `os.getenv*` (no built-in dotenv loader).

### LLM providers

- `OPENAI_API_KEY`: enable OpenAI provider
- `OPENROUTER_API_KEY`: enable OpenRouter provider
- `VAI_DEFAULT_MODEL`: default model name used by the default provider selection
- `VAI_OLLAMA_MODEL`: optional Ollama model name (if your setup uses it)

### Gateways / integrations (optional)

- `TELEGRAM_BOT_TOKEN`
- `WHATSAPP_PHONE_ID`, `WHATSAPP_TOKEN` *(WhatsApp Business)*
- `DISCORD_BOT_TOKEN`
- `DEBOX_APP_ID`, `DEBOX_APP_SECRET`

### Config file and workspace

- **Config file**: `~/.vai/config.json` (created by `vai onboard`). Structure includes `providers`, `agents.defaults`, `tools`, `workspace`, `cron`. Environment variables override where defined (e.g. `VAI_DEFAULT_MODEL`, `VAI_WORKSPACE`).
- **Workspace**: `~/.vai/workspace/` contains `memory/` (e.g. MEMORY.md, daily notes YYYY-MM-DD.md), template files, and skill directories. See `arch.md` for details.

## Web UI & REST API

The dashboard HTML is `web/static/index.html`. It calls the REST endpoints under `/api/*`.

### API endpoints

Implemented in `web/api.v`:

| Endpoint | Method | Notes |
|---|---:|---|
| `/api/health` | GET | Health check |
| `/api/agents` | GET | List agents |
| `/api/agents/:id` | GET | Get agent by id *(see note below)* |
| `/api/agents/:id/message` | POST | Send message to an agent |
| `/api/tasks` | POST | Submit a task |
| `/api/tasks/:id` | GET | Get task result *(see note below)* |
| `/api/conversations` | POST | Create conversation |
| `/api/conversations/:id/messages` | POST | Broadcast message |
| `/api/status` | GET | System status |
| `/api/stats` | GET | Stats |
| `/api/ws` | GET | Not implemented (501) |

### API response format

All `/api/*` endpoints now return a unified response format:
```json
{
  "success": true,
  "data": { ... }
}
```

On error:
```json
{
  "success": false,
  "error": "Error message",
  "code": 404
}
```

### Route parameters

Routes with parameters like `/api/agents/:id` are now fully supported. The `:id` parameter is extracted and available in handlers via `ctx.params['id']`.

## Common scenarios

### Run Web UI using OpenRouter

```bash
export OPENROUTER_API_KEY="..."
export VAI_DEFAULT_MODEL="gpt-4o-mini"
./vai web
```

### Run with local Ollama only

```bash
ollama serve
./vai web
```

## Architecture

For component overview, data flow, and config/workspace paths, see **[arch.md](../arch.md)** in the repo root.

## Troubleshooting

### Port 8080 already in use

- Stop the conflicting process or change the port in `start_web_ui()` inside `vai.v` (currently hard-coded to `8080`).

### Dashboard shows “0 agents / 0 tasks”

- Check the browser devtools Network tab for `/api/agents` and `/api/status` responses. Ensure they return `{"success":true,"data":...}` format.
- Verify that at least one agent is registered in the hub.

### No agent appears in the Web UI

- `./vai web` only registers a default agent if `llm_mgr.get_default_provider()` returns something. Ensure you set at least one API key (OpenAI/OpenRouter) or adjust the default provider selection logic.

### Authentication

When `auth_enabled=true` in WebConfig, API requests must include either:
- `Authorization: Bearer <api_key>` header, or
- `X-API-Key: <api_key>` header

Requests without valid authentication will receive a 401 Unauthorized response.

