// vai.skills.markdown - Markdown 技能加载器
// 支持从 Markdown 文件（带 YAML frontmatter）加载技能
module skills

import os

// MarkdownSkillLoader Markdown 技能加载器
pub struct MarkdownSkillLoader {
pub mut:
	skill_dirs []string
	loaded_skills map[string]MarkdownSkill
}

// MarkdownSkill Markdown 技能定义
pub struct MarkdownSkill {
pub:
	name        string
	description string
	category    string
	risk_level  RiskLevel
	parameters  map[string]ParameterSchema
	content     string  // Markdown 内容
	source_path string
}

// MarkdownSkillConfig YAML frontmatter 配置
struct MarkdownSkillConfig {
pub mut:
	name        string
	description string
	category    string = 'general'
	risk_level  string = 'safe'
	parameters  map[string]MarkdownParameterSchema
}

// MarkdownParameterSchema 参数模式
struct MarkdownParameterSchema {
pub:
	type_       string
	required    bool
	description string
	default_    ?string
	enum_vals   ?[]string
}

// 创建 Markdown 技能加载器
pub fn new_markdown_loader() MarkdownSkillLoader {
	return MarkdownSkillLoader{
		skill_dirs: [
			os.join_path(os.home_dir(), '.vai', 'workspace', 'skills'),
		]
		loaded_skills: map[string]MarkdownSkill{}
	}
}

// 添加技能目录
pub fn (mut l MarkdownSkillLoader) add_directory(path string) {
	l.skill_dirs << path
}

// 扫描并加载所有 Markdown 技能
pub fn (mut l MarkdownSkillLoader) scan_and_load() ![]MarkdownSkill {
	mut loaded := []MarkdownSkill{}
	
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
fn (mut l MarkdownSkillLoader) load_from_directory(dir string) ![]MarkdownSkill {
	mut skills_list := []MarkdownSkill{}
	
	entries := os.ls(dir) or { return skills_list }
	
	for entry in entries {
		path := os.join_path(dir, entry)
		
		if entry.ends_with('.md') && entry != 'README.md' {
			skill := l.load_markdown_skill(path) or { continue }
			skills_list << skill
			l.loaded_skills[skill.name] = skill
		}
	}
	
	return skills_list
}

// 加载 Markdown 技能文件
fn (mut l MarkdownSkillLoader) load_markdown_skill(path string) !MarkdownSkill {
	content := os.read_file(path) or {
		return error('failed to read markdown file: ${err}')
	}
	
	// 解析 YAML frontmatter
	frontmatter, body := parse_frontmatter(content) or {
		return error('failed to parse frontmatter: ${err}')
	}
	
	// 解析配置
	config := parse_yaml_config(frontmatter) or {
		return error('failed to parse YAML config: ${err}')
	}
	
	// 转换参数模式
	parameters := convert_parameters(config.parameters)
	
	// 解析风险等级
	risk_level := parse_risk_level(config.risk_level)
	
	return MarkdownSkill{
		name: config.name
		description: config.description
		category: config.category
		risk_level: risk_level
		parameters: parameters
		content: body
		source_path: path
	}
}

// 解析 YAML frontmatter
fn parse_frontmatter(content string) !(string, string) {
	if !content.starts_with('---') {
		return error('missing YAML frontmatter')
	}
	
	// 查找第二个 ---
	parts := content.split('\n---\n')
	if parts.len < 2 {
		return error('invalid frontmatter format')
	}
	
	frontmatter := parts[0].trim_left('---').trim_space()
	body := parts[1..].join('\n---\n')
	
	return frontmatter, body
}

// 解析 YAML 配置（简化实现）
fn parse_yaml_config(yaml_str string) !MarkdownSkillConfig {
	mut config := MarkdownSkillConfig{
		name: ''
		description: ''
		category: 'general'
		risk_level: 'safe'
		parameters: map[string]MarkdownParameterSchema{}
	}
	
	lines := yaml_str.split('\n')
	mut current_section := ''
	
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 || trimmed.starts_with('#') {
			continue
		}
		
		if trimmed.contains(':') {
			parts := trimmed.split(':')
			if parts.len >= 2 {
				key := parts[0].trim_space()
				value := parts[1..].join(':').trim_space().trim('"').trim("'")
				
				match key {
					'name' { config.name = value }
					'description' { config.description = value }
					'category' { config.category = value }
					'risk_level' { config.risk_level = value }
					'parameters' { current_section = 'parameters' }
					else {
						if current_section == 'parameters' && key.len > 0 {
							// 解析参数（简化）
							config.parameters[key] = MarkdownParameterSchema{
								type_: 'string'
								description: value
							}
						}
					}
				}
			}
		}
	}
	
	if config.name.len == 0 {
		return error('name is required')
	}
	
	return config
}

// 转换参数模式
fn convert_parameters(md_params map[string]MarkdownParameterSchema) map[string]ParameterSchema {
	mut params := map[string]ParameterSchema{}
	
	for key, md_param in md_params {
		mut default_val := ?Value(none)
		if default_str := md_param.default_ {
			default_val = Value(default_str)
		}
		
		params[key] = ParameterSchema{
			typ: md_param.type_
			description: md_param.description
			required: md_param.required
			default_: default_val
			enum_vals: md_param.enum_vals
		}
	}
	
	return params
}

// 解析风险等级
fn parse_risk_level(level_str string) RiskLevel {
	match level_str.to_lower() {
		'moderate' { return .moderate }
		'high' { return .high }
		'critical' { return .critical }
		else { return .safe }
	}
}

// 将 Markdown 技能转换为 Skill 接口实现
pub struct MarkdownSkillWrapper {
	MarkdownSkill
	pub mut:
		executor ?fn (args map[string]Value, content string, ctx SkillContext) !Result
}

pub fn (s MarkdownSkillWrapper) name() string {
	return s.MarkdownSkill.name
}

pub fn (s MarkdownSkillWrapper) description() string {
	return s.MarkdownSkill.description
}

pub fn (s MarkdownSkillWrapper) category() string {
	return s.MarkdownSkill.category
}

pub fn (s MarkdownSkillWrapper) risk_level() RiskLevel {
	return s.MarkdownSkill.risk_level
}

pub fn (s MarkdownSkillWrapper) parameters() map[string]ParameterSchema {
	return s.MarkdownSkill.parameters
}

pub fn (s MarkdownSkillWrapper) execute(args map[string]Value, ctx SkillContext) !Result {
	if executor := s.executor {
		return executor(args, s.MarkdownSkill.content, ctx)
	}
	
	// 默认实现：返回技能内容
	return Result{
		success: true
		data: Value(s.MarkdownSkill.content)
		error_msg: ''
		took_ms: 0
	}
}
