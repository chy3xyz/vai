# VAI（V AI Infrastructure）

VAI 是一个用 **V 语言**实现的轻量级 AI Agent 运行时与工具集。

*(English: [`README.md`](README.md))*

## 文档

- **Usage (English)**: [`docs/USAGE.md`](docs/USAGE.md)
- **使用指南（中文）**: [`docs/USAGE.zh-CN.md`](docs/USAGE.zh-CN.md)

## 特性

- 高性能、单文件二进制
- 多 LLM 提供商支持（OpenAI / OpenRouter / Ollama 等）
- 事件驱动消息总线与 Agent 循环（上下文 → LLM → 工具 → 记忆）
- 多 Agent 协作（Hub、消息路由、任务调度）
- 技能/工具执行框架（内置、动态、Markdown + YAML frontmatter）
- 分层记忆（会话存储、每日笔记、长期记忆）
- Cron 与心跳服务，支持定时与主动任务
- Web Dashboard + REST API
- CLI 控制台与交互式聊天

## 快速开始

### 编译

```bash
# 在仓库根目录
v -prod .
./vai --help
```

### 首次使用

初始化配置与工作区（会创建 `~/.vai/config.json` 和 `~/.vai/workspace/`）：

```bash
./vai onboard
```

然后编辑 `~/.vai/config.json` 添加 API Key 和模型等配置。

### 启动 Web Dashboard

```bash
./vai web
```

然后打开 `http://localhost:8080`。

### 最小配置（任选一个）

也可在执行 `vai onboard` 后，在 `~/.vai/config.json` 中配置；或使用环境变量：

```bash
# OpenAI
export OPENAI_API_KEY="..."

# 或 OpenRouter
export OPENROUTER_API_KEY="..."
export VAI_DEFAULT_MODEL="gpt-4o-mini"  # 可选

# 或本地 Ollama
ollama serve
```

## 命令一览

| 命令           | 说明                     |
|----------------|--------------------------|
| `vai onboard`  | 初始化配置与工作区       |
| `vai chat`     | 交互式聊天               |
| `vai cli`      | CLI 控制台               |
| `vai web`      | 启动 Web UI              |
| `vai cron list`| 列出定时任务             |
| `vai`（无参数）| 默认服务模式（网关 + Agent）|

## 目录结构（概览）

```
vai/
├── agent/       # Agent 循环、上下文构建、hub/协作
├── bus/         # 事件驱动消息总线（events, queue）
├── config/      # 配置结构与加载（~/.vai/config.json）
├── cron/        # 定时任务类型与调度
├── cli/         # CLI 控制台与命令
├── gateway/     # 平台适配器（Telegram/Discord/WhatsApp/DeBox/…）
├── heartbeat/   # 心跳服务（主动任务）
├── llm/         # LLM 客户端/提供商
├── memory/      # 存储、持久化、每日笔记、长期记忆、向量
├── planner/     # 规划策略
├── protocol/    # 消息协议
├── sandbox/     # 沙箱执行（简化）
├── scheduler/   # 调度器
├── skills/      # 注册表、内置/动态/Markdown 技能
├── workspace/   # 工作区管理与模板（~/.vai/workspace/）
└── web/         # Web UI + REST API + 静态 Dashboard
```

更多架构与数据流说明见 **[arch.md](arch.md)**。

## Web UI 当前行为说明

Dashboard（`web/static/index.html`）会请求 `/api/agents` 与 `/api/status`。目前前端期望 `{success,data}` 包装结构，但后端不少接口直接返回数组/对象 JSON。详见使用指南的说明与后续改进建议。

