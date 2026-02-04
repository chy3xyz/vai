// vai.agent.context - 上下文构建器
// 构建 Agent 处理消息时的上下文，结合历史记录、记忆、技能等
module agent

import protocol { Message, Conversation }
import memory { Store }
import skills { Registry }
import llm { user_message, assistant_message, system_message }

// Context 上下文结构
pub struct Context {
pub:
	conversation_id string
	conversation    Conversation
	messages        []Message
	memory_context  string
	available_tools []string
	system_prompt   string
}

// ContextBuilder 上下文构建器
@[heap]
pub struct ContextBuilder {
pub mut:
	memory_store  &Store
	skill_registry &Registry
	system_prompt string
}

// 创建上下文构建器
pub fn new_context_builder(memory_store &Store, skill_registry &Registry, system_prompt string) ContextBuilder {
	return ContextBuilder{
		memory_store: memory_store
		skill_registry: skill_registry
		system_prompt: system_prompt
	}
}

// 构建上下文
pub fn (mut cb ContextBuilder) build_context(conversation_id string, recent_messages []Message) !Context {
	// 获取会话
	conversation := cb.memory_store.get_conversation(conversation_id) or {
		return error('conversation not found: ${conversation_id}')
	}

	// 获取历史消息（最近 N 条）
	history_limit := 20
	history_messages := cb.memory_store.get_messages(conversation_id, history_limit)

	// 构建记忆上下文
	memory_context := cb.build_memory_context(conversation_id)

	// 获取可用工具列表
	available_tools := cb.get_available_tools()

	return Context{
		conversation_id: conversation_id
		conversation: conversation
		messages: history_messages
		memory_context: memory_context
		available_tools: available_tools
		system_prompt: cb.system_prompt
	}
}

// 构建记忆上下文
fn (mut cb ContextBuilder) build_memory_context(conversation_id string) string {
	mut context_parts := []string{}

	// 可以添加长期记忆检索逻辑
	// 目前返回空字符串，后续可以集成向量检索

	return context_parts.join('\n\n')
}

// 获取可用工具列表
fn (mut cb ContextBuilder) get_available_tools() []string {
	mut tools := []string{}
	for skill in cb.skill_registry.list() {
		tools << skill.name()
	}
	return tools
}

// 将上下文转换为 LLM 消息列表
pub fn (ctx &Context) to_llm_messages() []llm.Message {
	mut messages := []llm.Message{}

	// 系统提示
	if ctx.system_prompt.len > 0 {
		messages << llm.system_message(ctx.system_prompt)
	}

	// 记忆上下文（如果有）
	if ctx.memory_context.len > 0 {
		memory_msg := '## Context from Memory\n\n${ctx.memory_context}'
		messages << llm.system_message(memory_msg)
	}

	// 历史消息
	for msg in ctx.messages {
		if text := msg.text() {
			match msg.role {
				.user {
					messages << user_message(text)
				}
				.assistant {
					messages << assistant_message(text)
				}
				else {}
			}
		}
	}

	return messages
}

// 构建工具描述（用于 LLM 工具调用）
pub fn (ctx &Context) build_tools_description() string {
	if ctx.available_tools.len == 0 {
		return ''
	}

	mut desc := '## Available Tools\n\n'
	for tool in ctx.available_tools {
		desc += '- ${tool}\n'
	}
	desc += '\nYou can use these tools by calling them with appropriate parameters.\n'

	return desc
}
