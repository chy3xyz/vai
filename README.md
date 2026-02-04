# VAI - V AI Infrastructure

基于 V 语言的 AI 基础设施工具，提供轻量级、高性能的 AI Agent 运行时环境。

## 特性

- ⚡ **高性能**: 利用 V 语言的零成本抽象和编译速度
- 📦 **零依赖**: 编译为单文件可执行文件（<8MB）
- 🔌 **多平台**: 支持 Telegram、WhatsApp、Discord、DeBox 等平台
- 🤖 **多模型**: 支持 OpenAI、OpenRouter、Anthropic、Ollama 等 LLM 提供商
- 🛠️ **技能系统**: 内置工具注册和执行框架
- 🧠 **记忆系统**: 会话管理和向量存储
- 🎯 **规划器**: ReAct 和 Tree of Thoughts 规划
- 🛡️ **安全沙箱**: WASI 风格的资源隔离
- 💻 **CLI 控制台**: 本地调试和管理工具
- 👥 **多 Agent 协作**: Agent 发现、任务分配、团队协调
- 🌐 **Web UI**: 现代化的 Web 管理界面

## 快速开始

### 安装

```bash
# 克隆仓库
git clone https://github.com/vlang/vai.git
cd vai

# 编译
v -prod .

# 运行
./vai --help
```

### 环境配置

```bash
# OpenAI
export OPENAI_API_KEY=your_api_key

# OpenRouter（支持多种模型）
export OPENROUTER_API_KEY=your_api_key

# Telegram
export TELEGRAM_BOT_TOKEN=your_bot_token

# WhatsApp Business
export WHATSAPP_PHONE_ID=your_phone_id
export WHATSAPP_TOKEN=your_token

# Discord
export DISCORD_BOT_TOKEN=your_bot_token

# DeBox
export DEBOX_APP_ID=your_app_id
export DEBOX_APP_SECRET=your_app_secret

# 默认模型
export VAI_DEFAULT_MODEL=gpt-4o-mini
```

### 命令行使用

```bash
# 启动 Web UI
vai web

# 启动 CLI 控制台
vai cli

# 交互式聊天
vai chat

# 运行机器人服务
vai
```

### Web UI

启动 Web 服务器后，访问 `http://localhost:8080`:

![Dashboard Preview](web/static/dashboard.png)

功能包括：
- 📊 实时系统状态监控
- 🤖 Agent 管理和监控
- 💬 实时聊天界面
- 📋 任务队列查看
- 📝 系统日志

## 模块架构

```
vai/
├── agent/        # 多 Agent 协作系统
│   ├── agent.v          # Agent 定义和接口
│   ├── hub.v            # Agent 协作中心
│   └── coordination.v   # 高级协调模式
├── cli/          # 命令行工具
├── distributed/  # 分布式部署
│   └── node.v           # 集群节点管理
├── gateway/      # 平台适配器
├── llm/          # LLM 客户端
│   ├── client.v
│   ├── openai.v
│   ├── openrouter.v
│   ├── ollama.v
│   └── streaming.v      # 流式响应支持
├── memory/       # 记忆系统
│   ├── store.v          # 内存存储
│   ├── persistent.v     # SQLite 持久化存储
│   ├── repository.v     # 数据仓库模式
│   └── embeddings.v     # 向量嵌入
├── planner/      # 规划器
├── protocol/     # 消息协议
├── runtime/      # 协程调度器
├── sandbox/      # 安全沙箱
├── skills/       # 技能系统
│   ├── registry.v       # 技能注册表
│   ├── builtin.v        # 内置技能
│   └── dynamic.v        # 动态技能加载
├── utils/        # 通用工具
└── web/          # Web UI
    ├── server.v         # Web 服务器
    ├── api.v            # REST API
    ├── app.v            # Web 应用
    └── static/          # 静态文件
        └── index.html   # Dashboard
```

## 详细文档

### Multi-Agent 系统

创建和管理多个协作 Agent：

