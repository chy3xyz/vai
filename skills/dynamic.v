// vai.skills.dynamic - 动态技能加载
// 支持从动态库和脚本文件加载技能
module skills

import os
import json
import time

// DynamicSkillLoader 动态技能加载器
pub struct DynamicSkillLoader {
	pub mut:
		skill_dirs []string  // 技能搜索目录
		loaded_skills map[string]DynamicSkill
}

// DynamicSkill 动态技能定义
pub struct DynamicSkill {
	pub:
		name        string
		description string
		category    string
		version     string
		type_       DynamicSkillType  // 技能类型
		source      string            // 源代码/文件路径
		entry_point string            // 入口函数/命令
}

// DynamicSkillType 动态技能类型
pub enum DynamicSkillType {
	script       // 脚本文件 (Python, JavaScript, Shell等)
	wasm         // WebAssembly 模块
	executable   // 可执行文件
	v_script     // V 语言脚本
}

// 创建动态技能加载器
pub fn new_dynamic_loader() DynamicSkillLoader {
	return DynamicSkillLoader{
		skill_dirs: [
			os.join_path(os.home_dir(), '.vai', 'workspace', 'skills'),
			os.join_path(os.home_dir(), '.vai', 'skills'),
		]
		loaded_skills: map[string]DynamicSkill{}
	}
}

// 添加技能搜索目录
pub fn (mut l DynamicSkillLoader) add_directory(path string) {
	l.skill_dirs << path
}

// 扫描并加载所有动态技能
pub fn (mut l DynamicSkillLoader) scan_and_load() ![]DynamicSkill {
	mut loaded := []DynamicSkill{}
	
	for dir in l.skill_dirs {
		if !os.is_dir(dir) {
			continue
		}
		
		skills_list := l.load_from_directory(dir) or { continue }
		loaded << skills_list
	}
	
	return loaded
}

// 从目录加载技能
fn (mut l DynamicSkillLoader) load_from_directory(dir string) ![]DynamicSkill {
	mut skills_list := []DynamicSkill{}
	
	entries := os.ls(dir) or { return skills_list }
	
	for entry in entries {
		path := os.join_path(dir, entry)
		
		if entry.ends_with('.md') && entry != 'README.md' {
			// 加载 Markdown 技能（需要导入 markdown 模块）
			// skill := l.load_markdown_skill(path) or { continue }
			// skills_list << skill
			// 注意：Markdown 技能由 MarkdownSkillLoader 处理
			continue
		}
		else if entry.ends_with('.skill.json') {
			// 加载配置式技能
			skill := l.load_config_skill(path) or { continue }
			skills_list << skill
			l.loaded_skills[skill.name] = skill
		}
		else if entry.ends_with('.v') {
			// 加载 V 脚本技能
			skill := l.load_v_script(path) or { continue }
			skills_list << skill
		}
		else if entry.ends_with('.py') || entry.ends_with('.js') || entry.ends_with('.sh') {
			// 加载外部脚本技能
			skill := l.load_script_skill(path) or { continue }
			skills_list << skill
		}
	}
	
	return skills_list
}

// 加载配置式技能
fn (mut l DynamicSkillLoader) load_config_skill(path string) !DynamicSkill {
	content := os.read_file(path)!
	config := json.decode(DynamicSkillConfig, content)!
	
	return DynamicSkill{
		name: config.name
		description: config.description
		category: config.category
		version: config.version
		type_: parse_skill_type(config.type_)
		source: os.dir(path)
		entry_point: config.entry_point
	}
}

// 加载 V 脚本技能
fn (mut l DynamicSkillLoader) load_v_script(path string) !DynamicSkill {
	name := os.file_name(path).all_before('.')
	content := os.read_file(path)!
	
	// 提取描述（从注释中）
	mut description := 'V Script Skill'
	lines := content.split('\n')
	for line in lines[..min(lines.len, 10)] {
		if line.starts_with('//') || line.starts_with('/*') {
			desc := line.trim_left('/').trim_space()
			if desc.len > 5 {
				description = desc
				break
			}
		}
	}
	
	return DynamicSkill{
		name: name
		description: description
		category: 'dynamic'
		version: '1.0.0'
		type_: .v_script
		source: path
		entry_point: name
	}
}

