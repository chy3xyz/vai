// vai - V AI Infrastructure
// AI 基础设施工具主模块
module main

import scheduler { Scheduler, new_scheduler }
import protocol { Message, Conversation, new_text_message }
import gateway {
	GatewayManager, new_gateway_manager,
	new_telegram_adapter, new_whatsapp_adapter, new_whatsapp_business_adapter,
	new_discord_adapter, new_debox_adapter
}
import llm {
	LLMManager, new_llm_manager,
	new_openai_client, new_ollama_client, new_openrouter_client,
	user_message, system_message, CompletionRequest
}
import skills { Registry, new_registry, register_builtin_skills, Value, SkillContext }
import memory { MemoryStore, new_memory_store, new_ollama_embedder, new_simple_index }
import planner as _
import sandbox { SandboxManager, new_sandbox_manager }
import cli { new_cli, register_default_commands, StatusInfo }
import agent { AgentHub, new_hub, BaseAgent, new_base_agent, AgentRole }
import web { new_web_app, WebConfig }
import utils
import os
import time
import json

// VAIAgent 主 Agent 结构体
pub struct VAIAgent {
	pub mut:
		name           string
		version        string
		scheduler      &Scheduler
		gateway_mgr    GatewayManager
		llm_mgr        LLMManager
		skills_registry Registry
		memory_store   MemoryStore
		sandbox_mgr    SandboxManager
		conversations  map[string]Conversation
		running        bool
		config         AgentConfig
		// 统计
		start_time     time.Time
		messages_processed int
}

// AgentConfig Agent 配置
pub struct AgentConfig {
	pub mut:
		openai_api_key       string
		openrouter_api_key   string
		telegram_bot_token   string
		whatsapp_session_id  string
		whatsapp_phone_id    string
		whatsapp_token       string
		discord_bot_token    string
		debox_app_id         string
		debox_app_secret     string
		default_model        string = 'gpt-4o-mini'
		ollama_model         string = 'llama3.2'
		workers              int = 4
		system_prompt        string = 'You are a helpful AI assistant.'
		working_dir          string = '.'
}

// 创建新的 VAI Agent
pub fn new_agent(config AgentConfig) &VAIAgent {
	return &VAIAgent{
		name: 'vai'
		version: '0.2.0'
		scheduler: new_scheduler(config.workers)
		gateway_mgr: new_gateway_manager()
		llm_mgr: new_llm_manager()
		skills_registry: new_registry()
		memory_store: new_memory_store()
		sandbox_mgr: new_sandbox_manager()
		conversations: map[string]Conversation{}
		running: false
		config: config
		start_time: time.now()
		messages_processed: 0
	}
}

