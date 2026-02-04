// vai.llm.ollama - Ollama 本地模型客户端
module llm

import net.http
import json

// OllamaClient Ollama 客户端
pub struct OllamaClient {
	BaseClient
}

// OllamaRequest Ollama API 请求格式
pub struct OllamaRequest {
	pub:
		model    string    @[json: 'model']
		messages []Message @[json: 'messages']
		stream   bool      @[json: 'stream']
		options  ?OllamaOptions @[json: 'options'; omitempty]
}

// OllamaOptions Ollama 生成选项
pub struct OllamaOptions {
	pub:
		temperature f32  @[json: 'temperature'; omitempty]
		top_p       f32  @[json: 'top_p'; omitempty]
		num_predict ?int @[json: 'num_predict'; omitempty]
}

// OllamaResponse Ollama API 响应格式
pub struct OllamaResponse {
	pub:
		model     string @[json: 'model']
		created_at string @[json: 'created_at']
		message   OllamaMessage @[json: 'message']
		done      bool   @[json: 'done']
		done_reason ?string @[json: 'done_reason'; omitempty]
		prompt_eval_count int @[json: 'prompt_eval_count']
		eval_count int @[json: 'eval_count']
}

// OllamaMessage Ollama 消息格式
pub struct OllamaMessage {
	pub:
		role    string @[json: 'role']
		content string @[json: 'content']
}

// OllamaGenerateRequest 生成请求（简化 API）
pub struct OllamaGenerateRequest {
	pub:
		model  string @[json: 'model']
		prompt string @[json: 'prompt']
		stream bool   @[json: 'stream']
}

// OllamaGenerateResponse 生成响应
pub struct OllamaGenerateResponse {
	pub:
		model     string @[json: 'model']
		created_at string @[json: 'created_at']
		response  string @[json: 'response']
		done      bool   @[json: 'done']
		context   []int  @[json: 'context']
}

// OllamaModel Ollama 模型信息
pub struct OllamaModel {
	pub:
		name       string @[json: 'name']
		model      string @[json: 'model']
		modified_at string @[json: 'modified_at']
		size       i64    @[json: 'size']
		digest     string @[json: 'digest']
		details    OllamaModelDetails @[json: 'details']
}

// OllamaModelDetails 模型详情
pub struct OllamaModelDetails {
	pub:
		format            string @[json: 'format']
		family            string @[json: 'family']
		families          []string @[json: 'families']
		parameter_size    string @[json: 'parameter_size']
		quantization_level string @[json: 'quantization_level']
}

// OllamaModelsResponse 模型列表响应
pub struct OllamaModelsResponse {
	pub:
		models []OllamaModel @[json: 'models']
}

// OllamaEmbeddingResponse 嵌入向量响应
pub struct OllamaEmbeddingResponse {
	pub:
		embedding []f64 @[json: 'embedding']
}

// 创建 Ollama 客户端
pub fn new_ollama_client() &OllamaClient {
	return new_ollama_client_with_url('http://localhost:11434')
}

// 创建指定 URL 的 Ollama 客户端
pub fn new_ollama_client_with_url(base_url string) &OllamaClient {
	mut client := &OllamaClient{
		BaseClient: new_base_client('', base_url)
	}
	client.default_model = 'llama3.2'
	return client
}

// 获取提供商名称
pub fn (c &OllamaClient) name() string {
	return 'ollama'
}

// 发送补全请求
pub fn (c &OllamaClient) complete(request CompletionRequest) !CompletionResponse {
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
	
	options := OllamaOptions{
		temperature: request.temperature
		top_p: request.top_p
		num_predict: request.max_tokens
	}
	
	ollama_req := OllamaRequest{
		model: model
		messages: messages
		stream: false
		options: options
	}
	
	json_body := json.encode(ollama_req)
	
	// V 0.5: 使用 http.fetch 代替 http.Client
	mut header := http.new_header()
	header.add(.content_type, 'application/json')
	
	resp := http.fetch(
		url: '${c.base_url}/api/chat'
		method: .post
		header: header
		data: json_body
	)!
	
	if resp.status_code != 200 {
		return error('Ollama API error: ${resp.status_code} - ${resp.body}')
	}
	
	ollama_resp := json.decode(OllamaResponse, resp.body)!
	
	return CompletionResponse{
		id: '${ollama_resp.model}_${ollama_resp.created_at}'
		model: ollama_resp.model
		content: ollama_resp.message.content
		tokens_used: ollama_resp.prompt_eval_count + ollama_resp.eval_count
		finish_reason: ollama_resp.done_reason or { if ollama_resp.done { 'stop' } else { '' } }
	}
}

