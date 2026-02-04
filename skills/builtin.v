// vai.skills.builtin - 内置技能集合
// 提供常用的系统技能：文件操作、Shell执行、网络请求等
module skills

import os
import net.http
import time
import encoding.base64

// FileReadSkill 文件读取技能
pub struct FileReadSkill {}

pub fn (s FileReadSkill) name() string {
	return 'file_read'
}

pub fn (s FileReadSkill) description() string {
	return 'Read the contents of a file'
}

pub fn (s FileReadSkill) category() string {
	return 'filesystem'
}

pub fn (s FileReadSkill) risk_level() RiskLevel {
	return .safe
}

pub fn (s FileReadSkill) parameters() map[string]ParameterSchema {
	return {
		'path': ParameterSchema{
			typ: 'string'
			description: 'The path to the file to read'
			required: true
		}
		'encoding': ParameterSchema{
			typ: 'string'
			description: 'File encoding (utf-8, base64)'
			required: false
			default_: Value('utf-8')
			enum_vals: ['utf-8', 'base64']
		}
		'limit': ParameterSchema{
			typ: 'number'
			description: 'Maximum number of characters to read'
			required: false
		}
	}
}

pub fn (s FileReadSkill) execute(args map[string]Value, ctx SkillContext) !Result {
	path_val := args['path'] or { return error('path is required') }
	path := path_val as string
	
	encoding_val := args['encoding'] or { Value('utf-8') }
	encoding := encoding_val as string
	
	// 安全检查：确保路径在工作目录内
	if !is_safe_path(path, ctx.working_dir) {
		return error('unsafe path: ${path}')
	}
	
	if !os.exists(path) {
		return error('file not found: ${path}')
	}
	
	content := os.read_file(path) or {
		return error('failed to read file: ${err}')
	}
	
	mut result := content
	
	// 应用限制
	if limit_val := args['limit'] {
		limit := limit_val as i64
		if content.len > limit {
			result = content[..limit] + '... [truncated]'
		}
	}
	
	if encoding == 'base64' {
		result = base64.encode(content.bytes())
	}
	
	return Result{
		success: true
		data: Value(result)
		error_msg: ''
		took_ms: 0
	}
}

// FileWriteSkill 文件写入技能
pub struct FileWriteSkill {}

pub fn (s FileWriteSkill) name() string {
	return 'file_write'
}

pub fn (s FileWriteSkill) description() string {
	return 'Write content to a file'
}

pub fn (s FileWriteSkill) category() string {
	return 'filesystem'
}

pub fn (s FileWriteSkill) risk_level() RiskLevel {
	return .moderate
}

pub fn (s FileWriteSkill) parameters() map[string]ParameterSchema {
	return {
		'path': ParameterSchema{
			typ: 'string'
			description: 'The path to the file to write'
			required: true
		}
		'content': ParameterSchema{
			typ: 'string'
			description: 'The content to write'
			required: true
		}
		'append': ParameterSchema{
			typ: 'boolean'
			description: 'Append to file instead of overwriting'
			required: false
			default_: Value(false)
		}
	}
}

pub fn (s FileWriteSkill) execute(args map[string]Value, ctx SkillContext) !Result {
	path_val := args['path'] or { return error('path is required') }
	path := path_val as string
	
	content_val := args['content'] or { return error('content is required') }
	content := content_val as string
	
	mut append := false
	if append_val := args['append'] {
		append = append_val as bool
	}
	
	// 安全检查
	if !is_safe_path(path, ctx.working_dir) {
		return error('unsafe path: ${path}')
	}
	
	if append {
		mut existing := ''
		if os.exists(path) {
			existing = os.read_file(path) or { '' }
		}
		os.write_file(path, existing + content) or {
			return error('failed to write file: ${err}')
		}
	} else {
		os.write_file(path, content) or {
			return error('failed to write file: ${err}')
		}
	}
	
	return Result{
		success: true
		data: Value('File written successfully: ${path}')
		error_msg: ''
		took_ms: 0
	}
}

// ShellExecuteSkill Shell 执行技能
pub struct ShellExecuteSkill {
	pub mut:
		allowed_commands []string  // 允许执行的命令白名单
}

pub fn (s ShellExecuteSkill) name() string {
	return 'shell_execute'
}

pub fn (s ShellExecuteSkill) description() string {
	return 'Execute a shell command (restricted)'
}

pub fn (s ShellExecuteSkill) category() string {
	return 'system'
}

pub fn (s ShellExecuteSkill) risk_level() RiskLevel {
	return .high
}

