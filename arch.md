# VAI 架构说明

本文档描述 VAI 当前架构，面向 nanobot 风格的事件驱动与分层设计，便于后续升级与扩展。

## 一、整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│  Entry (vai.v)                                                   │
│  onboard | chat | cli | web | cron list | 默认服务模式            │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│  VAIAgent                                                         │
│  config, workspace_mgr, message_bus, agent_loop,                 │
│  cron_service, heartbeat_service, gateway_mgr, llm_mgr,           │
│  skills_registry, memory_store (PersistentStore)                  │
└───┬─────────┬─────────┬─────────┬─────────┬─────────┬───────────┘
    │         │         │         │         │         │
    ▼         ▼         ▼         ▼         ▼         ▼
 config   workspace   bus      agent    cron    heartbeat
  (schema, (manager,  (events, (context, (types,  (service)
   loader)  templates) queue)   loop)    service)
    │         │         │         │         │         │
    ▼         ▼         ▼         ▼         ▼         ▼
 gateway   memory    skills    llm     protocol   sandbox
 (adapters)(store,   (registry,(openai, (message)  (exec)
            daily_   builtin,   openrouter,
            notes,   dynamic,   ollama)
            long_    markdown)
            term)
```

## 二、核心组件

### 2.1 配置 (config/)

- **schema.v**：配置结构定义（providers / agents / tools / workspace / cron），支持环境变量覆盖。
- **loader.v**：从 `~/.vai/config.json` 加载、保存与初始化配置；`config_from_env()` 与 `merge_config()` 用于环境变量合并。

首次使用需执行 **`vai onboard`**（或 `init` / `setup`），生成默认配置与工作区。

### 2.2 工作区 (workspace/)

- **manager.v**：管理 `~/.vai/workspace/` 目录结构（如 `memory/`、`skills/`），初始化时创建目录与模板。
- **templates.v**：生成默认模板文件（如 AGENTS.md、SOUL.md、USER.md、HEARTBEAT.md、TOOLS.md、memory/MEMORY.md、每日笔记等）。

### 2.3 消息总线 (bus/)

- **events.v**：事件类型（EventType）与事件结构（MessageEvent、ToolCallEvent、AgentResponseEvent、ErrorEvent 等），实现 `Event` 接口（含 `get_message()` 等）。
- **queue.v**：消息总线实现，发布/订阅、事件队列与分发循环。

网关收到消息后发布 `MessageEvent`，Agent 循环订阅并处理。

### 2.4 Agent 循环 (agent/)

- **context.v**：上下文构建器（ContextBuilder），聚合会话历史、记忆、可用工具与系统提示，输出供 LLM 使用的上下文（含 `to_llm_messages()`）。
- **loop.v**：Agent 处理循环；订阅 `message_received`，构建上下文、调用 LLM（含工具调用）、执行技能、写回记忆并发布响应事件。

与 nanobot 的 agent/loop + context 对应，形成「收消息 → 建上下文 → LLM → 工具 → 记忆」的闭环。

### 2.5 记忆 (memory/)

- **store.v / repository.v**：会话与消息存储接口及实现。
- **persistent.v**：持久化存储，基于工作区路径，集成每日笔记与长期记忆管理器。
- **daily_notes.v**：按日的 Markdown 笔记（YYYY-MM-DD.md），用于近期上下文。
- **long_term.v**：长期记忆文件（如 MEMORY.md），结构化存储与检索。
- **embeddings.v**：向量相关（可选扩展）。

### 2.6 技能 (skills/)

- **registry.v**：技能注册表，内置技能注册、动态加载、执行与权限检查；支持转换为 OpenAI 工具格式。
- **builtin.v**：内置技能（文件、Shell、HTTP、目录列表、时间等）。
- **dynamic.v**：从目录动态加载（.v / .py / .sh / .skill.json 等），.md 由 markdown 模块处理。
- **markdown.v**：带 YAML frontmatter 的 Markdown 技能加载与执行封装。

### 2.7 定时与心跳

- **cron/**：Cron 表达式解析（types.v）与定时任务调度（service.v），用于周期任务。
- **heartbeat/**：心跳服务（service.v），按间隔执行后台任务，支持主动触发。

CLI 支持 **`vai cron list`** 列出定时任务。

### 2.8 网关 (gateway/)

适配器：Telegram、WhatsApp、WhatsApp Business、Discord、DeBox 等。通过环境变量配置（如 `TELEGRAM_BOT_TOKEN`），在 `VAIAgent.init()` 中注册。

### 2.9 LLM (llm/)

多提供商（OpenAI、OpenRouter、Ollama 等），由配置与环境变量驱动，通过 LLMManager 统一接口调用。

## 三、数据流（简化）

1. **入站**：Gateway 收到消息 → 发布 `MessageEvent` 到 MessageBus。
2. **处理**：AgentLoop 订阅 `message_received` → 从事件取 Message → ContextBuilder 构建上下文 → LLM 调用（含 tool_calls）→ 执行技能 → 更新记忆 → 发布 AgentResponseEvent。
3. **出站**：响应经 Gateway 回写到对应渠道（或内部会话）。

## 四、配置与工作区路径

| 用途       | 路径                     |
|------------|--------------------------|
| 配置文件   | `~/.vai/config.json`     |
| 工作区根目录 | `~/.vai/workspace/`    |
| 长期记忆   | `workspace/memory/MEMORY.md` |
| 每日笔记   | `workspace/memory/YYYY-MM-DD.md` |
| 技能目录   | `workspace/skills/` 等  |

环境变量可覆盖部分配置（如 `VAI_DEFAULT_MODEL`、`VAI_WORKSPACE` 等），见 config/schema.v 中 `config_from_env()` 与 `merge_config()`。

## 五、命令速查

| 命令           | 说明                     |
|----------------|--------------------------|
| `vai onboard` | 初始化配置与工作区       |
| `vai chat`    | 交互式聊天               |
| `vai cli`     | CLI 控制台               |
| `vai web`     | 启动 Web UI              |
| `vai cron list` | 列出定时任务           |
| `vai`（无参数）| 默认服务模式（网关 + Agent） |

## 六、与 nanobot 的对应关系

| nanobot        | VAI                          |
|----------------|------------------------------|
| bus/events, queue | bus/events.v, queue.v     |
| agent/loop, context | agent/loop.v, context.v |
| config/schema, loader | config/schema.v, loader.v |
| cron/service, types | cron/service.v, types.v |
| 每日笔记 + 长期记忆 | memory/daily_notes.v, long_term.v |
| Markdown 技能 + frontmatter | skills/markdown.v |
| 心跳/后台任务 | heartbeat/service.v |
| channels       | gateway/ 适配器              |

## 七、后续升级建议

- 在 config schema 中增加网关相关字段（如 telegram_bot_token），与现有环境变量并存或逐步迁移。
- 完善 Agent 响应事件到网关的闭环（确保回复正确路由到发起会话的渠道）。
- 扩展 Cron/Heartbeat 与工作区模板的配置项（如默认 cron 表达式、心跳间隔）。
- 长期记忆与每日笔记的检索接口（如按关键词/向量）供 ContextBuilder 使用。
- 技能权限与沙箱策略与配置绑定，便于按环境收紧或放宽。
