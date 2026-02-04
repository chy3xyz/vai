// vai.memory.long_term - 长期记忆管理
// 管理长期记忆文件（MEMORY.md）
module memory

import os
import time

// LongTermMemoryManager 长期记忆管理器
pub struct LongTermMemoryManager {
pub:
	workspace_path string
}

// 创建长期记忆管理器
pub fn new_long_term_memory_manager(workspace_path string) LongTermMemoryManager {
	return LongTermMemoryManager{
		workspace_path: workspace_path
	}
}

// 获取长期记忆文件路径
pub fn (ltm &LongTermMemoryManager) get_memory_path() string {
	memory_dir := os.join_path(ltm.workspace_path, 'memory')
	return os.join_path(memory_dir, 'MEMORY.md')
}

// 初始化长期记忆文件
pub fn (mut ltm LongTermMemoryManager) init() ! {
	memory_path := ltm.get_memory_path()
	if os.exists(memory_path) {
		return // 已存在
	}

	// 确保目录存在
	memory_dir := os.dir(memory_path)
	if !os.is_dir(memory_dir) {
		os.mkdir_all(memory_dir)!
	}

	// 创建默认内容
	content := '# Long-term Memory

This file stores important long-term memories and knowledge.

## Important Facts

Add important facts and knowledge here that should be remembered across sessions.

## User Information

Store user preferences, important details, and context here.

## System Knowledge

Store system-specific knowledge and configurations here.
'

	os.write_file(memory_path, content)!
}

// 读取长期记忆
pub fn (ltm &LongTermMemoryManager) read() string {
	memory_path := ltm.get_memory_path()
	if !os.exists(memory_path) {
		return ''
	}
	return os.read_file(memory_path) or { '' }
}

// 追加记忆内容
pub fn (mut ltm LongTermMemoryManager) append(section string, content string) ! {
	memory_path := ltm.get_memory_path()
	
	// 如果文件不存在，初始化
	if !os.exists(memory_path) {
		ltm.init()!
	}

	mut existing := os.read_file(memory_path) or { '' }
	timestamp := time.now().format_ss_micro()
	
	// 检查 section 是否存在
	if existing.contains('## ${section}') {
		// 追加到现有 section
		section_start := existing.index('## ${section}') or { existing.len }
		section_end := existing.index_after('## ', section_start + 1) or { existing.len }
		
		before := existing[..section_end]
		after := existing[section_end..]
		
		new_content := '${before}\n- [${timestamp}] ${content}\n${after}'
		os.write_file(memory_path, new_content)!
	} else {
		// 创建新 section
		new_section := '\n\n## ${section}\n\n- [${timestamp}] ${content}\n'
		os.write_file(memory_path, existing + new_section)!
	}
}

// 添加重要事实
pub fn (mut ltm LongTermMemoryManager) add_fact(fact string) ! {
	ltm.append('Important Facts', fact)!
}

// 添加用户信息
pub fn (mut ltm LongTermMemoryManager) add_user_info(info string) ! {
	ltm.append('User Information', info)!
}

// 添加系统知识
pub fn (mut ltm LongTermMemoryManager) add_system_knowledge(knowledge string) ! {
	ltm.append('System Knowledge', knowledge)!
}

// 搜索记忆内容
pub fn (ltm &LongTermMemoryManager) search(query string) string {
	content := ltm.read()
	if content.len == 0 {
		return ''
	}

	// 简单搜索：返回包含查询的行及其上下文
	lines := content.split('\n')
	mut results := []string{}
	
	for i, line in lines {
		if line.contains(query) {
			// 包含前后各 2 行上下文
			start := if i >= 2 { i - 2 } else { 0 }
			end := if i + 2 < lines.len { i + 3 } else { lines.len }
			context := lines[start..end].join('\n')
			results << context
		}
	}

	return results.join('\n\n---\n\n')
}

// 更新记忆（替换整个文件）
pub fn (mut ltm LongTermMemoryManager) update(content string) ! {
	memory_path := ltm.get_memory_path()
	
	// 确保目录存在
	memory_dir := os.dir(memory_path)
	if !os.is_dir(memory_dir) {
		os.mkdir_all(memory_dir)!
	}

	os.write_file(memory_path, content)!
}
