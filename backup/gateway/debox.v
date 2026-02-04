// vai.gateway.debox - DeBox 平台适配器
// DeBox 是一个 Web3 社交应用，提供聊天、社区和支付功能
// 参考: https://github.com/debox-pro/debox-chat-go-sdk
module gateway

import protocol { Message, MessageType, MessageRole, new_text_message, new_event_message, TextContent }
import net.http
import json
import time
import crypto.hmac
import crypto.sha256

// DeBoxAdapter DeBox 适配器
pub struct DeBoxAdapter {
	BaseAdapter
	pub mut:
		app_id       string
		app_secret   string
		api_base     string
		access_token string
		token_expire i64  // 令牌过期时间
		bot_info     DeBoxBotInfo
}

// DeBoxBotInfo DeBox 机器人信息
pub struct DeBoxBotInfo {
	pub:
		id          string @[json: 'id']
		name        string @[json: 'name']
		avatar      string @[json: 'avatar']
		description string @[json: 'description']
		group_count int    @[json: 'group_count']
		user_count  int    @[json: 'user_count']
}

// DeBoxUser DeBox 用户信息
pub struct DeBoxUser {
	pub:
		id         string @[json: 'id']
		nickname   string @[json: 'nickname']
		avatar     string @[json: 'avatar']
		address    string @[json: 'address']  // Web3 钱包地址
		is_follow  bool   @[json: 'is_follow']
		is_block   bool   @[json: 'is_block']
}

// DeBoxGroup DeBox 群组
pub struct DeBoxGroup {
	pub:
		id          string @[json: 'id']
		name        string @[json: 'name']
		icon        string @[json: 'icon']
		description string @[json: 'description']
		owner_id    string @[json: 'owner_id']
		member_count int   @[json: 'member_count']
		max_members int   @[json: 'max_members']
		is_private  bool  @[json: 'is_private']
		created_at  i64   @[json: 'created_at']
}

// DeBoxMessage DeBox 消息格式
pub struct DeBoxMessage {
	pub:
		id          string @[json: 'id']
		group_id    string @[json: 'group_id']
		channel_id  string @[json: 'channel_id']
		author      DeBoxUser @[json: 'author']
		content     string @[json: 'content']
		type_       int    @[json: 'type']  // 1: 文本, 2: 图片, 3: 音频, 4: 视频, 5: 文件, 6: 系统
		status      int    @[json: 'status']  // 0: 正常, 1: 已撤回
		timestamp   i64    @[json: 'timestamp']
		reply_to    ?string @[json: 'reply_to'; omitempty]
		ext         map[string]any @[json: 'ext']  // 扩展字段
}

// DeBoxSendRequest 发送消息请求
pub struct DeBoxSendRequest {
	pub:
		group_id   string @[json: 'group_id']
		channel_id string @[json: 'channel_id']
		content    string @[json: 'content']
		type_      int    @[json: 'type']
		reply_to   ?string @[json: 'reply_to'; omitempty]
}

// DeBoxAPIResponse API 响应
pub struct DeBoxAPIResponse {
	pub:
		code    int    @[json: 'code']
		msg     string @[json: 'msg']
		data    json.Any @[json: 'data']
	}

// DeBoxTokenResponse 令牌响应
pub struct DeBoxTokenResponse {
	pub:
		access_token string @[json: 'access_token']
		expires_in   int    @[json: 'expires_in']
		token_type   string @[json: 'token_type']
}

// DeBoxWebhookBody Webhook 回调体
pub struct DeBoxWebhookBody {
	pub:
		event     string @[json: 'event']
		timestamp i64    @[json: 'timestamp']
		sign      string @[json: 'sign']
		data      json.Any @[json: 'data']
}

// DeBoxMessageEvent 消息事件
pub struct DeBoxMessageEvent {
	pub:
		message DeBoxMessage @[json: 'message']
		group   DeBoxGroup   @[json: 'group']
}

// 创建 DeBox 适配器
pub fn new_debox_adapter(app_id string, app_secret string) DeBoxAdapter {
	return DeBoxAdapter{
		BaseAdapter: new_base_adapter('debox', AdapterConfig{
			api_key: app_id
			api_secret: app_secret
			timeout_ms: 30000
			retry_count: 3
		})
		app_id: app_id
		app_secret: app_secret
		api_base: 'https://open.debox.pro/openapi/v1'
		access_token: ''
		token_expire: 0
	}
}

// 创建带自定义 API 地址的适配器
pub fn new_debox_adapter_with_base(app_id string, app_secret string, api_base string) DeBoxAdapter {
	mut adapter := new_debox_adapter(app_id, app_secret)
	adapter.api_base = api_base
	return adapter
}

