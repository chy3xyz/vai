// vai.web - Web UI 服务器
// 提供 Web 界面和 REST API
module web

import json
import os
import net
import time

// Request HTTP 请求
pub struct Request {
pub:
	method  string
	url     string
	data    string
	headers map[string]string
}

// Response HTTP 响应
pub struct Response {
pub:
	status_code int = 200
	headers     map[string]string
	body        string
}

// Server Web 服务器
pub struct Server {
pub mut:
	host       string = '0.0.0.0'
	port       int    = 8080
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
	routes        map[string]map[string]Handler
	not_found     Handler                = unsafe { nil }
	error_handler fn (WebError) Response = unsafe { nil }
}

// Handler 请求处理器
pub type Handler = fn (Context) Response

// Middleware 中间件
pub type Middleware = fn (mut Context) bool

// Context 请求上下文
pub struct Context {
pub:
	request Request
	params  map[string]string
	query   map[string]string
	body    string
pub mut:
	status_code int
	headers     map[string]string
	data        map[string]string
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
		routes:        map[string]map[string]Handler{}
		not_found:     default_not_found_handler
		error_handler: default_error_handler
	}

	return &Server{
		host:       host
		port:       port
		router:     router
		middleware: []
		static_dir: 'static'
		running:    false
		on_start:   fn () {}
		on_stop:    fn () {}
		listener:   net.TcpListener{}
	}
}

// 默认 404 处理器
fn default_not_found_handler(ctx Context) Response {
	return Response{
		status_code: 404
		body:        json.encode({
			'error': 'Not Found'
			'path':  ctx.request.url
		})
	}
}