// 初始化 Agent
pub fn (mut vai_agent VAIAgent) init() ! {
	println(term_cyan('Initializing VAI Agent v${vai_agent.version}...'))

	// 启动调度器
	vai_agent.scheduler.start()!
	println(term_green('✓ Scheduler started'))

	// 注册 LLM 提供商
	if vai_agent.config.openai_api_key.len > 0 {
		mut openai := new_openai_client(vai_agent.config.openai_api_key)
		vai_agent.llm_mgr.register('openai', openai)
		println(term_green('✓ Registered OpenAI provider'))
	}

	// 注册 OpenRouter
	if vai_agent.config.openrouter_api_key.len > 0 {
		mut openrouter := new_openrouter_client(vai_agent.config.openrouter_api_key)
		vai_agent.llm_mgr.register('openrouter', openrouter)
		println(term_green('✓ Registered OpenRouter provider'))
	}

	// 尝试连接本地 Ollama
	mut ollama := new_ollama_client()
	vai_agent.llm_mgr.register('ollama', ollama)
	println(term_green('✓ Registered Ollama provider (local)'))

	// 注册网关适配器
	if vai_agent.config.telegram_bot_token.len > 0 {
		mut telegram := new_telegram_adapter(vai_agent.config.telegram_bot_token)
		vai_agent.gateway_mgr.register(telegram)
		println(term_green('✓ Registered Telegram adapter'))
	}

	if vai_agent.config.whatsapp_session_id.len > 0 {
		mut whatsapp := new_whatsapp_adapter(vai_agent.config.whatsapp_session_id)
		vai_agent.gateway_mgr.register(whatsapp)
		println(term_green('✓ Registered WhatsApp adapter'))
	}

	if vai_agent.config.whatsapp_phone_id.len > 0 && vai_agent.config.whatsapp_token.len > 0 {
		mut whatsapp_business := new_whatsapp_business_adapter(
			vai_agent.config.whatsapp_phone_id,
			vai_agent.config.whatsapp_token
		)
		vai_agent.gateway_mgr.register(whatsapp_business)
		println(term_green('✓ Registered WhatsApp Business adapter'))
	}

	if vai_agent.config.discord_bot_token.len > 0 {
		mut discord := new_discord_adapter(vai_agent.config.discord_bot_token)
		vai_agent.gateway_mgr.register(discord)
		println(term_green('✓ Registered Discord adapter'))
	}

	if vai_agent.config.debox_app_id.len > 0 && vai_agent.config.debox_app_secret.len > 0 {
		mut debox := new_debox_adapter(vai_agent.config.debox_app_id, vai_agent.config.debox_app_secret)
		vai_agent.gateway_mgr.register(debox)
		println(term_green('✓ Registered DeBox adapter'))
	}

	// 注册内置技能
	register_builtin_skills(mut vai_agent.skills_registry)!
	println(term_green('✓ Registered ${vai_agent.skills_registry.list().len} builtin skills'))

	println(term_cyan('\\nVAI Agent initialized successfully!'))
}

// 启动 Agent
pub fn (mut vai_agent VAIAgent) start() ! {
	if vai_agent.running {
		return error('agent already running')
	}

	vai_agent.running = true
	vai_agent.start_time = time.now()

	// 启动所有网关适配器
	vai_agent.gateway_mgr.start_all()!

	println(term_green('\\nVAI Agent is running!'))
	println('Press Ctrl+C to stop.\\n')

	// 主事件循环
	inbound_ch := vai_agent.gateway_mgr.inbound_channel()
	for vai_agent.running {
		select {
			msg := <-inbound_ch {
				vai_agent.handle_message(msg)
			}
			else {
				// 超时继续，检查 running 状态
				// Use sleep to prevent busy loop
				time.sleep(100 * time.millisecond)
			}
		}
	}
}

// 停止 Agent
pub fn (mut vai_agent VAIAgent) stop() {
	vai_agent.running = false
	vai_agent.gateway_mgr.stop_all() or { eprintln('Error stopping gateways: ${err}') }
	vai_agent.scheduler.stop()
	vai_agent.sandbox_mgr.cleanup_all()
	println(term_cyan('\\nVAI Agent stopped.'))
}

// 处理消息
fn (mut vai_agent VAIAgent) handle_message(msg Message) {
	vai_agent.messages_processed++

	// Process directly for now - closure capture would need redesign
	vai_agent.process_message(msg) or {
		eprintln('Failed to process message: ${err}')
	}
}