// 连接 DeBox（获取访问令牌）
pub fn (mut a DeBoxAdapter) connect() ! {
	// 获取访问令牌
	a.refresh_token()!
	
	// 加载 Bot 信息
	a.load_bot_info()!
	
	a.connected = true
	println('Connected to DeBox as bot: ${a.bot_info.name}')
}

// 刷新访问令牌
fn (mut a DeBoxAdapter) refresh_token() ! {
	timestamp := time.now().unix
	
	// 构造签名
	sign_str := '${a.app_id}${timestamp}'
	signature := a.generate_sign(sign_str)
	
	// 请求令牌
	params := {
		'app_id': a.app_id
		'timestamp': timestamp.str()
		'sign': signature
	}
	
	mut form_data := ''
	for key, value in params {
		if form_data.len > 0 {
			form_data += '&'
		}
		form_data += '${key}=${value}'
	}
	
	mut req := http.new_request(.post, '${a.api_base}/auth/token', form_data)
	req.header.add(.content_type, 'application/x-www-form-urlencoded')
	
	resp := http.fetch(req)!
	
	if resp.status_code != 200 {
		return error('DeBox auth failed: ${resp.status_code}')
	}
	
	api_resp := json.decode(DeBoxAPIResponse, resp.body)!
	
	if api_resp.code != 0 {
		return error('DeBox auth error: ${api_resp.msg}')
	}
	
	token_data := api_resp.data.str()
	token_resp := json.decode(DeBoxTokenResponse, token_data)!
	
	a.access_token = token_resp.access_token
	a.token_expire = time.now().unix() + token_resp.expires_in
	
	// 更新配置
	a.config.api_key = a.access_token
}

// 生成签名
fn (a &DeBoxAdapter) generate_sign(data string) string {
	return hmac.new(sha256.new(), a.app_secret.bytes(), data.bytes()).hex()
}

// 检查并刷新令牌
fn (mut a DeBoxAdapter) ensure_token() ! {
	if time.now().unix() >= a.token_expire - 60 {
		a.refresh_token()!
	}
}

// 加载 Bot 信息
fn (mut a DeBoxAdapter) load_bot_info() ! {
	a.ensure_token()!
	
	mut req := http.new_request(.get, '${a.api_base}/bot/info', '')
	req.header.add(.authorization, 'Bearer ${a.access_token}')
	
	resp := http.fetch(req)!
	
	if resp.status_code != 200 {
		return error('failed to load bot info: ${resp.status_code}')
	}
	
	api_resp := json.decode(DeBoxAPIResponse, resp.body)!
	
	if api_resp.code != 0 {
		return error('API error: ${api_resp.msg}')
	}
	
	bot_data := api_resp.data.str()
	a.bot_info = json.decode(DeBoxBotInfo, bot_data)!
}

// 断开连接
pub fn (mut a DeBoxAdapter) disconnect() ! {
	a.connected = false
}

// 发送消息
pub fn (mut a DeBoxAdapter) send_message(msg Message) ! {
	if !a.connected {
		return error('not connected to DeBox')
	}
	
	a.ensure_token()!
	
	// 解析 receiver_id 格式: "group_id:channel_id"
	group_id := msg.receiver_id
	channel_id := '1'  // 默认频道
	
	// 获取文本内容
	content := msg.text() or { '' }
	
	send_req := DeBoxSendRequest{
		group_id: group_id
		channel_id: channel_id
		content: content
		type_: 1  // 文本消息
		reply_to: msg.reply_to
	}
	
	json_body := json.encode(send_req)
	
	mut req := http.new_request(.post, '${a.api_base}/message/send', json_body)
	req.header.add(.content_type, 'application/json')
	req.header.add(.authorization, 'Bearer ${a.access_token}')
	
	resp := http.fetch(req)!
	
	if resp.status_code != 200 {
		return error('failed to send message: ${resp.status_code}')
	}
	
	api_resp := json.decode(DeBoxAPIResponse, resp.body)!
	
	if api_resp.code != 0 {
		return error('API error: ${api_resp.msg}')
	}
}

// 接收消息（轮询方式）
pub fn (mut a DeBoxAdapter) receive_message() !Message {
	if !a.connected {
		return error('not connected to DeBox')
	}
	
	a.ensure_token()!
	
	// 获取消息列表
	mut req := http.new_request(.get, '${a.api_base}/message/receive', '')
	req.header.add(.authorization, 'Bearer ${a.access_token}')
	
	resp := http.fetch(req)!
	
	if resp.status_code != 200 {
		return error('poll failed: ${resp.status_code}')
	}
	
	api_resp := json.decode(DeBoxAPIResponse, resp.body)!
	
	if api_resp.code != 0 {
		return error('API error: ${api_resp.msg}')
	}
	
	// 解析消息列表
	messages := api_resp.data.arr()
	if messages.len == 0 {
		return error('no new messages')
	}
	
	// 返回第一条消息
	msg_data := messages[0].str()
	debox_msg := json.decode(DeBoxMessage, msg_data)!
	
	return a.convert_to_message(debox_msg)
}

