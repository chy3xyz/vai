// vai.llm.streaming - LLM 流式响应支持
// 实现 Server-Sent Events (SSE) 和流式输出
module llm

import net.http
import json
import time
import strings

// StreamHandler 流式响应处理器
pub type StreamHandler = fn (chunk StreamChunk)

// StreamChunk 流式数据块
pub struct StreamChunk {
	pub:
		index       int      // 块序号
		content     string   // 内容片段
		is_final    bool     // 是否是最后一块
		timestamp   time.Time
		model       string   // 使用的模型
}

// StreamingClient 流式客户端
pub struct StreamingClient {
	pub mut:
		base_client LLMProvider
		handler     StreamHandler
		buffer      strings.Builder
}

// 创建流式客户端
pub fn new_streaming_client(base LLMProvider, handler StreamHandler) StreamingClient {
	return StreamingClient{
		base_client: base
		handler: handler
		buffer: strings.new_builder(1024)
	}
}

// 解析 SSE 流
fn parse_sse_stream(body string, model string, handler StreamHandler) {
	lines := body.split('\n')
	mut index := 0
	
	for line in lines {
		trimmed := line.trim_space()
		
		// 跳过空行
		if trimmed.len == 0 {
			continue
		}
		
		// 跳过注释
		if trimmed.starts_with(':') {
			continue
		}
		
		// 解析 data: 行
		if trimmed.starts_with('data: ') {
			data := trimmed[6..]
			
			// 检查是否结束
			if data == '[DONE]' {
				handler(StreamChunk{
					index: index
					content: ''
					is_final: true
					timestamp: time.now()
					model: model
				})
				break
			}
			
			// 解析 JSON
			stream_resp := json.decode(OpenAIStreamResponse, data) or { continue }
			
			if stream_resp.choices.len > 0 {
				delta := stream_resp.choices[0].delta
				
				if content := delta.content {
					handler(StreamChunk{
						index: index
						content: content
						is_final: stream_resp.choices[0].finish_reason != none
						timestamp: time.now()
						model: model
					})
					index++
				}
			}
		}
	}
}

// SSEWriter SSE 响应写入器
pub struct SSEWriter {
	pub mut:
		writer  fn (string) !
		closed  bool
}

// 创建 SSE 写入器
pub fn new_sse_writer(writer fn (string) !) SSEWriter {
	return SSEWriter{
		writer: writer
		closed: false
	}
}

// 发送 SSE 事件
pub fn (mut w SSEWriter) write_event(event string, data string) ! {
	if w.closed {
		return error('writer closed')
	}
	
	mut output := ''
	
	if event.len > 0 {
		output += 'event: ${event}\n'
	}
	
	// 多行数据需要分割
	lines := data.split('\n')
	for line in lines {
		output += 'data: ${line}\n'
	}
	
	output += '\n'
	
	w.writer(output)!
}

// 发送数据
pub fn (mut w SSEWriter) write_data(data string) ! {
	w.write_event('', data)!
}

// 发送结束标记
pub fn (mut w SSEWriter) close() ! {
	w.write_event('', '[DONE]')!
	w.closed = true
}

// BufferedStream 缓冲流
pub struct BufferedStream {
	pub mut:
		chunks      []StreamChunk
		buffer_size int = 10
		handler     StreamHandler
}

// 创建缓冲流
pub fn new_buffered_stream(handler StreamHandler, buffer_size int) BufferedStream {
	return BufferedStream{
		chunks: []StreamChunk{cap: buffer_size}
		buffer_size: buffer_size
		handler: handler
	}
}

// 添加块到缓冲
pub fn (mut b BufferedStream) add_chunk(chunk StreamChunk) {
	b.chunks << chunk
	
	if b.chunks.len >= b.buffer_size || chunk.is_final {
		b.flush()
	}
}

// 刷新缓冲
pub fn (mut b BufferedStream) flush() {
	// 合并相邻的块
	if b.chunks.len == 0 {
		return
	}
	
	mut merged_content := ''
	mut is_final := false
	mut last_model := ''
	mut last_index := 0
	
	for chunk in b.chunks {
		merged_content += chunk.content
		if chunk.is_final {
			is_final = true
		}
		last_model = chunk.model
		last_index = chunk.index
	}
	
	// 发送合并后的块
	b.handler(StreamChunk{
		index: last_index
		content: merged_content
		is_final: is_final
		timestamp: time.now()
		model: last_model
	})
	
	// 清空缓冲
	b.chunks.clear()
}

// RateLimitedStream 速率限制流
pub struct RateLimitedStream {
	pub mut:
		handler     StreamHandler
		min_delay   time.Duration = 50 * time.millisecond  // 最小延迟
		last_send   time.Time
}

// 创建速率限制流
pub fn new_rate_limited_stream(handler StreamHandler, min_delay_ms int) RateLimitedStream {
	return RateLimitedStream{
		handler: handler
		min_delay: min_delay_ms * time.millisecond
		last_send: time.now()
	}
}

// 发送块（带速率限制）
pub fn (mut r RateLimitedStream) send_chunk(chunk StreamChunk) {
	now := time.now()
	elapsed := now - r.last_send
	
	if elapsed < r.min_delay {
		time.sleep(r.min_delay - elapsed)
	}
	
	r.handler(chunk)
	r.last_send = time.now()
}
