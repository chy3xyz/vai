// VAI Chat Bot Example
// 演示如何使用 vai 框架构建一个简单的聊天机器人
module main

import scheduler { new_scheduler }
import protocol { new_text_message }
import llm { new_openrouter_client, CompletionRequest, user_message, system_message }
import time
import os

fn main() {
	println('=== VAI Chat Bot Example ===\\n')
	
	// 示例 1: 使用 OpenRouter 进行对话
	example_openrouter_llm()
	
	// 示例 2: 消息协议使用
	example_message_protocol()
	
	// 示例 3: 调度器使用
	example_scheduler()
}

// 示例 1: 使用 OpenRouter 进行对话
fn example_openrouter_llm() {
	println('--- Example 1: Chat with OpenRouter ---')
	
	api_key := os.getenv('OPENROUTER_API_KEY')
	if api_key.len == 0 {
		println('⚠ OPENROUTER_API_KEY not set, please export it first.')
		println('   export OPENROUTER_API_KEY=your_key_here\\n')
		return
	}
	
	mut client := new_openrouter_client(api_key)
	
	// 构造补全请求
	request := CompletionRequest{
		model: 'anthropic/claude-3.5-sonnet'
		messages: [
			system_message('You are a helpful assistant. Keep responses brief.'),
			user_message('Hello! What is V programming language?'),
		]
		temperature: 0.7
		max_tokens: 200
	}
	
	println('\\nUser: Hello! What is V programming language?')
	print('Assistant: ')
	
	response := client.complete(request) or {
		println('Error: ${err}')
		return
	}
	
	println(response.content)
	println('Tokens used: ${response.tokens_used}\\n')
}

// 示例 2: 消息协议
fn example_message_protocol() {
	println('--- Example 2: Message Protocol ---')
	
	// 创建文本消息
	mut msg := new_text_message('Hello, VAI!')
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
	mut sched := new_scheduler(2)
	
	// 启动调度器
	sched.start() or {
		eprintln('Error: ${err}')
		return
	}
	
	println('✓ Scheduler started with 2 workers')
	
	// 提交一些任务
	mut counter := 0
	
	for i := 0; i < 5; i++ {
		task_id := sched.submit_priority(
			fn [i, mut counter] () ! {
				println('  Task ${i} executing...')
				time.sleep(100 * time.millisecond)
				counter++
				println('  Task ${i} completed!')
			},
			i
		) or {
			eprintln('Failed to submit task: ${err}')
			continue
		}
		println('✓ Submitted task ${i} (ID: ${task_id})')
	}
	
	// 等待任务完成
	time.sleep(1 * time.second)
	
	// 停止调度器
	sched.stop()
	println('\\n✓ Scheduler stopped')
	println('  Completed tasks: ${counter}\\n')
}
