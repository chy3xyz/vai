// vai.web.api - REST API 端点
// 提供 Agent 管理、对话、任务等 API
module web

import agent { AgentHub, Task }
import protocol { new_text_message }
import json
import time

// APIConfig API 配置
pub struct APIConfig {
pub mut:
	hub           &AgentHub
	auth_enabled  bool
	api_key       string
	allow_origins []string = ['*']
}

// 注册 API 路由
pub fn register_api_routes(mut router Router, mut config APIConfig) {
	// 健康检查
	router.get('/api/health', fn [mut config] (ctx Context) Response {
		return success_response('{"status":"ok","time":"' + time.now().format_rfc3339() + '"}')
	})

	// === Agent API ===

	// 获取所有 Agent
	router.get('/api/agents', fn [mut config] (ctx Context) Response {
		agents := config.hub.list_agents()
		return success_response(json.encode(agents))
	})

	// 获取特定 Agent
	router.get('/api/agents/:id', fn [mut config] (ctx Context) Response {
		agent_id := ctx.params['id']
		if agent_id.len == 0 {
			return error_response(400, 'Missing agent id')
		}
		for ag in config.hub.list_agents() {
			if ag.id == agent_id {
				return success_response(json.encode(ag))
			}
		}
		return error_response(404, 'Agent not found')
	})

	// 发送消息给 Agent
	router.post('/api/agents/:id/message', fn [mut config] (ctx Context) Response {
		agent_id := ctx.params['id']

		body := json.decode(map[string]string, ctx.body) or {
			return error_response(400, 'Invalid JSON')
		}

		content := body['message'] or { return error_response(400, 'Missing message field') }

		msg := new_text_message(content)
		config.hub.route_message('web', agent_id, msg) or {
			return error_response(500, 'Failed to send message')
		}

		return success_response('{"sent":true}')
	})

	// === Task API ===

	// 提交任务
	router.post('/api/tasks', fn [mut config] (ctx Context) Response {
		body := json.decode(map[string]string, ctx.body) or {
			return error_response(400, 'Invalid JSON')
		}

		type_ := body['type'] or { 'generic' }
		description := body['description'] or { '' }
		priority_str := body['priority'] or { '0' }
		priority := priority_str.int()

		task := Task{
			id:          generate_id()
			type_:       type_
			description: description
			priority:    priority
		}

		task_id := config.hub.submit_task(task) or {
			return error_response(500, 'Failed to submit task')
		}

		return success_response('{"task_id":"' + task_id + '","status":"submitted"}')
	})

	// 获取任务结果
	router.get('/api/tasks/:id', fn [mut config] (ctx Context) Response {
		task_id := ctx.params['id']

		if task_id.len == 0 {
			return error_response(400, 'Missing task id')
		}

		if result := config.hub.get_task_result(task_id) {
			return success_response(json.encode(result))
		}

		return error_response(404, 'Task not found or not completed')
	})

	// === Conversation API ===

	// 创建会话
	router.post('/api/conversations', fn [config] (ctx Context) Response {
		conv_id := generate_id()
		return success_response('{"conversation_id":"' + conv_id + '","created_at":"' +
			time.now().format_rfc3339() + '"}')
	})

	// 发送消息
	router.post('/api/conversations/:id/messages', fn [mut config] (ctx Context) Response {
		_ := ctx.params['id']

		body := json.decode(map[string]string, ctx.body) or {
			return error_response(400, 'Invalid JSON')
		}

		content := body['message'] or { return error_response(400, 'Missing message field') }

		msg := new_text_message(content)
		config.hub.broadcast('web', msg) or {}

		return success_response('{"message_id":"' + generate_id() + '","sent_at":"' +
			time.now().format_rfc3339() + '"}')
	})

	// === System API ===

	// 获取系统状态
	router.get('/api/status', fn [mut config] (ctx Context) Response {
		agents := config.hub.list_agents()

		mut idle_count := 0
		mut busy_count := 0

		for ag in agents {
			match ag.status {
				.idle { idle_count++ }
				.busy { busy_count++ }
				else {}
			}
		}

		return success_response('{"agents_total":' + agents.len.str() + ',"agents_idle":' +
			idle_count.str() + ',"agents_busy":' + busy_count.str() + ',"timestamp":"' +
			time.now().format_rfc3339() + '"}')
	})

	// 获取统计信息
	router.get('/api/stats', fn [mut config] (ctx Context) Response {
		return success_response('{"uptime":' + time.now().unix().str() + ',"total_agents":' +
			config.hub.list_agents().len.str() + '}')
	})

	// WebSocket 端点（用于实时通信）
	router.get('/api/ws', fn [mut config] (ctx Context) Response {
		return error_response(501, 'WebSocket not implemented in this version')
	})
}

// CORS 中间件
pub fn cors_middleware(allow_origins []string) Middleware {
	return fn [allow_origins] (mut ctx Context) bool {
		ctx.headers['Access-Control-Allow-Origin'] = allow_origins.join(', ')
		ctx.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
		ctx.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'

		if ctx.request.method == 'OPTIONS' {
			return false
		}

		return true
	}
}

// 认证中间件
pub fn auth_middleware(api_key string) Middleware {
	return fn [api_key] (mut ctx Context) bool {
		if api_key.len == 0 {
			// 如果未配置 API key，跳过认证
			return true
		}

		// 检查 Authorization header (Bearer token)
		auth_header := ctx.request.headers['authorization'] or { '' }
		if auth_header.starts_with('Bearer ') {
			token := auth_header[7..]
			if token == api_key {
				return true
			}
		}

		// 检查 X-API-Key header
		if api_key_header := ctx.request.headers['x-api-key'] {
			if api_key_header == api_key {
				return true
			}
		}

		// 认证失败
		ctx.status_code = 401
		ctx.headers['Content-Type'] = 'application/json'
		return false
	}
}

// 日志中间件
pub fn logging_middleware() Middleware {
	return fn (mut ctx Context) bool {
		start := time.now()
		result := true
		elapsed := time.since(start)
		println('[${time.now().format_rfc3339()}] ${ctx.request.method} ${ctx.request.url} - ${elapsed}')
		return result
	}
}

// 生成唯一 ID
fn generate_id() string {
	return '${time.now().unix()}_${rand_chars(8)}'
}

fn rand_chars(len int) string {
	chars := 'abcdefghijklmnopqrstuvwxyz0123456789'
	mut result := ''
	seed := time.now().unix()
	for i := 0; i < len; i++ {
		idx := (seed + i * 31) % chars.len
		result += chars[idx].ascii_str()
	}
	return result
}
