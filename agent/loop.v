// vai.agent.loop - Agent 循环引擎
// 实现类似 nanobot loop.py 的完整处理流程
module agent

import protocol { Message, new_text_message }
import bus { MessageBus, new_message_event, new_agent_response_event, new_error_event }
import llm { LLMProvider, CompletionRequest, user_message, assistant_message }
import skills { Registry, Value, SkillContext }
import memory { Store }
import json

// AgentLoop Agent 循环引擎
@[heap]
pub struct AgentLoop {
pub mut:
	memory_store   &Store
	skill_registry &Registry
	llm_provider   &LLMProvider
	message_bus    &MessageBus
	system_prompt  string
	context_builder ContextBuilder
}

// 创建 Agent 循环
pub fn new_agent_loop(
	memory_store &Store,
	skill_registry &Registry,
	llm_provider &LLMProvider,
	message_bus &MessageBus,
	system_prompt string
) AgentLoop {
	mut cb := new_context_builder(memory_store, skill_registry, system_prompt)
	return AgentLoop{
		memory_store: memory_store
		skill_registry: skill_registry
		llm_provider: llm_provider
		message_bus: message_bus
		system_prompt: system_prompt
		context_builder: cb
	}
}

// 处理消息（主循环）
pub fn (mut al AgentLoop) process_message(msg Message) !Message {
	// 1. 获取或创建会话
	conversation_id := if msg.conversation_id.len > 0 { msg.conversation_id } else { '${msg.platform}_${msg.sender_id}' }
	
	if conversation_id !in al.memory_store.list_conversations().map(it.id) {
		al.memory_store.create_conversation(conversation_id) or {}
	}

	// 2. 添加消息到记忆
	al.memory_store.add_message(conversation_id, msg) or {}

	// 3. 构建上下文
	mut ctx := al.context_builder.build_context(conversation_id, [msg]) or {
		al.message_bus.publish(new_error_event('failed to build context: ${err}', 'context_error')) or {}
		return err
	}

	// 4. 调用 LLM（带工具调用支持）
	response := al.call_llm_with_tools(mut ctx) or {
		al.message_bus.publish(new_error_event('LLM call failed: ${err}', 'llm_error')) or {}
		return err
	}

	// 5. 处理工具调用（如果有）
	if tool_calls := response.tool_calls {
		for tool_call in tool_calls {
			_ := al.execute_tool(tool_call, conversation_id) or {
				al.message_bus.publish(new_error_event('tool execution failed: ${err}', 'tool_error')) or {}
				continue
			}
			
			// 将工具结果添加到上下文，再次调用 LLM
			// 这里简化处理，实际应该更复杂
		}
	}

	// 6. 创建响应消息
	mut reply := new_text_message(response.content)
	reply.receiver_id = msg.sender_id
	reply.platform = msg.platform
	reply.conversation_id = conversation_id

	// 7. 更新记忆
	al.memory_store.add_message(conversation_id, reply) or {}

	// 8. 发布响应事件
	al.message_bus.publish(new_agent_response_event(conversation_id, response.content)) or {}

	// 9. 返回响应消息（供调用者发送）
	return reply
}

// 调用 LLM（带工具支持）
fn (mut al AgentLoop) call_llm_with_tools(mut ctx Context) !llm.CompletionResponse {
	// 构建消息列表
	messages := ctx.to_llm_messages()

	// 获取工具列表（转换为 OpenAI 格式）
	skill_tools := al.skill_registry.to_openai_tools()
	
	// 转换为 LLM Tool 类型
	mut llm_tools := []llm.Tool{}
	for skill_tool in skill_tools {
		// 直接使用 parameters（类型兼容）
		params_map := skill_tool.function.parameters.clone()
		
		llm_tools << llm.Tool{
			typ: skill_tool.typ
			function: llm.Function{
				name: skill_tool.function.name
				description: skill_tool.function.description
				parameters: params_map
			}
		}
	}

	// 创建请求
	request := CompletionRequest{
		model: '' // 使用默认模型
		messages: messages
		tools: if llm_tools.len > 0 { llm_tools } else { none }
		temperature: 0.7
		max_tokens: 2000
	}

	// 调用 LLM
	return al.llm_provider.complete(request)
}

// 执行工具
fn (mut al AgentLoop) execute_tool(tool_call llm.ToolCall, conversation_id string) !skills.Result {
	tool_name := tool_call.function.name
	
	// 解析参数
	args := json.decode(map[string]Value, tool_call.function.arguments) or {
		return error('failed to parse tool arguments: ${err}')
	}

	// 创建技能上下文
	skill_ctx := skills.SkillContext{
		session_id: conversation_id
		user_id: 'user'
		working_dir: '.'
	}

	// 执行技能
	return al.skill_registry.execute(tool_name, args, skill_ctx)
}

// 启动循环（订阅消息事件）
pub fn (mut al AgentLoop) start() {
	al.message_bus.subscribe(.message_received, fn [mut al] (event bus.Event) {
		// 从事件中获取消息
		if msg := event.get_message() {
			al.process_message(msg) or {
				eprintln('Failed to process message: ${err}')
			}
		}
	})
}
