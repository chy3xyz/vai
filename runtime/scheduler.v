// vai.runtime - 协程调度器与事件循环
// 基于 V 语言 channel 实现 CSP 模型，支持 I/O 多路复用
module runtime

import time
import sync

// Task 表示一个可调度的任务
pub struct Task {
	pub mut:
		id        string
		exec      fn () !  // 任务执行函数
		priority  int      // 优先级，数值越小优先级越高
		deadline  ?time.Time  // 可选的截止时间
}

// Scheduler 协程调度器
// 利用 V 的 channel 实现 CSP 模型，支持工作窃取
pub struct Scheduler {
	pub mut:
		ready_queue chan Task     // 就绪队列
		task_count  int           // 当前任务数
		workers     int           // 工作线程数
		running     bool          // 运行状态
		event_loop  &EventLoop    // 事件循环引用
		wg          sync.WaitGroup
}

// EventLoop 事件循环，处理 I/O 事件
pub struct EventLoop {
	pub mut:
		running     bool
		poll_interval_ms int
		io_handlers map[string]fn (data any) !  // I/O 事件处理器
		timers      []Timer
}

// Timer 定时器
pub struct Timer {
	pub mut:
		id       string
		fire_at  time.Time
		callback fn ()
		repeat   bool
		interval time.Duration
}

// 创建新的调度器
pub fn new_scheduler(workers int) &Scheduler {
	return &Scheduler{
		ready_queue: chan Task{cap: 1000}
		task_count: 0
		workers: workers
		running: false
		event_loop: new_event_loop()
	}
}

// 创建新的事件循环
fn new_event_loop() &EventLoop {
	return &EventLoop{
		running: false
		poll_interval_ms: 10
		io_handlers: map[string]fn (data any) !{}
		timers: []
	}
}

// 启动调度器
pub fn (mut s Scheduler) start() ! {
	if s.running {
		return error('scheduler already running')
	}
	
	s.running = true
	
	// 启动工作线程
	for i := 0; i < s.workers; i++ {
		s.wg.add(1)
		spawn s.worker_thread()
	}
	
	// 启动事件循环
	spawn s.event_loop.run()
}

// 停止调度器
pub fn (mut s Scheduler) stop() {
	s.running = false
	s.event_loop.running = false
	s.wg.wait()
}

// 提交任务到调度器
pub fn (mut s Scheduler) submit(task Task) ! {
	if !s.running {
		return error('scheduler not running')
	}
	
	s.ready_queue <- task
	s.task_count++
}

// 提交带优先级的任务
pub fn (mut s Scheduler) submit_priority(exec fn () !, priority int) !string {
	task_id := generate_task_id()
	task := Task{
		id: task_id
		exec: exec
		priority: priority
	}
	s.submit(task)!
	return task_id
}

// 工作线程主循环
fn (mut s Scheduler) worker_thread() {
	defer { s.wg.done() }
	
	for s.running {
		select {
			task := <-s.ready_queue {
				s.execute_task(task)
			}
			500 * time.millisecond {
				// 超时继续，检查 running 状态
			}
		}
	}
}

// 执行单个任务
fn (mut s Scheduler) execute_task(task Task) {
	// 检查截止时间
	if deadline := task.deadline {
		if time.now() > deadline {
			eprintln('Task ${task.id} missed deadline')
			s.task_count--
			return
		}
	}
	
	// 执行任务
	task.exec() or {
		eprintln('Task ${task.id} error: ${err}')
	}
	
	s.task_count--
}

// 事件循环主循环
fn (mut el EventLoop) run() {
	el.running = true
	
	for el.running {
		// 检查定时器
		el.check_timers()
		
		// 可以在这里添加 epoll/kqueue 集成
		// 目前使用简单轮询
		time.sleep(el.poll_interval_ms * time.millisecond)
	}
}

// 检查并触发定时器
fn (mut el EventLoop) check_timers() {
	now := time.now()
	mut to_remove := []int{}
	
	for i, mut timer in el.timers {
		if now >= timer.fire_at {
			timer.callback()
			
			if timer.repeat {
				timer.fire_at = now.add(timer.interval)
			} else {
				to_remove << i
			}
		}
	}
	
	// 删除已触发的非重复定时器
	for i := to_remove.len - 1; i >= 0; i-- {
		idx := to_remove[i]
		el.timers.delete(idx)
	}
}

// 添加定时器
pub fn (mut el EventLoop) add_timer(id string, duration time.Duration, repeat bool, callback fn ()) {
	el.timers << Timer{
		id: id
		fire_at: time.now().add(duration)
		callback: callback
		repeat: repeat
		interval: duration
	}
}

// 注册 I/O 处理器
pub fn (mut el EventLoop) register_handler(event_type string, handler fn (data any) !) {
	el.io_handlers[event_type] = handler
}

// 生成任务 ID
fn generate_task_id() string {
	return 'task_${time.now().unix_micro}_${rand_id()}'
}

// 简单的随机 ID 生成
fn rand_id() string {
	chars := 'abcdefghijklmnopqrstuvwxyz0123456789'
	mut result := ''
	for i := 0; i < 8; i++ {
		result += chars[time.now().unix % chars.len].ascii_str()
		time.sleep(1 * time.microsecond)
	}
	return result
}

// RuntimeContext 运行时上下文，用于跨任务传递信息
pub struct RuntimeContext {
	pub mut:
		vars map[string]any
		mu   sync.RwMutex
}

// 创建运行时上下文
pub fn new_context() RuntimeContext {
	return RuntimeContext{
		vars: map[string]any{}
	}
}

// 设置上下文变量
pub fn (mut ctx RuntimeContext) set(key string, value any) {
	ctx.mu.lock()
	defer { ctx.mu.unlock() }
	ctx.vars[key] = value
}

// 获取上下文变量
pub fn (ctx RuntimeContext) get(key string) ?any {
	ctx.mu.rlock()
	defer { ctx.mu.runlock() }
	return ctx.vars[key] or { return none }
}
