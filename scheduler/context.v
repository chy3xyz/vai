// vai.runtime.context - 上下文管理 (简化版)
module scheduler

import time
import sync

// BaseContext 基础上下文实现
@[heap]
pub struct BaseContext {
	pub mut:
		done_ch    chan voidptr
		done_flag  bool
		err_val    ?IError
		deadline_t ?time.Time
		values     map[string]voidptr
		mu         sync.RwMutex
}

// 创建根上下文
pub fn background() &BaseContext {
	return &BaseContext{
		done_ch: chan voidptr{cap: 1}
		done_flag: false
		values: map[string]voidptr{}
	}
}

// 取消上下文
pub fn (mut ctx BaseContext) cancel(err IError) {
	if ctx.err_val != none {
		return
	}
	ctx.err_val = err
	ctx.done_flag = true
}

// IsCanceled 检查上下文是否已取消
pub fn (ctx &BaseContext) is_canceled() bool {
	return ctx.done_flag
}

// WithTimeout 创建带超时的上下文
pub fn with_timeout(parent &BaseContext, timeout time.Duration) (&BaseContext, fn ()) {
	mut child := &BaseContext{
		done_ch: chan voidptr{cap: 1}
		done_flag: false
		values: parent.values.clone()
	}
	
	child.deadline_t = time.now().add(timeout)
	
	cancel_fn := fn [mut child] () {
		child.cancel(error('context canceled'))
	}
	
	return child, cancel_fn
}

// WithValue 创建带值的上下文
pub fn with_value(parent &BaseContext, key string, value voidptr) &BaseContext {
	mut child := &BaseContext{
		done_ch: chan voidptr{cap: 1}
		done_flag: false
		values: parent.values.clone()
	}
	child.values[key] = value
	return child
}

// SleepContext 支持取消的 sleep
pub fn sleep_context(ctx &BaseContext, duration time.Duration) ! {
	if ctx.done_flag {
		if err_val := ctx.err_val {
			return err_val
		}
		return error('context done')
	}
	time.sleep(duration)
}