// 处理单条消息
fn (mut vai_agent VAIAgent) process_message(msg Message) ! {
	println('[${term_yellow(msg.platform)}] ${term_bold(msg.sender_id)}: ${msg.text() or { '' }}')

	// 获取或创建会话
	conversation_id := '${msg.platform}_${msg.sender_id}'
	if conversation_id !in vai_agent.conversations {
		vai_agent.conversations[conversation_id] = protocol.new_conversation(conversation_id)
		vai_agent.memory_store.create_conversation(conversation_id) or {}
	}

	mut conversation := vai_agent.conversations[conversation_id]
	conversation.add_message(msg)
	vai_agent.memory_store.add_message(conversation_id, msg) or {}

	// 获取文本内容
	text := msg.text() or { '' }
	if text.len == 0 {
		return
	}

	// 检查是否是命令
	if text.starts_with('/') {
		vai_agent.handle_command(msg, conversation_id)!
		return
	}

	// 调用 LLM 生成回复
	llm_response := vai_agent.chat_with_llm(conversation) or {
		eprintln('LLM error: ${err}')
		return
	}

	// 创建回复消息
	mut reply := new_text_message(llm_response)
	reply.receiver_id = msg.sender_id
	reply.platform = msg.platform

	// 添加 AI 回复到会话
	vai_agent.memory_store.add_message(conversation_id, reply) or {}

	// 发送回复
	vai_agent.gateway_mgr.send_to_platform(msg.platform, reply) or {
		eprintln('Failed to send reply: ${err}')
	}
}

// 处理命令
fn (mut vai_agent VAIAgent) handle_command(msg Message, conversation_id string) ! {
	text := msg.text() or { return }
	parts := text[1..].split(' ')
	if parts.len == 0 {
		return
	}

	cmd := parts[0]
	args := if parts.len > 1 { parts[1..] } else { []string{} }

	mut reply := new_text_message('')
	reply.receiver_id = msg.sender_id
	reply.platform = msg.platform

	match cmd {
		'skills', 'tools' {
			mut content := '**Available Skills:**\\n'
			for skill in vai_agent.skills_registry.list() {
				content += '\\n• ${skill.name()}: ${skill.description()}'
			}
			reply.content = protocol.TextContent{ text: content, format: 'markdown' }
		}
		'models' {
			mut content := '**Available Models:**\\n'
			models := vai_agent.llm_mgr.list_all_models() or { [] }
			for model in models[..min(models.len, 10)] {
				content += '\\n• ${model.name} (${model.provider})'
			}
			reply.content = protocol.TextContent{ text: content, format: 'markdown' }
		}
		'status' {
			uptime := time.since(vai_agent.start_time)
			content := '**Status:**\\n' +
				'Uptime: ${uptime}\\n' +
				'Messages processed: ${vai_agent.messages_processed}\\n' +
				'Active conversations: ${vai_agent.conversations.len}'
			reply.content = protocol.TextContent{ text: content, format: 'markdown' }
		}
		'memory' {
			// 搜索相关记忆
			query := args.join(' ')
			results := vai_agent.memory_store.search_messages(conversation_id, query, 5)
			mut content := '**Related memories:**\\n'
			for result in results {
				if result_text := result.text() {
					content += '\\n• ${result_text}'
				}
			}
			reply.content = protocol.TextContent{ text: content, format: 'markdown' }
		}
		'help' {
			content := '**Available Commands:**\\n' +
				'\\n/skills - List available skills' +
				'\\n/models - List available models' +
				'\\n/status - Show system status' +
				'\\n/memory <query> - Search conversation memory' +
				'\\n/help - Show this help'
			reply.content = protocol.TextContent{ text: content, format: 'markdown' }
		}
		else {
			reply.content = protocol.TextContent{
				text: 'Unknown command: /${cmd}. Type /help for available commands.'
			}
		}
	}

	vai_agent.gateway_mgr.send_to_platform(msg.platform, reply)!
}

// 与 LLM 对话
fn (mut vai_agent VAIAgent) chat_with_llm(conversation Conversation) !string {
	// 构建消息历史
	mut messages := [system_message(vai_agent.config.system_prompt)]

	for msg in conversation.last_messages(10) {
		if content := msg.text() {
			match msg.role {
				.user {
					messages << user_message(content)
				}
				.assistant {
					messages << llm.assistant_message(content)
				}
				else {}
			}
		}
	}

	// 发送请求
	request := CompletionRequest{
		model: vai_agent.config.default_model
		messages: messages
		temperature: 0.7
		max_tokens: 2000
	}

	provider := vai_agent.llm_mgr.get_default_provider() or {
		return error('no LLM provider available')
	}

	response := provider.complete(request)!

	// 处理工具调用
	if tool_calls := response.tool_calls {
		// 简化处理：直接执行第一个工具调用
		if tool_calls.len > 0 {
			tool_call := tool_calls[0]
			args := json.decode(map[string]Value, tool_call.function.arguments) or { map[string]Value{} }

			skill_ctx := skills.SkillContext{
				session_id: conversation.id
				user_id: 'user'
				working_dir: vai_agent.config.working_dir
			}

			result := vai_agent.skills_registry.execute(tool_call.function.name, args, skill_ctx) or {
				return 'Error executing tool: ${err}'
			}

			return 'Tool result: ${result.data}'
		}
	}

	return response.content
}

