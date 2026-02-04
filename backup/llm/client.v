// vai.llm - 多模型统一接口
// 支持 OpenAI、Anthropic、Ollama 等多个 LLM 提供商
module llm

import net.http
import json
import time

// LLMProvider LLM 提供商接口
pub interface LLMProvider {
	// 获取提供商名称
	name() string
	
	// 发送普通请求
	complete(request CompletionRequest) !CompletionResponse
	
	// 发送流式请求
	complete_stream(request CompletionRequest, callback fn (chunk CompletionChunk)) !
	
	// 获取可用模型列表
	list_models() ![]ModelInfo
	
	// 计算 token 数量（估算）
	count_tokens(text string) int
}

// CompletionRequest 补全请求
pub struct CompletionRequest {
	pub:
		model       string      // 模型名称
		messages    []Message   // 对话消息列表
		temperature f32 = 0.7   // 采样温度
		max_tokens  ?int        // 最大生成 token 数
		top_p       f32 = 1.0   // 核采样
		stream      bool        // 是否流式输出
		system      ?string     // 系统提示词
		tools       ?[]Tool     // 可用工具列表
		tool_choice ?ToolChoice // 工具选择策略
}

// CompletionResponse 补全响应
pub struct CompletionResponse {
	pub:
		id          string
		model       string
		content     string
		tokens_used int
		finish_reason string
		tool_calls  ?[]ToolCall
}

// CompletionChunk 流式响应块
pub struct CompletionChunk {
	pub:
		id          string
		model       string
		content     string
		finish_reason ?string
	}

// Message 对话消息
pub struct Message {
	pub:
		role    string  // system, user, assistant, tool
		content string
		name    ?string // 用于 tool 消息
	}

// ModelInfo 模型信息
pub struct ModelInfo {
	pub:
		id          string
		name        string
		provider    string
		max_tokens  int
		supports_tools bool
		supports_vision bool
}

// Tool 工具定义
pub struct Tool {
	pub:
		typ     string @[json: 'type']
		function Function
}

// Function 函数定义
pub struct Function {
	pub:
		name        string
		description string
		parameters  map[string]any
}

// ToolChoice 工具选择
pub struct ToolChoice {
	pub:
		typ      string @[json: 'type']  // 'none', 'auto', 'function'
		function ?ToolChoiceFunction
}

// ToolChoiceFunction 指定函数
pub struct ToolChoiceFunction {
	pub:
		name string
}

// ToolCall 工具调用
pub struct ToolCall {
	pub:
		id       string
		typ      string @[json: 'type']
		function FunctionCall
}

// FunctionCall 函数调用详情
pub struct FunctionCall {
	pub:
		name      string
		arguments string // JSON 字符串
}

// BaseClient 基础客户端
pub struct BaseClient {
	pub mut:
		api_key      string
		base_url     string
		timeout      time.Duration = 60 * time.second
		http_client  http.Client
		default_model string
}

// 创建基础客户端
pub fn new_base_client(api_key string, base_url string) BaseClient {
	return BaseClient{
		api_key: api_key
		base_url: base_url
		http_client: http.Client{
			timeout: 60 * time.second
		}
		default_model: ''
	}
}

// LLMManager LLM 管理器
pub struct LLMManager {
	pub mut:
		providers map[string]LLMProvider
		default_provider ?string
}

// 创建 LLM 管理器
pub fn new_llm_manager() LLMManager {
	return LLMManager{
		providers: map[string]LLMProvider{}
	}
}

// 注册提供商
pub fn (mut m LLMManager) register(name string, provider LLMProvider) {
	m.providers[name] = provider
	
	// 如果没有默认提供商，设置为第一个
	if m.default_provider == none {
		m.default_provider = name
	}
}

// 设置默认提供商
pub fn (mut m LLMManager) set_default_provider(name string) ! {
	if name !in m.providers {
		return error('provider ${name} not registered')
	}
	m.default_provider = name
}

// 获取提供商
pub fn (m &LLMManager) get_provider(name string) ?LLMProvider {
	return m.providers[name] or { return none }
}

// 获取默认提供商
pub fn (m &LLMManager) get_default_provider() ?LLMProvider {
	if name := m.default_provider {
		return m.providers[name] or { return none }
	}
	return none
}

// 发送补全请求
pub fn (m &LLMManager) complete(request CompletionRequest) !CompletionResponse {
	provider := m.get_default_provider() or {
		return error('no default provider set')
	}
	return provider.complete(request)
}

// 列出所有可用模型
pub fn (m &LLMManager) list_all_models() ![]ModelInfo {
	mut all_models := []ModelInfo{}
	
	for _, provider in m.providers {
		models := provider.list_models() or { continue }
		all_models << models
	}
	
	return all_models
}

// 创建用户消息
pub fn user_message(content string) Message {
	return Message{
		role: 'user'
		content: content
	}
}

// 创建助手消息
pub fn assistant_message(content string) Message {
	return Message{
		role: 'assistant'
		content: content
	}
}

// 创建系统消息
pub fn system_message(content string) Message {
	return Message{
		role: 'system'
		content: content
	}
}

// 创建工具消息
pub fn tool_message(content string, name string) Message {
	return Message{
		role: 'tool'
		content: content
		name: name
	}
}
