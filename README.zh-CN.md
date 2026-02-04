# VAI（V AI Infrastructure）

VAI 是一个用 **V 语言**实现的轻量级 AI Agent 运行时与工具集。

*(English: [`README.md`](README.md))*

## 文档

- **Usage (English)**: [`docs/USAGE.md`](docs/USAGE.md)
- **使用指南（中文）**: [`docs/USAGE.zh-CN.md`](docs/USAGE.zh-CN.md)

## 特性

- 高性能、单文件二进制
- 多 LLM 提供商支持（OpenAI / OpenRouter / Ollama 等）
- 多 Agent 协作（Hub、消息路由、任务调度）
- 技能/工具执行框架
- 记忆系统（会话存储 + 向量检索）
- Web Dashboard + REST API
- CLI 控制台与交互式聊天

## 快速开始

### 编译

```bash
# 在仓库根目录
v -prod .
./vai --help
```

### 启动 Web Dashboard

```bash
./vai web
```

然后打开 `http://localhost:8080`。

### 最小配置（任选一个）

```bash
# OpenAI
export OPENAI_API_KEY="..."

# 或 OpenRouter
export OPENROUTER_API_KEY="..."
export VAI_DEFAULT_MODEL="gpt-4o-mini"  # 可选

# 或本地 Ollama
ollama serve
```

## 目录结构（概览）

```
vai/
├── agent/        # 多 Agent 运行时（hub/agents/coordination）
├── cli/          # CLI 控制台
├── gateway/      # 平台适配器（Telegram/Discord/WhatsApp/DeBox/…）
├── llm/          # LLM 客户端/提供商
├── memory/       # 会话 + 向量存储
├── planner/      # 规划策略
├── protocol/     # 消息协议
├── sandbox/      # 沙箱执行（简化）
├── scheduler/    # 调度器
├── skills/       # 内置/动态技能
└── web/          # Web UI + REST API + 静态 Dashboard
```

## Web UI 当前行为说明

Dashboard（`web/static/index.html`）会请求 `/api/agents` 与 `/api/status`。目前前端期望 `{success,data}` 包装结构，但后端不少接口直接返回数组/对象 JSON。详见使用指南的说明与后续改进建议。

