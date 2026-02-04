// vai.web.api - REST API 端点
// 提供 Agent 管理、对话、任务等 API
module web

import agent { AgentHub, AgentInfo, Task }
import protocol { Message, new_text_message }
import json
import time

// APIConfig API 配置
pub struct APIConfig {
	pub mut:
		hub           &AgentHub
		auth_enabled  bool = false
		api_key       string
		allow_origins []string = ['*']
}

// 注册 API 路由
pub fn register_api_routes(mut router Router, config APIConfig) {
	// 健康检查
	router.get('/api/health', fn [config] (ctx Context) Response {
		return json_response({
			'status': 'ok'
			'time': time.now().format_rfc3339()
		})
	})
	
	// === Agent API ===
	
	// 获取所有 Agent
	router.get('/api/agents', fn [config] (ctx Context) Response {
		agents := config.hub.list_agents()
		return success_response(agents)
	})
	
	// 获取特定 Agent
	router.get('/api/agents/:id', fn [config] (ctx Context) Response {
		agent_id := ctx.params['id']
		for agent in config.hub.list_agents() {
			if agent.id == agent_id {
				return success_response(agent)
			}
		}
		return error_response(404, 'Agent not found')
	})
	
	// 发送消息给 Agent
	router.post('/api/agents/:id/message', fn [config] (ctx Context) Response {
		agent_id := ctx.params['id']
		
		// 解析请求体
		body := json.decode(map[string]string, ctx.body) or {
			return error_response(400, 'Invalid JSON')
		}
		
		content := body['message'] or {
			return error_response(400, 'Missing message field')
		}
		
		msg := new_text_message(content)
		config.hub.route_message('web', agent_id, msg) or {
			return error_response(500, 'Failed to send message')
		}
		
		return success_response({'sent': true})
	})
	
	// === Task API ===
	
	// 提交任务
	router.post('/api/tasks', fn [config] (ctx Context) Response {
		// 解析任务
		body := json.decode(map[string]any, ctx.body) or {
			return error_response(400, 'Invalid JSON')
		}
		
		task := Task{
			id: generate_id()
			type_: body['type'] or { 'generic' }.str()
			description: body['description'] or { '' }.str()
			input_data: body['input'] or { map[string]any{} } as map[string]any
			priority: body['priority'] or { 0 }.int()
		}
		
		task_id := config.hub.submit_task(task) or {
			return error_response(500, 'Failed to submit task')
		}
		
		return success_response({
			'task_id': task_id
			'status': 'submitted'
		})
	})
	
	// 获取任务结果
	router.get('/api/tasks/:id', fn [config] (ctx Context) Response {
		task_id := ctx.params['id']
		
		if result := config.hub.get_task_result(task_id) {
			return success_response(result)
		}
		
		return error_response(404, 'Task not found or not completed')
	})
	
	// === Conversation API ===
	
	// 创建会话
	router.post('/api/conversations', fn [config] (ctx Context) Response {
		conv_id := generate_id()
		return success_response({
			'conversation_id': conv_id
			'created_at': time.now().format_rfc3339()
		})
	})
	
	// 发送消息
	router.post('/api/conversations/:id/messages', fn [config] (ctx Context) Response {
		conv_id := ctx.params['id']
		
		body := json.decode(map[string]string, ctx.body) or {
			return error_response(400, 'Invalid JSON')
		}
		
		content := body['message'] or {
			return error_response(400, 'Missing message field')
		}
		
		// 广播给所有 Agent
		msg := new_text_message(content)
		config.hub.broadcast('web', msg) or {}
		
		return success_response({
			'message_id': generate_id()
			'sent_at': time.now().format_rfc3339()
		})
	})
	
	// === System API ===
	
	// 获取系统状态
	router.get('/api/status', fn [config] (ctx Context) Response {
		agents := config.hub.list_agents()
		
		mut online_count := 0
		mut busy_count := 0
		
		for agent in agents {
			match agent.status {
				.online { online_count++ }
				.busy { busy_count++ }
				else {}
			}
		}
		
		return success_response({
			'agents_total': agents.len
			'agents_online': online_count
			'agents_busy': busy_count
			'timestamp': time.now().format_rfc3339()
		})
	})
	
	// 获取统计信息
	router.get('/api/stats', fn [config] (ctx Context) Response {
		return success_response({
			'uptime': time.now().unix
			'total_agents': config.hub.list_agents().len
		})
	})
	
	// WebSocket 端点（用于实时通信）
	router.get('/api/ws', fn [config] (ctx Context) Response {
		// WebSocket 处理
		// 需要 net.websocket 支持
		return error_response(501, 'WebSocket not implemented in this version')
	})
}

// CORS 中间件
pub fn cors_middleware(allow_origins []string) Middleware {
	return fn [allow_origins] (ctx Context) bool {
		// 设置 CORS 头
		ctx.headers['Access-Control-Allow-Origin'] = allow_origins.join(', ')
		ctx.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
		ctx.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
		
		// 处理预检请求
		if ctx.request.method == .options {
			return false  // 终止处理，返回 CORS 头
		}
		
		return true
	}
}

// 认证中间件
pub fn auth_middleware(api_key string) Middleware {
	return fn [api_key] (ctx Context) bool {
		// 从 Header 获取认证信息
		auth := ctx.request.header.get(.authorization) or {
			ctx.status = 401
			return false
		}
		
		// 验证 API Key
		if auth != 'Bearer ${api_key}' {
			ctx.status = 403
			return false
		}
		
		return true
	}
}

// 日志中间件
pub fn logging_middleware() Middleware {
	return fn (ctx Context) bool {
		start := time.now()
		
		// 继续处理
		result := true
		
		elapsed := time.since(start)
		println('[${time.now().format_rfc3339()}] ${ctx.request.method} ${ctx.request.url} - ${elapsed}')
		
		return result
	}
}

// 生成唯一 ID
fn generate_id() string {
	return '${time.now().unix}_${rand_chars(8)}'
}

fn rand_chars(len int) string {
	chars := 'abcdefghijklmnopqrstuvwxyz0123456789'
	mut result := ''
	seed := time.now().unix
	for i := 0; i < len; i++ {
		idx := (seed + i * 31) % chars.len
		result += chars[idx].ascii_str()
	}
	return result
}