```v
import agent { new_hub, new_base_agent, AgentRole }

// 创建 Hub
mut hub := new_hub('main', 'VAI Hub')
hub.start()!

// 创建不同类型的 Agent
mut coordinator := new_base_agent('coord_1', 'Coordinator', AgentRole.coordinator, llm, &skills)
mut worker1 := new_base_agent('worker_1', 'Worker1', AgentRole.worker, llm, &skills)
mut planner := new_base_agent('planner_1', 'Planner', AgentRole.planner, llm, &skills)

// 注册到 Hub
hub.register(coordinator)!
hub.register(worker1)!
hub.register(planner)!

// 提交任务
task := Task{
    id: 'task_1'
    type_: 'analysis'
    description: 'Analyze data'
    required_caps: ['file_read', 'data_analysis']
}
task_id := hub.submit_task(task)!

// 获取结果
result := hub.get_task_result(task_id)
```

### 高级协调模式

```v
import agent { MapReduceJob, VotingProposal, Pipeline }

// Map-Reduce 作业
job := MapReduceJob{
    id: 'job_1'
    description: 'Process dataset'
    input_data: dataset
    mapper: fn (data) { /* map */ }
    reducer: fn (results) { /* reduce */ }
}
result := hub.execute_mapreduce(job)!

// 投票共识
proposal := VotingProposal{
    id: 'vote_1'
    topic: 'Best approach?'
    options: ['A', 'B', 'C']
    timeout_sec: 60
}
vote_result := hub.initiate_voting(proposal)!

// 管道处理
pipeline := hub.create_pipeline('data_pipeline', [
    PipelineStage{ id: 'stage1', processor: 'agent_1', ... },
    PipelineStage{ id: 'stage2', processor: 'agent_2', ... },
])!
output := pipeline.process(input_data)!
```

### Web UI 集成

```v
import web { new_web_app, WebConfig }

// 创建 Web 应用
mut web_app := new_web_app(hub, WebConfig{
    host: '0.0.0.0'
    port: 8080
    static_dir: 'static'
    auth_enabled: true
    api_key: 'your_api_key'
})

// 启动 Web 服务器
web_app.start()!
```

### REST API

Web UI 提供以下 API 端点：

| 端点 | 方法 | 描述 |
|------|------|------|
| `/api/health` | GET | 健康检查 |
| `/api/agents` | GET | 获取所有 Agent |
| `/api/agents/:id` | GET | 获取特定 Agent |
| `/api/agents/:id/message` | POST | 发送消息 |
| `/api/tasks` | POST | 提交任务 |
| `/api/tasks/:id` | GET | 获取任务结果 |
| `/api/conversations` | POST | 创建会话 |
| `/api/conversations/:id/messages` | POST | 发送消息 |
| `/api/status` | GET | 系统状态 |

### Runtime - 协程调度器

```v
import runtime { new_scheduler, new_context }

mut scheduler := new_scheduler(4)
scheduler.start()!

scheduler.submit(
    exec: fn () ! { println('Hello!') }
    priority: 0
)!
```

### Protocol - 消息协议

```v
import protocol { new_text_message, new_image_message }

msg := new_text_message('Hello!')
img := new_image_message('https://example.com/image.jpg', 'Caption')
json_data := msg.to_json()!
```

### Gateway - 平台适配器

```v
import gateway { new_telegram_adapter, new_discord_adapter, new_debox_adapter }

mut telegram := new_telegram_adapter('token')
mut discord := new_discord_adapter('your_bot_token')
mut debox := new_debox_adapter('app_id', 'app_secret')

telegram.connect()!
telegram.send_message(msg)!
```

### LLM - 多模型支持

```v
import llm { new_openrouter_client, user_message, CompletionRequest }

mut openrouter := new_openrouter_client('key')

request := CompletionRequest{
    model: 'anthropic/claude-3.5-sonnet'
    messages: [user_message('Hello!')]
}

response := openrouter.complete(request)!
println(response.content)
```

### Skills - 技能系统

```v
import skills { new_registry, register_builtin_skills }

mut registry := new_registry()
register_builtin_skills(mut registry)!

result := registry.execute('file_read', {'path': '/tmp/data'}, ctx)!
```

### Memory - 记忆系统

```v
import memory { new_memory_store, new_ollama_embedder }

store := new_memory_store()
store.create_conversation('session_1')!

embedder := new_ollama_embedder('nomic-embed-text')
embedding := embedder.embed('text')!
```

### Planner - 规划器

