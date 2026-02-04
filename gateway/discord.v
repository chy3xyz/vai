// vai.gateway.discord - Discord 平台适配器
// Discord Bot API 实现，支持 REST API 和 WebSocket Gateway
module gateway

import protocol { Message, MessageType, MessageRole, new_text_message, new_event_message, TextContent }
import net.http
import net.websocket
import json
import time

// DiscordAdapter Discord 适配器
pub struct DiscordAdapter {
	BaseAdapter
	pub mut:
		bot_token    string
		api_base     string = 'https://discord.com/api/v10'
		gateway_url  string = 'wss://gateway.discord.gg/?v=10&encoding=json'
		application_id string
		bot_info     DiscordBotInfo
		ws_client    ?websocket.Client
		session_id   string
		sequence     int  // 心跳序列号
		heartbeat_interval int
}

// DiscordBotInfo Discord 机器人信息
pub struct DiscordBotInfo {
	pub:
		id          string @[json: 'id']
		username    string @[json: 'username']
		discriminator string @[json: 'discriminator']
		avatar      string @[json: 'avatar']
		bot         bool   @[json: 'bot']
}

// DiscordUser Discord 用户
pub struct DiscordUser {
	pub:
		id            string @[json: 'id']
		username      string @[json: 'username']
		discriminator string @[json: 'discriminator']
		avatar        ?string @[json: 'avatar']
		bot           bool   @[json: 'bot']
}

// DiscordChannel Discord 频道
pub struct DiscordChannel {
	pub:
		id          string @[json: 'id']
		type_       int    @[json: 'type']  // 0: GUILD_TEXT, 1: DM, 3: GROUP_DM
		guild_id    ?string @[json: 'guild_id'; omitempty]
		name        string @[json: 'name']
	}

// DiscordMessage Discord 消息
pub struct DiscordMessage {
	pub:
		id          string @[json: 'id']
		channel_id  string @[json: 'channel_id']
		author      DiscordUser @[json: 'author']
		content     string @[json: 'content']
		timestamp   string @[json: 'timestamp']
		type_       int    @[json: 'type']
		referenced_message ?DiscordMessage @[json: 'referenced_message'; omitempty]
}

// DiscordSendMessageRequest 发送消息请求
pub struct DiscordSendMessageRequest {
	pub:
		content     string @[json: 'content']
		reply_to    ?string @[json: 'message_reference'; omitempty]
}

// DiscordGatewayPayload Gateway 消息
pub struct DiscordGatewayPayload {
	pub:
		op          int    @[json: 'op']
		d           json.Any @[json: 'd']
		s           ?int   @[json: 's'; omitempty]
		t           ?string @[json: 't'; omitempty]
}

// DiscordGatewayIdentify 认证消息
pub struct DiscordGatewayIdentify {
	pub:
		token      string @[json: 'token']
		intents    int    @[json: 'intents']
		properties map[string]string @[json: 'properties']
}

// DiscordGatewayHeartbeat 心跳消息
pub struct DiscordGatewayHeartbeat {
	pub:
		op int = 1
		d  ?int @[json: 'd']
}

// DiscordGatewayHello Hello 消息
pub struct DiscordGatewayHello {
	pub:
		heartbeat_interval int @[json: 'heartbeat_interval']
}

// DiscordEvent Discord 事件类型
pub enum DiscordEvent as u8 {
	dispatch = 0
	heartbeat = 1
	identify = 2
	presence_update = 3
	voice_state_update = 4
	resume = 6
	reconnect = 7
	request_guild_members = 8
	invalid_session = 9
	hello = 10
	heartbeat_ack = 11
}

// DiscordIntent 意图常量
pub const (
	discord_intent_guilds = 1 << 0
	discord_intent_guild_messages = 1 << 9
	discord_intent_direct_messages = 1 << 12
	discord_intent_message_content = 1 << 15
)

// 创建 Discord 适配器
pub fn new_discord_adapter(bot_token string) DiscordAdapter {
	return DiscordAdapter{
		BaseAdapter: new_base_adapter('discord', AdapterConfig{
			api_key: bot_token
			timeout_ms: 30000
			retry_count: 3
		})
		bot_token: bot_token
		api_base: 'https://discord.com/api/v10'
		gateway_url: 'wss://gateway.discord.gg/?v=10&encoding=json'
		ws_client: none
		session_id: ''
		sequence: 0
		heartbeat_interval: 0
	}
}

