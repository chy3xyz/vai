// vai.protocol.codec - 协议编解码器
// 实现多种消息格式的序列化和反序列化
module protocol

import json
import encoding.base64
import time

// Codec 编码器接口
pub interface Codec {
	encode(msg Message) ![]u8
	decode(data []u8) !Message
	content_type() string
}

// JSONCodec JSON 编码器
pub struct JSONCodec {}

pub fn (c JSONCodec) encode(msg Message) ![]u8 {
	json_str := msg.to_json()!
	return json_str.bytes()
}

pub fn (c JSONCodec) decode(data []u8) !Message {
	json_str := data.bytestr()
	return message_from_json(json_str)!
}

pub fn (c JSONCodec) content_type() string {
	return 'application/json'
}

// MessagePackCodec MessagePack 编码器 (简化实现)
pub struct MessagePackCodec {}

pub fn (c MessagePackCodec) encode(msg Message) ![]u8 {
	// 简化实现，实际应该使用 MessagePack 库
	// 这里使用 JSON 作为后备
	return JSONCodec{}.encode(msg)!
}

pub fn (c MessagePackCodec) decode(data []u8) !Message {
	// 简化实现
	return JSONCodec{}.decode(data)!
}

pub fn (c MessagePackCodec) content_type() string {
	return 'application/msgpack'
}

// ProtocolVersion 协议版本
pub enum ProtocolVersion {
	v1_0 = 1
	v2_0 = 2
}

// ProtocolHeader 协议头
pub struct ProtocolHeader {
pub:
	version     ProtocolVersion
	msg_type    MessageType
	compression CompressionType
	encrypted   bool
	timestamp   i64 // Unix 时间戳
}

// CompressionType 压缩类型
pub enum CompressionType {
	none
	gzip
	zlib
}

// Packet 数据包结构
pub struct Packet {
pub:
	header  ProtocolHeader
	payload []u8
}

// 打包消息
pub fn pack(msg Message, codec Codec, version ProtocolVersion) !Packet {
	data := codec.encode(msg)!

	return Packet{
		header:  ProtocolHeader{
			version:     version
			msg_type:    msg.msg_type
			compression: .none
			encrypted:   false
			timestamp:   msg.timestamp.unix()
		}
		payload: data
	}
}

// 解包消息
pub fn unpack(packet Packet, codec Codec) !Message {
	return codec.decode(packet.payload)!
}

// Base64 编码工具函数
pub fn encode_base64(data []u8) string {
	return base64.encode(data)
}

pub fn decode_base64(s string) ![]u8 {
	return base64.decode(s)
}

// WebSocketMessage WebSocket 专用消息格式
pub struct WebSocketMessage {
pub:
	op         string // 操作类型: message, ping, pong, connect, disconnect
	message_id string
	data       Message
	timestamp  i64
}

// 创建 WebSocket 消息
pub fn new_ws_message(op string, msg Message) WebSocketMessage {
	return WebSocketMessage{
		op:         op
		message_id: generate_message_id()
		data:       msg
		timestamp:  time.now().unix()
	}
}

// WebSocketMessage 转 JSON
pub fn (ws &WebSocketMessage) to_json() !string {
	return json.encode(ws)
}

// 从 JSON 解析 WebSocketMessage
pub fn ws_message_from_json(data string) !WebSocketMessage {
	return json.decode(WebSocketMessage, data)!
}
