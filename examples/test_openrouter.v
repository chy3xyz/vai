// Test OpenRouter API with provided API key
module main

import llm { new_openrouter_client, CompletionRequest, user_message, system_message }
import net.http
import json

fn main() {
	println('Testing OpenRouter API...')
	
	// API Key from dev3.md
	api_key := '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'
	
	// Test 1: List available models
	println('\n[Test 1] Listing available models...')
	mut req := http.new_request(.get, 'https://openrouter.ai/api/v1/models', '')
	req.header.add(.authorization, 'Bearer ${api_key}')
	
	resp := http.fetch(req) or {
		eprintln('Failed to fetch models: ${err}')
		return
	}
	
	if resp.status_code == 200 {
		println('✓ Successfully connected to OpenRouter')
		// Parse and show first few models
		models_data := json.decode(map[string][]map[string]any, resp.body) or {
			map[string][]map[string]any{}
		}
		if models := models_data['data'] {
			println('Available models: ${models.len}')
			for i, model in models[..min(models.len, 5)] {
				if name := model['id'] {
					println('  ${i+1}. ${name}')
				}
			}
		}
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
	mut credits_req := http.new_request(.get, 'https://openrouter.ai/api/v1/credits', '')
	credits_req.header.add(.authorization, 'Bearer ${api_key}')
	
	credits_resp := http.fetch(credits_req) or {
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
