# VAI 使用指南（中文）
*(English version: [`docs/USAGE.md`](USAGE.md))*

本文档以本仓库**当前实现**为准（参考 `vai.v`、`config/`、`workspace/`、`bus/`、`agent/`、`web/`、`gateway/`、`llm/`），目标是让你可以“照抄命令就能跑起来”。

## 快速开始

### 1）编译

```bash
# 在仓库根目录
v -prod .
./vai --help
```

### 2）首次使用（初始化）

执行一次初始化，会创建 `~/.vai/config.json` 和 `~/.vai/workspace/`（含 AGENTS.md、SOUL.md、USER.md、memory/MEMORY.md 等模板）：

```bash
./vai onboard
```

等价命令：`vai init`、`vai setup`。完成后编辑 `~/.vai/config.json` 填入 API Key 和模型等配置。

### 3）选择一个 LLM 提供商（三选一即可，也可在 config.json 中配置）

- **OpenAI**

```bash
export OPENAI_API_KEY="..."
```

- **OpenRouter**

```bash
export OPENROUTER_API_KEY="..."
export VAI_DEFAULT_MODEL="gpt-4o-mini"   # 可选
```

- **本地 Ollama**（默认会注册本地 provider）

```bash
# 确保本地 Ollama 已启动
ollama serve
```

## 运行模式

CLI 入口在 `vai.v`，目前支持以下模式：

### 命令一览

| 命令           | 说明                     |
|----------------|--------------------------|
| `vai onboard`  | 初始化配置与工作区       |
| `vai chat`     | 交互式聊天               |
| `vai cli`      | CLI 控制台               |
| `vai web`      | 启动 Web UI              |
| `vai cron list`| 列出定时任务             |
| `vai`（无参数）| 默认服务模式（网关 + Agent）|

### Web Dashboard

```bash
./vai web
```

- **访问地址**：`http://localhost:8080`
- **当前实现会启动**：一个 `AgentHub`、一个默认 Agent（前提是能拿到 default LLM provider）、以及 Web UI 服务。

### CLI 控制台

```bash
./vai cli
```

### 交互式聊天

```bash
./vai chat
```

### 默认服务模式

```bash
./vai
```

默认服务模式的具体行为以 `VAIAgent.start()` 为准（见 `vai.v`）。

## 环境变量

> 提示：你可以用 `.env` 辅助管理环境变量，但 VAI 目前是直接通过 `os.getenv*` 读取环境变量（没有内置 dotenv loader）。

### LLM 相关

- `OPENAI_API_KEY`：启用 OpenAI provider
- `OPENROUTER_API_KEY`：启用 OpenRouter provider
- `VAI_DEFAULT_MODEL`：默认模型名（用于默认 provider 选择/请求）
- `VAI_OLLAMA_MODEL`：可选（视你本地 Ollama 配置）

### 网关 / 平台接入（可选）

- `TELEGRAM_BOT_TOKEN`
- `WHATSAPP_PHONE_ID`、`WHATSAPP_TOKEN`
- `DISCORD_BOT_TOKEN`
- `DEBOX_APP_ID`、`DEBOX_APP_SECRET`

### 配置文件与工作区

- **配置文件**：`~/.vai/config.json`（由 `vai onboard` 创建）。结构包含 `providers`、`agents.defaults`、`tools`、`workspace`、`cron` 等。环境变量会覆盖对应项（如 `VAI_DEFAULT_MODEL`、`VAI_WORKSPACE`）。
- **工作区**：`~/.vai/workspace/` 下包含 `memory/`（如 MEMORY.md、每日笔记 YYYY-MM-DD.md）、模板文件及技能目录等。详见 `arch.md`。

## Web UI 与 REST API

Dashboard 页面是 `web/static/index.html`，会请求 `/api/*` 下的接口。

### API 列表

以 `web/api.v` 为准：

| 端点 | 方法 | 说明 |
|---|---:|---|
| `/api/health` | GET | 健康检查 |
| `/api/agents` | GET | 获取 Agent 列表 |
| `/api/agents/:id` | GET | 按 id 获取 Agent（见下方注意事项） |
| `/api/agents/:id/message` | POST | 给指定 Agent 发消息 |
| `/api/tasks` | POST | 提交任务 |
| `/api/tasks/:id` | GET | 获取任务结果（见下方注意事项） |
| `/api/conversations` | POST | 创建会话 |
| `/api/conversations/:id/messages` | POST | 广播消息 |
| `/api/status` | GET | 系统状态 |
| `/api/stats` | GET | 统计信息 |
| `/api/ws` | GET | 未实现（501） |

### API 返回格式

所有 `/api/*` 接口现在统一返回格式：
```json
{
  "success": true,
  "data": { ... }
}
```

错误时：
```json
{
  "success": false,
  "error": "错误信息",
  "code": 404
}
```

### 路由参数

带参数的路由如 `/api/agents/:id` 现已完整支持。`:id` 参数会被提取，在处理器中可通过 `ctx.params['id']` 访问。

## 常见场景

### 用 OpenRouter 跑 Web UI

```bash
export OPENROUTER_API_KEY="..."
export VAI_DEFAULT_MODEL="gpt-4o-mini"
./vai web
```

### 只用本地 Ollama 跑起来

```bash
ollama serve
./vai web
```

## 架构说明

组件概览、数据流与配置/工作区路径见仓库根目录 **[arch.md](../arch.md)**。

## 排错（Troubleshooting）

### 8080 端口被占用

- 停掉占用端口的进程，或修改 `vai.v` 里 `start_web_ui()` 的端口（当前写死为 `8080`）。

### Dashboard 显示 “0 agents / 0 tasks”

- 用浏览器开发者工具检查 `/api/agents`、`/api/status` 的响应体，确保返回 `{"success":true,"data":...}` 格式。
- 确认至少有一个 agent 已注册到 hub。

### Web UI 里没有默认 Agent

- `./vai web` 只有在 `llm_mgr.get_default_provider()` 能拿到默认 provider 时才会创建并注册默认 Agent。请确保设置了至少一个 API key（OpenAI/OpenRouter），或后续调整默认 provider 选择逻辑。

### 认证

当 WebConfig 中 `auth_enabled=true` 时，API 请求必须包含以下之一：
- `Authorization: Bearer <api_key>` 请求头，或
- `X-API-Key: <api_key>` 请求头

未携带有效认证的请求将收到 401 Unauthorized 响应。

