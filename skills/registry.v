// vai.skills - 技能系统
// 工具注册、执行和沙箱隔离
module skills

import protocol { Message }
import time
import json
import os
import sync

// Skill 技能/工具接口
pub interface Skill {
	name() string                                          // 技能名称
	description() string                                   // 技能描述
	parameters() map[string]ParameterSchema                // 参数模式
	execute(args map[string]any, ctx SkillContext) !Result // 执行技能
	category() string                                      // 技能分类
	risk_level() RiskLevel                                 // 风险等级
}

// ParameterSchema 参数模式定义
pub struct ParameterSchema {
	pub:
		typ         string   // string, number, boolean, array, object
		description string   // 参数描述
		required    bool     // 是否必需
		default_    ?any     // 默认值
		enum_vals   ?[]string // 枚举值
}

// RiskLevel 风险等级
pub enum RiskLevel {
	safe        // 安全：只读操作
	moderate    // 中等：写入文件等
	high        // 高风险：执行系统命令
	critical    // 极高风险：网络操作、删除数据
}

// Result 技能执行结果
pub struct Result {
	pub:
		success     bool
		data        any
		error_msg   string
		took_ms     i64
}

// SkillContext 技能执行上下文
pub struct SkillContext {
	pub mut:
		session_id    string
		user_id       string
		working_dir   string
		env_vars      map[string]string
		metadata      map[string]any
}

// Registry 技能注册表
pub struct Registry {
	pub mut:
		skills map[string]Skill
		by_category map[string][]Skill
		mu sync.RwMutex
}

// 创建技能注册表
pub fn new_registry() Registry {
	return Registry{
		skills: map[string]Skill{}
		by_category: map[string][]Skill{}
	}
}

// 注册技能
pub fn (mut r Registry) register(skill Skill) ! {
	r.mu.lock()
	defer { r.mu.unlock() }
	
	name := skill.name()
	if name in r.skills {
		return error('skill "${name}" already registered')
	}
	
	r.skills[name] = skill
	
	// 按分类索引
	category := skill.category()
	if category !in r.by_category {
		r.by_category[category] = []Skill{}
	}
	r.by_category[category] << skill
}

// 注销技能
pub fn (mut r Registry) unregister(name string) {
	r.mu.lock()
	defer { r.mu.unlock() }
	
	if skill := r.skills[name] {
		category := skill.category()
		if category in r.by_category {
			mut new_list := []Skill{}
			for s in r.by_category[category] {
				if s.name() != name {
					new_list << s
				}
			}
			r.by_category[category] = new_list
		}
	}
	
	r.skills.delete(name)
}

// 获取技能
pub fn (r &Registry) get(name string) ?Skill {
	r.mu.rlock()
	defer { r.mu.runlock() }
	return r.skills[name] or { return none }
}

// 列出所有技能
pub fn (r &Registry) list() []Skill {
	r.mu.rlock()
	defer { r.mu.runlock() }
	
	mut result := []Skill{}
	for _, skill in r.skills {
		result << skill
	}
	return result
}

// 按分类列出技能
pub fn (r &Registry) list_by_category(category string) []Skill {
	r.mu.rlock()
	defer { r.mu.runlock() }
	return r.by_category[category] or { return []Skill{} }
}

// 转换为 OpenAI 工具格式
pub fn (r &Registry) to_openai_tools() []Tool {
	r.mu.rlock()
	defer { r.mu.runlock() }
	
	mut tools := []Tool{}
	for _, skill in r.skills {
		tools << Tool{
			typ: 'function'
			function: Function{
				name: skill.name()
				description: skill.description()
				parameters: schema_to_json(skill.parameters())
			}
		}
	}
	return tools
}

// 执行技能
pub fn (r &Registry) execute(name string, args map[string]any, ctx SkillContext) !Result {
	skill := r.get(name) or {
		return error('skill "${name}" not found')
	}
	
	// 检查权限
	if !r.check_permission(skill, ctx) {
		return error('permission denied for skill "${name}"')
	}
	
	start := time.now()
	result := skill.execute(args, ctx) or {
		return Result{
			success: false
			error_msg: err.msg()
			took_ms: time.since(start).milliseconds()
		}
	}
	
	return Result{
		success: result.success
		data: result.data
		error_msg: result.error_msg
		took_ms: time.since(start).milliseconds()
	}
}

// 检查权限
fn (r &Registry) check_permission(skill Skill, ctx SkillContext) bool {
	// 根据风险等级检查权限
	match skill.risk_level() {
		.safe { return true }
		.moderate { return true }  // 可以添加用户确认逻辑
		.high { return true }      // 需要额外确认
		.critical { return false } // 默认禁止
	}
	return false
}

// Tool OpenAI 工具格式
pub struct Tool {
	pub:
		typ      string @[json: 'type']
		function Function @[json: 'function']
}

// Function 函数定义
pub struct Function {
	pub:
		name        string
		description string
		parameters  map[string]any
}

// 将参数模式转换为 JSON Schema
fn schema_to_json(params map[string]ParameterSchema) map[string]any {
	mut properties := map[string]any{}
	mut required := []string{}
	
	for name, schema in params {
		mut prop := map[string]any{}
		prop['type'] = schema.typ
		prop['description'] = schema.description
		
		if enum_vals := schema.enum_vals {
			prop['enum'] = enum_vals
		}
		
		if default_ := schema.default_ {
			prop['default'] = default_
		}
		
		properties[name] = prop
		
		if schema.required {
			required << name
		}
	}
	
	return {
		'type': 'object'
		'properties': properties
		'required': required
	}
}

// SkillCall 技能调用
pub struct SkillCall {
	pub:
		id       string
		name     string
		arguments string // JSON 字符串
}

// parse_arguments 解析参数
pub fn (sc &SkillCall) parse_arguments() !map[string]any {
	return json.decode(map[string]any, sc.arguments)!
}

// ExtensibleRegistry 可扩展注册表（支持动态技能）
pub struct ExtensibleRegistry {
	Registry
	pub mut:
		dynamic_loader DynamicSkillLoader
}

// 创建可扩展注册表
pub fn new_extensible_registry() ExtensibleRegistry {
	return ExtensibleRegistry{
		Registry: new_registry()
		dynamic_loader: new_dynamic_loader()
	}
}

// 加载动态技能目录
pub fn (mut r ExtensibleRegistry) load_dynamic_skills(dir string) ! {
	r.dynamic_loader.add_directory(dir)
	
	skills := r.dynamic_loader.scan_and_load()!
	
	for skill in skills {
		// 创建动态技能包装器
		wrapper := DynamicSkillWrapper{
			skill: skill
			loader: r.dynamic_loader
		}
		r.register(wrapper)!
	}
}

// 动态技能包装器
pub struct DynamicSkillWrapper {
	pub:
		skill  DynamicSkill
		loader DynamicSkillLoader
}

pub fn (w DynamicSkillWrapper) name() string {
	return w.skill.name
}

pub fn (w DynamicSkillWrapper) description() string {
	return w.skill.description
}

pub fn (w DynamicSkillWrapper) category() string {
	return w.skill.category
}

pub fn (w DynamicSkillWrapper) risk_level() RiskLevel {
	return .moderate  // 动态技能默认为中等风险
}

pub fn (w DynamicSkillWrapper) parameters() map[string]ParameterSchema {
	// 动态技能参数可以从配置中加载
	return map[string]ParameterSchema{}
}

pub fn (w DynamicSkillWrapper) execute(args map[string]any, ctx SkillContext) !Result {
	return w.loader.execute(w.skill, args)
}
