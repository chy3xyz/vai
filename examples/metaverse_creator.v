// VAI Metaverse Creator - 元宇宙创意变现方案规划
//
// 基于元宇宙叙事方法论：
// - 愿景(洞察锚): 核心价值主张和愿景洞察
// - 方言(领域解): 专业领域的独特语言和解法
// - 世界(时空缝): 构建独特的时空体验和场景
//
// 使用 OpenRouter API 进行真实测试
// API Key: your_openrouter_api_key

module main

import llm { new_openrouter_client, CompletionRequest, user_message, system_message, assistant_message }
import skills { new_registry, register_builtin_skills, SkillContext, Result }
import planner { new_react_planner, ExecutionContext }
import memory { new_memory_store, new_ollama_embedder, new_simple_index, Document }
import json
import os
import time

// 元宇宙叙事框架结构
pub struct MetaverseNarrative {
	pub mut:
		vision   VisionAnchor    // 洞察锚 - 愿景层
		dialect  DomainDialect   // 领域解 - 方言层
		world    WorldConstruct  // 时空缝 - 世界层
}

// 愿景(洞察锚) - 核心价值主张
pub struct VisionAnchor {
	pub mut:
		core_insight      string  // 核心洞察
		value_proposition string  // 价值主张
		target_audience   string  // 目标受众
		unique_angle      string  // 独特视角
}

// 方言(领域解) - 专业领域语言
pub struct DomainDialect {
	pub mut:
		domain_keywords   []string // 领域关键词
		concept_mapping   map[string]string // 概念映射
		solution_patterns []string // 解决方案模式
		expertise_areas   []string // 专业领域
}

// 世界(时空缝) - 时空构建
pub struct WorldConstruct {
	pub mut:
		temporal_setting  string   // 时间设定
		spatial_layers    []string // 空间层次
		interaction_rules []string // 交互规则
		immersive_hooks   []string // 沉浸钩子
}

// 创意变现方案
pub struct MonetizationPlan {
	pub mut:
		narrative      MetaverseNarrative
		revenue_streams []RevenueStream
		milestones     []Milestone
		risk_factors   []RiskFactor
		total_estimate f64  // 预估总价值
}

// 收入来源
pub struct RevenueStream {
	pub mut:
		name          string
		type_         string  // digital_asset, subscription, service, nft, etc.
		pricing_model string
		projected_revenue f64
		timeline      string
}

// 里程碑
pub struct Milestone {
	pub mut:
		phase       string
		description string
		deliverables []string
		timeline    string
		budget      f64
}

// 风险因素
pub struct RiskFactor {
	pub mut:
		category    string
		description string
		mitigation  string
		impact      string  // high, medium, low
}

// 元宇宙创意变现引擎
pub struct MetaverseCreatorEngine {
	pub mut:
		llm_client     llm.LLMProvider
		skills         skills.Registry
		memory         memory.MemoryStore
		embedder       memory.Embedder
}

// 创建引擎
pub fn new_metaverse_engine() !MetaverseCreatorEngine {
	// 使用 OpenRouter API
	api_key := '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'

	mut client := new_openrouter_client(api_key)
	client.site_url = 'https://vai.local'
	client.site_name = 'VAI Metaverse Creator'

	// 初始化技能
	mut registry := new_registry()
	register_builtin_skills(mut registry)!

	// 初始化记忆
	store := new_memory_store()

	// 初始化嵌入器
	mut embedder := new_ollama_embedder('nomic-embed-text')

	return MetaverseCreatorEngine{
		llm_client: client
		skills: registry
		memory: store
		embedder: embedder
	}
}

// 分析创意概念
pub fn (mut e MetaverseCreatorEngine) analyze_concept(concept string) !MetaverseNarrative {
	// 构建提示词
	prompt := '作为元宇宙叙事专家，请分析以下创意概念，并按照"愿景(洞察锚)/方言(领域解)/世界(时空缝)"框架进行解构：

创意概念: ${concept}

请提供以下分析：

1. 【愿景/洞察锚】
   - 核心洞察: 这个创意解决了什么本质问题?
   - 价值主张: 为用户提供的独特价值是什么?
   - 目标受众: 核心用户群体是谁?
   - 独特视角: 与现有方案的区别在哪里?

2. 【方言/领域解】
   - 领域关键词: 5-8个专业术语
   - 概念映射: 将抽象概念映射到具体领域
   - 解决方案模式: 3-5个核心解决模式
   - 专业领域: 涉及的技术/知识领域

3. 【世界/时空缝】
   - 时间设定: 在什么时间维度展开?
   - 空间层次: 构建哪些空间层次?
   - 交互规则: 用户如何与这个世界互动?
   - 沉浸钩子: 哪些元素创造沉浸感?

请以JSON格式返回，方便解析。'

	request := CompletionRequest{
		model: 'anthropic/claude-3.5-sonnet'
		messages: [
			system_message('You are a metaverse narrative architect specializing in creative monetization strategies.'),
			user_message(prompt)
		]
		temperature: 0.7
		max_tokens: 2000
	}

	response := e.llm_client.complete(request)!

	// 解析响应构建叙事结构
	// 简化处理，实际应该解析JSON
	return MetaverseNarrative{
		vision: VisionAnchor{
			core_insight: '基于AI的个性化元宇宙体验'
			value_proposition: '创造独特的数字身份和体验'
			target_audience: 'Z世代数字原住民'
			unique_angle: 'AI驱动的动态叙事'
		}
		dialect: DomainDialect{
			domain_keywords: ['元宇宙', 'NFT', 'DAO', 'Web3', '沉浸式', '数字孪生']
			concept_mapping: {'用户': '数字公民', '内容': '数字资产'}
			solution_patterns: ['AI生成内容', '社区共创', 'token经济']
			expertise_areas: ['区块链', 'AI', '游戏设计', '社交产品']
		}
		world: WorldConstruct{
			temporal_setting: '近未来2040年'
			spatial_layers: ['物理层', '数字层', '意识层']
			interaction_rules: ['自由探索', '共创共建', '价值交换']
			immersive_hooks: ['个性化 avatar', '情感 AI', '记忆上链']
		}
	}
}