// 连接 Discord（获取 Gateway 并连接 WebSocket）
pub fn (mut a DiscordAdapter) connect() ! {
	// 1. 获取 Bot 信息
	a.load_bot_info()!

	// 2. 获取 Gateway URL
	gateway_url := a.get_gateway_url()!

	// 3. 连接 WebSocket
	mut ws := websocket.new_client(gateway_url)!

	// 设置消息处理器
	ws.on_message_ref(fn [mut a] (mut ws websocket.Client, msg &websocket.Message) ! {
		a.handle_gateway_message(msg)!
	})

	ws.on_close(fn [mut a] (mut ws websocket.Client, code int, reason string) ! {
		println('Discord Gateway closed: ${code} - ${reason}')
		a.connected = false
	})

	ws.connect()!
	a.ws_client = ws

	// 4. 启动心跳
	if a.heartbeat_interval > 0 {
		spawn a.heartbeat_loop()
	}

	a.connected = true
	println('Connected to Discord as ${a.bot_info.username}#${a.bot_info.discriminator}')
}

// 断开连接
pub fn (mut a DiscordAdapter) disconnect() ! {
	a.connected = false
	if mut ws := a.ws_client {
		ws.close(1000, 'Normal closure')!
	}
}

// 发送消息
pub fn (mut a DiscordAdapter) send_message(msg Message) ! {
	if !a.connected {
		return error('not connected to Discord')
	}

	channel_id := msg.receiver_id
	content := msg.text() or { '' }

	mut send_req := DiscordSendMessageRequest{
		content: content
	}

	// 如果有 reply_to
	if reply_id := msg.reply_to {
		send_req = DiscordSendMessageRequest{
			content: content
			reply_to: reply_id
		}
	}

	json_body := json.encode(send_req)

	mut req := http.new_request(.post, '${a.api_base}/channels/${channel_id}/messages', json_body)
	req.header.add(.content_type, 'application/json')
	req.header.add(.authorization, 'Bot ${a.bot_token}')

	resp := http.fetch(req)!

	if resp.status_code != 200 && resp.status_code != 201 {
		return error('failed to send message: ${resp.status_code} - ${resp.body}')
	}
}

// 接收消息（通过 WebSocket）
pub fn (mut a DiscordAdapter) receive_message() !Message {
	if !a.connected {
		return error('not connected to Discord')
	}

	// WebSocket 消息通过回调处理
	// 这里使用阻塞等待模拟
	time.sleep(100 * time.millisecond)

	return error('use message handler for Discord WebSocket')
}

// 获取用户信息
pub fn (mut a DiscordAdapter) get_user_info(user_id string) !UserInfo {
	mut req := http.new_request(.get, '${a.api_base}/users/${user_id}', '')
	req.header.add(.authorization, 'Bot ${a.bot_token}')

	resp := http.fetch(req)!

	if resp.status_code != 200 {
		return error('failed to get user info: ${resp.status_code}')
	}

	user := json.decode(DiscordUser, resp.body)!

	return UserInfo{
		id: user.id
		username: user.username
		display_name: '${user.username}#${user.discriminator}'
		avatar_url: if avatar := user.avatar { 'https://cdn.discordapp.com/avatars/${user.id}/${avatar}.png' } else { '' }
		is_bot: user.bot
	}
}

// 加载 Bot 信息
fn (mut a DiscordAdapter) load_bot_info() ! {
	mut req := http.new_request(.get, '${a.api_base}/users/@me', '')
	req.header.add(.authorization, 'Bot ${a.bot_token}')

	resp := http.fetch(req)!

	if resp.status_code != 200 {
		return error('failed to load bot info: ${resp.status_code}')
	}

	a.bot_info = json.decode(DiscordBotInfo, resp.body)!
	a.application_id = a.bot_info.id
}

// 获取 Gateway URL
fn (mut a DiscordAdapter) get_gateway_url() !string {
	mut req := http.new_request(.get, '${a.api_base}/gateway/bot', '')
	req.header.add(.authorization, 'Bot ${a.bot_token}')

	resp := http.fetch(req)!

	if resp.status_code != 200 {
		return error('failed to get gateway: ${resp.status_code}')
	}

	// 解析响应
	gateway_resp := json.decode(map[string]json.Any, resp.body)!

	if url := gateway_resp['url'] {
		return url.str()
	}

	return a.gateway_url
}

// 处理 Gateway 消息
fn (mut a DiscordAdapter) handle_gateway_message(msg &websocket.Message) ! {
	if msg.payload.len == 0 {
		return
	}

	payload := json.decode(DiscordGatewayPayload, msg.payload.bytestr()) or {
		return error('failed to parse gateway message')
	}

	match payload.op {
		0 { // Dispatch (事件)
			a.sequence = payload.s or { a.sequence }
			a.handle_dispatch(payload.t or { '' }, payload.d)!
		}
		10 { // Hello
			hello := json.decode(DiscordGatewayHello, payload.d.str())!
			a.heartbeat_interval = hello.heartbeat_interval
			// 发送 Identify
			a.send_identify()!
		}
		11 { // Heartbeat ACK
			// 心跳确认
		}
		1 { // Heartbeat Request
			a.send_heartbeat()!
		}
		9 { // Invalid Session
			a.connected = false
		}
		else {}
	}
}