// 加载脚本技能
fn (mut l DynamicSkillLoader) load_script_skill(path string) !DynamicSkill {
	ext := os.file_ext(path)
	name := os.file_name(path).all_before('.')
	
	type_ := match ext {
		'.py' { DynamicSkillType.script }
		'.js' { DynamicSkillType.script }
		'.sh' { DynamicSkillType.script }
		else { DynamicSkillType.executable }
	}
	
	interpreter := match ext {
		'.py' { 'python3' }
		'.js' { 'node' }
		'.sh' { 'bash' }
		else { '' }
	}
	
	return DynamicSkill{
		name: name
		description: '${interpreter} script skill'
		category: 'dynamic'
		version: '1.0.0'
		type_: type_
		source: path
		entry_point: interpreter
	}
}

// 执行动态技能
pub fn (l &DynamicSkillLoader) execute(skill DynamicSkill, args map[string]Value) !Result {
	match skill.type_ {
		.v_script {
			return l.execute_v_script(skill, args)
		}
		.script {
			return l.execute_script(skill, args)
		}
		.executable {
			return l.execute_executable(skill, args)
		}
		.wasm {
			return error('WASM execution not implemented')
		}
	}
}

// 执行 V 脚本
fn (l &DynamicSkillLoader) execute_v_script(skill DynamicSkill, args map[string]Value) !Result {
	start := time.now()
	
	// 构建参数
	args_json := json.encode(args)
	
	// 执行 V 脚本
	result := os.execute('v run ${skill.source} \'${args_json}\'')
	
	took := time.since(start)
	
	return Result{
		success: result.exit_code == 0
		data: Value(result.output)
		error_msg: if result.exit_code != 0 { result.output } else { '' }
		took_ms: took.milliseconds()
	}
}

// 执行外部脚本
fn (l &DynamicSkillLoader) execute_script(skill DynamicSkill, args map[string]Value) !Result {
	start := time.now()
	
	// 构建命令
	mut cmd := '${skill.entry_point} ${skill.source}'
	
	// 添加参数
	for key, value in args {
		val_str := value as string
		cmd += ' --${key}="${val_str}"'
	}
	
	result := os.execute(cmd)
	
	took := time.since(start)
	
	return Result{
		success: result.exit_code == 0
		data: Value(result.output)
		error_msg: if result.exit_code != 0 { result.output } else { '' }
		took_ms: took.milliseconds()
	}
}

// 执行可执行文件
fn (l &DynamicSkillLoader) execute_executable(skill DynamicSkill, args map[string]Value) !Result {
	start := time.now()
	
	mut cmd := skill.source
	
	// 添加参数
	for key, value in args {
		val_str := value as string
		cmd += ' --${key}="${val_str}"'
	}
	
	result := os.execute(cmd)
	
	took := time.since(start)
	
	return Result{
		success: result.exit_code == 0
		data: Value(result.output)
		error_msg: if result.exit_code != 0 { result.output } else { '' }
		took_ms: took.milliseconds()
	}
}

// DynamicSkillConfig 技能配置文件
pub struct DynamicSkillConfig {
	pub:
		name        string @[json: 'name']
		description string @[json: 'description']
		category    string @[json: 'category']
		version     string @[json: 'version']
		type_       string @[json: 'type']
		entry_point string @[json: 'entry_point']
		parameters  ?map[string]ParameterSchema @[json: 'parameters']
}

// 解析技能类型
fn parse_skill_type(s string) DynamicSkillType {
	return match s {
		'script' { DynamicSkillType.script }
		'wasm' { DynamicSkillType.wasm }
		'executable' { DynamicSkillType.executable }
		'v_script' { DynamicSkillType.v_script }
		else { DynamicSkillType.script }
	}
}

fn min(a int, b int) int {
	if a < b { return a }
	return b
}