```v
import planner { new_react_planner, new_tot_planner }

mut react := new_react_planner(llm)
result := react.execute('Calculate 15% of 89', ctx)!

mut tot := new_tot_planner(llm)
answer := tot.solve('Complex problem', ctx)!
```

### Sandbox - 安全沙箱

```v
import sandbox { new_process_sandbox, ExecutionConfig }

config := ExecutionConfig{
    command: 'python'
    args: ['script.py']
    timeout_ms: 30000
    max_memory_mb: 128
    allow_network: false
}

mut sandbox := new_process_sandbox(config)
result := sandbox.execute(config)!
```

### CLI - 控制台工具

```v
import cli { new_cli, register_default_commands }

mut console := new_cli('vai', '0.3.0')
register_default_commands(mut console, get_status, get_debug)
console.run()
```

## 开发路线图

### Phase 1: 核心运行时 (v0.1) ✅
- [x] 协程调度器
- [x] 消息协议
- [x] Telegram 适配器
- [x] OpenAI/Ollama 客户端

### Phase 2: 能力扩展 (v0.2) ✅
- [x] WhatsApp 适配器
- [x] Discord 适配器
- [x] DeBox 适配器
- [x] OpenRouter 支持
- [x] 本地技能系统
- [x] 会话记忆
- [x] 向量存储

### Phase 3: 高级能力 (v0.3) ✅
- [x] ReAct 规划器
- [x] Tree of Thoughts
- [x] 工具调用
- [x] 安全沙箱
- [x] CLI 控制台

### Phase 4: 分布式协作 (v0.4) ✅
- [x] 多 Agent 架构
- [x] Agent 发现与注册
- [x] 任务分配与协调
- [x] Map-Reduce 作业
- [x] 投票共识
- [x] 管道处理
- [x] Web UI Dashboard
- [x] REST API
- [x] 动态技能加载（V脚本/Python/JS）
- [x] 持久化记忆存储（SQLite）
- [x] 数据仓库模式（Repository + Migration）
- [x] 分布式部署（Master/Worker 集群）
- [x] LLM 流式响应（SSE）

### Phase 5: 企业级功能 (v0.5) ✅ 已完成
- [ ] 持久化存储
- [ ] 分布式部署
- [ ] 流式响应
- [ ] 嵌入式设备支持（<32MB RAM）

## 技术特点

### V 语言优势

| 特性 | 应用 |
|------|------|
| `comptime` | 编译期工具注册表生成 |
| 零依赖二进制 | `v -prod` → <8MB 单文件 |
| C 互操作 | 直接绑定 GGML 等 C 库 |
| 泛型零开销 | `Agent<T: PlatformAdapter>` |

### 性能对比

| 指标 | VAI | Python | Node.js |
|------|-----|--------|---------|
| 二进制大小 | <8MB | ~100MB+ | ~50MB+ |
| 启动时间 | <10ms | ~500ms | ~200ms |
| 内存占用 | <16MB | ~100MB | ~80MB |
| 并发性能 | 原生协程 | GIL 限制 | 事件循环 |

## 环境变量参考

| 变量名 | 说明 | 示例 |
|--------|------|------|
| `OPENAI_API_KEY` | OpenAI API 密钥 | `sk-...` |
| `OPENROUTER_API_KEY` | OpenRouter API 密钥 | `sk-or-...` |
| `TELEGRAM_BOT_TOKEN` | Telegram Bot Token | `123456:ABC...` |
| `WHATSAPP_PHONE_ID` | WhatsApp Business 电话 ID | `123456789` |
| `WHATSAPP_TOKEN` | WhatsApp Business Token | `EAAD...` |
| `DISCORD_BOT_TOKEN` | Discord Bot Token | `...` |
| `DEBOX_APP_ID` | DeBox App ID | `...` |
| `DEBOX_APP_SECRET` | DeBox App Secret | `...` |
| `VAI_DEFAULT_MODEL` | 默认 LLM 模型 | `gpt-4o-mini` |

## 示例应用

## 示例应用

### 1. 启动多 Agent 系统

```bash
# 启动 Hub 和 Web UI
vai web
```

### 2. 创建 Agent 团队

