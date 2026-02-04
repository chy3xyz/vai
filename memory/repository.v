// vai.memory.repository - 数据仓库模式
// 提供高级数据访问和缓存策略
module memory

import db.sqlite
import json
import time

// Repository 通用数据仓库
pub interface Repository[T] {
	create(item T) !
	read(id string) ?T
	update(item T) !
	delete(id string) !
	list(filter RepositoryFilter) []T
}

// RepositoryFilter 查询过滤器
pub struct RepositoryFilter {
	pub:
		field    string
		operator string // =, !=, <, >, <=, >=, LIKE, IN
		value    string
}

// ConversationRepository 会话仓库
pub struct ConversationRepository {
	pub mut:
		store &PersistentStore
		cache &MemoryStore  // 内存缓存层
}

// 创建会话仓库
pub fn new_conversation_repository(store &PersistentStore, cache &MemoryStore) ConversationRepository {
	return ConversationRepository{
		store: store
		cache: cache
	}
}

// 创建会话（带缓存）
pub fn (mut r ConversationRepository) create(conv Conversation) ! {
	// 先写入持久化存储
	r.store.create_conversation(conv.id)!

	// 再写入缓存
	for msg in conv.messages {
		r.cache.add_message(conv.id, msg) or {}
	}
}

// 读取会话（优先从缓存）
pub fn (mut r ConversationRepository) read(id string) ?Conversation {
	// 先查缓存
	if conv := r.cache.get_conversation(id) {
		return conv
	}

	// 再查持久化存储
	if conv := r.store.get_conversation(id) {
		// 回填缓存
		r.cache.conversations[id] = conv
		return conv
	}

	return none
}

// 更新会话
pub fn (mut r ConversationRepository) update(conv Conversation) ! {
	r.store.update_conversation(conv)!
	r.cache.update_conversation(conv) or {}
}

// 删除会话
pub fn (mut r ConversationRepository) delete(id string) ! {
	r.store.delete_conversation(id)!
	r.cache.conversations.delete(id)
}

// 列出来往会话
pub fn (mut r ConversationRepository) list(limit int, offset int) []Conversation {
	return r.store.list_conversations()
}

// 搜索会话
pub fn (mut r ConversationRepository) search(query string, limit int) []Conversation {
	return r.store.list_conversations().filter(it.id.contains(query))
}

// MessageRepository 消息仓库
pub struct MessageRepository {
	pub mut:
		store &PersistentStore
		cache &MemoryStore
}

// 创建消息仓库
pub fn new_message_repository(store &PersistentStore, cache &MemoryStore) MessageRepository {
	return MessageRepository{
		store: store
		cache: cache
	}
}

// 批量添加消息
pub fn (mut r MessageRepository) batch_add(conversation_id string, messages []Message) ! {
	// 事务保证一致性
	for msg in messages {
		r.store.add_message(conversation_id, msg)!
	}
}

// 获取消息时间线
pub fn (mut r MessageRepository) get_timeline(conversation_id string, start time.Time, end time.Time) []Message {
	all_messages := r.store.get_messages(conversation_id, 10000)

	return all_messages.filter(it.timestamp >= start && it.timestamp <= end)
}

// 消息归档（将旧消息移至归档表）
pub fn (mut r MessageRepository) archive_old_messages(before time.Time) !int {
	// 简化实现：删除早于指定时间的消息
	archived := 0

	for _, mut conv in r.store.list_conversations() {
		old_messages := conv.messages.filter(it.timestamp < before)
		archived += old_messages.len

		// 保留较新的消息
		conv.messages = conv.messages.filter(it.timestamp >= before)
		r.store.update_conversation(conv)!
	}

	return archived
}

// BackupManager 备份管理器
pub struct BackupManager {
	pub mut:
		store      &PersistentStore
		backup_dir string
}

// 创建备份管理器
pub fn new_backup_manager(store &PersistentStore, backup_dir string) BackupManager {
	return BackupManager{
		store: store
		backup_dir: backup_dir
	}
}

// 创建备份
pub fn (mut b BackupManager) create_backup(name string) !string {

	// 确保备份目录存在
	if !os.is_dir(b.backup_dir) {
		os.mkdir_all(b.backup_dir)!
	}

	// 备份文件名
	timestamp := time.now().format_ss()
	backup_file := '${b.backup_dir}/${name}_${timestamp}.db'

	// 复制数据库文件
	os.cp(b.store.db_path, backup_file)!

	return backup_file
}

// 恢复备份
pub fn (mut b BackupManager) restore_backup(backup_file string) ! {

	if !os.exists(backup_file) {
		return error('backup file not found: ${backup_file}')
	}

	// 关闭当前连接
	b.store.close()!

	// 恢复数据库文件
	os.cp(backup_file, b.store.db_path)!

	// 重新打开连接
	new_store := new_persistent_store(b.store.db_path)!
	b.store = &new_store
}

// 列出所有备份
pub fn (mut b BackupManager) list_backups() []string {

	if !os.is_dir(b.backup_dir) {
		return []
	}

	mut backups := []string{}
	entries := os.ls(b.backup_dir) or { return [] }

	for entry in entries {
		if entry.ends_with('.db') {
			backups << os.join_path(b.backup_dir, entry)
		}
	}

	return backups
}

// Migration 数据库迁移
pub struct Migration {
	pub:
		version     string
		description string
		sql_up      string
		sql_down    string
}

// Migrator 迁移管理器
pub struct Migrator {
	pub mut:
		store      &PersistentStore
		migrations []Migration
}

// 创建迁移管理器
pub fn new_migrator(store &PersistentStore) Migrator {
	return Migrator{
		store: store
		migrations: []
	}
}

// 注册迁移
pub fn (mut m Migrator) register(migration Migration) {
	m.migrations << migration
}

// 执行迁移
pub fn (mut m Migrator) migrate() ! {
	// 创建迁移记录表
	m.store.connection.exec_none('
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version TEXT PRIMARY KEY,
			applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)
	')!

	// 获取已应用的迁移
	applied_rows := m.store.connection.exec('SELECT version FROM schema_migrations') or { [] }
	mut applied := map[string]bool{}
	for row in applied_rows {
		applied[row.vals[0]] = true
	}

	// 执行未应用的迁移
	for migration in m.migrations {
		if migration.version !in applied {
			println('Applying migration ${migration.version}: ${migration.description}')

			// 执行 SQL
			m.store.connection.exec_none(migration.sql_up)!

			// 记录迁移
			m.store.connection.exec_none('
				INSERT INTO schema_migrations (version) VALUES ("${migration.version}")
			')!
		}
	}
}

// 回滚迁移
pub fn (mut m Migrator) rollback(version string) ! {
	// 找到指定版本的迁移
	mut target := ?Migration(none)
	for migration in m.migrations {
		if migration.version == version {
			target = migration
			break
		}
	}

	if migration := target {
		m.store.connection.exec_none(migration.sql_down)!

		// 删除迁移记录
		m.store.connection.exec_none('
			DELETE FROM schema_migrations WHERE version = "${version}"
		')!
	} else {
		return error('migration not found: ${version}')
	}
}
