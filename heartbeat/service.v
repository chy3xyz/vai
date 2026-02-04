// vai.heartbeat.service - 主动心跳服务
// 支持后台任务和自主行为
module heartbeat

import os
import time
import sync

// HeartbeatTask 心跳任务
pub struct HeartbeatTask {
pub:
	id          string
	description string
	interval    time.Duration  // 执行间隔
	handler     fn () ! @[required]  // 任务处理函数
pub mut:
	enabled     bool
	last_run    ?time.Time
	run_count   int
	error_count int
}

// HeartbeatService 心跳服务
@[heap]
pub struct HeartbeatService {
pub mut:
	tasks    map[string]HeartbeatTask
	running  bool
	mu       sync.RwMutex
}

// 创建心跳服务
pub fn new_heartbeat_service() &HeartbeatService {
	return &HeartbeatService{
		tasks: map[string]HeartbeatTask{}
		running: false
	}
}

// 启动心跳服务
pub fn (mut hs HeartbeatService) start() {
	hs.running = true
	spawn hs.run_loop()
}

// 停止心跳服务
pub fn (mut hs HeartbeatService) stop() {
	hs.running = false
}

// 主循环
fn (mut hs HeartbeatService) run_loop() {
	for hs.running {
		now := time.now()
		hs.check_and_run_tasks(now)
		time.sleep(10 * time.second) // 每 10 秒检查一次
	}
}

// 检查并运行任务
fn (mut hs HeartbeatService) check_and_run_tasks(now time.Time) {
	hs.mu.rlock()
	defer { hs.mu.runlock() }
	
	for _, mut task in hs.tasks {
		if !task.enabled {
			continue
		}
		
		// 检查是否到了运行时间
		should_run := if last_run := task.last_run {
			now - last_run >= task.interval
		} else {
			true  // 首次运行
		}
		
		if should_run {
			spawn hs.execute_task(mut task)
		}
	}
}

// 执行任务
fn (mut hs HeartbeatService) execute_task(mut task HeartbeatTask) {
	hs.mu.lock()
	task.last_run = time.now()
	task.run_count++
	hs.mu.unlock()
	
	// 执行处理函数
	task.handler() or {
		hs.mu.lock()
		task.error_count++
		hs.mu.unlock()
		eprintln('Heartbeat task ${task.id} failed: ${err}')
	}
}

// 添加任务
pub fn (mut hs HeartbeatService) add_task(task HeartbeatTask) ! {
	hs.mu.lock()
	defer { hs.mu.unlock() }
	
	if task.id in hs.tasks {
		return error('task already exists: ${task.id}')
	}
	
	hs.tasks[task.id] = task
}

// 删除任务
pub fn (mut hs HeartbeatService) remove_task(id string) {
	hs.mu.lock()
	defer { hs.mu.unlock() }
	hs.tasks.delete(id)
}

// 启用任务
pub fn (mut hs HeartbeatService) enable_task(id string) ! {
	hs.mu.lock()
	defer { hs.mu.unlock() }
	
	if mut task := hs.tasks[id] {
		task.enabled = true
	} else {
		return error('task not found: ${id}')
	}
}

// 禁用任务
pub fn (mut hs HeartbeatService) disable_task(id string) ! {
	hs.mu.lock()
	defer { hs.mu.unlock() }
	
	if mut task := hs.tasks[id] {
		task.enabled = false
	} else {
		return error('task not found: ${id}')
	}
}

// 列出所有任务
pub fn (mut hs HeartbeatService) list_tasks() []HeartbeatTask {
	hs.mu.rlock()
	defer { hs.mu.runlock() }
	
	mut tasks := []HeartbeatTask{}
	for _, task in hs.tasks {
		tasks << task
	}
	return tasks
}

// 获取任务
pub fn (mut hs HeartbeatService) get_task(id string) ?HeartbeatTask {
	hs.mu.rlock()
	defer { hs.mu.runlock() }
	return hs.tasks[id] or { return none }
}

// 从文件加载任务（从 HEARTBEAT.md）
pub fn (mut hs HeartbeatService) load_from_file(file_path string) ! {
	if !os.exists(file_path) {
		return error('file not found: ${file_path}')
	}
	
	_ := os.read_file(file_path) or {
		return error('failed to read file: ${err}')
	}
	
	// 解析 Markdown 文件，提取任务定义
	// 简化实现：这里可以扩展为解析特定格式的 Markdown
	// 目前返回空，后续可以添加解析逻辑
}

// 创建心跳任务
pub fn new_heartbeat_task(id string, description string, interval time.Duration, handler fn () !) HeartbeatTask {
	return HeartbeatTask{
		id: id
		description: description
		interval: interval
		enabled: true
		handler: handler
		run_count: 0
		error_count: 0
	}
}
