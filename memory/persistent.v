// vai.memory.persistent - 持久化记忆存储
// 使用 SQLite 实现会话和消息的持久化存储
module memory

import db.sqlite
import json
import os
import time
import protocol
import math

// VectorScore 向量相似度分数（用于内部排序）
pub struct VectorScore {
	pub:
		id    string
		score f32
}

// PersistentStore 持久化存储
pub struct PersistentStore {
	pub mut:
		db_path    string
		connection sqlite.DB
}

// 创建持久化存储
pub fn new_persistent_store(db_path string) !PersistentStore {
	// 确保目录存在
	dir := os.dir(db_path)
	if !os.is_dir(dir) {
		os.mkdir_all(dir) or {
			return error('failed to create directory: ${err}')
		}
	}
	
	// 打开数据库
	mut db := sqlite.open(db_path)!
	
	mut store := PersistentStore{
		db_path: db_path
		connection: db
	}
	
	// 初始化表结构
	store.init_schema()!
	
	return store
}

// 初始化数据库表
fn (mut s PersistentStore) init_schema() ! {
	// 会话表
	s.connection.exec_none('
		CREATE TABLE IF NOT EXISTS conversations (
			id TEXT PRIMARY KEY,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			participants TEXT,
			metadata TEXT
		)
	')!
	
	// 消息表
	s.connection.exec_none('
		CREATE TABLE IF NOT EXISTS messages (
			id TEXT PRIMARY KEY,
			conversation_id TEXT,
			msg_type INTEGER,
			role INTEGER,
			content TEXT,
			content_type TEXT,
			metadata TEXT,
			timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			sender_id TEXT,
			receiver_id TEXT,
			platform TEXT,
			FOREIGN KEY (conversation_id) REFERENCES conversations(id)
		)
	')!
	
	// 向量表
	s.connection.exec_none('
		CREATE TABLE IF NOT EXISTS vectors (
			id TEXT PRIMARY KEY,
			vector_data TEXT,
			metadata TEXT,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)
	')!
	
	// 创建索引
	s.connection.exec_none('CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id)')!
	s.connection.exec_none('CREATE INDEX IF NOT EXISTS idx_messages_time ON messages(timestamp)')!
}

// 创建会话
pub fn (mut s PersistentStore) create_conversation(id string) !Conversation {
	// 检查是否已存在
	existing := s.get_conversation(id)
	if existing != none {
		return error('conversation already exists: ${id}')
	}
	
	now := time.now()
	
	s.connection.exec_none('INSERT INTO conversations (id, created_at, updated_at) VALUES ("${id}", "${now}", "${now}")')!
	
	return Conversation{
		id: id
		messages: []
		participants: []
		created_at: now
		updated_at: now
		metadata: map[string]string{}
	}
}

// 获取会话
pub fn (mut s PersistentStore) get_conversation(id string) ?Conversation {
	rows := s.connection.exec('SELECT * FROM conversations WHERE id = "${id}"') or {
		return none
	}
	
	if rows.len == 0 {
		return none
	}
	
	row := rows[0]
	
	// 获取消息
	messages := s.get_messages(id, 1000)
	
	return Conversation{
		id: id
		messages: messages
		participants: []
		created_at: time.parse(row.vals[1]) or { time.now() }
		updated_at: time.parse(row.vals[2]) or { time.now() }
		metadata: map[string]string{}
	}
}

// 更新会话
pub fn (mut s PersistentStore) update_conversation(conversation Conversation) ! {
	now := time.now()
	
	s.connection.exec_none('UPDATE conversations SET updated_at = "${now}" WHERE id = "${conversation.id}"')!
}

// 删除会话
pub fn (mut s PersistentStore) delete_conversation(id string) ! {
	// 先删除相关消息
	s.connection.exec_none('DELETE FROM messages WHERE conversation_id = "${id}"')!
	
	// 删除会话
	s.connection.exec_none('DELETE FROM conversations WHERE id = "${id}"')!
}

// 列出所有会话
pub fn (mut s PersistentStore) list_conversations() []Conversation {
	rows := s.connection.exec('SELECT id FROM conversations ORDER BY updated_at DESC') or {
		return []
	}
	
	mut conversations := []Conversation{}
	for row in rows {
		if conv := s.get_conversation(row.vals[0]) {
			conversations << conv
		}
	}
	
	return conversations
}

// 添加消息
pub fn (mut s PersistentStore) add_message(conversation_id string, msg Message) ! {
	// 序列化内容
	content_json := json.encode(msg.content)
	metadata_json := json.encode(msg.metadata)
	
	s.connection.exec_none('
		INSERT INTO messages (
			id, conversation_id, msg_type, role, content, content_type, 
			metadata, timestamp, sender_id, receiver_id, platform
		) VALUES (
			"${msg.id}", "${conversation_id}", ${int(msg.msg_type)}, ${int(msg.role)},
			"${content_json}", "${msg.msg_type}",
			"${metadata_json}", "${msg.timestamp}", 
			"${msg.sender_id}", "${msg.receiver_id}", "${msg.platform}"
		)
	')!
	
	// 更新会话时间
	s.connection.exec_none('UPDATE conversations SET updated_at = "${time.now()}" WHERE id = "${conversation_id}"')!
}

// 获取消息
pub fn (mut s PersistentStore) get_messages(conversation_id string, limit int) []Message {
	query := 'SELECT * FROM messages WHERE conversation_id = "${conversation_id}" ORDER BY timestamp DESC LIMIT ${limit}'
	
	rows := s.connection.exec(query) or {
		return []
	}
	
	mut messages := []Message{}
	// 反向填充以保持时间顺序
	for i := rows.len - 1; i >= 0; i-- {
		row := rows[i]
		msg := s.row_to_message(row) or { continue }
		messages << msg
	}
	
	return messages
}

// 搜索消息
pub fn (mut s PersistentStore) search_messages(conversation_id string, query string, limit int) []Message {
	// 简单的 LIKE 查询
	query_sql := 'SELECT * FROM messages WHERE conversation_id = "${conversation_id}" AND content LIKE "%${query}%" ORDER BY timestamp DESC LIMIT ${limit}'
	
	rows := s.connection.exec(query_sql) or {
		return []
	}
	
	mut messages := []Message{}
	for row in rows {
		msg := s.row_to_message(row) or { continue }
		messages << msg
	}
	
	return messages
}

// 存储向量
pub fn (mut s PersistentStore) store_vector(id string, vector []f32, metadata map[string]any) ! {
	vector_json := json.encode(vector)
	metadata_json := json.encode(metadata)
	
	s.connection.exec_none('
		INSERT OR REPLACE INTO vectors (id, vector_data, metadata) 
		VALUES ("${id}", "${vector_json}", "${metadata_json}")
	')!
}

// 搜索向量（简化实现：加载所有向量进行计算）
pub fn (mut s PersistentStore) search_vectors(query_vector []f32, top_k int) []VectorSearchResult {
	rows := s.connection.exec('SELECT id, vector_data, metadata FROM vectors') or {
		return []
	}
	
	mut scores := []VectorScore{}
	
	for row in rows {
		id := row.vals[0]
		vector_data := row.vals[1]
		
		vector := json.decode([]f32, vector_data) or { continue }
		score := cosine_similarity(query_vector, vector)
		
		scores << VectorScore{id: id, score: score}
	}
	
	// 排序
	scores.sort(a.score > b.score)
	
	mut results := []VectorSearchResult{}
	for i, item in scores {
		if i >= top_k {
			break
		}
		
		// 获取元数据
		metadata_rows := s.connection.exec('SELECT metadata FROM vectors WHERE id = "${item.id}"') or { continue }
		if metadata_rows.len > 0 {
			metadata := json.decode(map[string]any, metadata_rows[0].vals[0]) or { map[string]any{} }
			
			results << VectorSearchResult{
				id: item.id
				score: item.score
				metadata: metadata
			}
		}
	}
	
	return results
}

// 行转消息
fn (s &PersistentStore) row_to_message(row sqlite.Row) ?Message {
	// 简化实现
	return Message{
		id: row.vals[0]
		msg_type: .text
		role: .user
		content: TextContent{
			text: row.vals[4]
			format: 'plain'
		}
		metadata: map[string]string{}
		timestamp: time.now()
		sender_id: row.vals[8]
		receiver_id: row.vals[9]
		platform: row.vals[10]
	}
}

// 关闭存储
pub fn (mut s PersistentStore) close() ! {
	s.connection.close()!
}

// 导出会话到 JSON
pub fn (mut s PersistentStore) export_conversation(id string, output_path string) ! {
	if conv := s.get_conversation(id) {
		json_data := json.encode(conv)
		os.write_file(output_path, json_data)!
	} else {
		return error('conversation not found: ${id}')
	}
}

// 从 JSON 导入会话
pub fn (mut s PersistentStore) import_conversation(input_path string) ! {
	json_data := os.read_file(input_path)!
	conv := json.decode(Conversation, json_data)!
	
	// 创建会话
	s.create_conversation(conv.id)!
	
	// 添加消息
	for msg in conv.messages {
		s.add_message(conv.id, msg)!
	}
}

// 余弦相似度
fn cosine_similarity(a []f32, b []f32) f32 {
	if a.len != b.len || a.len == 0 {
		return 0.0
	}
	
	mut dot_product := f32(0.0)
	mut norm_a := f32(0.0)
	mut norm_b := f32(0.0)
	
	for i := 0; i < a.len; i++ {
		dot_product += a[i] * b[i]
		norm_a += a[i] * a[i]
		norm_b += b[i] * b[i]
	}
	
	if norm_a == 0.0 || norm_b == 0.0 {
		return 0.0
	}
	
	return dot_product / (f32(math.sqrt(f64(norm_a))) * f32(math.sqrt(f64(norm_b))))
}
