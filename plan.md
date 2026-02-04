深度参考 nanobot的架构，阅读核心原理 https://zread.ai/HKUDS/nanobot，给出对vai的重构方案，方案要点编写到 arch.md 文件中，并考虑下一版本的升级

部分总结
# vai onboard
此命令将执行以下任务：

1.创建配置文件：根据 schema.v 中的默认设置在 ~/.vai/config.json 创建配置文件
2.创建工作区目录：在 ~/.vai/workspace/ 创建用于 Agent 上下文的工作目录

3.生成模板文件：
AGENTS.md - Agent 指令和指南
SOUL.md - Agent 个性与价值观
USER.md - 用户偏好（可自定义）
memory/MEMORY.md - 长期记忆存储

# 编辑 ~/.vai/config.json 添加你的 LLM 提供商凭证：

{
  "providers": {
    "openrouter": {
      "apiKey": "sk-or-v1-xxx"
    }
  },
  "agents": {
    "defaults": {
      "model": "anthropic/claude-opus-4-5"
    }
  },
  "tools": {
    "web": {
      "search": {
        "apiKey": "BSA-xxx"
      }
    }
  }
}


# 命令
vai onboard	初始化配置和工作区
vai agent -m "message"	发送消息给 Agent
vai status	检查设置状态
vai channels status	查看渠道连接状态
vai cron list	列出定时任务



# 参考 nanobot 功能
能力	描述
Agent 循环引擎	核心处理引擎，负责接收消息，结合历史记录/记忆/技能构建上下文，调用 LLM，执行工具，并将响应发回
多渠道支持**	内置对 Telegram 和 WhatsApp 的支持，设置简单；提供可扩展的渠道接口以添加新平台
工具系统	动态工具注册表，包含用于文件操作、Shell 命令、Web 搜索/获取、消息处理和生成 Subagent 的内置工具
记忆系统	具有每日笔记和长期存储的持久化记忆，使 Agent 能够跨会话记住重要信息
技能框架	可扩展的技能系统，允许通过带有 YAML frontmatter 的简单 Markdown 文件添加新功能
定时任务	Cron 服务，用于在特定时间或间隔运行作业，非常适合提醒和周期性任务
主动心跳	可以在无需用户输入的情况下触发任务的后台服务，从而实现自主行为
多 LLM 提供商	通过统一接口支持 Anthropic、OpenAI、OpenRouter、Groq、Zhipu、vLLM 和 Gemini

# nano仓库
nanobot/
├── agent/              │   ├── loop.py         # Agent processing engine
│   ├── context.py      # Context and prompt building
│   ├── memory.py       # Persistent memory store
│   ├── skills.py       # Skill loader and manager
│   ├── subagent.py     # Background task execution
│   └── tools/          # Built-in tool implementations
├── bus/                # Event-driven message system
│   ├── events.py       # Message event types
│   └── queue.py        # Message bus implementation
├── channels/           # Chat platform integrations
│   ├── base.py         # Abstract channel interface
│   ├── manager.py      # Channel coordination
│   ├── telegram.py     # Telegram implementation
│   └── whatsapp.py     # WhatsApp implementation
├── config/             # Configuration management
│   ├── schema.py       # Pydantic config models
│   └── loader.py       # Config file loading
├── cron/               # Scheduled task system
│   ├── service.py      # Job scheduler
│   └── types.py        # Job type definitions
├── heartbeat/          # Proactive task service
│   └── service.py      # Heartbeat implementation
├── providers/          # LLM provider integrations
│   ├── base.py         # Abstract provider interface
│   └── litellm_provider.py  # Unified LLM interface
├── session/            # Session management
│   └── manager.py      # Session state handling
├── skills/             # Built-in skills
│   ├── github/         # GitHub integration
│   ├── weather/        # Weather information
│   ├── summarize/      # Content summarization
│   └── tmux/           # Terminal multiplexing
└── cli/                # Command-line interface
    └── commands.py     # CLI command definitions

bridge/                # WhatsApp bridge server (TypeScript)
workspace/             # User workspace and configuration
├── AGENTS.md          # Agent instructions
├── SOUL.md            # Personality and behavior
├── HEARTBEAT.md       # Proactive tasks
├── TOOLS.md           # Tool descriptions
├── USER.md            # User preferences
└── memory/            # Persistent memory files


# 存储结构
内存系统在工作区内以分层目录结构组织数据，不同类型的信息之间有清晰的分隔：
存储类型	文件位置	用途	持久性
长期记忆	workspace/memory/MEMORY.md	核心知识库	永久
每日笔记	workspace/memory/YYYY-MM-DD.md	临时日志和观察记录	默认 7 天
最近记忆	从每日文件聚合而来	用于对话的最近上下文	可配置