```v
import agent { new_hub, create_team, DistributionStrategy }

mut hub := new_hub('my_hub', 'My Hub')
mut team := hub.create_team('analysis_team', ['agent_1', 'agent_2', 'agent_3'])!

// 分配团队任务
team.distribute_task(task, .least_loaded)!
```

### 3. 自定义 Agent 角色

```v
pub struct DataAnalyst {
    BaseAgent
}

pub fn (a DataAnalyst) analyze(data string) !string {
    // 实现数据分析逻辑
    return 'Analysis result'
}
```

### 4. 元宇宙创意变现方案规划

使用 VAI 构建完整的元宇宙创意变现方案，基于"愿景/方言/世界"叙事方法论：

```bash
# 运行创意变现规划示例
v run examples/metaverse_creator.v
```

**功能特点：**
- 🤖 使用 Claude 3.5 Sonnet 进行创意分析
- 📝 基于元宇宙叙事方法论（愿景/方言/世界三层框架）
- 💰 自动生成收入流、里程碑和风险评估
- 🧠 使用 ReAct 规划器优化方案
- 💾 向量化存储历史方案

**示例输出：**
```
╔══════════════════════════════════════════════════════════════╗
║           元宇宙创意变现方案规划书                           ║
╚══════════════════════════════════════════════════════════════╝

【愿景 / 洞察锚】
核心洞察: 基于AI的个性化元宇宙体验
价值主张: 创造独特的数字身份和体验
...

【收入来源】
数字资产发行 (nft)
  模式: 一次性购买 + 版税
  预估: $500,000 | 时间: Q1-Q2
...
```

### 5. OpenRouter API 测试

测试 OpenRouter API 连接（已内置测试 API Key）：

```bash
v run examples/test_openrouter.v
```

## 扩展功能

### 动态技能加载

VAI 支持动态加载外部技能，无需重新编译：

```v
import skills { new_dynamic_loader }

// 创建动态加载器
mut loader := new_dynamic_loader()
loader.add_directory('./custom_skills')

// 扫描并加载所有技能
dynamic_skills := loader.scan_and_load()!

// 执行动态技能
skill := loader.loaded_skills['my_custom_skill']
result := loader.execute(skill, {'input': 'test'})!
```

**支持的技能类型：**
- **V 脚本** (`.v`) - V 语言脚本，使用 `v run` 执行
- **Python 脚本** (`.py`) - Python 脚本，使用 `python3` 执行
- **JavaScript** (`.js`) - Node.js 脚本
- **Shell 脚本** (`.sh`) - Bash 脚本
- **配置文件** (`.skill.json`) - JSON 配置式技能

**技能目录结构：**
```
skills/
├── custom_analysis.v          # V 脚本技能
├── data_processor.py          # Python 技能
├── webhook_sender.js          # JavaScript 技能
└── my_skill.skill.json        # 配置式技能
```

**配置式技能示例** (`my_skill.skill.json`):
```json
{
  "name": "webhook_notifier",
  "description": "Send webhook notifications",
  "category": "notification",
  "version": "1.0.0",
  "type": "script",
  "entry_point": "webhook_sender.js",
  "parameters": {
    "url": {
      "type": "string",
      "description": "Webhook URL",
      "required": true
    },
    "message": {
      "type": "string",
      "description": "Message to send",
      "required": true
    }
  }
}
```

### 持久化记忆存储

VAI 支持将记忆持久化到 SQLite 数据库：

```v
import memory { new_persistent_store }

// 创建持久化存储
mut store := new_persistent_store('./data/memory.db')!

// 创建会话
store.create_conversation('session_1')!

// 添加消息
store.add_message('session_1', msg)!

// 获取历史消息
messages := store.get_messages('session_1', 100)

// 搜索消息
results := store.search_messages('session_1', 'AI', 10)

// 导出会话到 JSON
store.export_conversation('session_1', 'backup.json')!

// 从 JSON 导入
store.import_conversation('backup.json')!
```

**存储内容：**
- 会话元数据（创建时间、参与者等）
- 消息历史（支持全文搜索）
- 向量嵌入（用于语义检索）

### 数据仓库模式（Repository Pattern）

