# VAI (V AI Infrastructure)

VAI is a lightweight AI agent runtime and tooling suite built in **V**.

*(中文版本: [`README.zh-CN.md`](README.zh-CN.md))*

## Documentation

- **Usage (English)**: [`docs/USAGE.md`](docs/USAGE.md)
- **使用指南（中文）**: [`docs/USAGE.zh-CN.md`](docs/USAGE.zh-CN.md)

## Features

- High performance, single binary build
- Multi-provider LLM support (OpenAI, OpenRouter, Ollama, …)
- Event-driven message bus and Agent loop (context → LLM → tools → memory)
- Multi-agent collaboration (hub, routing, task scheduling)
- Skills/tool execution framework (builtin, dynamic, Markdown with YAML frontmatter)
- Layered memory (conversation store, daily notes, long-term storage)
- Cron and heartbeat services for scheduled and proactive tasks
- Web dashboard + REST API
- CLI console and interactive chat mode

## Quick start

### Build

```bash
# in repo root
v -prod .
./vai --help
```

### First-time setup

Initialize configuration and workspace (creates `~/.vai/config.json` and `~/.vai/workspace/`):

```bash
./vai onboard
```

Then edit `~/.vai/config.json` to add API keys and model settings.

### Run the web dashboard

```bash
./vai web
```

Then open `http://localhost:8080`.

### Minimal configuration

Pick **one** provider (or set in `~/.vai/config.json` after `vai onboard`):

```bash
# OpenAI
export OPENAI_API_KEY="..."

# or OpenRouter
export OPENROUTER_API_KEY="..."
export VAI_DEFAULT_MODEL="gpt-4o-mini"  # optional

# or local Ollama
ollama serve
```

## Commands

| Command        | Description                    |
|----------------|--------------------------------|
| `vai onboard`  | Initialize config and workspace |
| `vai chat`     | Interactive chat mode          |
| `vai cli`      | CLI console                    |
| `vai web`      | Start Web UI server            |
| `vai cron list`| List scheduled cron jobs       |
| `vai`          | Default service mode (gateways + Agent) |

## Repository layout (high level)

```
vai/
├── agent/       # Agent loop, context builder, hub/coordination
├── bus/         # Event-driven message bus (events, queue)
├── config/      # Config schema and loader (~/.vai/config.json)
├── cron/        # Cron job types and scheduler
├── cli/         # CLI console and commands
├── gateway/     # Platform adapters (Telegram/Discord/WhatsApp/DeBox/…)
├── heartbeat/   # Heartbeat service for proactive tasks
├── llm/         # LLM clients/providers
├── memory/      # Store, persistent, daily_notes, long_term, embeddings
├── planner/     # Planning strategies
├── protocol/    # Message protocol
├── sandbox/     # Sandbox execution (simplified)
├── scheduler/   # Task scheduler
├── skills/      # Registry, builtin, dynamic, markdown skills
├── workspace/   # Workspace manager and templates (~/.vai/workspace/)
└── web/         # Web UI server + REST API + static dashboard
```

See **[arch.md](arch.md)** for architecture details and data flow.

## Notes on current Web UI behavior

The dashboard page (`web/static/index.html`) calls `/api/agents` and `/api/status`.
At the moment, the frontend expects a `{success,data}` wrapper, while many API endpoints return plain JSON arrays/objects. See the usage guide for details and workarounds.
