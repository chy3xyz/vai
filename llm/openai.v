// vai.llm.openai - OpenAI API 客户端
module llm

import net.http
import json
import time

// OpenAIClient OpenAI 客户端
pub struct OpenAIClient {
	BaseClient
}

// OpenAIRequest OpenAI API 请求格式
pub struct OpenAIRequest {
	pub:
		model       string    @[json: 'model']
		messages    []Message @[json: 'messages']
		temperature f32       @[json: 'temperature']
		max_tokens  ?int      @[json: 'max_tokens'; omitempty]
		top_p       f32       @[json: 'top_p']
		stream      bool      @[json: 'stream']
		tools       ?[]Tool   @[json: 'tools'; omitempty]
		tool_choice ?ToolChoice @[json: 'tool_choice'; omitempty]
}

// OpenAIResponse OpenAI API 响应格式
pub struct OpenAIResponse {
	pub:
		id      string         @[json: 'id']
		object  string         @[json: 'object']
		created i64            @[json: 'created']
		model   string         @[json: 'model']
		choices []OpenAIChoice @[json: 'choices']
		usage   OpenAIUsage    @[json: 'usage']
}

// OpenAIChoice 选择项
pub struct OpenAIChoice {
	pub:
		index         int            @[json: 'index']
		message       OpenAIMessage  @[json: 'message']
		finish_reason string         @[json: 'finish_reason']
}

// OpenAIMessage 消息格式
pub struct OpenAIMessage {
	pub:
		role       string     @[json: 'role']
		content    ?string    @[json: 'content']
		tool_calls ?[]ToolCall @[json: 'tool_calls'; omitempty]
}

// OpenAIUsage Token 使用统计
pub struct OpenAIUsage {
	pub:
		prompt_tokens     int @[json: 'prompt_tokens']
		completion_tokens int @[json: 'completion_tokens']
		total_tokens      int @[json: 'total_tokens']
}

// OpenAIStreamResponse 流式响应
pub struct OpenAIStreamResponse {
	pub:
		id      string              @[json: 'id']
		object  string              @[json: 'object']
		created i64                 @[json: 'created']
		model   string              @[json: 'model']
		choices []OpenAIStreamChoice @[json: 'choices']
}

// OpenAIStreamChoice 流式选择项
pub struct OpenAIStreamChoice {
	pub:
		index        int                  @[json: 'index']
		delta        OpenAIMessageDelta   @[json: 'delta']
		finish_reason ?string             @[json: 'finish_reason']
}

// OpenAIMessageDelta 增量消息
pub struct OpenAIMessageDelta {
	pub:
		role    ?string @[json: 'role'; omitempty]
		content ?string @[json: 'content'; omitempty]
}

// OpenAIModelsResponse 模型列表响应
pub struct OpenAIModelsResponse {
	pub:
		object string         @[json: 'object']
		data   []OpenAIModel  @[json: 'data']
}

// OpenAIModel 模型信息
pub struct OpenAIModel {
	pub:
		id         string @[json: 'id']
		object     string @[json: 'object']
		created    i64    @[json: 'created']
		owned_by   string @[json: 'owned_by']
}

// 创建 OpenAI 客户端
pub fn new_openai_client(api_key string) OpenAIClient {
	return OpenAIClient{
		BaseClient: new_base_client(api_key, 'https://api.openai.com/v1')
		default_model: 'gpt-4o-mini'
	}
}

// 创建自定义 OpenAI 客户端（用于兼容 API）
pub fn new_openai_compatible_client(api_key string, base_url string, default_model string) OpenAIClient {
	return OpenAIClient{
		BaseClient: new_base_client(api_key, base_url)
		default_model: default_model
	}
}

// 获取提供商名称
pub fn (c &OpenAIClient) name() string {
	return 'openai'
}

