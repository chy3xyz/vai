// vai.bus.events - 事件类型定义
// 定义消息总线中的事件类型
module bus

import protocol { Message }
import time

// EventType 事件类型
pub enum EventType {
	message_received    // 消息接收事件
	tool_call           // 工具调用事件
	memory_update       // 记忆更新事件
	agent_response      // Agent 响应事件
	error_occurred      // 错误事件
	system_event        // 系统事件
}

// Event 基础事件接口
pub interface Event {
	event_type() EventType
	timestamp() time.Time
	payload() map[string]string
	// 获取消息（如果事件包含消息）
	get_message() ?Message
}

// MessageEvent 消息事件
pub struct MessageEvent {
pub:
	msg       Message
	event_ts  time.Time
}

pub fn (e MessageEvent) event_type() EventType {
	return .message_received
}

pub fn (e MessageEvent) timestamp() time.Time {
	return e.event_ts
}

pub fn (e MessageEvent) payload() map[string]string {
	return {
		'platform': e.msg.platform
		'sender_id': e.msg.sender_id
		'conversation_id': e.msg.conversation_id
	}
}

pub fn (e MessageEvent) get_message() ?Message {
	return e.msg
}

// ToolCallEvent 工具调用事件
pub struct ToolCallEvent {
pub:
	tool_name string
	arguments map[string]string
	event_ts  time.Time
}

pub fn (e ToolCallEvent) event_type() EventType {
	return .tool_call
}

pub fn (e ToolCallEvent) timestamp() time.Time {
	return e.event_ts
}

pub fn (e ToolCallEvent) payload() map[string]string {
	mut p := map[string]string{}
	p['tool_name'] = e.tool_name
	for key, val in e.arguments {
		p[key] = val
	}
	return p
}

pub fn (e ToolCallEvent) get_message() ?Message {
	return none
}

// MemoryUpdateEvent 记忆更新事件
pub struct MemoryUpdateEvent {
pub:
	conversation_id string
	memory_type     string // 'daily' or 'long_term'
	content         string
	event_ts        time.Time
}

pub fn (e MemoryUpdateEvent) event_type() EventType {
	return .memory_update
}

pub fn (e MemoryUpdateEvent) timestamp() time.Time {
	return e.event_ts
}

pub fn (e MemoryUpdateEvent) payload() map[string]string {
	return {
		'conversation_id': e.conversation_id
		'memory_type': e.memory_type
		'content': e.content
	}
}

pub fn (e MemoryUpdateEvent) get_message() ?Message {
	return none
}

// AgentResponseEvent Agent 响应事件
pub struct AgentResponseEvent {
pub:
	conversation_id string
	response_text   string
	event_ts        time.Time
}

pub fn (e AgentResponseEvent) event_type() EventType {
	return .agent_response
}

pub fn (e AgentResponseEvent) timestamp() time.Time {
	return e.event_ts
}

pub fn (e AgentResponseEvent) payload() map[string]string {
	return {
		'conversation_id': e.conversation_id
		'response_text': e.response_text
	}
}

pub fn (e AgentResponseEvent) get_message() ?Message {
	return none
}

// ErrorEvent 错误事件
pub struct ErrorEvent {
pub:
	error_msg  string
	error_type string
	event_ts   time.Time
}

pub fn (e ErrorEvent) event_type() EventType {
	return .error_occurred
}

pub fn (e ErrorEvent) timestamp() time.Time {
	return e.event_ts
}

pub fn (e ErrorEvent) payload() map[string]string {
	return {
		'error_msg': e.error_msg
		'error_type': e.error_type
	}
}

pub fn (e ErrorEvent) get_message() ?Message {
	return none
}

// SystemEvent 系统事件
pub struct SystemEvent {
pub:
	system_type string
	message     string
	event_ts    time.Time
}

pub fn (e SystemEvent) event_type() EventType {
	return .system_event
}

pub fn (e SystemEvent) timestamp() time.Time {
	return e.event_ts
}

pub fn (e SystemEvent) payload() map[string]string {
	return {
		'system_type': e.system_type
		'message': e.message
	}
}

pub fn (e SystemEvent) get_message() ?Message {
	return none
}

// 创建消息事件
pub fn new_message_event(msg Message) MessageEvent {
	return MessageEvent{
		msg: msg
		event_ts: time.now()
	}
}

// 创建工具调用事件
pub fn new_tool_call_event(tool_name string, arguments map[string]string) ToolCallEvent {
	return ToolCallEvent{
		tool_name: tool_name
		arguments: arguments
		event_ts: time.now()
	}
}

// 创建记忆更新事件
pub fn new_memory_update_event(conversation_id string, memory_type string, content string) MemoryUpdateEvent {
	return MemoryUpdateEvent{
		conversation_id: conversation_id
		memory_type: memory_type
		content: content
		event_ts: time.now()
	}
}

// 创建 Agent 响应事件
pub fn new_agent_response_event(conversation_id string, response_text string) AgentResponseEvent {
	return AgentResponseEvent{
		conversation_id: conversation_id
		response_text: response_text
		event_ts: time.now()
	}
}

// 创建错误事件
pub fn new_error_event(error_msg string, error_type string) ErrorEvent {
	return ErrorEvent{
		error_msg: error_msg
		error_type: error_type
		event_ts: time.now()
	}
}

// 创建系统事件
pub fn new_system_event(system_type string, message string) SystemEvent {
	return SystemEvent{
		system_type: system_type
		message: message
		event_ts: time.now()
	}
}
