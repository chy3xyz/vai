// vai.llm.openrouter - OpenRouter API 客户端
// OpenRouter 提供统一的 LLM API 接口，支持多种模型
module llm

import net.http
import json

// OpenRouterClient OpenRouter 客户端
// OpenRouter 是 OpenAI API 的兼容超集，提供额外的路由功能
pub struct OpenRouterClient {
	BaseClient
pub mut:
	site_url  string // 可选：用于在 OpenRouter 排名中标识来源
	site_name string // 可选：应用名称
}

// OpenRouterRequest OpenRouter API 请求格式
// 兼容 OpenAI 格式，但包含额外的 OpenRouter 特定字段
pub struct OpenRouterRequest {
pub:
	model              string          @[json: 'model']
	messages           []Message       @[json: 'messages']
	prompt             ?string         @[json: 'prompt'; omitempty] // 用于完成 API
	stream             bool            @[json: 'stream']
	max_tokens         ?int            @[json: 'max_tokens'; omitempty]
	temperature        f32             @[json: 'temperature']
	top_p              f32             @[json: 'top_p']
	top_k              ?int            @[json: 'top_k'; omitempty]
	frequency_penalty  f32             @[json: 'frequency_penalty']
	presence_penalty   f32             @[json: 'presence_penalty']
	repetition_penalty ?f32            @[json: 'repetition_penalty'; omitempty]
	seed               ?int            @[json: 'seed'; omitempty]
	tools              ?[]Tool         @[json: 'tools'; omitempty]
	tool_choice        ?ToolChoice     @[json: 'tool_choice'; omitempty]
	response_format    ?ResponseFormat @[json: 'response_format'; omitempty]
	// OpenRouter 特定字段
	transforms ?[]string           @[json: 'transforms'; omitempty] // ["middle-out"]
	models     ?[]string           @[json: 'models'; omitempty]     // 备用模型列表
	route      ?string             @[json: 'route'; omitempty]      // "fallback"
	provider   ?ProviderPreference @[json: 'provider'; omitempty]
}

// ResponseFormat 响应格式控制
pub struct ResponseFormat {
pub:
	typ string @[json: 'type'] // "json_object", "json_schema"
}

// ProviderPreference 提供商偏好设置
pub struct ProviderPreference {
pub:
	order              ?[]string @[json: 'order'; omitempty] // ["Anthropic", "OpenAI"]
	allow_fallbacks    ?bool     @[json: 'allow_fallbacks'; omitempty]
	require_parameters ?bool     @[json: 'require_parameters'; omitempty]
}

// OpenRouterResponse OpenRouter API 响应格式
pub struct OpenRouterResponse {
pub:
	id       string             @[json: 'id']
	provider string             @[json: 'provider'] // 实际提供模型的服务商
	model    string             @[json: 'model']
	object   string             @[json: 'object']
	created  i64                @[json: 'created']
	choices  []OpenRouterChoice @[json: 'choices']
	usage    OpenRouterUsage    @[json: 'usage']
}

// OpenRouterChoice 选择项
pub struct OpenRouterChoice {
pub:
	logprobs      ?map[string]string @[json: 'logprobs'; omitempty]
	finish_reason string             @[json: 'finish_reason']
	index         int                @[json: 'index']
	message       OpenRouterMessage  @[json: 'message']
}

// OpenRouterMessage 消息格式
pub struct OpenRouterMessage {
pub:
	role       string      @[json: 'role']
	content    ?string     @[json: 'content'; omitempty]
	refusal    ?string     @[json: 'refusal'; omitempty]
	tool_calls ?[]ToolCall @[json: 'tool_calls'; omitempty]
}

// OpenRouterUsage Token 使用统计
pub struct OpenRouterUsage {
pub:
	prompt_tokens     int @[json: 'prompt_tokens']
	completion_tokens int @[json: 'completion_tokens']
	total_tokens      int @[json: 'total_tokens']
	// OpenRouter 特定字段
	prompt_tokens_details     ?TokenDetails @[json: 'prompt_tokens_details'; omitempty]
	completion_tokens_details ?TokenDetails @[json: 'completion_tokens_details'; omitempty]
	cost                      ?f64          @[json: 'cost'; omitempty] // 美元成本
}

// TokenDetails Token 详情
pub struct TokenDetails {
pub:
	cached_tokens int @[json: 'cached_tokens']
}

// OpenRouterStreamResponse 流式响应
pub struct OpenRouterStreamResponse {
pub:
	id       string                   @[json: 'id']
	provider string                   @[json: 'provider']
	model    string                   @[json: 'model']
	object   string                   @[json: 'object']
	created  i64                      @[json: 'created']
	choices  []OpenRouterStreamChoice @[json: 'choices']
}

// OpenRouterStreamChoice 流式选择项
pub struct OpenRouterStreamChoice {
pub:
	index         int                    @[json: 'index']
	delta         OpenRouterMessageDelta @[json: 'delta']
	finish_reason ?string                @[json: 'finish_reason']
	logprobs      ?map[string]string     @[json: 'logprobs'; omitempty]
}

