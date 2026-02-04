// VAI Telegram Bot Example
// 演示如何创建 Telegram 机器人
module main

import gateway { new_telegram_adapter }
import protocol { new_text_message }
import time
import os

fn main() {
	println('=== VAI Telegram Bot Example ===\\n')
	
	// 从环境变量获取 Bot Token
	bot_token := os.getenv('TELEGRAM_BOT_TOKEN')
	if bot_token.len == 0 {
		eprintln('Error: TELEGRAM_BOT_TOKEN environment variable not set')
		eprintln('')
		eprintln('To create a Telegram bot:')
		eprintln('1. Message @BotFather on Telegram')
		eprintln('2. Create a new bot with /newbot')
		eprintln('3. Copy the token and set it:')
		eprintln('   export TELEGRAM_BOT_TOKEN=your_token_here')
		exit(1)
	}
	
	// 创建 Telegram 适配器
	mut telegram := new_telegram_adapter(bot_token)
	
	// 连接到 Telegram
	println('Connecting to Telegram...')
	telegram.connect() or {
		eprintln('Failed to connect: ${err}')
		exit(1)
	}
	
	println('✓ Connected to Telegram!')
	println('\\nBot is running. Send messages to your bot on Telegram.')
	println('Press Ctrl+C to stop.\\n')
	
	// 设置消息处理器
	telegram.set_message_handler(fn (msg protocol.Message) {
		if text := msg.text() {
			println('[${msg.sender_id}] ${text}')
			
			// 简单的回声回复
			reply_text := 'Echo: ${text}'
			reply := new_text_message(reply_text)
			reply.receiver_id = msg.sender_id
			
			// 发送回复
			// 注意：需要可变引用才能发送
		}
	})
	
	// 接收循环
	for telegram.is_connected() {
		msg := telegram.receive_message() or {
			// 没有新消息或出错
			time.sleep(100 * time.millisecond)
			continue
		}
		
		// 处理消息
		if text := msg.text() {
			println('[${msg.sender_id}] ${text}')
			
			// 回声回复
			reply := new_text_message('You said: ${text}')
			reply.receiver_id = msg.sender_id
			reply.platform = 'telegram'
			
			// 这里简化处理，实际应该存储并异步发送
		}
	}
}
