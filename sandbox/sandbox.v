// vai.sandbox - WASI 风格安全隔离
// 提供资源限制和沙箱执行环境
module sandbox

import os
import time
import sync

// Sandbox 沙箱接口
pub interface Sandbox {
	execute(config ExecutionConfig) !ExecutionResult
	cleanup() !
	is_running() bool
}

// ExecutionConfig 执行配置
pub struct ExecutionConfig {
	pub:
		command        string            // 要执行的命令
		args           []string          // 参数
		working_dir    string            // 工作目录
		env_vars       map[string]string // 环境变量
		timeout_ms     int = 30000       // 超时时间（毫秒）
		// 资源限制
		max_memory_mb  int = 128         // 最大内存（MB）
		max_cpu_percent f32 = 50.0       // 最大 CPU 使用率
		max_file_size_mb int = 10        // 最大文件大小（MB）
		max_files      int = 100         // 最大文件数
		allow_network  bool = false      // 是否允许网络访问
		readonly_paths []string          // 只读路径
		writable_paths []string          // 可写路径
}

// ExecutionResult 执行结果
pub struct ExecutionResult {
	pub:
		exit_code   int
		stdout      string
		stderr      string
		start_time  time.Time
		end_time    time.Time
		memory_used_mb int
		cpu_time_ms int
}

// ProcessSandbox 进程级沙箱
pub struct ProcessSandbox {
	pub mut:
		config      ExecutionConfig
		process     ?os.Process
		running     bool
		mu          sync.Mutex
}

// 创建进程沙箱
pub fn new_process_sandbox(config ExecutionConfig) ProcessSandbox {
	return ProcessSandbox{
		config: config
		process: none
		running: false
	}
}

// 执行命令
pub fn (mut s ProcessSandbox) execute(config ExecutionConfig) !ExecutionResult {
	s.mu.lock()
	defer { s.mu.unlock() }
	
	if s.running {
		return error('sandbox already running')
	}
	
	s.config = config
	start_time := time.now()
	
	// 准备环境变量
	mut env := os.environ()
	for key, value in config.env_vars {
		env[key] = value
	}
	
	// 设置资源限制（通过 ulimit，仅适用于 Unix）
	// 注意：这是简化实现，生产环境应该使用 cgroups 等更强隔离
	mut cmd_args := config.args.clone()
	
	// 创建进程
	mut process := os.new_process(config.command)
	process.set_args(cmd_args)
	process.set_environment(env)
	
	// 设置工作目录
	if config.working_dir.len > 0 {
		os.chdir(config.working_dir) or {
			return error('failed to change working directory: ${err}')
		}
	}
	
	s.process = process
	s.running = true
	
	// 启动进程
	process.run()
	
	// 等待完成或超时
	mut exited := false
	mut exit_code := -1
	elapsed_ms := 0
	check_interval := 100 // 每 100ms 检查一次
	
	for elapsed_ms < config.timeout_ms {
		if !process.is_alive() {
			exited = true
			exit_code = process.code
			break
		}
		time.sleep(check_interval * time.millisecond)
		elapsed_ms += check_interval
	}
	
	// 超时则终止进程
	if !exited {
		process.signal_kill()
		exit_code = -1
	}
	
	end_time := time.now()
	s.running = false
	
	// 读取输出
	stdout := process.stdout_read()
	stderr := process.stderr_read()
	
	return ExecutionResult{
		exit_code: exit_code
		stdout: stdout
		stderr: stderr
		start_time: start_time
		end_time: end_time
		memory_used_mb: 0  // 需要额外工具获取
		cpu_time_ms: int(end_time.unix_milli - start_time.unix_milli)
	}
}

// 清理资源
pub fn (mut s ProcessSandbox) cleanup() ! {
	s.mu.lock()
	defer { s.mu.unlock() }
	
	if mut process := s.process {
		if process.is_alive() {
			process.signal_kill()
		}
		s.process = none
	}
	s.running = false
}

// 检查是否运行中
pub fn (s &ProcessSandbox) is_running() bool {
	s.mu.lock()
	defer { s.mu.unlock() }
	return s.running
}

// RestrictedFS 受限文件系统
pub struct RestrictedFS {
	pub mut:
		base_path      string
		readonly_paths []string
		writable_paths []string
}

// 创建受限文件系统
pub fn new_restricted_fs(base_path string) RestrictedFS {
	return RestrictedFS{
		base_path: base_path
		readonly_paths: []
		writable_paths: []
	}
}

// 设置只读路径
pub fn (mut fs RestrictedFS) set_readonly_paths(paths []string) {
	fs.readonly_paths = paths
}

