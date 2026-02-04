// vai.gateway - 多平台适配器
// 定义统一的 PlatformAdapter 接口，支持 WhatsApp、Telegram 等平台
module gateway

import protocol { Message, MessageType, MessageRole, new_text_message, new_event_message }
import time

// PlatformAdapter 平台适配器接口
// 所有平台适配器必须实现此接口
pub interface PlatformAdapter {
	// 获取平台名称
	name() string
	
	// 连接平台
	connect() !
	
	// 断开连接
	disconnect() !
	
	// 发送消息
	send_message(msg Message) !
	
	// 接收消息（阻塞）
	receive_message() !Message
	
	// 设置消息处理器
	set_message_handler(handler fn (Message))
	
	// 获取连接状态
	is_connected() bool
	
	// 获取用户信息
	get_user_info(user_id string) !UserInfo
}

// UserInfo 用户信息
pub struct UserInfo {
	pub:
		id          string
		username    string
		display_name string
		avatar_url  string
		is_bot      bool
}

// ChatInfo 聊天/群组信息
pub struct ChatInfo {
	pub:
		id          string
		type_       string // private, group, channel
		title       string
		member_count int
}

// BaseAdapter 适配器基类，提供通用功能
pub struct BaseAdapter {
	pub mut:
		platform_name    string
		connected        bool
		message_handler  ?fn (Message)
		config           AdapterConfig
}

// AdapterConfig 适配器配置
pub struct AdapterConfig {
	pub mut:
		api_key      string
		api_secret   string
		webhook_url  string
		timeout_ms   int
		retry_count  int
}

// 初始化基类适配器
pub fn new_base_adapter(name string, config AdapterConfig) BaseAdapter {
	return BaseAdapter{
		platform_name: name
		connected: false
		message_handler: none
		config: config
	}
}

// 获取平台名称
pub fn (a &BaseAdapter) name() string {
	return a.platform_name
}

// 获取连接状态
pub fn (a &BaseAdapter) is_connected() bool {
	return a.connected
}

// 设置消息处理器
pub fn (mut a BaseAdapter) set_message_handler(handler fn (Message)) {
	a.message_handler = handler
}

// 触发消息处理器
fn (a &BaseAdapter) on_message(msg Message) {
	if handler := a.message_handler {
		handler(msg)
	}
}

// GatewayManager 网关管理器
// 管理多个平台适配器
pub struct GatewayManager {
	pub mut:
		adapters map[string]PlatformAdapter
		inbound_ch chan Message  // 入站消息通道
}

// 创建网关管理器
pub fn new_gateway_manager() GatewayManager {
	return GatewayManager{
		adapters: map[string]PlatformAdapter{}
		inbound_ch: chan Message{cap: 100}
	}
}

// 注册适配器
pub fn (mut gm GatewayManager) register(adapter PlatformAdapter) {
	gm.adapters[adapter.name()] = adapter
}

// 获取适配器
pub fn (gm &GatewayManager) get_adapter(name string) ?PlatformAdapter {
	return gm.adapters[name] or { return none }
}

// 启动所有适配器
pub fn (mut gm GatewayManager) start_all() ! {
	for _, mut adapter in gm.adapters {
		adapter.connect()!
		
		// 设置消息处理器，将消息转发到入站通道
		adapter.set_message_handler(fn [mut gm] (msg Message) {
			gm.inbound_ch <- msg
		})
		
		// 启动接收循环
		spawn gm.receive_loop(adapter)
	}
}

// 停止所有适配器
pub fn (mut gm GatewayManager) stop_all() ! {
	for _, mut adapter in gm.adapters {
		adapter.disconnect()!
	}
}

// 接收循环
fn (mut gm GatewayManager) receive_loop(adapter PlatformAdapter) {
	for adapter.is_connected() {
		msg := adapter.receive_message() or {
			eprintln('Error receiving message from ${adapter.name()}: ${err}')
			time.sleep(1 * time.second)
			continue
		}
		gm.inbound_ch <- msg
	}
}

// 获取入站消息通道
pub fn (gm &GatewayManager) inbound_channel() chan Message {
	return gm.inbound_ch
}

// 发送消息到指定平台
pub fn (mut gm GatewayManager) send_to_platform(platform string, msg Message) ! {
	adapter := gm.adapters[platform] or {
		return error('platform ${platform} not found')
	}
	adapter.send_message(msg)!
}

// 广播消息到所有平台
pub fn (mut gm GatewayManager) broadcast(msg Message) ! {
	for _, mut adapter in gm.adapters {
		adapter.send_message(msg) or {
			eprintln('Failed to send to ${adapter.name()}: ${err}')
			continue
		}
	}
}
