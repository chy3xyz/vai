// vai.memory.embeddings - 嵌入向量生成
// 支持本地和远程的文本嵌入服务
module memory

import net.http
import json
import llm

// Embedder 嵌入生成器接口
pub interface Embedder {
	embed(text string) ![]f32
	embed_batch(texts []string) ![][]f32
	model_name() string
	dimension() int
}

// OllamaEmbedder 使用 Ollama 生成嵌入
pub struct OllamaEmbedder {
	pub mut:
		model      string = 'nomic-embed-text'
		base_url   string = 'http://localhost:11434'
		http_client http.Client
}

// OllamaEmbeddingRequest 嵌入请求
pub struct OllamaEmbeddingRequest {
	pub:
		model string @[json: 'model']
		prompt string @[json: 'prompt']
}

// OllamaEmbeddingResponse 嵌入响应
pub struct OllamaEmbeddingResponse {
	pub:
		embedding []f32 @[json: 'embedding']
}

// 创建 Ollama 嵌入生成器
pub fn new_ollama_embedder(model string) OllamaEmbedder {
	return OllamaEmbedder{
		model: model
		base_url: 'http://localhost:11434'
	}
}

// 生成单条文本嵌入
pub fn (mut e OllamaEmbedder) embed(text string) ![]f32 {
	req := OllamaEmbeddingRequest{
		model: e.model
		prompt: text
	}
	
	json_body := json.encode(req)
	
	mut http_req := http.new_request(.post, '${e.base_url}/api/embeddings', json_body)
	http_req.header.add(.content_type, 'application/json')
	
	resp := e.http_client.do(http_req) or {
		return error('failed to generate embedding: ${err}')
	}
	
	if resp.status_code != 200 {
		return error('embedding API error: ${resp.status_code}')
	}
	
	embed_resp := json.decode(OllamaEmbeddingResponse, resp.body)!
	return embed_resp.embedding
}

// 批量生成嵌入
pub fn (mut e OllamaEmbedder) embed_batch(texts []string) ![][]f32 {
	mut results := [][]f32{}
	
	for text in texts {
		embedding := e.embed(text)!
		results << embedding
	}
	
	return results
}

// 获取模型名称
pub fn (e &OllamaEmbedder) model_name() string {
	return e.model
}

// 获取嵌入维度
pub fn (e &OllamaEmbedder) dimension() int {
	// nomic-embed-text 默认 768 维
	// mxbai-embed-large 默认 1024 维
	match e.model {
		'nomic-embed-text' { return 768 }
		'mxbai-embed-large' { return 1024 }
		'all-minilm' { return 384 }
		else { return 768 }
	}
}

// OpenAIEmbedder 使用 OpenAI API 生成嵌入
pub struct OpenAIEmbedder {
	pub mut:
		model      string = 'text-embedding-3-small'
		api_key    string
		base_url   string = 'https://api.openai.com/v1'
		http_client http.Client
}

// OpenAIEmbeddingRequest 嵌入请求
pub struct OpenAIEmbeddingRequest {
	pub:
		model string @[json: 'model']
		input string @[json: 'input']
}

// OpenAIEmbeddingResponse 嵌入响应
pub struct OpenAIEmbeddingResponse {
	pub:
		object string @[json: 'object']
		data   []EmbeddingData @[json: 'data']
		model  string @[json: 'model']
		usage  EmbeddingUsage @[json: 'usage']
}

// EmbeddingData 嵌入数据
pub struct EmbeddingData {
	pub:
		object    string @[json: 'object']
		embedding []f32  @[json: 'embedding']
		index     int    @[json: 'index']
}

// EmbeddingUsage 用量统计
pub struct EmbeddingUsage {
	pub:
		prompt_tokens int @[json: 'prompt_tokens']
		total_tokens  int @[json: 'total_tokens']
}

// 创建 OpenAI 嵌入生成器
pub fn new_openai_embedder(api_key string, model string) OpenAIEmbedder {
	return OpenAIEmbedder{
		model: model
		api_key: api_key
		base_url: 'https://api.openai.com/v1'
	}
}