// 发送流式补全请求
pub fn (c &OllamaClient) complete_stream(request CompletionRequest, callback fn (chunk CompletionChunk)) ! {
	model := if request.model.len > 0 { request.model } else { c.default_model }
	
	mut messages := request.messages.clone()
	
	if system := request.system {
		if messages.len == 0 || messages[0].role != 'system' {
			mut new_msgs := [system_message(system)]
			new_msgs << messages
			messages = new_msgs.clone()
		}
	}
	
	options := OllamaOptions{
		temperature: request.temperature
		top_p: request.top_p
		num_predict: request.max_tokens
	}
	
	ollama_req := OllamaRequest{
		model: model
		messages: messages
		stream: true
		options: options
	}
	
	json_body := json.encode(ollama_req)
	
	// V 0.5: 使用 http.fetch 代替 http.Client
	mut header := http.new_header()
	header.add(.content_type, 'application/json')
	
	resp := http.fetch(
		url: '${c.base_url}/api/chat'
		method: .post
		header: header
		data: json_body
	)!
	
	if resp.status_code != 200 {
		return error('Ollama API error: ${resp.status_code}')
	}
	
	// 解析 NDJSON 响应
	lines := resp.body.split('\n')
	for line in lines {
		if line.trim_space().len == 0 {
			continue
		}
		
		chunk_resp := json.decode(OllamaResponse, line) or { continue }
		
		callback(CompletionChunk{
			id: '${chunk_resp.model}_${chunk_resp.created_at}'
			model: chunk_resp.model
			content: chunk_resp.message.content
			finish_reason: if chunk_resp.done { 'stop' } else { none }
		})
		
		if chunk_resp.done {
			break
		}
	}
}

// 获取可用模型列表
pub fn (c &OllamaClient) list_models() ![]ModelInfo {
	// V 0.5: 使用 http.fetch 代替 http.Client
	resp := http.fetch(
		url: '${c.base_url}/api/tags'
		method: .get
	)!
	
	if resp.status_code != 200 {
		return error('failed to list models: ${resp.status_code}')
	}
	
	models_resp := json.decode(OllamaModelsResponse, resp.body)!
	
	mut models := []ModelInfo{}
	for model in models_resp.models {
		models << ModelInfo{
			id: model.model
			name: model.name
			provider: 'ollama'
			max_tokens: 32768  // 默认上下文长度
			supports_tools: model.details.family.contains('llama3') || model.details.family.contains('mistral')
			supports_vision: model.name.contains('vision') || model.name.contains('llava')
		}
	}
	
	return models
}

// 计算 token 数量（简化估算）
pub fn (c &OllamaClient) count_tokens(text string) int {
	// 与 OpenAI 相同的估算方法
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

// 拉取模型
pub fn (c &OllamaClient) pull_model(model_name string) ! {
	json_body := '{"name": "${model_name}"}'
	
	// V 0.5: 使用 http.fetch 代替 http.Client
	mut header := http.new_header()
	header.add(.content_type, 'application/json')
	
	resp := http.fetch(
		url: '${c.base_url}/api/pull'
		method: .post
		header: header
		data: json_body
	)!
	
	if resp.status_code != 200 {
		return error('failed to pull model: ${resp.status_code}')
	}
}

// 生成嵌入向量
pub fn (c &OllamaClient) embeddings(model string, prompt string) ![]f32 {
	json_body := '{"model": "${model}", "prompt": "${prompt}"}'
	
	// V 0.5: 使用 http.fetch 代替 http.Client
	mut header := http.new_header()
	header.add(.content_type, 'application/json')
	
	resp := http.fetch(
		url: '${c.base_url}/api/embeddings'
		method: .post
		header: header
		data: json_body
	)!
	
	if resp.status_code != 200 {
		return error('failed to get embeddings: ${resp.status_code}')
	}
	
	// 解析嵌入向量
	// V 0.5: 使用具体结构体代替 json.Any
	embeddings_resp := json.decode(OllamaEmbeddingResponse, resp.body)!
	
	// 尝试解析为数组
	mut result := []f32{}
	for v in embeddings_resp.embedding {
		result << f32(v)
	}
	
	return result
}
