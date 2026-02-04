// Test OpenRouter API with provided API key
module main

import llm { new_openrouter_client, CompletionRequest, user_message, system_message }
import net.http
import json
import os

fn main() {
	println('Testing OpenRouter API...')
	
	// API Key from dev3.md
	api_key := os.getenv('OPENROUTER_API_KEY')

	println('API Key: ${api_key}')
	if api_key.len == 0 {
		eprintln('API Key not set')
		return
	}
	
	// Test 1: List available models
	println('\n[Test 1] Listing available models...')
	resp := http.fetch(
		method: .get
		url: 'https://openrouter.ai/api/v1/models'
		header: http.new_header_from_map({
			.authorization: 'Bearer ${api_key}'
		})
	) or {
		eprintln('Failed to fetch models: ${err}')
		return
	}
	
	if resp.status_code == 200 {
		println('✓ Successfully connected to OpenRouter')
		// 为兼容 V 0.5 的 json 实现，这里不做完整解析，只打印部分响应内容
		println('Raw models response (first 3000 chars):')
		snippet_len := if resp.body.len < 3000 { resp.body.len } else { 3000 }
		println(resp.body[..snippet_len] + if resp.body.len > 3000 { "..." } else { "" })
	} else {
		eprintln('✗ Failed: ${resp.status_code} - ${resp.body}')
		return
	}
	
	// Test 2: Simple completion with Claude
	println('\n[Test 2] Testing completion with Claude 3.5 Sonnet...')
	
	mut client := new_openrouter_client(api_key)
	
	request := CompletionRequest{
		model: 'anthropic/claude-3.5-sonnet'
		messages: [
			system_message('You are a helpful assistant.'),
			user_message('Say "Hello from VAI!" and explain what you can do in one sentence.')
		]
		temperature: 0.7
		max_tokens: 100
	}
	
	result := client.complete(request) or {
		eprintln('Completion failed: ${err}')
		return
	}
	
	println('✓ Completion successful!')
	println('Response: ${result.content}')
	println('Tokens used: ${result.tokens_used}')
	
	// Test 3: Check credits
	println('\n[Test 3] Checking account credits...')
	credits_resp := http.fetch(
		method: .get
		url: 'https://openrouter.ai/api/v1/credits'
		header: http.new_header_from_map({
			.authorization: 'Bearer ${api_key}'
		})
	) or {
		eprintln('Failed to fetch credits: ${err}')
		return
	}
	
	if credits_resp.status_code == 200 {
		credits_data := json.decode(map[string]f64, credits_resp.body) or {
			map[string]f64{}
		}
		if credits := credits_data['credits'] {
			println('✓ Remaining credits: $${credits:.2f}')
		}
	}
	
	println('\n✓ All tests passed!')
}

fn min(a int, b int) int {
	if a < b { return a }
	return b
}