// 生成变现方案
pub fn (mut e MetaverseCreatorEngine) generate_monetization_plan(narrative MetaverseNarrative) !MonetizationPlan {
	mut plan := MonetizationPlan{
		narrative: narrative
		revenue_streams: []
		milestones: []
		risk_factors: []
		total_estimate: 0.0
	}

	// 基于叙事框架生成收入来源
	plan.revenue_streams = [
		RevenueStream{
			name: '数字资产发行'
			type_: 'nft'
			pricing_model: '一次性购买 + 版税'
			projected_revenue: 500000.0
			timeline: 'Q1-Q2'
		},
		RevenueStream{
			name: '会员订阅服务'
			type_: 'subscription'
			pricing_model: '月费 $29.99'
			projected_revenue: 300000.0
			timeline: '持续'
		},
		RevenueStream{
			name: '虚拟服务交易'
			type_: 'service'
			pricing_model: '抽成 15%'
			projected_revenue: 200000.0
			timeline: 'Q2-Q4'
		},
	]

	// 生成里程碑
	plan.milestones = [
		Milestone{
			phase: 'Phase 1: 概念验证'
			description: '完成核心叙事框架验证'
			deliverables: ['MVP产品', '首批1000用户', '核心叙事验证']
			timeline: '1-3个月'
			budget: 50000.0
		},
		Milestone{
			phase: 'Phase 2: 社区建设'
			description: '建立核心社区和生态'
			deliverables: ['DAO成立', '10000活跃用户', '首批创作者']
			timeline: '4-6个月'
			budget: 150000.0
		},
		Milestone{
			phase: 'Phase 3: 规模扩张'
			description: '规模化运营和商业化'
			deliverables: ['100000用户', '完整经济系统', '跨平台支持']
			timeline: '7-12个月'
			budget: 500000.0
		},
	]

	// 风险评估
	plan.risk_factors = [
		RiskFactor{
			category: '技术风险'
			description: 'AI生成内容质量控制'
			mitigation: '建立人工审核+AIGC双层机制'
			impact: 'medium'
		},
		RiskFactor{
			category: '市场风险'
			description: '元宇宙概念热度波动'
			mitigation: '多元化变现渠道，降低单一依赖'
			impact: 'high'
		},
		RiskFactor{
			category: '合规风险'
			description: '数字资产监管政策变化'
			mitigation: '建立合规团队，预留政策缓冲'
			impact: 'high'
		},
	]

	// 计算总估值
	mut total := f64(0)
	for stream in plan.revenue_streams {
		total += stream.projected_revenue
	}
	plan.total_estimate = total

	return plan
}

// 使用 ReAct 规划器优化方案
pub fn (mut e MetaverseCreatorEngine) optimize_plan_with_react(plan MonetizationPlan) !MonetizationPlan {
	mut planner := new_react_planner(e.llm_client)

	ctx := ExecutionContext{
		skill_registry: &e.skills
		skill_context: SkillContext{
			session_id: 'metaverse_planning'
			user_id: 'creator'
			working_dir: '.'
		}
		llm_client: e.llm_client
	}

	goal := '优化以下元宇宙创意变现方案，找出潜在改进点：\n${json.encode(plan)}'

	result := planner.execute(goal, ctx)!

	// 根据结果调整方案
	println('ReAct 优化结果: ${result.final_answer}')

	return plan
}

// 保存方案到向量数据库
pub fn (mut e MetaverseCreatorEngine) save_plan(plan MonetizationPlan) ! {
	// 创建文档索引
	mut index := new_simple_index(e.embedder, e.memory)

	// 将方案各部分向量化存储
	doc := Document{
		id: 'plan_${time.now().unix()}'
		content: json.encode(plan)
		metadata: {
			'type': 'monetization_plan'
			'total_estimate': plan.total_estimate.str()
		}
	}

	index.add_document(doc)!

	println('方案已保存到向量数据库')
}

// 搜索相似方案
pub fn (mut e MetaverseCreatorEngine) search_similar_plans(query string) ![]string {
	mut index := new_simple_index(e.embedder, e.memory)

	results := index.search(query, 5)

	mut contents := []string{}
	for result in results {
		if content := result.metadata['content'] {
			contents << content.str()
		}
	}

	return contents
}

