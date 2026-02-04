// vai.sandbox - WASI 风格安全隔离
module sandbox

import os
import time
import sync

// ExecutionConfig 执行配置
pub struct ExecutionConfig {
pub:
	command       string
	args          []string
	working_dir   string
	env_vars      map[string]string
	timeout_ms    int = 30000
	max_memory_mb int = 128
	allow_network bool
}

// ExecutionResult 执行结果
pub struct ExecutionResult {
pub:
	exit_code   int
	stdout      string
	stderr      string
	start_time  time.Time
	end_time    time.Time
	cpu_time_ms int
}

// ProcessSandbox 进程级沙箱
@[heap]
pub struct ProcessSandbox {
pub mut:
	config  ExecutionConfig
	process ?os.Process
	running bool
	mu      sync.Mutex
}

// 创建进程沙箱
pub fn new_process_sandbox(config ExecutionConfig) &ProcessSandbox {
	return &ProcessSandbox{
		config:  config
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

	// 网络限制：当 allow_network=false 时，设置环境变量提示（实际限制需要系统级支持）
	if !config.allow_network {
		env['VAI_SANDBOX_NO_NETWORK'] = '1'
		// 注意：实际网络限制需要平台特定的实现（如 macOS 的 sandbox-exec）
		// 当前实现依赖进程自身遵守环境变量提示
	}

	// 创建进程
	mut process := os.new_process(config.command)
	process.set_args(config.args.clone())
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
	mut elapsed_ms := 0
	check_interval := 100

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
		exit_code:   exit_code
		stdout:      stdout
		stderr:      stderr
		start_time:  start_time
		end_time:    end_time
		cpu_time_ms: int(end_time.unix_milli() - start_time.unix_milli())
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
pub fn (mut s ProcessSandbox) is_running() bool {
	s.mu.lock()
	defer { s.mu.unlock() }
	return s.running
}

// ResourceLimiter 资源限制器
pub struct ResourceLimiter {
pub mut:
	max_memory_mb    int = 128
	max_cpu_percent  f32 = 50.0
	max_file_size_mb int = 10
	max_files        int = 100
}

// 创建资源限制器
pub fn new_resource_limiter() ResourceLimiter {
	return ResourceLimiter{
		max_memory_mb:    128
		max_cpu_percent:  50.0
		max_file_size_mb: 10
		max_files:        100
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
@[heap]
pub struct SandboxManager {
pub mut:
	sandboxes map[string]&ProcessSandbox
	mu        sync.RwMutex
}

// 创建沙箱管理器
pub fn new_sandbox_manager() &SandboxManager {
	return &SandboxManager{
		sandboxes: map[string]&ProcessSandbox{}
	}
}

// 创建沙箱
pub fn (mut sm SandboxManager) create(id string, config ExecutionConfig) !&ProcessSandbox {
	sm.mu.lock()
	defer { sm.mu.unlock() }

	if id in sm.sandboxes {
		return error('sandbox ${id} already exists')
	}

	mut sb := new_process_sandbox(config)
	sm.sandboxes[id] = sb
	return sb
}

// 获取沙箱
pub fn (mut sm SandboxManager) get(id string) ?&ProcessSandbox {
	sm.mu.rlock()
	defer { sm.mu.runlock() }
	return sm.sandboxes[id] or { return none }
}

// 销毁沙箱
pub fn (mut sm SandboxManager) destroy(id string) ! {
	sm.mu.lock()
	defer { sm.mu.unlock() }

	if mut sandbox := sm.sandboxes[id] {
		sandbox.cleanup()!
		sm.sandboxes.delete(id)
	}
}

// 清理所有沙箱
pub fn (mut sm SandboxManager) cleanup_all() {
	sm.mu.lock()
	defer { sm.mu.unlock() }

	for _, mut sandbox in sm.sandboxes {
		sandbox.cleanup() or { continue }
	}
	sm.sandboxes.clear()
}

// SecureExecutor 安全执行器
@[heap]
pub struct SecureExecutor {
pub mut:
	sandbox_manager  &SandboxManager
	resource_limiter ResourceLimiter
}

// 创建安全执行器
pub fn new_secure_executor(sm &SandboxManager) &SecureExecutor {
	return &SecureExecutor{
		sandbox_manager:  sm
		resource_limiter: new_resource_limiter()
	}
}

// 安全执行命令
pub fn (mut se SecureExecutor) run_secure(command string, args []string, timeout_ms int) !ExecutionResult {
	config := ExecutionConfig{
		command:       command
		args:          args
		timeout_ms:    timeout_ms
		max_memory_mb: se.resource_limiter.max_memory_mb

		allow_network: false
	}

	mut sb := new_process_sandbox(config)
	return sb.execute(config)
}