// OpenRouterMessageDelta 增量消息
pub struct OpenRouterMessageDelta {
pub:
	role       ?string     @[json: 'role'; omitempty]
	content    ?string     @[json: 'content'; omitempty]
	tool_calls ?[]ToolCall @[json: 'tool_calls'; omitempty]
}

// OpenRouterModel OpenRouter 模型信息
pub struct OpenRouterModel {
pub:
	id             string       @[json: 'id']
	name           string       @[json: 'name']
	description    string       @[json: 'description']
	pricing        ModelPricing @[json: 'pricing']
	context_length int          @[json: 'context_length']
}

// ModelPricing 模型定价
pub struct ModelPricing {
pub:
	prompt     f64 @[json: 'prompt'] // 每 1K tokens 价格
	completion f64 @[json: 'completion']
	image      f64 @[json: 'image'] // 每 1K 图像 tokens
}

// OpenRouterModelsResponse 模型列表响应
pub struct OpenRouterModelsResponse {
pub:
	data []OpenRouterModel @[json: 'data']
}

// OpenRouterError OpenRouter 错误响应
pub struct OpenRouterError {
pub:
	code     ?string            @[json: 'code'; omitempty]
	message  string             @[json: 'message']
	metadata ?map[string]string @[json: 'metadata'; omitempty]
}

// OpenRouterErrorResponse 错误响应包装
pub struct OpenRouterErrorResponse {
pub:
	error OpenRouterError @[json: 'error']
}

// GenerationStats 生成统计（用于获取请求的详细统计）
pub struct GenerationStats {
pub:
	id                string @[json: 'id']
	total_cost        f64    @[json: 'total_cost']
	tokens_prompt     int    @[json: 'tokens_prompt']
	tokens_completion int    @[json: 'tokens_completion']
	latency           f64    @[json: 'latency'] // 毫秒
}

// 创建 OpenRouter 客户端
pub fn new_openrouter_client(api_key string) &OpenRouterClient {
	mut client := &OpenRouterClient{
		BaseClient: new_base_client(api_key, 'https://openrouter.ai/api/v1')
	}
	client.default_model = 'openai/gpt-4o-mini'
	return client
}

// 创建带应用信息的 OpenRouter 客户端
pub fn new_openrouter_client_with_app(api_key string, site_url string, site_name string) &OpenRouterClient {
	mut client := &OpenRouterClient{
		BaseClient: new_base_client(api_key, 'https://openrouter.ai/api/v1')
		site_url:   site_url
		site_name:  site_name
	}
	client.default_model = 'openai/gpt-4o-mini'
	return client
}

// 获取提供商名称
pub fn (c &OpenRouterClient) name() string {
	return 'openrouter'
}

// 发送补全请求
pub fn (c &OpenRouterClient) complete(request CompletionRequest) !CompletionResponse {
	model := if request.model.len > 0 { request.model } else { c.default_model }

	mut messages := request.messages.clone()

	// 添加系统提示词
	if system := request.system {
		if messages.len == 0 || messages[0].role != 'system' {
			mut new_msgs := [system_message(system)]
			new_msgs << messages
			messages = new_msgs.clone()
		}
	}

	openrouter_req := OpenRouterRequest{
		model:       model
		messages:    messages
		stream:      false
		temperature: request.temperature
		max_tokens:  request.max_tokens
		top_p:       request.top_p
		tools:       request.tools
		tool_choice: request.tool_choice
	}

	json_body := json.encode(openrouter_req)

	// V 0.5: 使用 http.fetch 代替 http.Client
	mut header := http.new_header()
	header.add(.content_type, 'application/json')
	header.add(.authorization, 'Bearer ${c.api_key}')

	// 添加 OpenRouter 特定的 HTTP 头
	if c.site_url.len > 0 {
		header.add_custom('HTTP-Referer', c.site_url)!
	}
	if c.site_name.len > 0 {
		header.add_custom('X-Title', c.site_name)!
	}

	resp := http.fetch(
		url:    '${c.base_url}/chat/completions'
		method: .post
		header: header
		data:   json_body
	)!

	if resp.status_code != 200 {
		// 尝试解析错误响应
		if err_resp := json.decode(OpenRouterErrorResponse, resp.body) {
			return error('OpenRouter API error [${resp.status_code}]: ${err_resp.error.message}')
		}
		return error('OpenRouter API error: ${resp.status_code} - ${resp.body}')
	}

	openrouter_resp := json.decode(OpenRouterResponse, resp.body)!

	if openrouter_resp.choices.len == 0 {
		return error('no choices in response')
	}

	choice := openrouter_resp.choices[0]
	content := choice.message.content or { '' }

	return CompletionResponse{
		id:            openrouter_resp.id
		model:         openrouter_resp.model
		content:       content
		tokens_used:   openrouter_resp.usage.total_tokens
		finish_reason: choice.finish_reason
		tool_calls:    choice.message.tool_calls
	}
}

