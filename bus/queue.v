// vai.bus.queue - 消息队列和事件分发
// 实现事件驱动的消息总线
module bus

import sync
import time

// EventHandler 事件处理器类型
pub type EventHandler = fn (Event)

// MessageBus 消息总线
@[heap]
pub struct MessageBus {
pub mut:
	event_queue    chan Event
	handlers      map[EventType][]EventHandler
	running       bool
	mu            sync.RwMutex
}

// 创建消息总线
pub fn new_message_bus() &MessageBus {
	return &MessageBus{
		event_queue: chan Event{cap: 1000}
		handlers: map[EventType][]EventHandler{}
		running: false
	}
}

// 启动消息总线
pub fn (mut mb MessageBus) start() {
	mb.running = true
	spawn mb.event_loop()
}

// 停止消息总线
pub fn (mut mb MessageBus) stop() {
	mb.running = false
}

// 事件循环
fn (mut mb MessageBus) event_loop() {
	for mb.running {
		select {
			event := <-mb.event_queue {
				mb.dispatch_event(event)
			}
			100 * time.millisecond {
				// 超时继续检查
			}
		}
	}
}

// 发布事件
pub fn (mut mb MessageBus) publish(event Event) ! {
	if !mb.running {
		return error('message bus not running')
	}

	select {
		mb.event_queue <- event {
			// 成功发送
		}
		1 * time.second {
			return error('event queue full, timeout')
		}
	}
}

// 订阅事件
pub fn (mut mb MessageBus) subscribe(event_type EventType, handler EventHandler) {
	mb.mu.lock()
	defer { mb.mu.unlock() }

	if event_type !in mb.handlers {
		mb.handlers[event_type] = []EventHandler{}
	}
	mb.handlers[event_type] << handler
}

// 取消订阅
pub fn (mut mb MessageBus) unsubscribe(event_type EventType, handler EventHandler) {
	mb.mu.lock()
	defer { mb.mu.unlock() }

	if event_type in mb.handlers {
		mut handlers := mb.handlers[event_type]
		mut new_handlers := []EventHandler{}
		for h in handlers {
			if h != handler {
				new_handlers << h
			}
		}
		mb.handlers[event_type] = new_handlers
	}
}

// 分发事件
fn (mut mb MessageBus) dispatch_event(event Event) {
	mb.mu.rlock()
	defer { mb.mu.runlock() }

	event_type := event.event_type()
	if handlers := mb.handlers[event_type] {
		for handler in handlers {
			handler(event)
		}
	}

	// 也通知通用处理器（如果有）
	_ := mb.handlers[.system_event]  // 可以添加通用处理逻辑
}

// 获取事件队列大小
pub fn (mb &MessageBus) queue_size() int {
	return int(mb.event_queue.len)
}

// 检查是否运行中
pub fn (mb &MessageBus) is_running() bool {
	return mb.running
}