// 命令行交互模式
fn (mut vai_agent VAIAgent) interactive_mode() ! {
	println('\\n' + term_cyan('=== VAI Interactive Mode ==='))
	println('Type your message and press Enter. Type "quit" to exit.\\n')

	conversation_id := 'cli_${utils.generate_short_id()}'
	vai_agent.conversations[conversation_id] = protocol.new_conversation(conversation_id)
	vai_agent.memory_store.create_conversation(conversation_id)!

	for {
		print(term_green('You: '))
		input := os.input('')

		if input == 'quit' || input == 'exit' {
			break
		}

		if input.len == 0 {
			continue
		}

		// 处理命令
		if input.starts_with('/') {
			mut msg := new_text_message(input)
			msg.sender_id = 'cli_user'
			msg.platform = 'cli'
			vai_agent.handle_command(msg, conversation_id)!
			continue
		}

		// 添加用户消息
		user_msg := new_text_message(input)
		vai_agent.conversations[conversation_id].add_message(user_msg)
		vai_agent.memory_store.add_message(conversation_id, user_msg)!

		// 获取 AI 回复
		response := vai_agent.chat_with_llm(vai_agent.conversations[conversation_id]) or {
			eprintln('Error: ${err}')
			continue
		}

		println(term_blue('AI: ') + response)

		// 添加 AI 消息到会话
		mut ai_msg := new_text_message(response)
		ai_msg.role = protocol.MessageRole.assistant
		vai_agent.conversations[conversation_id].add_message(ai_msg)
		vai_agent.memory_store.add_message(conversation_id, ai_msg)!
	}

	println('\\nGoodbye!')
}

// 启动 CLI 控制台
fn (mut vai_agent VAIAgent) start_cli() {
	mut console := new_cli('vai', vai_agent.version)

	get_status := fn [mut vai_agent] () StatusInfo {
		return StatusInfo{
			uptime: time.since(vai_agent.start_time)
			active_agents: vai_agent.gateway_mgr.adapters.len
			messages_processed: vai_agent.messages_processed
			memory_usage: 'N/A'  // 需要实现
		}
	}

	register_default_commands(mut console, get_status)
	console.run()
}

// 主函数
fn main() {
	mut config := AgentConfig{}

	// 从环境变量读取配置
	if api_key := os.getenv_opt('OPENAI_API_KEY') {
		config.openai_api_key = api_key
	}

	if api_key := os.getenv_opt('OPENROUTER_API_KEY') {
		config.openrouter_api_key = api_key
	}

	if bot_token := os.getenv_opt('TELEGRAM_BOT_TOKEN') {
		config.telegram_bot_token = bot_token
	}

	if phone_id := os.getenv_opt('WHATSAPP_PHONE_ID') {
		config.whatsapp_phone_id = phone_id
	}

	if token := os.getenv_opt('WHATSAPP_TOKEN') {
		config.whatsapp_token = token
	}

	if bot_token := os.getenv_opt('DISCORD_BOT_TOKEN') {
		config.discord_bot_token = bot_token
	}

	if app_id := os.getenv_opt('DEBOX_APP_ID') {
		config.debox_app_id = app_id
	}

	if app_secret := os.getenv_opt('DEBOX_APP_SECRET') {
		config.debox_app_secret = app_secret
	}

	if model := os.getenv_opt('VAI_DEFAULT_MODEL') {
		config.default_model = model
	}

	if model := os.getenv_opt('VAI_OLLAMA_MODEL') {
		config.ollama_model = model
	}

	// 创建 Agent
	mut vai := new_agent(config)

	// 初始化
	vai.init() or {
		eprintln('Failed to initialize agent: ${err}')
		exit(1)
	}

	// 检查命令行参数
	if os.args.len > 1 {
		match os.args[1] {
			'chat', 'interactive' {
				vai.interactive_mode() or {
					eprintln('Error in interactive mode: ${err}')
				}
			}
			'cli', 'console' {
				vai.start_cli()
			}
			'version' {
				println('VAI v${vai.version}')
			}
			'web', 'server' {
				start_web_ui(vai)
			}
			'help', '--help', '-h' {
				show_help()
			}
			else {
				println('Unknown command: ${os.args[1]}')
				show_help()
			}
		}
		return
	}

	// 默认启动服务模式
	vai.start() or {
		eprintln('Agent error: ${err}')
	}
}

