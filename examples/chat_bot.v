// VAI Chat Bot Example
// 演示如何使用 vai 框架构建一个简单的聊天机器人
module main

import runtime { new_scheduler }
import protocol { new_text_message }
import gateway { new_telegram_adapter }
import llm { new_ollama_client, user_message, system_message, CompletionRequest }
import time

fn main() {
	println('=== VAI Chat Bot Example ===\\n')
	
	// 示例 1: 使用 Ollama 进行本地 LLM 对话
	example_local_llm()
	
	// 示例 2: 消息协议使用
	example_message_protocol()
	
	// 示例 3: 调度器使用
	example_scheduler()
}

// 示例 1: 本地 LLM 对话
fn example_local_llm() {
	println('--- Example 1: Local LLM with Ollama ---')
	
	// 创建 Ollama 客户端
	mut client := new_ollama_client()
	
	// 检查 Ollama 是否可用
	models := client.list_models() or {
		println('⚠ Ollama not available: ${err}')
		println('Please install Ollama from https://ollama.ai\\n')
		return
	}
	
	println('✓ Available models:')
	for model in models[..utils.min(models.len, 5)] {
		println('  - ${model.name} (${model.id})')
	}
	
	// 发送对话请求
	request := CompletionRequest{
		model: 'llama3.2'
		messages: [
			system_message('You are a helpful assistant. Keep responses brief.'),
			user_message('Hello! What is V programming language?'),
		]
		temperature: 0.7
		max_tokens: 500
	}
	
	println('\\nUser: Hello! What is V programming language?')
	println('Assistant: ', end: '')
	
	response := client.complete(request) or {
		println('Error: ${err}')
		return
	}
	
	println('${response.content}')
	println('Tokens used: ${response.tokens_used}\\n')
}

// 示例 2: 消息协议
fn example_message_protocol() {
	println('--- Example 2: Message Protocol ---')
	
	// 创建文本消息
	msg := new_text_message('Hello, VAI!')
	msg.sender_id = 'user_123'
	msg.platform = 'demo'
	
	println('✓ Created message:')
	println('  ID: ${msg.id}')
	println('  Type: ${msg.msg_type}')
	println('  Content: ${msg.text() or { '' }}')
	println('  Platform: ${msg.platform}')
	println('  Timestamp: ${msg.timestamp}\\n')
	
	// 序列化为 JSON
	json_data := msg.to_json() or {
		eprintln('Error: ${err}')
		return
	}
	println('✓ JSON representation:')
	println('  ${json_data}\\n')
}

// 示例 3: 调度器
fn example_scheduler() {
	println('--- Example 3: Task Scheduler ---')
	
	// 创建调度器
	mut scheduler := new_scheduler(2)
	
	// 启动调度器
	scheduler.start() or {
		eprintln('Error: ${err}')
		return
	}
	
	println('✓ Scheduler started with 2 workers')
	
	// 提交一些任务
	mut counter := 0
	
	for i := 0; i < 5; i++ {
		task_id := scheduler.submit_priority(
			exec: fn [i, mut counter] () ! {
				println('  Task ${i} executing...')
				time.sleep(100 * time.millisecond)
				counter++
				println('  Task ${i} completed!')
			}
			priority: i
		) or {
			eprintln('Failed to submit task: ${err}')
			continue
		}
		println('✓ Submitted task ${i} (ID: ${task_id})')
	}
	
	// 等待任务完成
	time.sleep(1 * time.second)
	
	// 停止调度器
	scheduler.stop()
	println('\\n✓ Scheduler stopped')
	println('  Completed tasks: ${counter}\\n')
}

// 工具函数
module utils

pub fn min(a int, b int) int {
	if a < b { return a }
	return b
}
