// vai.web - Web UI 服务器
// 提供 Web 界面和 REST API
module web

import net.http
import json
import time
import os

// Server Web 服务器
pub struct Server {
	pub mut:
		host       string = '0.0.0.0'
		port       int = 8080
		router     &Router
		middleware []Middleware
		static_dir string = 'static'
		running    bool
		on_start   fn ()
		on_stop    fn ()
}

// Router 路由处理器
pub struct Router {
	pub mut:
		routes     map[string]map[string]Handler  // method -> path -> handler
		not_found  Handler
		error_handler fn (Error) Response
}

// Handler 请求处理器
pub type Handler = fn (Context) Response

// Middleware 中间件
pub type Middleware = fn (Context) bool  // 返回 false 表示终止处理

// Context 请求上下文
pub struct Context {
	pub:
		request    http.Request
		params     map[string]string  // URL 参数
		query      map[string]string  // 查询参数
		body       string
	pub mut:
		status     int
		headers    map[string]string
		data       map[string]any  // 中间件数据传递
}

// Response HTTP 响应
pub struct Response {
	pub:
		status  int = 200
		headers map[string]string
		body    string
}

// Error 错误信息
pub struct Error {
	pub:
		code    int
		message string
}

// 创建 Web 服务器
pub fn new_server(host string, port int) &Server {
	mut router := &Router{
		routes: map[string]map[string]Handler{}
		not_found: default_not_found_handler
		error_handler: default_error_handler
	}
	
	return &Server{
		host: host
		port: port
		router: router
		middleware: []
		static_dir: 'static'
		running: false
		on_start: fn () {}
		on_stop: fn () {}
	}
}

// 默认 404 处理器
fn default_not_found_handler(ctx Context) Response {
	return Response{
		status: 404
		body: json.encode({
			'error': 'Not Found'
			'path': ctx.request.url
		})
	}
}

// 默认错误处理器
fn default_error_handler(err Error) Response {
	return Response{
		status: err.code
		body: json.encode({
			'error': err.message
			'code': err.code
		})
	}
}

// 注册路由
pub fn (mut r Router) register(method string, path string, handler Handler) {
	method_upper := method.to_upper()
	if method_upper !in r.routes {
		r.routes[method_upper] = map[string]Handler{}
	}
	r.routes[method_upper][path] = handler
}

// GET 路由快捷方法
pub fn (mut r Router) get(path string, handler Handler) {
	r.register('GET', path, handler)
}

// POST 路由快捷方法
pub fn (mut r Router) post(path string, handler Handler) {
	r.register('POST', path, handler)
}

// PUT 路由快捷方法
pub fn (mut r Router) put(path string, handler Handler) {
	r.register('PUT', path, handler)
}

// DELETE 路由快捷方法
pub fn (mut r Router) delete(path string, handler Handler) {
	r.register('DELETE', path, handler)
}

// 使用中间件
pub fn (mut s Server) use(mw Middleware) {
	s.middleware << mw
}

// 启动服务器
pub fn (mut s Server) start() ! {
	s.running = true
	s.on_start()
	
	// 创建 HTTP 处理器
	mut mux := http.Router{}
	
	// 注册 API 路由
	mux.route('/api/', fn [s] (mut ctx http.Context) {
		handle_api_request(s, mut ctx)
	})
	
	// 静态文件服务
	mux.route('/', fn [s] (mut ctx http.Context) {
		handle_static_request(s, mut ctx)
	})
	
	// 启动 HTTP 服务器
	addr := '${s.host}:${s.port}'
	println('Web server starting on http://${addr}')
	
	// 使用 V 的 http 模块启动服务器
	go http.start_server(mux, addr)
}

// 停止服务器
pub fn (mut s Server) stop() {
	s.running = false
	s.on_stop()
}

// 处理 API 请求
fn handle_api_request(s &Server, mut ctx http.Context) {
	method := ctx.req.method.str()
	path := ctx.req.url
	
	// 查找处理器
	if method_handlers := s.router.routes[method] {
		if handler := method_handlers[path] {
			// 构建 Context
			req_ctx := Context{
				request: ctx.req
				params: extract_params(path, ctx.req.url)
				query: parse_query(ctx.req.url)
				body: ctx.req.data
				status: 200
				headers: map[string]string{}
				data: map[string]any{}
			}
			
			// 执行中间件
			for mw in s.middleware {
				if !mw(req_ctx) {
					return
				}
			}
			
			// 执行处理器
			resp := handler(req_ctx)
			
			// 设置响应
			ctx.resp.status_code = resp.status
			for key, value in resp.headers {
				ctx.resp.header.add_custom(key, value) or {}
			}
			ctx.resp.body = resp.body
			return
		}
	}
	
	// 404
	resp := s.router.not_found(Context{
		request: ctx.req
	})
	ctx.resp.status_code = resp.status
	ctx.resp.body = resp.body
}

// 处理静态文件请求
fn handle_static_request(s &Server, mut ctx http.Context) {
	mut path := ctx.req.url
	if path == '/' {
		path = '/index.html'
	}
	
	file_path := os.join_path(s.static_dir, path)
	
	if os.exists(file_path) && os.is_file(file_path) {
		content := os.read_file(file_path) or {
			ctx.resp.status_code = 500
			ctx.resp.body = 'Internal Server Error'
			return
		}
		
		// 设置 Content-Type
		content_type := get_content_type(file_path)
		ctx.resp.header.add_custom('Content-Type', content_type) or {}
		ctx.resp.body = content
	} else {
		ctx.resp.status_code = 404
		ctx.resp.body = 'Not Found'
	}
}

// 提取 URL 参数
fn extract_params(route string, url string) map[string]string {
	// 简化实现：解析路径参数
	return map[string]string{}
}

// 解析查询参数
fn parse_query(url string) map[string]string {
	mut params := map[string]string{}
	
	if idx := url.index('?') {
		query := url[idx + 1..]
		pairs := query.split('&')
		
		for pair in pairs {
			kv := pair.split('=')
			if kv.len == 2 {
				params[kv[0]] = kv[1]
			}
		}
	}
	
	return params
}

// 获取 Content-Type
fn get_content_type(file_path string) string {
	ext := os.file_ext(file_path).to_lower()
	
	return match ext {
		'.html' { 'text/html; charset=utf-8' }
		'.css' { 'text/css; charset=utf-8' }
		'.js' { 'application/javascript; charset=utf-8' }
		'.json' { 'application/json; charset=utf-8' }
		'.png' { 'image/png' }
		'.jpg', '.jpeg' { 'image/jpeg' }
		'.gif' { 'image/gif' }
		'.svg' { 'image/svg+xml' }
		'.ico' { 'image/x-icon' }
		else { 'application/octet-stream' }
	}
}

// JSON 响应辅助函数
pub fn json_response(data any) Response {
	return Response{
		status: 200
		headers: {'Content-Type': 'application/json'}
		body: json.encode(data)
	}
}

// 成功响应
pub fn success_response(data any) Response {
	return json_response({
		'success': true
		'data': data
	})
}

// 错误响应
pub fn error_response(code int, message string) Response {
	return Response{
		status: code
		headers: {'Content-Type': 'application/json'}
		body: json.encode({
			'success': false
			'error': message
			'code': code
		})
	}
}

// HTML 响应
pub fn html_response(html string) Response {
	return Response{
		status: 200
		headers: {'Content-Type': 'text/html; charset=utf-8'}
		body: html
	}
}

// 重定向响应
pub fn redirect_response(url string) Response {
	return Response{
		status: 302
		headers: {'Location': url}
		body: ''
	}
}
