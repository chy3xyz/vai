// vai.memory.persistent - 持久化记忆存储
// 实现文件存储的持久化记忆系统，支持每日笔记和长期记忆
module memory

import protocol
import json
import os
import time
// DailyNotesManager 和 LongTermMemoryManager 在同一模块中，直接使用

// VectorScore 向量相似度分数（用于内部排序）
pub struct VectorScore {
pub:
	id    string
	score f32
}

// PersistentStore 持久化存储（文件存储实现）
@[heap]
pub struct PersistentStore {
pub mut:
	workspace_path      string
	conversations       map[string]protocol.Conversation
	messages            map[string][]protocol.Message
	vectors             map[string]VectorData
	daily_notes_mgr     DailyNotesManager
	long_term_mgr       LongTermMemoryManager
}

struct VectorData {
	vector   []f32
	metadata map[string]string
}

// 创建持久化存储
pub fn new_persistent_store(workspace_path string) !PersistentStore {
	expanded_path := os.expand_tilde_to_home(workspace_path)
	
	// 确保目录存在
	if !os.is_dir(expanded_path) {
		os.mkdir_all(expanded_path) or { return error('failed to create directory: ${err}') }
	}

	mut store := PersistentStore{
		workspace_path: expanded_path
		conversations: map[string]protocol.Conversation{}
		messages: map[string][]protocol.Message{}
		vectors: map[string]VectorData{}
		daily_notes_mgr: new_daily_notes_manager(expanded_path)
		long_term_mgr: new_long_term_memory_manager(expanded_path)
	}

	// 初始化长期记忆
	store.long_term_mgr.init() or {}

	return store
}

// 初始化数据库表（内存版无需操作）
fn (mut s PersistentStore) init_schema() {}

// 创建会话
pub fn (mut s PersistentStore) create_conversation(id string) !protocol.Conversation {
	// 检查是否已存在
	if id in s.conversations {
		return error('conversation already exists: ${id}')
	}

	now := time.now()
	conv := protocol.Conversation{
		id:           id
		messages:     []
		participants: []
		created_at:   now
		updated_at:   now
		metadata:     map[string]string{}
	}

	s.conversations[id] = conv
	return conv
}

// 获取会话
pub fn (mut s PersistentStore) get_conversation(id string) ?protocol.Conversation {
	if conv := s.conversations[id] {
		return conv
	}
	return none
}

// 更新会话
pub fn (mut s PersistentStore) update_conversation(conv protocol.Conversation) ! {
	s.conversations[conv.id] = conv
}

// 删除会话
pub fn (mut s PersistentStore) delete_conversation(id string) ! {
	s.conversations.delete(id)
	s.messages.delete(id)
}

// 列出所有会话
pub fn (mut s PersistentStore) list_conversations() []protocol.Conversation {
	mut result := []protocol.Conversation{}
	for _, conv in s.conversations {
		result << conv
	}
	return result
}

// 添加消息
pub fn (mut s PersistentStore) add_message(conversation_id string, msg protocol.Message) ! {
	if conversation_id !in s.messages {
		s.messages[conversation_id] = []protocol.Message{}
	}
	mut msgs := s.messages[conversation_id]
	msgs << msg
	s.messages[conversation_id] = msgs

	// 更新会话时间
	if mut conv := s.conversations[conversation_id] {
		conv.updated_at = time.now()
		s.conversations[conversation_id] = conv
	}

	// 添加到每日笔记（如果是用户消息）
	if msg.role == .user {
		if text := msg.text() {
			s.daily_notes_mgr.add_conversation_summary(conversation_id, text) or {}
		}
	}
}

// 获取消息
pub fn (mut s PersistentStore) get_messages(conversation_id string, limit int) []protocol.Message {
	if msgs := s.messages[conversation_id] {
		if msgs.len <= limit {
			return msgs
		}
		return msgs[msgs.len - limit..]
	}
	return []
}

// 搜索消息
pub fn (mut s PersistentStore) search_messages(conversation_id string, query string, limit int) []protocol.Message {
	mut results := []protocol.Message{}
	if msgs := s.messages[conversation_id] {
		for msg in msgs {
			// 简单文本匹配
			if msg.content is protocol.TextContent {
				if msg.content.text.contains(query) {
					results << msg
					if results.len >= limit {
						break
					}
				}
			}
		}
	}
	return results
}

// 存储向量
pub fn (mut s PersistentStore) store_vector(id string, vector []f32, metadata map[string]string) ! {
	s.vectors[id] = VectorData{
		vector:   vector
		metadata: metadata
	}
}

// 搜索向量
pub fn (mut s PersistentStore) search_vectors(query_vector []f32, top_k int) []VectorSearchResult {
	mut scores := []VectorScore{}

	for id, data in s.vectors {
		score := compute_cosine_similarity(query_vector, data.vector)
		scores << VectorScore{
			id:    id
			score: score
		}
	}

	// 排序
	scores.sort(a.score > b.score)

	mut results := []VectorSearchResult{}
	for i, item in scores {
		if i >= top_k {
			break
		}
		if vec_data := s.vectors[item.id] {
			results << VectorSearchResult{
				id:       item.id
				score:    item.score
				metadata: vec_data.metadata
			}
		}
	}

	return results
}

// 关闭存储（内存版无需操作）
pub fn (mut s PersistentStore) close() {}

// 导出会话到 JSON
pub fn (mut s PersistentStore) export_conversation(id string, output_path string) ! {
	if conv := s.conversations[id] {
		json_data := json.encode(conv)
		os.write_file(output_path, json_data)!
	} else {
		return error('conversation not found: ${id}')
	}
}

// 从 JSON 导入会话
pub fn (mut s PersistentStore) import_conversation(input_path string) ! {
	json_data := os.read_file(input_path)!
	conv := json.decode(protocol.Conversation, json_data)!

	// 创建会话
	s.conversations[conv.id] = conv

	// 添加消息
	for msg in conv.messages {
		if msg.conversation_id == '' {
			mut new_msg := msg
			new_msg.conversation_id = conv.id
			if conv.id !in s.messages {
				s.messages[conv.id] = []protocol.Message{}
			}
			mut msgs := s.messages[conv.id]
			msgs << new_msg
			s.messages[conv.id] = msgs
		} else {
			if conv.id !in s.messages {
				s.messages[conv.id] = []protocol.Message{}
			}
			mut msgs := s.messages[conv.id]
			msgs << msg
			s.messages[conv.id] = msgs
		}
	}
}

// 计算余弦相似度（本地实现，避免依赖 embeddings 模块）
fn compute_cosine_similarity(a []f32, b []f32) f32 {
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

	// 简单的平方根近似
	mut sqrt_a := norm_a
	mut sqrt_b := norm_b
	for _ in 0 .. 10 {
		sqrt_a = (sqrt_a + norm_a / sqrt_a) / 2.0
		sqrt_b = (sqrt_b + norm_b / sqrt_b) / 2.0
	}

	if sqrt_a == 0.0 || sqrt_b == 0.0 {
		return 0.0
	}

	return dot_product / (sqrt_a * sqrt_b)
}
