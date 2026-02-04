// vai.workspace.manager - 工作区管理器
// 管理工作区目录结构和文件
module workspace

import os
import config

// WorkspaceManager 工作区管理器
pub struct WorkspaceManager {
pub:
	workspace_path string
}

// 创建工作区管理器
pub fn new_workspace_manager(workspace_path string) WorkspaceManager {
	expanded_path := os.expand_tilde_to_home(workspace_path)
	return WorkspaceManager{
		workspace_path: expanded_path
	}
}

// 从配置创建工作区管理器
pub fn workspace_from_config(cfg config.Config) WorkspaceManager {
	return new_workspace_manager(cfg.workspace.path)
}

// 初始化工作区（创建目录结构）
pub fn (mut wm WorkspaceManager) init() ! {
	// 创建工作区根目录
	if !os.is_dir(wm.workspace_path) {
		os.mkdir_all(wm.workspace_path) or {
			return error('failed to create workspace directory: ${err}')
		}
	}

	// 创建 memory 目录
	memory_dir := os.join_path(wm.workspace_path, 'memory')
	if !os.is_dir(memory_dir) {
		os.mkdir_all(memory_dir) or {
			return error('failed to create memory directory: ${err}')
		}
	}

	// 创建 skills 目录
	skills_dir := os.join_path(wm.workspace_path, 'skills')
	if !os.is_dir(skills_dir) {
		os.mkdir_all(skills_dir) or {
			return error('failed to create skills directory: ${err}')
		}
	}

	// 创建模板文件（如果不存在）
	wm.ensure_template_files()!
}

// 确保模板文件存在
fn (mut wm WorkspaceManager) ensure_template_files() ! {
	templates := get_template_files()

	for file_name, content in templates {
		file_path := os.join_path(wm.workspace_path, file_name)
		if !os.exists(file_path) {
			os.write_file(file_path, content) or {
				return error('failed to create template file ${file_name}: ${err}')
			}
		}
	}
}

// 获取工作区路径
pub fn (wm &WorkspaceManager) get_path() string {
	return wm.workspace_path
}

// 获取 memory 目录路径
pub fn (wm &WorkspaceManager) get_memory_dir() string {
	return os.join_path(wm.workspace_path, 'memory')
}

// 获取 skills 目录路径
pub fn (wm &WorkspaceManager) get_skills_dir() string {
	return os.join_path(wm.workspace_path, 'skills')
}

// 获取长期记忆文件路径
pub fn (wm &WorkspaceManager) get_long_term_memory_path() string {
	return os.join_path(wm.get_memory_dir(), 'MEMORY.md')
}

// 获取每日笔记文件路径
pub fn (wm &WorkspaceManager) get_daily_note_path(date string) string {
	return os.join_path(wm.get_memory_dir(), '${date}.md')
}

// 检查工作区是否已初始化
pub fn (wm &WorkspaceManager) is_initialized() bool {
	return os.is_dir(wm.workspace_path) && os.is_dir(wm.get_memory_dir())
}

// 获取模板文件内容
fn get_template_files() map[string]string {
	return {
		'AGENTS.md': get_agents_template()
		'SOUL.md': get_soul_template()
		'USER.md': get_user_template()
		'HEARTBEAT.md': get_heartbeat_template()
		'TOOLS.md': get_tools_template()
	}
}

// AGENTS.md 模板
fn get_agents_template() string {
	return '# Agent Instructions

This file contains instructions and guidelines for the AI agent.

## Instructions

- Be helpful, harmless, and honest
- Use available tools and skills when appropriate
- Remember important information in memory
- Follow user preferences from USER.md

## Guidelines

- Always verify information when possible
- Ask for clarification when needed
- Respect user privacy and data
'
}

// SOUL.md 模板
fn get_soul_template() string {
	return '# Agent Personality and Values

This file defines the agent\'s personality, values, and behavioral guidelines.

## Personality

- Friendly and approachable
- Professional and reliable
- Curious and eager to learn
- Respectful and considerate

## Values

- User privacy and data security
- Honesty and transparency
- Continuous improvement
- Helpful and supportive interactions
'
}

// USER.md 模板
fn get_user_template() string {
	return '# User Preferences

This file contains user-specific preferences and customizations.

## Preferences

- Language: English (can be changed)
- Response style: Concise and clear
- Tool usage: Automatic when helpful

## Customizations

Add your personal preferences here.
'
}

// HEARTBEAT.md 模板
fn get_heartbeat_template() string {
	return '# Heartbeat Tasks

This file defines proactive tasks that the agent should perform periodically.

## Tasks

Add tasks here that should be executed automatically, for example:

- Check for updates
- Review and summarize recent conversations
- Clean up old memory files

## Format

Each task should be defined with:
- Schedule (cron format or interval)
- Description
- Action to perform
'
}

// TOOLS.md 模板
fn get_tools_template() string {
	return '# Available Tools

This file describes the available tools and skills.

## Built-in Tools

- File operations (read, write, list)
- Shell execution (restricted)
- HTTP requests
- Memory management

## Custom Skills

Add descriptions of custom skills here.
'
}