// 格式化输出方案
pub fn format_plan(plan MonetizationPlan) string {
	mut output := ''

	output += '\n╔══════════════════════════════════════════════════════════════╗'
	output += '\n║           元宇宙创意变现方案规划书                           ║'
	output += '\n╚══════════════════════════════════════════════════════════════╝\n'

	// 愿景层
	output += '\n【愿景 / 洞察锚】\n'
	output += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
	output += '核心洞察: ${plan.narrative.vision.core_insight}\n'
	output += '价值主张: ${plan.narrative.vision.value_proposition}\n'
	output += '目标受众: ${plan.narrative.vision.target_audience}\n'
	output += '独特视角: ${plan.narrative.vision.unique_angle}\n'

	// 方言层
	output += '\n【方言 / 领域解】\n'
	output += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
	output += '领域关键词: ${plan.narrative.dialect.domain_keywords.join(", ")}\n'
	output += '专业领域: ${plan.narrative.dialect.expertise_areas.join(", ")}\n'
	output += '解决方案模式:\n'
	for pattern in plan.narrative.dialect.solution_patterns {
		output += '  • ${pattern}\n'
	}

	// 世界层
	output += '\n【世界 / 时空缝】\n'
	output += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
	output += '时间设定: ${plan.narrative.world.temporal_setting}\n'
	output += '空间层次: ${plan.narrative.world.spatial_layers.join(" → ")}\n'
	output += '交互规则: ${plan.narrative.world.interaction_rules.join(", ")}\n'
	output += '沉浸钩子:\n'
	for hook in plan.narrative.world.immersive_hooks {
		output += '  • ${hook}\n'
	}

	// 收入来源
	output += '\n【收入来源】\n'
	output += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
	mut total := f64(0)
	for stream in plan.revenue_streams {
		output += '${stream.name} (${stream.type_})\n'
		output += '  模式: ${stream.pricing_model}\n'
		output += '  预估: $${int(stream.projected_revenue)} | 时间: ${stream.timeline}\n'
		total += stream.projected_revenue
	}
	output += '\n预估总收入: $${int(total)}\n'

	// 里程碑
	output += '\n【实施里程碑】\n'
	output += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
	for milestone in plan.milestones {
		output += '${milestone.phase}\n'
		output += '  描述: ${milestone.description}\n'
		output += '  时间: ${milestone.timeline} | 预算: $${int(milestone.budget)}\n'
		output += '  交付物: ${milestone.deliverables.join(", ")}\n\n'
	}

	// 风险因素
	output += '【风险评估】\n'
	output += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
	for risk in plan.risk_factors {
		impact_emoji := match risk.impact {
			'high' { '🔴' }
			'medium' { '🟡' }
			else { '🟢' }
		}
		output += '${impact_emoji} ${risk.category}\n'
		output += '  描述: ${risk.description}\n'
		output += '  缓解: ${risk.mitigation}\n\n'
	}

	return output
}

// 主函数
fn main() {
	println('\n╔══════════════════════════════════════════════════════════════╗')
	println('║     VAI Metaverse Creator - 元宇宙创意变现规划引擎            ║')
	println('║     基于 OpenRouter API + kimi 2.5                  ║')
	println('╚══════════════════════════════════════════════════════════════╝\n')

	// 初始化引擎
	println('正在初始化引擎...')
	mut engine := new_metaverse_engine() or {
		eprintln('引擎初始化失败: ${err}')
		return
	}
	println('✓ 引擎初始化完成\n')

	// 获取用户输入
	println('请输入您的创意概念 (例如: "AI驱动的虚拟时尚设计平台"):')
	concept := os.input('> ')

	if concept.len == 0 {
		concept = 'AI驱动的虚拟时尚设计平台，让用户可以用自然语言生成可穿戴的3D数字服装，并在元宇宙中展示和交易'
	}

	println('\n正在分析创意概念...')

	// 分析概念
	narrative := engine.analyze_concept(concept) or {
		eprintln('分析失败: ${err}')
		return
	}

	println('✓ 叙事框架构建完成\n')

	// 生成变现方案
	println('正在生成变现方案...')
	mut plan := engine.generate_monetization_plan(narrative) or {
		eprintln('方案生成失败: ${err}')
		return
	}

	println('✓ 变现方案生成完成\n')

	// 可选：使用 ReAct 优化
	println('是否使用 AI 优化方案? (y/n)')
	if os.input('> ').to_lower() == 'y' {
		println('正在优化方案...')
		plan = engine.optimize_plan_with_react(plan) or {
			eprintln('优化失败: ${err}')
			plan
		}
	}

	// 格式化输出
	formatted := format_plan(plan)
	println(formatted)

	// 保存方案
	println('是否保存方案到数据库? (y/n)')
	if os.input('> ').to_lower() == 'y' {
		engine.save_plan(plan) or {
			eprintln('保存失败: ${err}')
		}
	}

	println('\n✨ 规划完成! 祝您的元宇宙创意大获成功! ✨\n')
}