// 默认错误处理器
fn default_error_handler(err WebError) Response {
	return Response{
		status_code: err.error_code
		body:        json.encode({
			'error': err.error_message
			'code':  err.error_code.str()
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

// RouteMatch 路由匹配结果
struct RouteMatch {
	handler Handler = unsafe { nil }
	params  map[string]string
}

// 匹配路由（支持 :param 模式）
fn (mut s Server) match_route(method string, path string) ?RouteMatch {
	if method_handlers := s.router.routes[method] {
		// 先尝试精确匹配
		if handler := method_handlers[path] {
			return RouteMatch{
				handler: handler
				params:  map[string]string{}
			}
		}

		// 尝试模式匹配（:param）
		for pattern, handler in method_handlers {
			if !pattern.contains(':') {
				continue
			}

			params := extract_params(pattern, path)
			// 如果提取到了参数，说明匹配成功
			if params.len > 0 {
				return RouteMatch{
					handler: handler
					params:  params
				}
			}
		}
	}
	return none
}

// 处理请求
fn (mut s Server) handle_request(req Request) Response {
	method := req.method
	path := strip_query(req.url)

	// 尝试匹配路由（精确或模式匹配）
	if result := s.match_route(method, path) {
		handler := result.handler
		params := result.params.clone()
		mut req_ctx := Context{
			request:     req
			params:      params
			query:       parse_query(req.url)
			body:        req.data
			status_code: 200
			headers:     map[string]string{}
			data:        map[string]string{}
		}

		for mw in s.middleware {
			if !mw(mut req_ctx) {
				return Response{
					status_code: req_ctx.status_code
					headers:     req_ctx.headers.clone()
					body:        ''
				}
			}
		}

		return handler(req_ctx)
	}

	// /api/ 走 API，其他走静态文件
	if req.url.starts_with('/api/') {
		return s.handle_api(req)
	}
	return s.handle_static(req)
}

fn (mut s Server) handle_api(req Request) Response {
	method := req.method
	path := strip_query(req.url)

	// 使用统一的路由匹配
	if result := s.match_route(method, path) {
		handler := result.handler
		params := result.params.clone()
		mut req_ctx := Context{
			request:     req
			params:      params
			query:       parse_query(req.url)
			body:        req.data
			status_code: 200
			headers:     map[string]string{}
			data:        map[string]string{}
		}

		for mw in s.middleware {
			if !mw(mut req_ctx) {
				return Response{
					status_code: req_ctx.status_code
					headers:     req_ctx.headers.clone()
					body:        ''
				}
			}
		}

		return handler(req_ctx)
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

	// os.join_path 遇到以 '/' 开头的 path 可能会忽略前缀目录
	// 这里统一去掉开头的 '/'，确保拼到 static_dir 下
	clean_path := strip_query(path).trim_left('/')
	file_path := os.join_path(s.static_dir, clean_path)

	if os.exists(file_path) && os.is_file(file_path) {
		content := os.read_file(file_path) or {
			return Response{
				status_code: 500
				body:        'Internal Server Error'
			}
		}

		content_type := get_content_type(file_path)
		mut headers := map[string]string{}
		headers['Content-Type'] = content_type

		return Response{
			status_code: 200
			headers:     headers
			body:        content
		}
	} else {
		return Response{
			status_code: 404
			body:        'Not Found'
		}
	}
}

// 启动服务器 - 使用 TCP listener
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

			// 解析 HTTP 请求
			req := read_http_request(mut conn) or {
				write_raw_http(mut conn, 400, {
					'Content-Type': 'text/plain; charset=utf-8'
				}, 'Bad Request')
				conn.close() or {}
				continue
			}

			resp := srv.handle_request(req)
			write_http_response(mut conn, resp)
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

// 提取 URL 参数（支持 :param 路由匹配）
fn extract_params(route_pattern string, url_path string) map[string]string {
	mut params := map[string]string{}

	// 移除查询字符串
	path := strip_query(url_path)

	// 分段匹配
	pattern_parts := route_pattern.split('/')
	path_parts := path.split('/')

	// 长度必须匹配
	if pattern_parts.len != path_parts.len {
		return map[string]string{}
	}

	for i := 0; i < pattern_parts.len; i++ {
		pattern_part := pattern_parts[i]
		path_part := path_parts[i]

		// 如果是参数占位符（:param）
		if pattern_part.starts_with(':') && pattern_part.len > 1 {
			param_name := pattern_part[1..]
			params[param_name] = path_part
		} else if pattern_part != path_part {
			// 如果静态部分不匹配，返回空 map（表示不匹配）
			return map[string]string{}
		}
	}

	return params
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

// ==============
// HTTP 解析/写回
// ==============

fn strip_query(url string) string {
	if idx := url.index('?') {
		return url[..idx]
	}
	return url
}

fn status_text(code int) string {
	return match code {
		200 { 'OK' }
		201 { 'Created' }
		202 { 'Accepted' }
		204 { 'No Content' }
		301 { 'Moved Permanently' }
		302 { 'Found' }
		304 { 'Not Modified' }
		400 { 'Bad Request' }
		401 { 'Unauthorized' }
		403 { 'Forbidden' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		500 { 'Internal Server Error' }
		501 { 'Not Implemented' }
		else { 'OK' }
	}
}

fn read_http_request(mut conn net.TcpConn) !Request {
	// 先读一段（通常足够包含 headers + 小 body）
	mut buf := []u8{len: 64 * 1024}
	n := conn.read(mut buf) or { return error('read failed') }
	if n <= 0 {
		return error('empty request')
	}
	mut raw := buf[..n].bytestr()

	header_end := raw.index('\r\n\r\n') or { return error('no header end') }
	header_part := raw[..header_end]
	mut body := raw[header_end + 4..]

	lines := header_part.split('\r\n')
	if lines.len == 0 {
		return error('no request line')
	}

	// Request-Line: METHOD SP REQUEST-TARGET SP HTTP-VERSION
	parts := lines[0].split(' ')
	if parts.len < 2 {
		return error('invalid request line')
	}
	method := parts[0].to_upper()
	url := parts[1]

	// 解析 headers
	mut headers := map[string]string{}
	mut content_len := 0

	for i in 1 .. lines.len {
		line := lines[i]
		if line.len == 0 || !line.contains(':') {
			continue
		}
		kv := line.split_nth(':', 2)
		key := kv[0].trim_space().to_lower()
		val := kv[1].trim_space()

		// 保存所有 headers（保留原始大小写键名用于某些场景，但查询时用 lowercase）
		headers[key] = val

		if key == 'content-length' {
			content_len = val.int()
		}

		// 检查 Transfer-Encoding: chunked（不支持）
		if key == 'transfer-encoding' && val.to_lower().contains('chunked') {
			return error('chunked encoding not supported')
		}
	}

	// 如果 body 未读全，继续读剩余
	for content_len > 0 && body.len < content_len {
		mut more := []u8{len: 64 * 1024}
		m := conn.read(mut more) or { break }
		if m <= 0 {
			break
		}
		body += more[..m].bytestr()
	}

	if content_len > 0 && body.len > content_len {
		body = body[..content_len]
	}

	return Request{
		method:  method
		url:     url
		data:    body
		headers: headers
	}
}

fn write_raw_http(mut conn net.TcpConn, code int, headers map[string]string, body string) {
	write_http_response(mut conn, Response{
		status_code: code
		headers:     headers
		body:        body
	})
}

fn write_http_response(mut conn net.TcpConn, resp Response) {
	mut headers := resp.headers.clone()

	// 默认 Content-Type（尽量不改变现有逻辑，但避免空 header）
	if 'Content-Type' !in headers {
		if resp.body.len > 0 && (resp.body.starts_with('{') || resp.body.starts_with('[')) {
			headers['Content-Type'] = 'application/json; charset=utf-8'
		} else {
			headers['Content-Type'] = 'text/plain; charset=utf-8'
		}
	}

	headers['Content-Length'] = resp.body.bytes().len.str()
	headers['Connection'] = 'close'

	mut head := 'HTTP/1.1 ${resp.status_code} ${status_text(resp.status_code)}\r\n'
	for k, v in headers {
		head += '${k}: ${v}\r\n'
	}
	head += '\r\n'

	conn.write((head + resp.body).bytes()) or {}
}

// JSON 响应辅助函数
pub fn json_response(json_body string) Response {
	return Response{
		status_code: 200
		headers:     {
			'Content-Type': 'application/json'
		}
		body:        json_body
	}
}

// 成功响应（统一 API 返回格式）
pub fn success_response(data string) Response {
	return json_response('{"success":true,"data":' + data + '}')
}

// 错误响应
pub fn error_response(code int, message string) Response {
	escaped := message.replace('"', '\\"')
	return Response{
		status_code: code
		headers:     {
			'Content-Type': 'application/json'
		}
		body:        '{"success":false,"error":"' + escaped + '","code":' + code.str() + '}'
	}
}

// HTML 响应
pub fn html_response(html string) Response {
	return Response{
		status_code: 200
		headers:     {
			'Content-Type': 'text/html; charset=utf-8'
		}
		body:        html
	}
}

// 重定向响应
pub fn redirect_response(url string) Response {
	return Response{
		status_code: 302
		headers:     {
			'Location': url
		}
		body:        ''
	}
}