// 处理分发事件
fn (mut a DiscordAdapter) handle_dispatch(event_type string, data json.Any) ! {
	match event_type {
		'READY' {
			// 连接成功
			ready_data := json.decode(map[string]json.Any, data.str())!
			if session_id := ready_data['session_id'] {
				a.session_id = session_id.str()
			}
			println('Discord Gateway ready')
		}
		'MESSAGE_CREATE' {
			// 新消息
			discord_msg := json.decode(DiscordMessage, data.str())!

			// 忽略自己的消息
			if discord_msg.author.id == a.bot_info.id {
				return
			}

			msg := a.convert_to_message(discord_msg)

			// 触发消息处理器
			a.on_message(msg)
		}
		'GUILD_CREATE' {}
		'GUILD_DELETE' {}
		else {}
	}
}

// 发送 Identify
fn (mut a DiscordAdapter) send_identify() ! {
	identify := DiscordGatewayIdentify{
		token: a.bot_token
		intents: discord_intent_guilds | discord_intent_guild_messages |
		         discord_intent_direct_messages | discord_intent_message_content
		properties: {
			'os': 'linux'
			'browser': 'vai'
			'device': 'vai'
		}
	}

	payload := DiscordGatewayPayload{
		op: int(DiscordEvent.identify)
		d: json.Any(json.encode(identify))
	}

	if mut ws := a.ws_client {
		ws.write_string(json.encode(payload))!
	}
}

// 发送心跳
fn (mut a DiscordAdapter) send_heartbeat() ! {
	heartbeat := DiscordGatewayHeartbeat{
		op: int(DiscordEvent.heartbeat)
		d: if a.sequence > 0 { a.sequence } else { none }
	}

	if mut ws := a.ws_client {
		ws.write_string(json.encode(heartbeat))!
	}
}

// 心跳循环
fn (mut a DiscordAdapter) heartbeat_loop() {
	for a.connected && a.heartbeat_interval > 0 {
		time.sleep(a.heartbeat_interval * time.millisecond)

		if a.connected {
			a.send_heartbeat() or {
				eprintln('Heartbeat failed: ${err}')
			}
		}
	}
}

// 将 Discord 消息转换为统一消息格式
fn (a &DiscordAdapter) convert_to_message(discord_msg DiscordMessage) Message {
	return Message{
		id: discord_msg.id
		msg_type: .text
		role: if discord_msg.author.bot { .assistant } else { .user }
		content: TextContent{
			text: discord_msg.content
			format: 'plain'
		}
		metadata: map[string]string{}
		timestamp: time.parse_rfc3339(discord_msg.timestamp) or { time.now() }
		sender_id: discord_msg.author.id
		receiver_id: discord_msg.channel_id
		reply_to: if ref := discord_msg.referenced_message { ref.id } else { none }
		platform: 'discord'
		conversation_id: discord_msg.channel_id
	}
}

// 触发消息处理器
fn (mut a DiscordAdapter) on_message(msg Message) {
	if handler := a.message_handler {
		handler(msg)
	}
}

// 获取频道列表
pub fn (mut a DiscordAdapter) list_channels(guild_id string) ![]DiscordChannel {
	mut req := http.new_request(.get, '${a.api_base}/guilds/${guild_id}/channels', '')
	req.header.add(.authorization, 'Bot ${a.bot_token}')

	resp := http.fetch(req)!

	if resp.status_code != 200 {
		return error('failed to list channels: ${resp.status_code}')
	}

	channels := json.decode([]DiscordChannel, resp.body)!
	return channels
}

// 加入频道（需要权限）
pub fn (mut a DiscordAdapter) join_channel(channel_id string) ! {
	// Discord 通过邀请链接加入，这里简化处理
	println('Use Discord invite links to join channels')
}

// 离开频道
pub fn (mut a DiscordAdapter) leave_channel(channel_id string) ! {
	mut req := http.new_request(.delete, '${a.api_base}/users/@me/channels/${channel_id}', '')
	req.header.add(.authorization, 'Bot ${a.bot_token}')

	resp := http.fetch(req)!

	if resp.status_code != 200 && resp.status_code != 204 {
		return error('failed to leave channel: ${resp.status_code}')
	}
}
