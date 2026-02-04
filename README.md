# VAI (V AI Infrastructure)

VAI is a lightweight AI agent runtime and tooling suite built in **V**.

*(中文版本: [`README.zh-CN.md`](README.zh-CN.md))*

## Documentation

- **Usage (English)**: [`docs/USAGE.md`](docs/USAGE.md)
- **使用指南（中文）**: [`docs/USAGE.zh-CN.md`](docs/USAGE.zh-CN.md)

## Features

- High performance, single binary build
- Multi-provider LLM support (OpenAI, OpenRouter, Ollama, …)
- Multi-agent collaboration (hub, routing, task scheduling)
- Skills/tool execution framework
- Memory subsystem (conversation store + vector search)
- Web dashboard + REST API
- CLI console and interactive chat mode

## Quick start

### Build

```bash
# in repo root
v -prod .
./vai --help
```

### Run the web dashboard

```bash
./vai web
```

Then open `http://localhost:8080`.

### Minimal configuration

Pick **one** provider:

```bash
# OpenAI
export OPENAI_API_KEY="..."

# or OpenRouter
export OPENROUTER_API_KEY="..."
export VAI_DEFAULT_MODEL="gpt-4o-mini"  # optional

# or local Ollama
ollama serve
```

## Repository layout (high level)

```
vai/
├── agent/        # multi-agent runtime (hub/agents/coordination)
├── cli/          # CLI console
├── gateway/      # platform adapters (Telegram/Discord/WhatsApp/DeBox/…)
├── llm/          # LLM clients/providers
├── memory/       # conversation + vector storage
├── planner/      # planning strategies
├── protocol/     # message protocol
├── sandbox/      # sandbox execution (simplified)
├── scheduler/    # task scheduler
├── skills/       # builtin + dynamic skills
└── web/          # Web UI server + REST API + static dashboard
```

## Notes on current Web UI behavior

The dashboard page (`web/static/index.html`) calls `/api/agents` and `/api/status`.
At the moment, the frontend expects a `{success,data}` wrapper, while many API endpoints return plain JSON arrays/objects. See the usage guide for details and workarounds.
