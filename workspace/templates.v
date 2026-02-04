// vai.workspace.templates - 模板文件生成器
// 生成工作区模板文件
module workspace

import os
import time

// 生成默认的长期记忆文件
pub fn generate_long_term_memory(workspace_path string) ! {
	memory_dir := os.join_path(workspace_path, 'memory')
	if !os.is_dir(memory_dir) {
		os.mkdir_all(memory_dir)!
	}

	memory_file := os.join_path(memory_dir, 'MEMORY.md')
	if os.exists(memory_file) {
		return // 已存在，不覆盖
	}

	content := '# Long-term Memory

This file stores important long-term memories and knowledge.

## Important Facts

Add important facts and knowledge here that should be remembered across sessions.

## User Information

Store user preferences, important details, and context here.

## System Knowledge

Store system-specific knowledge and configurations here.
'

	os.write_file(memory_file, content)!
}

// 生成每日笔记文件
pub fn generate_daily_note(workspace_path string, date string) ! {
	memory_dir := os.join_path(workspace_path, 'memory')
	if !os.is_dir(memory_dir) {
		os.mkdir_all(memory_dir)!
	}

	note_file := os.join_path(memory_dir, '${date}.md')
	if os.exists(note_file) {
		return // 已存在，不覆盖
	}

	content := '# Daily Notes - ${date}

## Observations

- 

## Conversations

- 

## Tasks Completed

- 

## Notes

- 
'

	os.write_file(note_file, content)!
}

// 生成今日笔记
pub fn generate_today_note(workspace_path string) ! {
	today := time.now().format_ss_micro().split(' ')[0] // YYYY-MM-DD
	generate_daily_note(workspace_path, today)!
}

// 清理旧的每日笔记（保留最近 N 天）
pub fn cleanup_old_daily_notes(workspace_path string, keep_days int) ! {
	memory_dir := os.join_path(workspace_path, 'memory')
	if !os.is_dir(memory_dir) {
		return
	}

	entries := os.ls(memory_dir) or { return }
	cutoff_date := time.now().add_days(-keep_days)

	mut to_delete := []string{}
	for entry in entries {
		if !entry.ends_with('.md') || entry == 'MEMORY.md' {
			continue
		}

		// 尝试解析日期
		date_str := entry.all_before_last('.')
		date_parts := date_str.split('-')
		if date_parts.len != 3 {
			continue
		}

		year := date_parts[0].int()
		month := date_parts[1].int()
		day := date_parts[2].int()
		if year == 0 || month == 0 || day == 0 {
			continue
		}

		file_date := time.Time{
			year: year
			month: month
			day: day
		}

		if file_date < cutoff_date {
			file_path := os.join_path(memory_dir, entry)
			to_delete << file_path
		}
	}

	for file_path in to_delete {
		os.rm(file_path) or { continue }
	}
}