pub fn (s ShellExecuteSkill) parameters() map[string]ParameterSchema {
	return {
		'command': ParameterSchema{
			typ: 'string'
			description: 'The command to execute'
			required: true
		}
		'timeout': ParameterSchema{
			typ: 'number'
			description: 'Timeout in seconds'
			required: false
			default_: Value(i64(30))
		}
	}
}

pub fn (s ShellExecuteSkill) execute(args map[string]Value, ctx SkillContext) !Result {
	command_val := args['command'] or { return error('command is required') }
	command := command_val as string
	
	mut timeout := 30
	if timeout_val := args['timeout'] {
		timeout = int(timeout_val as i64)
	}
	
	// 安全检查：命令白名单
	if !s.is_allowed(command) {
		return error('command not allowed: ${command}')
	}
	
	// 设置超时
	start := time.now()
	result := os.execute(command)
	elapsed := time.since(start)
	
	if elapsed > time.second * timeout {
		return error('command timeout after ${timeout}s')
	}
	
	mut data_map := map[string]Value{}
	data_map['stdout'] = Value(result.output)
	data_map['stderr'] = Value('')
	data_map['exit_code'] = Value(i64(result.exit_code))
	
	return Result{
		success: result.exit_code == 0
		data: Value(data_map)
		error_msg: if result.exit_code != 0 { 'exit code: ${result.exit_code}' } else { '' }
		took_ms: 0
	}
}

fn (s ShellExecuteSkill) is_allowed(command string) bool {
	if s.allowed_commands.len == 0 {
		// 默认允许安全的命令
		safe_prefixes := ['ls', 'cat', 'echo', 'pwd', 'which', 'head', 'tail', 'grep', 'find', 'wc']
		cmd := command.trim_space().split(' ')[0]
		return cmd in safe_prefixes
	}
	
	for allowed in s.allowed_commands {
		if command.starts_with(allowed) {
			return true
		}
	}
	return false
}

// HttpRequestSkill HTTP 请求技能
pub struct HttpRequestSkill {}

pub fn (s HttpRequestSkill) name() string {
	return 'http_request'
}

pub fn (s HttpRequestSkill) description() string {
	return 'Make an HTTP request'
}

pub fn (s HttpRequestSkill) category() string {
	return 'network'
}

pub fn (s HttpRequestSkill) risk_level() RiskLevel {
	return .critical
}

pub fn (s HttpRequestSkill) parameters() map[string]ParameterSchema {
	return {
		'url': ParameterSchema{
			typ: 'string'
			description: 'The URL to request'
			required: true
		}
		'method': ParameterSchema{
			typ: 'string'
			description: 'HTTP method'
			required: false
			default_: Value('GET')
			enum_vals: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']
		}
		'headers': ParameterSchema{
			typ: 'object'
			description: 'HTTP headers'
			required: false
		}
		'body': ParameterSchema{
			typ: 'string'
			description: 'Request body'
			required: false
		}
	}
}

pub fn (s HttpRequestSkill) execute(args map[string]Value, ctx SkillContext) !Result {
	url_val := args['url'] or { return error('url is required') }
	url := url_val as string
	
	mut method_str := 'GET'
	if method_val := args['method'] {
		method_str = (method_val as string).to_upper()
	}
	
	// URL 安全检查
	if !is_safe_url(url) {
		return error('unsafe URL: ${url}')
	}
	
	method := match method_str {
		'GET' { http.Method.get }
		'POST' { http.Method.post }
		'PUT' { http.Method.put }
		'DELETE' { http.Method.delete }
		'PATCH' { http.Method.patch }
		else { http.Method.get }
	}
	
	mut body := ''
	if body_val := args['body'] {
		body = body_val as string
	}
	
	// 设置 headers
	mut config := http.FetchConfig{
		url: url
		method: method
		data: body
	}
	
	if headers_val := args['headers'] {
		headers_map := headers_val as map[string]Value
		for key, value in headers_map {
			val_str := value as string
			config.header.add_custom(key, val_str)!
		}
	}
	
	resp := http.fetch(config) or {
		return error('HTTP request failed: ${err}')
	}
	
	mut data_map := map[string]Value{}
	data_map['status_code'] = Value(i64(resp.status_code))
	data_map['body'] = Value(resp.body)
	
	return Result{
		success: resp.status_code >= 200 && resp.status_code < 300
		data: Value(data_map)
		error_msg: ''
		took_ms: 0
	}
}

// ListDirectorySkill 目录列表技能
pub struct ListDirectorySkill {}

pub fn (s ListDirectorySkill) name() string {
	return 'list_directory'
}

