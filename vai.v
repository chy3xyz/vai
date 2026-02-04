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
import memory { PersistentStore, new_persistent_store }
import planner as _
import sandbox { SandboxManager, new_sandbox_manager }
import cli { new_cli, register_default_commands, StatusInfo, new_onboard_command }
import agent { AgentHub, new_hub, BaseAgent, new_base_agent, AgentRole, AgentLoop, new_agent_loop }
import web { new_web_app, WebConfig }
import config { load_config, init_config, Config }
import workspace { new_workspace_manager, workspace_from_config }
import bus { new_message_bus, MessageBus, new_message_event }
import cron { new_cron_service, CronService }
import heartbeat { new_heartbeat_service, HeartbeatService }
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
		memory_store   &PersistentStore  // 统一使用持久化存储
		sandbox_mgr    SandboxManager
		conversations  map[string]Conversation
		running        bool
		config         Config  // 统一使用新配置系统
		workspace_mgr  workspace.WorkspaceManager
		message_bus    &MessageBus
		agent_loop     &AgentLoop
		cron_service   &CronService
		heartbeat_service &HeartbeatService
		// 统计
		start_time     time.Time
		messages_processed int
	}

// 创建新的 VAI Agent
pub fn new_agent(config_data Config) !&VAIAgent {
	// 创建工作区管理器
	mut workspace_mgr := workspace_from_config(config_data)
	workspace_mgr.init()!

	// 创建持久化存储（统一使用）
	memory_store := new_persistent_store(workspace_mgr.get_path())!

	// 创建消息总线
	message_bus := new_message_bus()

	// 创建技能注册表
	skills_registry := new_registry()

	// 创建 LLM 管理器
	mut llm_mgr := new_llm_manager()

	// 注册 LLM 提供商
	if openai_cfg := config_data.providers.openai {
		mut openai := new_openai_client(openai_cfg.api_key)
		llm_mgr.register('openai', openai)
	}
	if openrouter_cfg := config_data.providers.openrouter {
		mut openrouter := new_openrouter_client(openrouter_cfg.api_key)
		llm_mgr.register('openrouter', openrouter)
	}
	mut ollama := new_ollama_client()
	_ := config_data.providers.ollama  // 可以设置 base_url
	llm_mgr.register('ollama', ollama)

	// 获取默认 LLM 提供商
	default_provider := llm_mgr.get_default_provider() or {
		return error('no LLM provider available')
	}

	// 创建 Agent 循环
	agent_loop := new_agent_loop(
		unsafe { memory_store },
		unsafe { &skills_registry },
		unsafe { default_provider },
		unsafe { message_bus },
		config_data.agents.defaults.system_prompt
	)

	// 创建 Cron 服务
	cron_service := new_cron_service()

	// 创建心跳服务
	heartbeat_service := new_heartbeat_service()

	return &VAIAgent{
		name: 'vai'
		version: '0.3.0'
		scheduler: new_scheduler(4)
		gateway_mgr: new_gateway_manager()
		llm_mgr: llm_mgr
		skills_registry: skills_registry
		memory_store: &memory_store
		sandbox_mgr: new_sandbox_manager()
		conversations: map[string]Conversation{}
		running: false
		config: config_data
		workspace_mgr: workspace_mgr
		message_bus: message_bus
		agent_loop: &agent_loop
		cron_service: cron_service
		heartbeat_service: heartbeat_service
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

	// 启动消息总线
	vai_agent.message_bus.start()
	println(term_green('✓ Message bus started'))

	// 启动 Agent 循环
	vai_agent.agent_loop.start()
	println(term_green('✓ Agent loop started'))

	// 启动 Cron 服务
	if vai_agent.config.cron.enabled {
		vai_agent.cron_service.start()
		println(term_green('✓ Cron service started'))
	}

	// 启动心跳服务
	vai_agent.heartbeat_service.start()
	println(term_green('✓ Heartbeat service started'))

	// 注册网关适配器（从环境变量读取）
	if telegram_token := os.getenv_opt('TELEGRAM_BOT_TOKEN') {
		mut telegram := new_telegram_adapter(telegram_token)
		vai_agent.gateway_mgr.register(telegram)
		println(term_green('✓ Registered Telegram adapter'))
	}
	
	if whatsapp_phone_id := os.getenv_opt('WHATSAPP_PHONE_ID') {
		if whatsapp_token := os.getenv_opt('WHATSAPP_TOKEN') {
			mut whatsapp_business := new_whatsapp_business_adapter(whatsapp_phone_id, whatsapp_token)
			vai_agent.gateway_mgr.register(whatsapp_business)
			println(term_green('✓ Registered WhatsApp Business adapter'))
		}
	}
	
	if discord_token := os.getenv_opt('DISCORD_BOT_TOKEN') {
		mut discord := new_discord_adapter(discord_token)
		vai_agent.gateway_mgr.register(discord)
		println(term_green('✓ Registered Discord adapter'))
	}
	
	if debox_app_id := os.getenv_opt('DEBOX_APP_ID') {
		if debox_app_secret := os.getenv_opt('DEBOX_APP_SECRET') {
			mut debox := new_debox_adapter(debox_app_id, debox_app_secret)
			vai_agent.gateway_mgr.register(debox)
			println(term_green('✓ Registered DeBox adapter'))
		}
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

	// 主事件循环 - 使用消息总线
	inbound_ch := vai_agent.gateway_mgr.inbound_channel()
	for vai_agent.running {
		select {
			msg := <-inbound_ch {
				// 发布消息事件到消息总线
				msg_event := new_message_event(msg)
				vai_agent.message_bus.publish(msg_event) or {
					eprintln('Failed to publish message: ${err}')
				}
			}
			else {
				// 超时继续，检查 running 状态
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
	vai_agent.message_bus.stop()
	vai_agent.cron_service.stop()
	vai_agent.heartbeat_service.stop()
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

	// 消息已通过消息总线处理，AgentLoop 会生成响应
	// 这里只需要等待响应事件（简化实现）
	// 实际应该通过消息总线订阅响应事件
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
		'cron' {
			if args.len > 0 && args[0] == 'list' {
				jobs := vai_agent.cron_service.list_jobs()
				mut content := '**Cron Jobs:**\\n'
				if jobs.len == 0 {
					content += '\\nNo cron jobs configured.'
				} else {
					for job in jobs {
						status := if job.enabled { 'enabled' } else { 'disabled' }
						content += '\\n• ${job.id}: ${job.description} (${job.schedule}) [${status}]'
					}
				}
				reply.content = protocol.TextContent{ text: content, format: 'markdown' }
			} else {
				reply.content = protocol.TextContent{ text: 'Usage: /cron list' }
			}
		}
		'help' {
			content := '**Available Commands:**\\n' +
				'\\n/skills - List available skills' +
				'\\n/models - List available models' +
				'\\n/status - Show system status' +
				'\\n/memory <query> - Search conversation memory' +
				'\\n/cron list - List cron jobs' +
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
	mut messages := [system_message(vai_agent.config.agents.defaults.system_prompt)]

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
		model: vai_agent.config.agents.defaults.model
		messages: messages
		temperature: f32(vai_agent.config.agents.defaults.temperature)
		max_tokens: vai_agent.config.agents.defaults.max_tokens
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
				working_dir: vai_agent.workspace_mgr.get_path()
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
	// 检查命令行参数
	if os.args.len > 1 {
		match os.args[1] {
			'onboard', 'init', 'setup' {
				handle_onboard() or {
					eprintln('Failed to initialize: ${err}')
					exit(1)
				}
				return
			}
			'version' {
				println('VAI v0.3.0')
				return
			}
			'help', '--help', '-h' {
				show_help()
				return
			}
			else {
				// 继续执行，让后续代码处理其他命令
			}
		}
	}

	// 加载配置
	config_data := load_config() or {
		eprintln('Failed to load config: ${err}')
		eprintln('Run "vai onboard" to initialize configuration.')
		exit(1)
	}

	// 创建 Agent
	mut vai := new_agent(config_data) or {
		eprintln('Failed to create agent: ${err}')
		exit(1)
	}

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
			'web', 'server' {
				start_web_ui(vai)
			}
			'cron' {
				if os.args.len > 2 && os.args[2] == 'list' {
					jobs := vai.cron_service.list_jobs()
					println('Cron jobs:')
					if jobs.len == 0 {
						println('  (No cron jobs configured)')
					} else {
						for job in jobs {
							status := if job.enabled { 'enabled' } else { 'disabled' }
							println('  ${job.id}: ${job.description} (${job.schedule}) [${status}]')
						}
					}
				} else {
					println('Usage: vai cron list')
				}
			}
			else {
				println('Unknown command: ${os.args[1]}')
				show_help()
			}
		}
		return
	} else {
		// 无参数时的默认行为
	}

	// 默认启动服务模式
	vai.start() or {
		eprintln('Agent error: ${err}')
	}
}

// 处理 onboard 命令
fn handle_onboard() ! {
	println(term_cyan('Initializing VAI...'))
	
	// 初始化配置
	config_data := init_config()!
	println(term_green('✓ Configuration initialized'))
	
	// 初始化工作区
	mut workspace_mgr := workspace_from_config(config_data)
	workspace_mgr.init()!
	println(term_green('✓ Workspace initialized'))
	
	println(term_cyan('\\nVAI initialized successfully!'))
	println('Configuration: ~/.vai/config.json')
	println('Workspace: ~/.vai/workspace/')
	println('\\nEdit ~/.vai/config.json to add your API keys.')
}

fn show_help() {
	println('VAI - V AI Infrastructure v0.3.0')
	println('')
	println('Usage:')
	println('  vai [command]')
	println('')
	println('Commands:')
	println('  onboard      Initialize configuration and workspace')
	println('  chat         Start interactive chat mode')
	println('  cli          Start CLI console')
	println('  web          Start Web UI server')
	println('  cron list    List cron jobs')
	println('  version      Show version')
	println('  help         Show this help message')
	println('')
	println('Configuration:')
	println('  Configuration file: ~/.vai/config.json')
	println('  Workspace: ~/.vai/workspace/')
	println('')
	println('Run "vai onboard" to initialize VAI for the first time.')
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
