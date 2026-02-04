// vai.web - Web UI 服务器
// 提供 Web 界面和 REST API
module web

import json
import os
import net
import time

// Request HTTP 请求（简化版）
pub struct Request {
	pub:
		method string
		url    string
		data   string
}

// Response HTTP 响应
pub struct Response {
	pub:
		status_code  int = 200
		headers map[string]string
		body    string
}

// Server Web 服务器
pub struct Server {
	pub mut:
		host       string = '0.0.0.0'
		port       int = 8080
		router     &Router
		middleware []Middleware
		static_dir string = 'static'
		running    bool
		on_start   fn () = unsafe { nil }
		on_stop    fn () = unsafe { nil }
		listener   net.TcpListener
}

// Router 路由处理器
pub struct Router {
	pub mut:
		routes     map[string]map[string]Handler
		not_found  Handler = unsafe { nil }
		error_handler fn (WebError) Response = unsafe { nil }
}

// Handler 请求处理器
pub type Handler = fn (Context) Response

// Middleware 中间件
pub type Middleware = fn (mut Context) bool

// Context 请求上下文
pub struct Context {
	pub:
		request    Request
		params     map[string]string
		query      map[string]string
		body       string
	pub mut:
		status_code int
		headers    map[string]string
		data       map[string]string
}

// WebError 错误信息
pub struct WebError {
	pub:
		error_code    int
		error_message string
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
		listener: net.TcpListener{}
	}
}

// 默认 404 处理器
fn default_not_found_handler(ctx Context) Response {
	return Response{
		status_code: 404
		body: json.encode({
			'error': 'Not Found'
			'path': ctx.request.url
		})
	}
}

// 默认错误处理器
fn default_error_handler(err WebError) Response {
	return Response{
		status_code: err.error_code
		body: json.encode({
			'error': err.error_message
			'code': err.error_code.str()
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

// 处理请求
fn (mut s Server) handle_request(req Request) Response {
	if !req.url.starts_with('/api/') {
		return s.handle_static(req)
	}
	return s.handle_api(req)
}

fn (mut s Server) handle_api(req Request) Response {
	method := req.method
	path := req.url
	
	if method_handlers := s.router.routes[method] {
		if handler := method_handlers[path] {
			mut req_ctx := Context{
				request: req
				params: extract_params(path, req.url)
				query: parse_query(req.url)
				body: req.data
				status_code: 200
				headers: map[string]string{}
				data: map[string]string{}
			}
			
			for mw in s.middleware {
				if !mw(mut req_ctx) {
					return Response{
						status_code: req_ctx.status_code
						headers: req_ctx.headers.clone()
						body: ''
					}
				}
			}
			
			return handler(req_ctx)
		}
	}
	
	return s.router.not_found(Context{
		request: req
	})
}

fn (mut s Server) handle_static(req Request) Response {
	mut path := req.url
	if path == '/' {
		path = '/index.html'
	}
	
	file_path := os.join_path(s.static_dir, path)
	
	if os.exists(file_path) && os.is_file(file_path) {
		content := os.read_file(file_path) or {
			return Response{
				status_code: 500
				body: 'Internal Server Error'
			}
		}
		
		content_type := get_content_type(file_path)
		mut headers := map[string]string{}
		headers['Content-Type'] = content_type
		
		return Response{
			status_code: 200
			headers: headers
			body: content
		}
	} else {
		return Response{
			status_code: 404
			body: 'Not Found'
		}
	}
}

// 启动服务器 - 简化版，使用 TCP listener
pub fn (mut s Server) start() ! {
	s.running = true
	s.on_start()
	
	addr := '${s.host}:${s.port}'
	println('Web server starting on http://${addr}')
	
	// 创建 TCP listener
	mut listener := net.listen_tcp(.ip, '${s.host}:${s.port}', net.ListenOptions{})!
	s.listener = listener
	
	// 在后台接受连接
	spawn fn (mut srv Server) {
		for srv.running {
			mut conn := srv.listener.accept() or {
				time.sleep(100 * time.millisecond)
				continue
			}
			// 简化处理：直接返回简单响应
			response := 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nVAI Web Server\n'
			conn.write(response.bytes()) or {}
			conn.close() or {}
		}
	}(mut s)
}

// 停止服务器
pub fn (mut s Server) stop() {
	s.running = false
	s.on_stop()
	s.listener.close() or {}
}

// 提取 URL 参数
fn extract_params(route string, url string) map[string]string {
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
pub fn json_response(json_body string) Response {
	return Response{
		status_code: 200
		headers: {'Content-Type': 'application/json'}
		body: json_body
	}
}

// 成功响应
pub fn success_response(data string) Response {
	return json_response('{"success":true,"data":' + data + '}')
}

// 错误响应
pub fn error_response(code int, message string) Response {
	escaped := message.replace('"', '\\"')
	return Response{
		status_code: code
		headers: {'Content-Type': 'application/json'}
		body: '{"success":false,"error":"' + escaped + '","code":' + code.str() + '}'
	}
}

// HTML 响应
pub fn html_response(html string) Response {
	return Response{
		status_code: 200
		headers: {'Content-Type': 'text/html; charset=utf-8'}
		body: html
	}
}

// 重定向响应
pub fn redirect_response(url string) Response {
	return Response{
		status_code: 302
		headers: {'Location': url}
		body: ''
	}
}
