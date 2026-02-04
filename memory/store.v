// vai.memory - 会话状态与向量存储
// 提供对话历史管理和简单的向量检索功能
module memory

import protocol { Message, Conversation }
import json
import time
import math
import crypto.md5
import sync

// Store 记忆存储接口
pub interface Store {
	// 会话管理
	mut:
		create_conversation(id string) !Conversation
		get_conversation(id string) ?Conversation
		update_conversation(conversation Conversation) !
		delete_conversation(id string) !
		list_conversations() []Conversation
		
		// 消息存储
		add_message(conversation_id string, msg Message) !
		get_messages(conversation_id string, limit int) []Message
		search_messages(conversation_id string, query string, limit int) []Message
		
		// 向量存储
		store_vector(id string, vector []f32, metadata map[string]string) !
		search_vectors(query_vector []f32, top_k int) []VectorSearchResult
}

// VectorSearchResult 向量搜索结果
pub struct VectorSearchResult {
	pub:
		id       string
		score    f32  // 相似度分数
		metadata map[string]string
}

// MemoryStore 内存存储实现（适合开发和测试）
@[heap]
pub struct MemoryStore {
	pub mut:
		conversations map[string]Conversation
		vectors       map[string]VectorEntry
		mu            sync.RwMutex
}

// VectorEntry 向量条目
pub struct VectorEntry {
	pub:
		id       string
		vector   []f32
		metadata map[string]string
}

// 创建内存存储
pub fn new_memory_store() MemoryStore {
	return MemoryStore{
		conversations: map[string]Conversation{}
		vectors: map[string]VectorEntry{}
	}
}

// 创建会话
pub fn (mut s MemoryStore) create_conversation(id string) !Conversation {
	s.mu.lock()
	defer { s.mu.unlock() }
	
	if id in s.conversations {
		return error('conversation already exists: ${id}')
	}
	
	conversation := Conversation{
		id: id
		messages: []
		participants: []
		created_at: time.now()
		updated_at: time.now()
		metadata: map[string]string{}
	}
	
	s.conversations[id] = conversation
	return conversation
}

// 获取会话
pub fn (mut s MemoryStore) get_conversation(id string) ?Conversation {
	s.mu.rlock()
	defer { s.mu.runlock() }
	return s.conversations[id] or { return none }
}

// 更新会话
pub fn (mut s MemoryStore) update_conversation(conversation Conversation) ! {
	s.mu.lock()
	defer { s.mu.unlock() }
	
	mut updated := conversation
	updated.updated_at = time.now()
	s.conversations[conversation.id] = updated
}

// 删除会话
pub fn (mut s MemoryStore) delete_conversation(id string) ! {
	s.mu.lock()
	defer { s.mu.unlock() }
	s.conversations.delete(id)
}

// 列出所有会话
pub fn (mut s MemoryStore) list_conversations() []Conversation {
	s.mu.rlock()
	defer { s.mu.runlock() }
	
	mut result := []Conversation{}
	for _, conv in s.conversations {
		result << conv
	}
	return result
}

// 添加消息
pub fn (mut s MemoryStore) add_message(conversation_id string, msg Message) ! {
	s.mu.lock()
	defer { s.mu.unlock() }
	
	if mut conv := s.conversations[conversation_id] {
		conv.messages << msg
		conv.updated_at = time.now()
	} else {
		return error('conversation not found: ${conversation_id}')
	}
}

// 获取消息
pub fn (mut s MemoryStore) get_messages(conversation_id string, limit int) []Message {
	s.mu.rlock()
	defer { s.mu.runlock() }
	
	if conv := s.conversations[conversation_id] {
		if limit <= 0 || conv.messages.len <= limit {
			return conv.messages
		}
		return conv.messages[conv.messages.len - limit..]
	}
	return []
}

// 搜索消息（简单的关键词搜索）
pub fn (mut s MemoryStore) search_messages(conversation_id string, query string, limit int) []Message {
	s.mu.rlock()
	defer { s.mu.runlock() }
	
	if conv := s.conversations[conversation_id] {
		mut results := []Message{}
		query_lower := query.to_lower()
		
		for msg in conv.messages {
			if text := msg.text() {
				if text.to_lower().contains(query_lower) {
					results << msg
					if limit > 0 && results.len >= limit {
						break
					}
				}
			}
		}
		return results
	}
	return []
}

// 存储向量
pub fn (mut s MemoryStore) store_vector(id string, vector []f32, metadata map[string]string) ! {
	s.mu.lock()
	defer { s.mu.unlock() }
	
	s.vectors[id] = VectorEntry{
		id: id
		vector: vector
		metadata: metadata
	}
}

// 向量搜索（余弦相似度）
pub fn (mut s MemoryStore) search_vectors(query_vector []f32, top_k int) []VectorSearchResult {
	s.mu.rlock()
	defer { s.mu.runlock() }
	
	mut scores := []VectorScore{}
	
	for _, entry in s.vectors {
		score := cosine_similarity(query_vector, entry.vector)
		scores << VectorScore{entry.id, score}
	}
	
	// 按分数排序（降序）
	scores.sort(a.score > b.score)
	
	mut results := []VectorSearchResult{}
	for i, item in scores {
		if i >= top_k {
			break
		}
		if entry := s.vectors[item.id] {
			results << VectorSearchResult{
				id: item.id
				score: item.score
				metadata: entry.metadata
			}
		}
	}
	
	return results
}

// 余弦相似度计算
// fn cosine_similarity(a []f32, b []f32) f32 {
// 	if a.len != b.len || a.len == 0 {
// 		return 0.0
// 	}
// 	
// 	mut dot_product := f32(0.0)
// 	mut norm_a := f32(0.0)
// 	mut norm_b := f32(0.0)
// 	
// 	for i := 0; i < a.len; i++ {
// 		dot_product += a[i] * b[i]
// 		norm_a += a[i] * a[i]
// 		norm_b += b[i] * b[i]
// 	}
// 	
// 	if norm_a == 0.0 || norm_b == 0.0 {
// 		return 0.0
// 	}
// 	
// 	return dot_product / (f32(math.sqrt(f64(norm_a))) * f32(math.sqrt(f64(norm_b))))
// }

// 导出会话为 JSON
pub fn (s &MemoryStore) export_conversation(id string) !string {
	if conv := s.conversations[id] {
		return json.encode(conv)
	}
	return error('conversation not found: ${id}')
}

// 从 JSON 导入会话
pub fn (mut s MemoryStore) import_conversation(data string) ! {
	conv := json.decode(Conversation, data)!
	s.conversations[conv.id] = conv
}

// 获取会话统计
pub struct ConversationStats {
	pub:
		conversation_id string
		message_count   int
		created_at      time.Time
		updated_at      time.Time
		participants    []string
}

pub fn (s &MemoryStore) get_stats(conversation_id string) ?ConversationStats {
	if conv := s.conversations[conversation_id] {
		return ConversationStats{
			conversation_id: conv.id
			message_count: conv.messages.len
			created_at: conv.created_at
			updated_at: conv.updated_at
			participants: conv.participants
		}
	}
	return none
}

// 清理旧会话
pub fn (mut s MemoryStore) cleanup_old_sessions(max_age_hours int) int {
	s.mu.lock()
	defer { s.mu.unlock() }
	
	now := time.now()
	mut deleted := 0
	
	for id, conv in s.conversations {
		age := now - conv.updated_at
		if age > time.hour * max_age_hours {
			s.conversations.delete(id)
			deleted++
		}
	}
	
	return deleted
}
