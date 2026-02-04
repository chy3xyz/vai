// vai.protocol - 消息协议抽象层
// 定义统一的消息模型，支持文本、图片、文件、命令等多种消息类型
module protocol

import json
import time

// MessageType 消息类型枚举
pub enum MessageType {
	unknown
	text       // 纯文本消息
	image      // 图片消息
	file       // 文件消息
	audio      // 音频消息
	video      // 视频消息
	command    // 命令消息
	event      // 事件消息
	location   // 位置消息
	contact    // 联系人消息
}

// MessageRole 消息角色
pub enum MessageRole {
	unknown
	system     // 系统角色
	user       // 用户
	assistant  // AI 助手
	tool       // 工具/技能
}

// Message 统一消息结构体
// 使用 sumtype 实现多态消息内容
pub struct Message {
	pub mut:
		id          string            // 消息唯一标识
		msg_type    MessageType       // 消息类型
		role        MessageRole       // 消息角色
		content     MessageContent    // 消息内容 (sumtype)
		metadata    map[string]string // 元数据
		timestamp   time.Time         // 时间戳
		sender_id   string            // 发送者ID
		receiver_id string            // 接收者ID
		reply_to    ?string           // 回复的消息ID
		platform    string            // 来源平台
		conversation_id string        // 会话ID
}

// MessageContent 消息内容 sumtype
// 支持多种内容类型
pub type MessageContent = TextContent | ImageContent | FileContent | AudioContent | VideoContent | CommandContent | EventContent | LocationContent | ContactContent | RawContent

// TextContent 文本内容
pub struct TextContent {
	pub:
		text       string  // 文本内容
		format     string  // 格式: plain, markdown, html
		mentions   []string // @提及的用户ID列表
}

// ImageContent 图片内容
pub struct ImageContent {
	pub:
		url        string  // 图片URL
		data       ?[]u8   // 图片二进制数据
		caption    string  // 图片说明
		mime_type  string  // MIME类型
		width      int     // 宽度
		height     int     // 高度
		file_size  int     // 文件大小(字节)
}

// FileContent 文件内容
pub struct FileContent {
	pub:
		url        string  // 文件URL
		data       ?[]u8   // 文件二进制数据
		filename   string  // 文件名
		mime_type  string  // MIME类型
		file_size  int     // 文件大小
}

// AudioContent 音频内容
pub struct AudioContent {
	pub:
		url        string  // 音频URL
		data       ?[]u8   // 音频二进制数据
		duration   int     // 时长(秒)
		mime_type  string  // MIME类型
		transcript ?string // 语音转文字
}

// VideoContent 视频内容
pub struct VideoContent {
	pub:
		url        string  // 视频URL
		data       ?[]u8   // 视频二进制数据
		duration   int     // 时长(秒)
		width      int     // 宽度
		height     int     // 高度
		mime_type  string  // MIME类型
		file_size  int     // 文件大小
}

// CommandContent 命令内容
pub struct CommandContent {
	pub:
		command    string            // 命令名
		args       []string          // 参数列表
		kwargs     map[string]string // 键值参数
		skill_id   string            // 关联的技能ID
}

// EventContent 事件内容
pub struct EventContent {
	pub:
		event_type string            // 事件类型
		payload    map[string]any    // 事件数据
}

// LocationContent 位置内容
pub struct LocationContent {
	pub:
		latitude   f64     // 纬度
		longitude  f64     // 经度
		address    string  // 地址描述
		name       string  // 地点名称
}

// ContactContent 联系人内容
pub struct ContactContent {
	pub:
		user_id    string  // 用户ID
		username   string  // 用户名
		first_name string  // 名
		last_name  string  // 姓
		phone      string  // 电话
}

// RawContent 原始内容（用于自定义扩展）
pub struct RawContent {
	pub:
		data []u8
	}

// 创建文本消息
pub fn new_text_message(text string) Message {
	return Message{
		id: generate_message_id()
		msg_type: .text
		role: .user
		content: TextContent{
			text: text
			format: 'plain'
		}
		timestamp: time.now()
		metadata: map[string]string{}
	}
}

// 创建图片消息
pub fn new_image_message(url string, caption string) Message {
	return Message{
		id: generate_message_id()
		msg_type: .image
		role: .user
		content: ImageContent{
			url: url
			caption: caption
			mime_type: 'image/jpeg'
		}
		timestamp: time.now()
		metadata: map[string]string{}
	}
}

// 创建命令消息
pub fn new_command_message(command string, args []string, kwargs map[string]string) Message {
	return Message{
		id: generate_message_id()
		msg_type: .command
		role: .user
		content: CommandContent{
			command: command
			args: args
			kwargs: kwargs
		}
		timestamp: time.now()
		metadata: map[string]string{}
	}
}

// 创建事件消息
pub fn new_event_message(event_type string, payload map[string]any) Message {
	return Message{
		id: generate_message_id()
		msg_type: .event
		role: .system
		content: EventContent{
			event_type: event_type
			payload: payload
		}
		timestamp: time.now()
		metadata: map[string]string{}
	}
}

// 获取文本内容
pub fn (msg &Message) text() ?string {
	if msg.msg_type != .text {
		return none
	}
	if content := msg.content as TextContent {
		return content.text
	}
	return none
}

// 获取命令内容
pub fn (msg &Message) command() ?CommandContent {
	if msg.msg_type != .command {
		return none
	}
	if content := msg.content as CommandContent {
		return content
	}
	return none
}

// 序列化为 JSON
pub fn (msg &Message) to_json() !string {
	return json.encode(msg)
}

// 从 JSON 反序列化
pub fn message_from_json(data string) !Message {
	return json.decode(Message, data)!
}

// 生成消息 ID
fn generate_message_id() string {
	return 'msg_${time.now().unix_micro}_${rand_chars(6)}'
}

// 生成随机字符
fn rand_chars(len int) string {
	chars := 'abcdefghijklmnopqrstuvwxyz0123456789'
	mut result := ''
	seed := time.now().unix
	for i := 0; i < len; i++ {
		idx := (seed + i * 7) % chars.len
		result += chars[idx].ascii_str()
	}
	return result
}

// Conversation 会话管理
pub struct Conversation {
	pub mut:
		id          string
		messages    []Message
		participants []string
		created_at  time.Time
		updated_at  time.Time
		metadata    map[string]string
}

// 创建新会话
pub fn new_conversation(id string) Conversation {
	now := time.now()
	return Conversation{
		id: id
		messages: []
		participants: []
		created_at: now
		updated_at: now
		metadata: map[string]string{}
	}
}

// 添加消息到会话
pub fn (mut c Conversation) add_message(msg Message) {
	c.messages << msg
	c.updated_at = time.now()
}

// 获取最后 N 条消息
pub fn (c &Conversation) last_messages(n int) []Message {
	if c.messages.len <= n {
		return c.messages
	}
	return c.messages[c.messages.len - n..]
}

// 获取会话中的消息数
pub fn (c &Conversation) message_count() int {
	return c.messages.len
}
