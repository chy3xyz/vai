// vai.runtime.context - 上下文管理
// 实现类似 Go context 的功能，支持取消信号、超时和值传递
module runtime

import time
import sync

// Context 接口定义
pub interface Context {
	deadline() ?time.Time
	done() chan struct{}
	err() ?IError
	value(key string) ?any
}

// BaseContext 基础上下文实现
pub struct BaseContext {
	pub mut:
		done_ch    chan struct{}
		err_val    ?IError
		deadline_t ?time.Time
		values     map[string]any
		mu         sync.RwMutex
}

// 创建根上下文
pub fn background() &BaseContext {
	return &BaseContext{
		done_ch: chan struct{}{cap: 1}
		values: map[string]any{}
	}
}

// 实现 Context 接口
pub fn (ctx &BaseContext) deadline() ?time.Time {
	return ctx.deadline_t
}

pub fn (ctx &BaseContext) done() chan struct{} {
	return ctx.done_ch
}

pub fn (ctx &BaseContext) err() ?IError {
	return ctx.err_val
}

pub fn (ctx &BaseContext) value(key string) ?any {
	ctx.mu.rlock()
	defer { ctx.mu.runlock() }
	return ctx.values[key] or { return none }
}

// WithCancel 创建可取消的子上下文
pub fn with_cancel(parent Context) (&BaseContext, fn ()) {
	child := &BaseContext{
		done_ch: chan struct{}{cap: 1}
		values: map[string]any{}
	}
	
	// 复制父上下文的值
	if parent is BaseContext {
		child.values = parent.values.clone()
	}
	
	cancel_fn := fn [child, parent] () {
		child.cancel(error('context canceled'))
	}
	
	// 监听父上下文取消
	spawn fn [child, parent] () {
		<-parent.done()
		child.cancel(parent.err() or { error('parent context done') })
	}()
	
	return child, cancel_fn
}

// WithTimeout 创建带超时的上下文
pub fn with_timeout(parent Context, timeout time.Duration) (&BaseContext, fn ()) {
	child, cancel := with_cancel(parent)
	child.deadline_t = time.now().add(timeout)
	
	// 启动超时计时器
	spawn fn [child, timeout] () {
		time.sleep(timeout)
		child.cancel(error('context deadline exceeded'))
	}()
	
	return child, cancel
}

// WithValue 创建带值的上下文
pub fn with_value(parent Context, key string, value any) &BaseContext {
	child := &BaseContext{
		done_ch: chan struct{}{cap: 1}
		values: map[string]any{}
	}
	
	// 复制父上下文的值
	if parent is BaseContext {
		child.values = parent.values.clone()
	}
	
	child.values[key] = value
	return child
}

// 取消上下文
pub fn (mut ctx BaseContext) cancel(err IError) {
	if ctx.err_val != none {
		return  // 已取消
	}
	
	ctx.err_val = err
	close(ctx.done_ch)
}

// IsCanceled 检查上下文是否已取消
pub fn (ctx &BaseContext) is_canceled() bool {
	select {
		<-ctx.done_ch {
			return true
		}
		else {
			return false
		}
	}
}

// SleepContext 支持取消的 sleep
pub fn sleep_context(ctx Context, duration time.Duration) ! {
	select {
		<-ctx.done() {
			return ctx.err() or { error('context done') }
		}
		duration {
			// 正常完成
		}
	}
}
