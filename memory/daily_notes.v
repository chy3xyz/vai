// vai.memory.daily_notes - 每日笔记管理
// 管理每日笔记文件（YYYY-MM-DD.md）
module memory

import os
import time

// DailyNotesManager 每日笔记管理器
pub struct DailyNotesManager {
pub:
	workspace_path string
}

// 创建每日笔记管理器
pub fn new_daily_notes_manager(workspace_path string) DailyNotesManager {
	return DailyNotesManager{
		workspace_path: workspace_path
	}
}

// 获取今日笔记文件路径
pub fn (dnm &DailyNotesManager) get_today_path() string {
	today := time.now().format_ss_micro().split(' ')[0] // YYYY-MM-DD
	return dnm.get_daily_note_path(today)
}

// 获取指定日期的笔记文件路径
pub fn (dnm &DailyNotesManager) get_daily_note_path(date string) string {
	memory_dir := os.join_path(dnm.workspace_path, 'memory')
	return os.join_path(memory_dir, '${date}.md')
}

// 追加笔记内容
pub fn (mut dnm DailyNotesManager) append_note(content string) ! {
	today_path := dnm.get_today_path()
	dnm.append_to_file(today_path, content)!
}

// 追加到文件
fn (mut dnm DailyNotesManager) append_to_file(file_path string, content string) ! {
	// 确保目录存在
	dir := os.dir(file_path)
	if !os.is_dir(dir) {
		os.mkdir_all(dir)!
	}

	// 如果文件不存在，创建它
	if !os.exists(file_path) {
		header := '# Daily Notes - ${os.file_name(file_path).all_before_last('.')}\n\n'
		os.write_file(file_path, header)!
	}

	// 追加内容
	mut existing := os.read_file(file_path) or { '' }
	timestamp := time.now().format_ss_micro()
	new_content := '${existing}\n## ${timestamp}\n\n${content}\n'
	os.write_file(file_path, new_content)!
}

// 添加观察记录
pub fn (mut dnm DailyNotesManager) add_observation(observation string) ! {
	content := '**Observation:** ${observation}'
	dnm.append_note(content)!
}

// 添加对话记录
pub fn (mut dnm DailyNotesManager) add_conversation_summary(conversation_id string, summary string) ! {
	content := '**Conversation ${conversation_id}:** ${summary}'
	dnm.append_note(content)!
}

// 添加任务完成记录
pub fn (mut dnm DailyNotesManager) add_task_completed(task_description string) ! {
	content := '**Task Completed:** ${task_description}'
	dnm.append_note(content)!
}

// 读取今日笔记
pub fn (dnm &DailyNotesManager) read_today_notes() string {
	today_path := dnm.get_today_path()
	if !os.exists(today_path) {
		return ''
	}
	return os.read_file(today_path) or { '' }
}

// 读取指定日期的笔记
pub fn (dnm &DailyNotesManager) read_daily_notes(date string) string {
	path := dnm.get_daily_note_path(date)
	if !os.exists(path) {
		return ''
	}
	return os.read_file(path) or { '' }
}

// 获取最近 N 天的笔记
pub fn (dnm &DailyNotesManager) get_recent_notes(days int) []string {
	memory_dir := os.join_path(dnm.workspace_path, 'memory')
	if !os.is_dir(memory_dir) {
		return []
	}

	_ := os.ls(memory_dir) or { return [] }
	mut notes := []string{}

	for i := 0; i < days; i++ {
		date := time.now().add_days(-i).format_ss_micro().split(' ')[0]
		note_path := os.join_path(memory_dir, '${date}.md')
		if os.exists(note_path) {
			content := os.read_file(note_path) or { '' }
			if content.len > 0 {
				notes << content
			}
		}
	}

	return notes
}

// 搜索笔记内容
pub fn (dnm &DailyNotesManager) search_notes(query string, days int) []string {
	recent_notes := dnm.get_recent_notes(days)
	mut results := []string{}

	for note in recent_notes {
		if note.contains(query) {
			results << note
		}
	}

	return results
}