// 发送流式补全请求
pub fn (c &OpenRouterClient) complete_stream(request CompletionRequest, callback fn (chunk CompletionChunk)) ! {
	model := if request.model.len > 0 { request.model } else { c.default_model }

	mut messages := request.messages.clone()

	if system := request.system {
		if messages.len == 0 || messages[0].role != 'system' {
			mut new_msgs := [system_message(system)]
			new_msgs << messages
			messages = new_msgs.clone()
		}
	}

	openrouter_req := OpenRouterRequest{
		model:       model
		messages:    messages
		stream:      true
		temperature: request.temperature
		max_tokens:  request.max_tokens
		top_p:       request.top_p
	}

	json_body := json.encode(openrouter_req)

	// V 0.5: 使用 http.fetch 代替 http.Client
	mut header := http.new_header()
	header.add(.content_type, 'application/json')
	header.add(.authorization, 'Bearer ${c.api_key}')

	if c.site_url.len > 0 {
		header.add_custom('HTTP-Referer', c.site_url)!
	}
	if c.site_name.len > 0 {
		header.add_custom('X-Title', c.site_name)!
	}

	resp := http.fetch(
		url:    '${c.base_url}/chat/completions'
		method: .post
		header: header
		data:   json_body
	)!

	if resp.status_code != 200 {
		return error('OpenRouter API error: ${resp.status_code}')
	}

	// 解析 SSE 流式响应
	lines := resp.body.split('\n')
	for line in lines {
		if line.starts_with('data: ') {
			data := line[6..]
			if data == '[DONE]' {
				break
			}

			stream_resp := json.decode(OpenRouterStreamResponse, data) or { continue }
			if stream_resp.choices.len > 0 {
				delta := stream_resp.choices[0].delta
				if content := delta.content {
					callback(CompletionChunk{
						id:            stream_resp.id
						model:         stream_resp.model
						content:       content
						finish_reason: stream_resp.choices[0].finish_reason
					})
				}
			}
		}
	}
}

// 获取可用模型列表
pub fn (c &OpenRouterClient) list_models() ![]ModelInfo {
	// V 0.5: 使用 http.fetch 代替 http.Client
	mut header := http.new_header()
	header.add(.authorization, 'Bearer ${c.api_key}')

	if c.site_url.len > 0 {
		header.add_custom('HTTP-Referer', c.site_url)!
	}

	resp := http.fetch(
		url:    '${c.base_url}/models'
		method: .get
		header: header
	)!

	if resp.status_code != 200 {
		return error('failed to list models: ${resp.status_code}')
	}

	models_resp := json.decode(OpenRouterModelsResponse, resp.body)!

	mut models := []ModelInfo{}
	for model in models_resp.data {
		models << ModelInfo{
			id:              model.id
			name:            model.name
			provider:        'openrouter'
			max_tokens:      model.context_length
			supports_tools:  model.id.contains('gpt-4') || model.id.contains('claude')
				|| model.id.contains('mistral')
			supports_vision: model.id.contains('vision') || model.id.contains('claude-3')
				|| model.id.contains('gpt-4o')
		}
	}

	return models
}

// 计算 token 数量（估算）
pub fn (c &OpenRouterClient) count_tokens(text string) int {
	// OpenRouter 支持多种模型，这里使用保守估算
	// 平均约 4 字符/token（英文），中文约 2 字符/token
	mut count := 0
	for ch in text {
		if ch < 128 {
			count += 1
		} else {
			count += 2
		}
	}
	return count / 4 + 1
}

// 获取请求的生成统计（OpenRouter 特有功能）
pub fn (c &OpenRouterClient) get_generation_stats(generation_id string) !GenerationStats {
	// V 0.5: 使用 http.fetch 代替 http.Client
	mut header := http.new_header()
	header.add(.authorization, 'Bearer ${c.api_key}')

	resp := http.fetch(
		url:    '${c.base_url}/generation?id=${generation_id}'
		method: .get
		header: header
	)!

	if resp.status_code != 200 {
		return error('failed to get generation stats: ${resp.status_code}')
	}

	return json.decode(GenerationStats, resp.body)!
}

// 获取当前信用余额（OpenRouter 特有功能）
pub fn (c &OpenRouterClient) get_credits() !f64 {
	// V 0.5: 使用 http.fetch 代替 http.Client
	mut header := http.new_header()
	header.add(.authorization, 'Bearer ${c.api_key}')

	resp := http.fetch(
		url:    '${c.base_url}/credits'
		method: .get
		header: header
	)!

	if resp.status_code != 200 {
		return error('failed to get credits: ${resp.status_code}')
	}

	// 解析响应
	credits_resp := json.decode(map[string]f64, resp.body) or {
		return error('failed to parse credits response')
	}

	return credits_resp['credits'] or { 0.0 }
}

// 路由策略常量
pub const route_default = ''
pub const route_fallback = 'fallback'

// 转换策略常量
pub const transform_middle_out = 'middle-out'
