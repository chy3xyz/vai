// vai.cli.debug - 调试和性能分析工具
module cli

import time
import term

// Debugger 调试器
pub struct Debugger {
	pub mut:
		enabled       bool
		breakpoints   map[string]bool
		watch_vars    map[string]fn () string
		step_mode     bool
		log_level     LogLevel
}

// LogLevel 日志级别
pub enum LogLevel {
	debug
	info
	warn
	error
}

// 创建调试器
pub fn new_debugger() Debugger {
	return Debugger{
		enabled: false
		breakpoints: map[string]bool{}
		watch_vars: map[string]fn () string{}
		step_mode: false
		log_level: .info
	}
}

// 启用调试
pub fn (mut d Debugger) enable() {
	d.enabled = true
}

// 禁用调试
pub fn (mut d Debugger) disable() {
	d.enabled = false
}

// 设置断点
pub fn (mut d Debugger) set_breakpoint(location string) {
	d.breakpoints[location] = true
}

// 移除断点
pub fn (mut d Debugger) remove_breakpoint(location string) {
	d.breakpoints.delete(location)
}

// 检查断点
pub fn (d &Debugger) check_breakpoint(location string) bool {
	if !d.enabled {
		return false
	}
	return d.breakpoints[location] or { false }
}

// 记录日志
pub fn (d &Debugger) log(level LogLevel, message string) {
	if !d.enabled || int(level) < int(d.log_level) {
		return
	}
	
	timestamp := time.now().format_rfc3339()
	level_str := match level {
		.debug { term.blue('DEBUG') }
		.info  { term.green('INFO') }
		.warn  { term.yellow('WARN') }
		.error { term.red('ERROR') }
	}
	
	eprintln('[${timestamp}] [${level_str}] ${message}')
}

// PerformanceProfiler 性能分析器
pub struct PerformanceProfiler {
	pub mut:
		profiles map[string]Profile
		active   map[string]time.Time
}

// Profile 性能分析数据
pub struct Profile {
	pub mut:
		name      string
		call_count u64
		total_time time.Duration
		min_time   time.Duration
		max_time   time.Duration
}

// 创建性能分析器
pub fn new_profiler() PerformanceProfiler {
	return PerformanceProfiler{
		profiles: map[string]Profile{}
		active: map[string]time.Time{}
	}
}

// 开始分析
pub fn (mut p PerformanceProfiler) start(name string) {
	p.active[name] = time.now()
}

// 结束分析
pub fn (mut p PerformanceProfiler) end(name string) {
	if start_time := p.active[name] {
		elapsed := time.since(start_time)
		
		if mut profile := p.profiles[name] {
			profile.call_count++
			profile.total_time += elapsed
			if elapsed < profile.min_time || profile.min_time == 0 {
				profile.min_time = elapsed
			}
			if elapsed > profile.max_time {
				profile.max_time = elapsed
			}
		} else {
			p.profiles[name] = Profile{
				name: name
				call_count: 1
				total_time: elapsed
				min_time: elapsed
				max_time: elapsed
			}
		}
		
		p.active.delete(name)
	}
}

// pad_right pads a string to the specified width
fn pad_right(s string, width int) string {
	if s.len >= width {
		return s
	}
	return s + ' '.repeat(width - s.len)
}

// 获取报告
pub fn (p &PerformanceProfiler) report() string {
	mut output := '\n=== Performance Report ===\n\n'
	output += pad_right('Function', 30) + pad_right('Calls', 10) + pad_right('Total', 15) + pad_right('Avg', 15) + pad_right('Min', 15) + pad_right('Max', 15) + '\n'
	output += '-'.repeat(100) + '\n'
	
	for _, profile in p.profiles {
		avg := if profile.call_count > 0 {
			profile.total_time / int(profile.call_count)
		} else {
			time.Duration(0)
		}
		
		output += pad_right(profile.name, 30)
		output += pad_right(profile.call_count.str(), 10)
		output += pad_right(profile.total_time.str(), 15)
		output += pad_right(avg.str(), 15)
		output += pad_right(profile.min_time.str(), 15)
		output += pad_right(profile.max_time.str(), 15)
		output += '\n'
	}
	
	return output
}