fn show_help() {
	println('VAI - V AI Infrastructure v0.2.0')
	println('')
	println('Usage:')
	println('  vai [command]')
	println('')
	println('Commands:')
	println('  chat         Start interactive chat mode')
	println('  cli          Start CLI console')
	println('  web          Start Web UI server')
	println('  version      Show version')
	println('  help         Show this help message')
	println('')
	println('Environment Variables:')
	println('  OPENAI_API_KEY        OpenAI API key')
	println('  OPENROUTER_API_KEY    OpenRouter API key')
	println('  TELEGRAM_BOT_TOKEN    Telegram bot token')
	println('  WHATSAPP_PHONE_ID     WhatsApp Business phone ID')
	println('  WHATSAPP_TOKEN        WhatsApp Business token')
	println('  DISCORD_BOT_TOKEN     Discord bot token')
	println('  DEBOX_APP_ID          DeBox app ID')
	println('  DEBOX_APP_SECRET      DeBox app secret')
	println('  VAI_DEFAULT_MODEL     Default LLM model')
}

// term 辅助函数
fn term_cyan(s string) string { return '\x1b[36m${s}\x1b[0m' }
fn term_green(s string) string { return '\x1b[32m${s}\x1b[0m' }
fn term_yellow(s string) string { return '\x1b[33m${s}\x1b[0m' }
fn term_blue(s string) string { return '\x1b[34m${s}\x1b[0m' }
fn term_red(s string) string { return '\x1b[31m${s}\x1b[0m' }
fn term_bold(s string) string { return '\x1b[1m${s}\x1b[0m' }

// 启动 Web UI
fn start_web_ui(vai_instance &VAIAgent) {
	// 创建 Agent Hub
	mut hub := new_hub('main', 'VAI Hub')
	hub.start() or {
		eprintln('Failed to start hub: ${err}')
		return
	}

	// 创建默认 Agent 并注册
	if provider := vai_instance.llm_mgr.get_default_provider() {
		mut base_agent := new_base_agent(
			'agent_1',
			'Assistant',
			AgentRole.worker,
			provider,
			&vai_instance.skills_registry
		)
		base_agent.start() or {
			eprintln('Failed to start agent: ${err}')
			return
		}
		hub.register(mut base_agent) or {
			eprintln('Failed to register agent: ${err}')
			return
		}
	}

	// 启动 Web 服务器
	mut web_app := new_web_app(hub, WebConfig{
		host: '0.0.0.0'
		port: 8080
		static_dir: 'static'
		auth_enabled: false
	})

	web_app.start() or {
		eprintln('Failed to start web server: ${err}')
		return
	}

	println(term_green('✓ Web UI started at http://localhost:8080'))
	println('Press Ctrl+C to stop')

	// 保持运行
	for {}
}

// 辅助函数：min
fn min(a int, b int) int {
	if a < b { return a }
	return b
}