pub fn (s ListDirectorySkill) description() string {
	return 'List files and directories'
}

pub fn (s ListDirectorySkill) category() string {
	return 'filesystem'
}

pub fn (s ListDirectorySkill) risk_level() RiskLevel {
	return .safe
}

pub fn (s ListDirectorySkill) parameters() map[string]ParameterSchema {
	return {
		'path': ParameterSchema{
			typ: 'string'
			description: 'Directory path to list'
			required: true
		}
		'recursive': ParameterSchema{
			typ: 'boolean'
			description: 'List recursively'
			required: false
			default_: Value(false)
		}
	}
}

pub fn (s ListDirectorySkill) execute(args map[string]Value, ctx SkillContext) !Result {
	path_val := args['path'] or { return error('path is required') }
	path := path_val as string
	
	_ := args['recursive'] or { Value(false) }
	
	// 安全检查
	if !is_safe_path(path, ctx.working_dir) {
		return error('unsafe path: ${path}')
	}
	
	if !os.exists(path) {
		return error('path not found: ${path}')
	}
	
	if !os.is_dir(path) {
		return error('not a directory: ${path}')
	}
	
	entries := os.ls(path) or {
		return error('failed to list directory: ${err}')
	}
	
	mut result := []Value{}
	
	for entry in entries {
		full_path := os.join_path(path, entry)
		is_dir := os.is_dir(full_path)
		
		mut item := map[string]Value{}
		item['name'] = Value(entry)
		item['path'] = Value(full_path)
		item['is_dir'] = Value(is_dir)
		
		if !is_dir {
			item['size'] = Value(i64(os.file_size(full_path)))
		}
		
		result << Value(item)
	}
	
	return Result{
		success: true
		data: Value(result)
		error_msg: ''
		took_ms: 0
	}
}

// GetCurrentTimeSkill 获取当前时间技能
pub struct GetCurrentTimeSkill {}

pub fn (s GetCurrentTimeSkill) name() string {
	return 'get_current_time'
}

pub fn (s GetCurrentTimeSkill) description() string {
	return 'Get the current time in various formats'
}

pub fn (s GetCurrentTimeSkill) category() string {
	return 'utility'
}

pub fn (s GetCurrentTimeSkill) risk_level() RiskLevel {
	return .safe
}

pub fn (s GetCurrentTimeSkill) parameters() map[string]ParameterSchema {
	return {
		'timezone': ParameterSchema{
			typ: 'string'
			description: 'Timezone (e.g., UTC, Asia/Shanghai)'
			required: false
			default_: Value('UTC')
		}
		'format': ParameterSchema{
			typ: 'string'
			description: 'Time format'
			required: false
			default_: Value('RFC3339')
			enum_vals: ['RFC3339', 'unix', 'iso8601']
		}
	}
}

pub fn (s GetCurrentTimeSkill) execute(args map[string]Value, ctx SkillContext) !Result {
	mut format := 'RFC3339'
	if format_val := args['format'] {
		format = format_val as string
	}
	
	now := time.now()
	
	mut result := ''
	match format {
		'unix' { result = now.unix().str() }
		'iso8601' { result = now.format_rfc3339() }
		else { result = now.format_rfc3339() }
	}
	
	mut tz := 'UTC'
	if tz_val := args['timezone'] {
		tz = tz_val as string
	}
	
	mut data_map := map[string]Value{}
	data_map['time'] = Value(result)
	data_map['timestamp'] = Value(now.unix())
	data_map['timezone'] = Value(tz)
	
	return Result{
		success: true
		data: Value(data_map)
		error_msg: ''
		took_ms: 0
	}
}

// 注册所有内置技能
pub fn register_builtin_skills(mut registry Registry) ! {
	registry.register(FileReadSkill{})!
	registry.register(FileWriteSkill{})!
	registry.register(ShellExecuteSkill{})!
	registry.register(HttpRequestSkill{})!
	registry.register(ListDirectorySkill{})!
	registry.register(GetCurrentTimeSkill{})!
}

// 辅助函数：检查路径安全
fn is_safe_path(path string, working_dir string) bool {
	// 解析绝对路径
	abs_path := os.real_path(path)
	abs_working := os.real_path(working_dir)
	
	// 确保路径在工作目录内
	return abs_path.starts_with(abs_working)
}

// 辅助函数：检查 URL 安全
fn is_safe_url(url string) bool {
	// 禁止访问内部网络
	blocked_hosts := ['localhost', '127.0.0.1', '0.0.0.0', '[::1]']
	
	for host in blocked_hosts {
		if url.contains(host) {
			return false
		}
	}
	
	return true
}
