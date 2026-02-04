# VAI Usage Guide (English)
*(Chinese version: [`docs/USAGE.zh-CN.md`](USAGE.zh-CN.md))*

This guide is written to match the current implementation in this repository (see `vai.v`, `web/`, `gateway/`, `llm/`).

## Quick start

### 1) Build

```bash
# in repo root
v -prod .
./vai --help
```

### 2) Pick ONE LLM provider

VAI can run with different providers. For a minimal working setup, pick one:

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

