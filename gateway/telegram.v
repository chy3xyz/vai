// vai.gateway.telegram - Telegram 平台适配器
// 基于 HTTP API 实现 Telegram Bot 适配
module gateway

import protocol { Message, MessageType, MessageRole, new_text_message, new_event_message, TextContent }
import net.http
import json
import time


// TelegramAdapter Telegram 适配器
pub struct TelegramAdapter {
	BaseAdapter
	pub mut:
		bot_token    string
		api_base     string
		offset       int  // 更新偏移量
	
}

// TelegramUpdate Telegram 更新对象
pub struct TelegramUpdate {
	update_id      int                @[json: 'update_id']
	message        ?TelegramMessage   @[json: 'message']
	edited_message ?TelegramMessage   @[json: 'edited_message']
}

// TelegramMessage Telegram 消息对象
pub struct TelegramMessage {
	message_id int                @[json: 'message_id']
	from       ?TelegramUser      @[json: 'from']
	date       int                @[json: 'date']
	chat       TelegramChat       @[json: 'chat']
	text       ?string            @[json: 'text']
	caption    ?string            @[json: 'caption']
	photo      ?[]TelegramPhotoSize @[json: 'photo']
	document   ?TelegramDocument  @[json: 'document']
	audio      ?TelegramAudio     @[json: 'audio']
	voice      ?TelegramVoice     @[json: 'voice']
	video      ?TelegramVideo     @[json: 'video']
	location   ?TelegramLocation  @[json: 'location']
	contact    ?TelegramContact   @[json: 'contact']
}

// TelegramUser Telegram 用户
pub struct TelegramUser {
	id         int    @[json: 'id']
	is_bot     bool   @[json: 'is_bot']
	first_name string @[json: 'first_name']
	last_name  ?string @[json: 'last_name']
	username   ?string @[json: 'username']
}

// TelegramChat Telegram 聊天
pub struct TelegramChat {
	id    int    @[json: 'id']
	type_ string @[json: 'type']
	title ?string @[json: 'title']
}

// TelegramPhotoSize Telegram 图片
pub struct TelegramPhotoSize {
	file_id   string @[json: 'file_id']
	file_unique_id string @[json: 'file_unique_id']
	width     int    @[json: 'width']
	height    int    @[json: 'height']
	file_size ?int   @[json: 'file_size']
}

// TelegramDocument Telegram 文档
pub struct TelegramDocument {
	file_id   string @[json: 'file_id']
	file_unique_id string @[json: 'file_unique_id']
	file_name ?string @[json: 'file_name']
	mime_type ?string @[json: 'mime_type']
	file_size ?int   @[json: 'file_size']
}

// TelegramAudio Telegram 音频
pub struct TelegramAudio {
	file_id   string @[json: 'file_id']
	file_unique_id string @[json: 'file_unique_id']
	duration  int    @[json: 'duration']
	mime_type ?string @[json: 'mime_type']
	file_size ?int   @[json: 'file_size']
}

// TelegramVoice Telegram 语音
pub struct TelegramVoice {
	file_id   string @[json: 'file_id']
	file_unique_id string @[json: 'file_unique_id']
	duration  int    @[json: 'duration']
	mime_type ?string @[json: 'mime_type']
	file_size ?int   @[json: 'file_size']
}

// TelegramVideo Telegram 视频
pub struct TelegramVideo {
	file_id   string @[json: 'file_id']
	file_unique_id string @[json: 'file_unique_id']
	width     int    @[json: 'width']
	height    int    @[json: 'height']
	duration  int    @[json: 'duration']
	mime_type ?string @[json: 'mime_type']
	file_size ?int   @[json: 'file_size']
}

// TelegramLocation Telegram 位置
pub struct TelegramLocation {
	latitude  f64 @[json: 'latitude']
	longitude f64 @[json: 'longitude']
}

// TelegramContact Telegram 联系人
pub struct TelegramContact {
	phone_number string @[json: 'phone_number']
	first_name   string @[json: 'first_name']
	last_name    ?string @[json: 'last_name']
	user_id      ?int    @[json: 'user_id']
}

// TelegramResponse API 响应
pub struct TelegramResponse {
	ok          bool @[json: 'ok']
	result      string @[json: 'result']
	description ?string @[json: 'description']
}