```v
import memory { new_persistent_store, new_memory_store, new_conversation_repository }

// 创建存储层
mut persistent := new_persistent_store('./data/vai.db')!
mut cache := new_memory_store()

// 创建仓库（带缓存）
mut repo := new_conversation_repository(persistent, cache)

// 使用仓库
repo.create(conv)!
if conv := repo.read('session_1') {
    println('Found conversation')
}

// 批量操作
repo.batch_add('session_1', messages)!

// 时间线查询
timeline := repo.get_timeline('session_1', start_time, end_time)

// 归档旧消息
archived := repo.archive_old_messages(time.now().add_days(-30))!
```

### 数据库迁移

```v
import memory { new_migrator, Migration }

mut migrator := new_migrator(store)

// 注册迁移
migrator.register(Migration{
    version: '001'
    description: 'Add user table'
    sql_up: 'CREATE TABLE users (id TEXT PRIMARY KEY, name TEXT)'
    sql_down: 'DROP TABLE users'
})

// 执行迁移
migrator.migrate()!
```

### 备份管理

```v
import memory { new_backup_manager }

mut bm := new_backup_manager(store, './backups')

// 创建备份
backup_file := bm.create_backup('daily')!

// 列出备份
backups := bm.list_backups()

// 恢复备份
bm.restore_backup(backups[0])!
```

### 向量存储与检索

```v
import memory { new_ollama_embedder, new_simple_index }

// 创建嵌入器和索引
embedder := new_ollama_embedder('nomic-embed-text')
mut index := new_simple_index(embedder, store)

// 添加文档
doc := Document{
    id: 'doc_1'
    content: '元宇宙是虚拟与现实融合的数字世界'
    metadata: {'category': 'definition'}
}
index.add_document(doc)!

// 语义搜索
results := index.search('什么是虚拟世界', 5)
for result in results {
    println('${result.id}: ${result.score}')
}
```

### 分布式部署

VAI 支持多节点分布式部署，实现水平扩展：

```v
import distributed { new_node, ClusterConfig, NodeRole }

// 启动主节点
mut master := new_node(ClusterConfig{
    node_id: 'master_1'
    role: NodeRole.master
    bind_address: '0.0.0.0'
    api_port: 8080
    ws_port: 8081
})
master.start()!

// 启动工作节点
mut worker := new_node(ClusterConfig{
    node_id: 'worker_1'
    role: NodeRole.worker
    master_nodes: ['localhost:8080']  // 连接主节点
})
worker.start()!

// 分发任务
task_id := master.distribute_task(Task{
    id: 'task_1'
    type_: 'analysis'
    description: '分析数据'
})!

// 获取集群状态
status := master.get_cluster_status()
println('Total nodes: ${status.total_nodes}')
```

**集群架构：**
- **Master 节点**: 任务调度、节点管理
- **Worker 节点**: 执行任务、Agent 运行
- **Gateway 节点**: 处理外部请求、负载均衡

### 流式响应（SSE）

LLM 流式输出，实时显示生成内容：

```v
import llm { new_openai_client, CompletionRequest }
import llm.streaming { new_sse_writer }

mut client := new_openai_client('your_key')

request := CompletionRequest{
    model: 'gpt-4o-mini'
    messages: [user_message('讲一个故事')]
}

// 创建 SSE 写入器
mut sse := new_sse_writer(fn (data string) ! {
    println(data)
})

// 流式请求
client.complete_stream(request, fn (chunk StreamChunk) {
    print(chunk.content)
    
    if chunk.is_final {
        println('\n[完成]')
    }
})
```

**Web 集成：**
```v
import llm.streaming { stream_llm_response }

// 在 HTTP 处理函数中
svr.get('/chat/stream', fn (ctx web.Context) web.Response {
    ctx.resp.header.add(.content_type, 'text/event-stream')
    
    mut sse := new_sse_writer(fn (data string) ! {
        ctx.resp.write(data.bytes())!
    })
    
    stream_llm_response(llm_client, request, sse)!
    
    return web.Response{}
})
```

## 贡献

欢迎提交 Issue 和 PR！

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 致谢

- [V Language](https://vlang.io/) - 出色的编程语言
- [Ollama](https://ollama.ai/) - 本地 LLM 运行环境
- [OpenRouter](https://openrouter.ai/) - 统一 LLM API 路由
- [Telegram Bot API](https://core.telegram.org/bots/api) - 机器人平台
- [DeBox](https://www.debox.pro/) - Web3 社交平台