// 获取用户信息
pub fn (mut a DeBoxAdapter) get_user_info(user_id string) !UserInfo {
	a.ensure_token()!
	
	mut req := http.new_request(.get, '${a.api_base}/user/info?user_id=${user_id}', '')
	req.header.add(.authorization, 'Bearer ${a.access_token}')
	
	resp := http.fetch(req)!
	
	if resp.status_code != 200 {
		return error('failed to get user info: ${resp.status_code}')
	}
	
	api_resp := json.decode(DeBoxAPIResponse, resp.body)!
	
	if api_resp.code != 0 {
		return error('API error: ${api_resp.msg}')
	}
	
	user_data := api_resp.data.str()
	user := json.decode(DeBoxUser, user_data)!
	
	return UserInfo{
		id: user.id
		username: user.nickname
		display_name: user.nickname
		avatar_url: user.avatar
		is_bot: false
	}
}

// 将 DeBox 消息转换为统一消息格式
fn (a &DeBoxAdapter) convert_to_message(debox_msg DeBoxMessage) Message {
	// 确定消息类型
	mut msg_type := MessageType.text
	match debox_msg.type_ {
		2 { msg_type = .image }
		3 { msg_type = .audio }
		4 { msg_type = .video }
		5 { msg_type = .file }
		6 { msg_type = .event }
		else {}
	}
	
	return Message{
		id: debox_msg.id
		msg_type: msg_type
		role: if debox_msg.author.id == a.bot_info.id { .assistant } else { .user }
		content: TextContent{
			text: debox_msg.content
			format: 'plain'
		}
		metadata: map[string]string{}
		timestamp: time.unix(debox_msg.timestamp / 1000)  // DeBox 使用毫秒时间戳
		sender_id: debox_msg.author.id
		receiver_id: debox_msg.group_id
		reply_to: debox_msg.reply_to
		platform: 'debox'
		conversation_id: debox_msg.group_id
	}
}

// 获取群组列表
pub fn (mut a DeBoxAdapter) list_groups() ![]DeBoxGroup {
	a.ensure_token()!
	
	mut req := http.new_request(.get, '${a.api_base}/group/list', '')
	req.header.add(.authorization, 'Bearer ${a.access_token}')
	
	resp := http.fetch(req)!
	
	if resp.status_code != 200 {
		return error('failed to list groups: ${resp.status_code}')
	}
	
	api_resp := json.decode(DeBoxAPIResponse, resp.body)!
	
	if api_resp.code != 0 {
		return error('API error: ${api_resp.msg}')
	}
	
	mut groups := []DeBoxGroup{}
	for g_data in api_resp.data.arr() {
		group := json.decode(DeBoxGroup, g_data.str()) or { continue }
		groups << group
	}
	
	return groups
}

// 获取群组成员
pub fn (mut a DeBoxAdapter) get_group_members(group_id string) ![]DeBoxUser {
	a.ensure_token()!
	
	mut req := http.new_request(.get, '${a.api_base}/group/members?group_id=${group_id}', '')
	req.header.add(.authorization, 'Bearer ${a.access_token}')
	
	resp := http.fetch(req)!
	
	if resp.status_code != 200 {
		return error('failed to get group members: ${resp.status_code}')
	}
	
	api_resp := json.decode(DeBoxAPIResponse, resp.body)!
	
	if api_resp.code != 0 {
		return error('API error: ${api_resp.msg}')
	}
	
	mut members := []DeBoxUser{}
	for m_data in api_resp.data.arr() {
		member := json.decode(DeBoxUser, m_data.str()) or { continue }
		members << member
	}
	
	return members
}

// 验证 Webhook 签名
pub fn (a &DeBoxAdapter) verify_webhook_sign(body string, sign string) bool {
	expected_sign := a.generate_sign(body)
	return hmac.equal(sign.bytes(), expected_sign.bytes())
}

// 解析 Webhook 事件
pub fn (a &DeBoxAdapter) parse_webhook_event(body string) !DeBoxWebhookBody {
	return json.decode(DeBoxWebhookBody, body)!
}

// 消息类型常量
pub const (
	msg_type_text  = 1
	msg_type_image = 2
	msg_type_audio = 3
	msg_type_video = 4
	msg_type_file  = 5
	msg_type_system = 6
)