// 创建 Telegram 适配器
pub fn new_telegram_adapter(bot_token string) &TelegramAdapter {
	return &TelegramAdapter{
		BaseAdapter: new_base_adapter('telegram', AdapterConfig{
			timeout_ms: 30000
			retry_count: 3
		})
		bot_token: bot_token
		api_base: 'https://api.telegram.org/bot${bot_token}'
		offset: 0
	}
}

// 连接 Telegram（验证 token）
pub fn (mut a TelegramAdapter) connect() ! {
	resp := a.make_request('getMe', {})!
	
	if !resp.ok {
		return error('failed to connect to Telegram: ${resp.description or { 'unknown error' }}')
	}
	
	a.connected = true
	println('Connected to Telegram Bot API')
}

// 断开连接
pub fn (mut a TelegramAdapter) disconnect() ! {
	a.connected = false
}

// 发送消息
pub fn (mut a TelegramAdapter) send_message(msg Message) ! {
	if !a.connected {
		return error('not connected to Telegram')
	}
	
	// 从 receiver_id 解析 chat_id
	chat_id := msg.receiver_id.int()
	
	match msg.msg_type {
		.text {
			if msg.content is TextContent {
				params := {
					'chat_id': chat_id.str()
					'text': msg.content.text
				}
				a.make_request('sendMessage', params)!
			}
		}
		else {
			// 其他类型暂未实现，发送文本提示
			params := {
				'chat_id': chat_id.str()
				'text': '[${msg.msg_type}] Message (unsupported in this version)'
			}
			a.make_request('sendMessage', params)!
		}
	}
}

// 接收消息（轮询方式）
pub fn (mut a TelegramAdapter) receive_message() !Message {
	if !a.connected {
		return error('not connected to Telegram')
	}
	
	// 使用长轮询获取更新
	params := {
		'offset': (a.offset + 1).str()
		'limit': '10'
		'timeout': '30'
	}
	
	resp := a.make_request('getUpdates', params)!
	
	if !resp.ok {
		return error('failed to get updates: ${resp.description or { 'unknown error' }}')
	}
	
	// For V 0.5, parse updates directly from string
	// Parse JSON array from response
	if resp.result.len < 3 {  // Empty array "[]"
		time.sleep(100 * time.millisecond)
		return error('no new messages')
	}
	
	// TODO: Implement proper JSON array parsing for V 0.5
	// For now, return placeholder
	return error('no new messages')
}

// 获取用户信息
pub fn (mut a TelegramAdapter) get_user_info(user_id string) !UserInfo {
	// Telegram Bot API 没有直接获取用户信息的方法
	// 返回占位信息
	return UserInfo{
		id: user_id
		username: 'unknown'
		display_name: 'Unknown'
		is_bot: false
	}
}

// 发送 API 请求
fn (mut a TelegramAdapter) make_request(method string, params map[string]string) !TelegramResponse {
	url := '${a.api_base}/${method}'
	
	mut form_data := ''
	for key, value in params {
		if form_data.len > 0 {
			form_data += '&'
		}
		form_data += '${key}=${value}'
	}
	
	mut req := http.new_request(.post, url, form_data)
	req.header.add(.content_type, 'application/x-www-form-urlencoded')
	
	resp := http.fetch(url: req.url, method: .post, header: req.header, data: req.data)!
	
	if resp.status_code != 200 {
		return error('HTTP error: ${resp.status_code}')
	}
	
	return json.decode(TelegramResponse, resp.body)!
}

// 将 Telegram 消息转换为统一消息格式
fn (a &TelegramAdapter) convert_to_message(tg_msg TelegramMessage) Message {
	user_id := if user := tg_msg.from { user.id.str() } else { '0' }
	chat_id := tg_msg.chat.id.str()
	
	// 确定消息类型和内容
	mut msg_type := MessageType.text
	mut content := protocol.MessageContent(TextContent{
		text: tg_msg.text or { '' }
		format: 'plain'
	})
	
	if tg_msg.photo != none {
		msg_type = .image
	} else if tg_msg.document != none {
		msg_type = .file
	} else if tg_msg.audio != none || tg_msg.voice != none {
		msg_type = .audio
	} else if tg_msg.video != none {
		msg_type = .video
	} else if tg_msg.location != none {
		msg_type = .location
	} else if tg_msg.contact != none {
		msg_type = .contact
	}
	
	return Message{
		id: tg_msg.message_id.str()
		msg_type: msg_type
		role: .user
		content: content
		metadata: map[string]string{}
		timestamp: time.unix(int(tg_msg.date))
		sender_id: user_id
		receiver_id: chat_id
		platform: 'telegram'
	}
}