// 生成单条文本嵌入
pub fn (mut e OpenAIEmbedder) embed(text string) ![]f32 {
	req := OpenAIEmbeddingRequest{
		model: e.model
		input: text
	}
	
	json_body := json.encode(req)
	
	mut http_req := http.new_request(.post, '${e.base_url}/embeddings', json_body)
	http_req.header.add(.content_type, 'application/json')
	http_req.header.add(.authorization, 'Bearer ${e.api_key}')
	
	resp := e.http_client.do(http_req) or {
		return error('failed to generate embedding: ${err}')
	}
	
	if resp.status_code != 200 {
		return error('embedding API error: ${resp.status_code}')
	}
	
	embed_resp := json.decode(OpenAIEmbeddingResponse, resp.body)!
	
	if embed_resp.data.len == 0 {
		return error('no embedding data in response')
	}
	
	return embed_resp.data[0].embedding
}

// 批量生成嵌入
pub fn (mut e OpenAIEmbedder) embed_batch(texts []string) ![][]f32 {
	// OpenAI 支持批量请求，这里简化处理
	req := struct {
		model string   @[json: 'model']
		input []string @[json: 'input']
	}{
		model: e.model
		input: texts
	}
	
	json_body := json.encode(req)
	
	mut http_req := http.new_request(.post, '${e.base_url}/embeddings', json_body)
	http_req.header.add(.content_type, 'application/json')
	http_req.header.add(.authorization, 'Bearer ${e.api_key}')
	
	resp := e.http_client.do(http_req)!
	
	if resp.status_code != 200 {
		return error('embedding API error: ${resp.status_code}')
	}
	
	embed_resp := json.decode(OpenAIEmbeddingResponse, resp.body)!
	
	mut results := [][]f32{}
	for data in embed_resp.data {
		results << data.embedding
	}
	
	return results
}

// 获取模型名称
pub fn (e &OpenAIEmbedder) model_name() string {
	return e.model
}

// 获取嵌入维度
pub fn (e &OpenAIEmbedder) dimension() int {
	match e.model {
		'text-embedding-3-small' { return 1536 }
		'text-embedding-3-large' { return 3072 }
		'text-embedding-ada-002' { return 1536 }
		else { return 1536 }
	}
}

// SimpleMemoryIndex 简单的内存向量索引
pub struct SimpleMemoryIndex {
	pub mut:
		embedder  Embedder
		store     Store
		dimension int
}

// Document 文档
pub struct Document {
	pub:
		id      string
		content string
		metadata map[string]any
}

// 创建简单内存索引
pub fn new_simple_index(embedder Embedder, store Store) SimpleMemoryIndex {
	return SimpleMemoryIndex{
		embedder: embedder
		store: store
		dimension: embedder.dimension()
	}
}

// 添加文档
pub fn (mut idx SimpleMemoryIndex) add_document(doc Document) ! {
	// 生成嵌入
	embedding := idx.embedder.embed(doc.content)!
	
	// 存储向量
	metadata := doc.metadata.clone()
	metadata['content'] = doc.content
	
	idx.store.store_vector(doc.id, embedding, metadata)!
}

// 搜索文档
pub fn (mut idx SimpleMemoryIndex) search(query string, top_k int) []VectorSearchResult {
	// 生成查询嵌入
	query_embedding := idx.embedder.embed(query) or {
		eprintln('Failed to generate query embedding: ${err}')
		return []
	}
	
	// 搜索向量
	return idx.store.search_vectors(query_embedding, top_k)
}

// 添加多条文档
pub fn (mut idx SimpleMemoryIndex) add_documents(docs []Document) ! {
	for doc in docs {
		idx.add_document(doc)!
	}
}

// 归一化向量
pub fn normalize_vector(vector []f32) []f32 {
	mut sum := f32(0.0)
	for v in vector {
		sum += v * v
	}
	
	if sum == 0.0 {
		return vector.clone()
	}
	
	norm := f32(math.sqrt(f64(sum)))
	mut result := []f32{cap: vector.len}
	
	for v in vector {
		result << v / norm
	}
	
	return result
}

import math