// 发送补全请求
pub fn (mut c OpenAIClient) complete(request CompletionRequest) !CompletionResponse {
	model := if request.model.len > 0 { request.model } else { c.default_model }
	
	mut messages := request.messages.clone()
	
	// 添加系统提示词
	if system := request.system {
		if messages.len == 0 || messages[0].role != 'system' {
			messages = [system_message(system), ...messages]
		}
	}
	
	openai_req := OpenAIRequest{
		model: model
		messages: messages
		temperature: request.temperature
		max_tokens: request.max_tokens
		top_p: request.top_p
		stream: false
		tools: request.tools
		tool_choice: request.tool_choice
	}
	
	json_body := json.encode(openai_req)
	
	mut http_req := http.new_request(.post, '${c.base_url}/chat/completions', json_body)
	http_req.header.add(.content_type, 'application/json')
	http_req.header.add(.authorization, 'Bearer ${c.api_key}')
	
	resp := c.http_client.do(http_req)!
	
	if resp.status_code != 200 {
		return error('OpenAI API error: ${resp.status_code} - ${resp.body}')
	}
	
	openai_resp := json.decode(OpenAIResponse, resp.body)!
	
	if openai_resp.choices.len == 0 {
		return error('no choices in response')
	}
	
	choice := openai_resp.choices[0]
	content := choice.message.content or { '' }
	
	return CompletionResponse{
		id: openai_resp.id
		model: openai_resp.model
		content: content
		tokens_used: openai_resp.usage.total_tokens
		finish_reason: choice.finish_reason
		tool_calls: choice.message.tool_calls
	}
}

// 发送流式补全请求
pub fn (mut c OpenAIClient) complete_stream(request CompletionRequest, callback fn (chunk CompletionChunk)) ! {
	model := if request.model.len > 0 { request.model } else { c.default_model }
	
	mut messages := request.messages.clone()
	
	if system := request.system {
		if messages.len == 0 || messages[0].role != 'system' {
			messages = [system_message(system), ...messages]
		}
	}
	
	openai_req := OpenAIRequest{
		model: model
		messages: messages
		temperature: request.temperature
		max_tokens: request.max_tokens
		top_p: request.top_p
		stream: true
		tools: request.tools
	}
	
	json_body := json.encode(openai_req)
	
	mut http_req := http.new_request(.post, '${c.base_url}/chat/completions', json_body)
	http_req.header.add(.content_type, 'application/json')
	http_req.header.add(.authorization, 'Bearer ${c.api_key}')
	
	// 流式请求处理简化版
	// 实际应该使用 SSE 解析
	resp := c.http_client.do(http_req)!
	
	if resp.status_code != 200 {
		return error('OpenAI API error: ${resp.status_code}')
	}
	
	// 解析流式响应（简化处理）
	lines := resp.body.split('\n')
	for line in lines {
		if line.starts_with('data: ') {
			data := line[6..]
			if data == '[DONE]' {
				break
			}
			
			stream_resp := json.decode(OpenAIStreamResponse, data) or { continue }
			if stream_resp.choices.len > 0 {
				delta := stream_resp.choices[0].delta
				if content := delta.content {
					callback(CompletionChunk{
						id: stream_resp.id
						model: stream_resp.model
						content: content
						finish_reason: stream_resp.choices[0].finish_reason
					})
				}
			}
		}
	}
}

// 获取可用模型列表
pub fn (mut c OpenAIClient) list_models() ![]ModelInfo {
	mut req := http.new_request(.get, '${c.base_url}/models', '')
	req.header.add(.authorization, 'Bearer ${c.api_key}')
	
	resp := c.http_client.do(req)!
	
	if resp.status_code != 200 {
		return error('failed to list models: ${resp.status_code}')
	}
	
	models_resp := json.decode(OpenAIModelsResponse, resp.body)!
	
	mut models := []ModelInfo{}
	for model in models_resp.data {
		// 只包含 GPT 模型
		if model.id.starts_with('gpt-') {
			models << ModelInfo{
				id: model.id
				name: model.id
				provider: 'openai'
				max_tokens: 128000  // 默认，实际应该根据模型确定
				supports_tools: model.id.contains('gpt-4') || model.id.contains('gpt-3.5-turbo')
				supports_vision: model.id.contains('vision') || model.id.contains('gpt-4o')
			}
		}
	}
	
	return models
}

// 计算 token 数量（简单估算）
pub fn (c &OpenAIClient) count_tokens(text string) int {
	// 简化估算：英文约 4 字符/token，中文约 1 字符/token
	// 实际应该使用 tiktoken 库
	mut count := 0
	for ch in text {
		if ch < 128 {
			count += 1
		} else {
			count += 2  // 非 ASCII 字符估算
		}
	}
	return count / 4 + 1
}