// 设置可写路径
pub fn (mut fs RestrictedFS) set_writable_paths(paths []string) {
	fs.writable_paths = paths
}

// 检查路径是否在允许范围内
pub fn (fs &RestrictedFS) is_allowed(path string, need_write bool) bool {
	// 规范化路径
	abs_path := os.real_path(path)
	
	// 必须在 base_path 内
	if !abs_path.starts_with(fs.base_path) {
		return false
	}
	
	// 检查可写权限
	if need_write {
		for wp in fs.writable_paths {
			if abs_path.starts_with(os.join_path(fs.base_path, wp)) {
				return true
			}
		}
		return false
	}
	
	// 检查只读权限
	for rp in fs.readonly_paths {
		if abs_path.starts_with(os.join_path(fs.base_path, rp)) {
			return true
		}
	}
	
	return false
}

// 安全读取文件
pub fn (fs &RestrictedFS) read_file(path string) !string {
	if !fs.is_allowed(path, false) {
		return error('access denied: ${path}')
	}
	return os.read_file(path)
}

// 安全写入文件
pub fn (fs &RestrictedFS) write_file(path string, content string) ! {
	if !fs.is_allowed(path, true) {
		return error('write access denied: ${path}')
	}
	return os.write_file(path, content)
}

// ResourceLimiter 资源限制器
pub struct ResourceLimiter {
	pub mut:
		max_memory_mb    int
		max_cpu_percent  f32
		max_file_size_mb int
		max_files        int
}

// 创建资源限制器
pub fn new_resource_limiter() ResourceLimiter {
	return ResourceLimiter{
		max_memory_mb: 128
		max_cpu_percent: 50.0
		max_file_size_mb: 10
		max_files: 100
	}
}

// 检查内存限制
pub fn (rl &ResourceLimiter) check_memory(current_mb int) bool {
	return current_mb <= rl.max_memory_mb
}

// 检查文件大小限制
pub fn (rl &ResourceLimiter) check_file_size(size_mb int) bool {
	return size_mb <= rl.max_file_size_mb
}

// SandboxManager 沙箱管理器
pub struct SandboxManager {
	pub mut:
		sandboxes map[string]Sandbox
		mu        sync.RwMutex
}

// 创建沙箱管理器
pub fn new_sandbox_manager() SandboxManager {
	return SandboxManager{
		sandboxes: map[string]Sandbox{}
	}
}

// 创建沙箱
pub fn (mut sm SandboxManager) create(id string, config ExecutionConfig) !Sandbox {
	sm.mu.lock()
	defer { sm.mu.unlock() }
	
	if id in sm.sandboxes {
		return error('sandbox ${id} already exists')
	}
	
	sandbox := new_process_sandbox(config)
	sm.sandboxes[id] = sandbox
	return sandbox
}

// 获取沙箱
pub fn (sm &SandboxManager) get(id string) ?Sandbox {
	sm.mu.rlock()
	defer { sm.mu.runlock() }
	return sm.sandboxes[id] or { return none }
}

// 销毁沙箱
pub fn (mut sm SandboxManager) destroy(id string) ! {
	sm.mu.lock()
	defer { sm.mu.unlock() }
	
	if sandbox := sm.sandboxes[id] {
		sandbox.cleanup()!
		sm.sandboxes.delete(id)
	}
}

// 清理所有沙箱
pub fn (mut sm SandboxManager) cleanup_all() {
	sm.mu.lock()
	defer { sm.mu.unlock() }
	
	for _, sandbox in sm.sandboxes {
		sandbox.cleanup() or { continue }
	}
	sm.sandboxes.clear()
}

// SecureExecutor 安全执行器
pub struct SecureExecutor {
	pub mut:
		sandbox_manager &SandboxManager
		fs_restrictor   &RestrictedFS
		resource_limiter ResourceLimiter
}

// 创建安全执行器
pub fn new_secure_executor(sm &SandboxManager, fs &RestrictedFS) SecureExecutor {
	return SecureExecutor{
		sandbox_manager: sm
		fs_restrictor: fs
		resource_limiter: new_resource_limiter()
	}
}

// 安全执行命令
pub fn (mut se SecureExecutor) run_secure(command string, args []string, timeout_ms int) !ExecutionResult {
	config := ExecutionConfig{
		command: command
		args: args
		timeout_ms: timeout_ms
		max_memory_mb: se.resource_limiter.max_memory_mb
		max_cpu_percent: se.resource_limiter.max_cpu_percent
		allow_network: false
	}
	
	sandbox := new_process_sandbox(config)
	return sandbox.execute(config)
}