// 打印报告
pub fn (p &PerformanceProfiler) print_report() {
	println(p.report())
}

// MemoryMonitor 内存监控器
pub struct MemoryMonitor {
	pub mut:
		snapshots []MemorySnapshot
		max_snapshots int = 100
}

// MemorySnapshot 内存快照
pub struct MemorySnapshot {
	pub:
		timestamp time.Time
		heap_used u64
		heap_free u64
		system_ram u64
}

// 创建内存监控器
pub fn new_memory_monitor() MemoryMonitor {
	return MemoryMonitor{
		snapshots: []
		max_snapshots: 100
	}
}

// 捕获快照
pub fn (mut m MemoryMonitor) snapshot() {
	// 简化实现：runtime.gc_stats() 在 V 0.5 中不可用
	// 使用模拟数据
	snapshot := MemorySnapshot{
		timestamp: time.now()
		heap_used: 0
		heap_free: 0
		system_ram: 0  // 需要平台特定实现
	}
	
	m.snapshots << snapshot
	
	// 限制快照数量
	if m.snapshots.len > m.max_snapshots {
		m.snapshots = m.snapshots[m.snapshots.len - m.max_snapshots..]
	}
}

// 获取当前内存使用
pub fn (m &MemoryMonitor) current() MemorySnapshot {
	if m.snapshots.len > 0 {
		return m.snapshots[m.snapshots.len - 1]
	}
	return MemorySnapshot{
		timestamp: time.now()
		heap_used: 0
		heap_free: 0
		system_ram: 0
	}
}

// 获取内存趋势
pub fn (m &MemoryMonitor) trend() string {
	if m.snapshots.len < 2 {
		return 'Not enough data'
	}
	
	first := m.snapshots[0]
	last := m.snapshots[m.snapshots.len - 1]
	
	change := i64(last.heap_used) - i64(first.heap_used)
	if change > 0 {
		return '+${change} bytes growth'
	} else if change < 0 {
		return '${change} bytes decrease'
	}
	return 'Stable'
}

// TraceTracer 执行追踪器
pub struct TraceTracer {
	pub mut:
		enabled   bool
		events    []TraceEvent
		indent    int
}

// TraceEvent 追踪事件
pub struct TraceEvent {
	pub:
		timestamp time.Time
		level     int
		name      string
		details   string
}

// 创建追踪器
pub fn new_tracer() TraceTracer {
	return TraceTracer{
		enabled: false
		events: []
		indent: 0
	}
}

// 开始追踪
pub fn (mut t TraceTracer) trace_enter(name string, details string) {
	if !t.enabled {
		return
	}
	
	t.events << TraceEvent{
		timestamp: time.now()
		level: t.indent
		name: '> ${name}'
		details: details
	}
	
	t.indent++
}

// 结束追踪
pub fn (mut t TraceTracer) trace_exit(name string, details string) {
	if !t.enabled {
		return
	}
	
	if t.indent > 0 {
		t.indent--
	}
	
	t.events << TraceEvent{
		timestamp: time.now()
		level: t.indent
		name: '< ${name}'
		details: details
	}
}

// 打印追踪结果
pub fn (t &TraceTracer) print() {
	if !t.enabled || t.events.len == 0 {
		return
	}
	
	println('\n=== Execution Trace ===\n')
	
	for event in t.events {
		indent := '  '.repeat(event.level)
		timestamp := event.timestamp.format_ss()
		println('[${timestamp}] ${indent}${event.name} ${event.details}')
	}
	
	println('')
}

// 清空追踪
pub fn (mut t TraceTracer) clear() {
	t.events.clear()
	t.indent = 0
}
