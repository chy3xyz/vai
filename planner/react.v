// vai.planner - ReAct/ToT 规划器
// 实现 Reasoning + Acting 循环和 Tree of Thoughts 规划
module planner

import skills { Registry, Skill, SkillContext, Result, SkillCall }
import llm { CompletionRequest, Message, user_message, assistant_message, system_message }
import time

// Planner 规划器接口
pub interface Planner {
	plan(goal string, context PlanContext) !Plan
	execute(plan Plan, ctx ExecutionContext) !ExecutionResult
}

// Plan 执行计划
pub struct Plan {
	pub:
		goal        string
		steps       []PlanStep
		created_at  time.Time
}

// PlanStep 计划步骤
pub struct PlanStep {
	pub:
		id          string
		description string
		action      Action
		depends_on  []string  // 依赖的步骤 ID
}

// Action 动作类型
pub type Action = ThoughtAction | SkillAction | FinalAction

// ThoughtAction 思考动作
pub struct ThoughtAction {
	pub:
		thought string
}

// SkillAction 技能调用动作
pub struct SkillAction {
	pub:
		skill_name string
		arguments  map[string]skills.Value
}

// FinalAction 最终答案动作
pub struct FinalAction {
	pub:
		answer string
}

// PlanContext 规划上下文
pub struct PlanContext {
	pub:
		conversation_history []Message
		available_skills     []string  // 可用的技能名称列表
		max_steps            int = 10
		system_prompt        string
}

// ExecutionContext 执行上下文
pub struct ExecutionContext {
	pub mut:
		skill_registry &Registry
		skill_context  SkillContext
		llm_client     llm.LLMProvider
}

// ExecutionResult 执行结果
pub struct ExecutionResult {
	pub:
		success     bool
		final_answer string
		steps_executed []StepExecution
		total_time_ms i64
}

// StepExecution 步骤执行记录
pub struct StepExecution {
	pub:
		step_id     string
		success     bool
		result      string
		error_msg   string
		took_ms     i64
}

// ReActPlanner ReAct 规划器
pub struct ReActPlanner {
	pub mut:
		max_iterations int = 10
		llm_client     llm.LLMProvider
}

// 创建 ReAct 规划器
pub fn new_react_planner(llm_client llm.LLMProvider) ReActPlanner {
	return ReActPlanner{
		max_iterations: 10
		llm_client: llm_client
	}
}

// ReAct 循环执行
pub fn (mut p ReActPlanner) execute(goal string, mut ctx ExecutionContext) !ExecutionResult {
	start_time := time.now()
	mut iterations := 0
	mut history := []Message{}
	mut step_executions := []StepExecution{}
	
	// 系统提示词
	system_prompt := 'You are an AI assistant that helps users by thinking step by step and using available tools.
When you need to use a tool, respond with:
Action: <tool_name>
Action Input: {"arg1": "value1", "arg2": "value2"}

When you have the final answer, respond with:
Final Answer: <your answer>

Think step by step and explain your reasoning.'
	
	history << system_message(system_prompt)
	history << user_message('Goal: ${goal}')
	
	for iterations < p.max_iterations {
		iterations++
		
		// 调用 LLM 获取下一步
		request := CompletionRequest{
			model: ''
			messages: history
			temperature: 0.7
			max_tokens: 1000
		}
		
		response := ctx.llm_client.complete(request)!
		content := response.content
		
		history << assistant_message(content)
		
		// 解析响应
		if content.contains('Final Answer:') {
			answer := content.split('Final Answer:')[1].trim_space()
			
			return ExecutionResult{
				success: true
				final_answer: answer
				steps_executed: step_executions
				total_time_ms: time.since(start_time).milliseconds()
			}
		}
		
		// 尝试解析 Action
		if content.contains('Action:') && content.contains('Action Input:') {
			action_parts := content.split('Action:')
			if action_parts.len >= 2 {
				action_line := action_parts[1].split('\n')[0].trim_space()
				
				// 解析参数
				mut args := map[string]skills.Value{}
				if content.contains('Action Input:') {
					input_parts := content.split('Action Input:')
					if input_parts.len >= 2 {
						_ := input_parts[1].split('\n')[0].trim_space()
						// Note: json.decode with sum types needs special handling
							// For now, use empty map - parsing can be enhanced later
							args = map[string]skills.Value{}
					}
				}
				
				// 执行技能
				step_start := time.now()
				result := ctx.skill_registry.execute(action_line, args, ctx.skill_context) or {
					step_executions << StepExecution{
						step_id: 'step_${iterations}'
						success: false
						error_msg: err.msg()
						took_ms: time.since(step_start).milliseconds()
					}
					history << user_message('Observation: Error - ${err.msg()}')
					continue
				}
				
				step_executions << StepExecution{
					step_id: 'step_${iterations}'
					success: result.success
					result: result.data.str()
					took_ms: time.since(step_start).milliseconds()
				}
				
				// 添加观察结果到历史
				observation := if result.success {
					result.data.str()
				} else {
					'Error: ${result.error_msg}'
				}
				
				history << user_message('Observation: ${observation}')
			}
		} else {
			// 没有明确的动作，继续思考
			history << user_message('Please continue thinking or provide a Final Answer.')
		}
	}
	
	// 达到最大迭代次数
	return ExecutionResult{
		success: false
		final_answer: 'Reached maximum iterations without finding an answer.'
		steps_executed: step_executions
		total_time_ms: time.since(start_time).milliseconds()
	}
}

// TreeOfThoughtsPlanner Tree of Thoughts 规划器
pub struct TreeOfThoughtsPlanner {
	pub mut:
		llm_client      llm.LLMProvider
		max_depth       int = 5
		branching_factor int = 3
		beam_width      int = 2
}

// ThoughtNode 思考节点
pub struct ThoughtNode {
	pub mut:
		id          string
		thought     string
		parent      ?string
		children    []string
		score       f32
		depth       int
		is_terminal bool
		answer      string
}

// 创建 ToT 规划器
pub fn new_tot_planner(llm_client llm.LLMProvider) TreeOfThoughtsPlanner {
	return TreeOfThoughtsPlanner{
		llm_client: llm_client
		max_depth: 5
		branching_factor: 3
		beam_width: 2
	}
}

// 执行 ToT 规划
pub fn (mut p TreeOfThoughtsPlanner) solve(problem string, ctx ExecutionContext) !string {
	mut root := ThoughtNode{
		id: 'root'
		thought: problem
		parent: none
		children: []
		score: 1.0
		depth: 0
		is_terminal: false
	}
	
	mut nodes := map[string]ThoughtNode{}
	mut current_level := ['root']
	nodes['root'] = root
	
	for depth := 0; depth < p.max_depth; depth++ {
		mut next_level := []string{}
		
		for node_id in current_level {
			if node := nodes[node_id] {
				// 生成候选思考
				candidates := p.generate_thoughts(node, problem, ctx)
				
				for i, thought in candidates {
					child_id := '${node_id}_${i}'
					
					// 评估思考
					score := p.evaluate_thought(thought, problem, ctx)
					
					// 检查是否是最终答案
					is_terminal := p.is_solution(thought, problem, ctx)
					
					child := ThoughtNode{
						id: child_id
						thought: thought
						parent: node_id
						children: []
						score: score
						depth: depth + 1
						is_terminal: is_terminal
						answer: if is_terminal { thought } else { '' }
					}
					
					nodes[child_id] = child
					nodes[node_id].children << child_id
					next_level << child_id
					
					if is_terminal {
						return thought
					}
				}
			}
		}
		
		// 选择最佳候选（Beam Search）
		if next_level.len == 0 {
			break
		}
		
		// Sort by score descending - using bubble sort since V 0.5 sort requires simple comparison
		for i := 0; i < next_level.len - 1; i++ {
			for j := i + 1; j < next_level.len; j++ {
				if nodes[next_level[i]].score < nodes[next_level[j]].score {
					temp := next_level[i]
					next_level[i] = next_level[j]
					next_level[j] = temp
				}
			}
		}
		
		if next_level.len > p.beam_width {
			current_level = next_level[..p.beam_width].clone()
		} else {
			current_level = next_level.clone()
		}
	}
	
	// 返回最佳答案
	mut best_score := f32(-1.0)
	mut best_answer := ''
	
	for _, node in nodes {
		if node.is_terminal && node.score > best_score {
			best_score = node.score
			best_answer = node.answer
		}
	}
	
	if best_answer.len > 0 {
		return best_answer
	}
	
	return error('Failed to find solution')
}

// 生成候选思考
fn (mut p TreeOfThoughtsPlanner) generate_thoughts(parent ThoughtNode, problem string, ctx ExecutionContext) []string {
	prompt := 'Given the problem: ${problem}
Current thought: ${parent.thought}
Generate ${p.branching_factor} possible next thoughts or steps. Be concise.

Thoughts:'
	
	request := CompletionRequest{
		model: ''
		messages: [user_message(prompt)]
		temperature: 0.8
		max_tokens: 500
	}
	
	response := ctx.llm_client.complete(request) or { return [] }
	content := response.content
	
	// 解析思考列表
	mut thoughts := []string{}
	lines := content.split('\n')
	
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len > 0 && !trimmed.starts_with('Thoughts:') {
			// 移除编号（如 "1. "）
			thought := trimmed.trim_left('0123456789. ')
			if thought.len > 0 {
				thoughts << thought
			}
		}
	}
	
	return thoughts
}

// 评估思考质量
fn (mut p TreeOfThoughtsPlanner) evaluate_thought(thought string, problem string, ctx ExecutionContext) f32 {
	prompt := 'Rate how good this thought is for solving the problem, from 0 to 10.
Problem: ${problem}
Thought: ${thought}

Score (0-10):'
	
	request := CompletionRequest{
		model: ''
		messages: [user_message(prompt)]
		temperature: 0.3
		max_tokens: 10
	}
	
	response := ctx.llm_client.complete(request) or { return 0.5 }
	content := response.content.trim_space()
	
	// 解析分数
	score := content.find_between('0', '10').int()
	if score >= 0 && score <= 10 {
		return f32(score) / 10.0
	}
	
	return 0.5
}

// 检查是否是解决方案
fn (mut p TreeOfThoughtsPlanner) is_solution(thought string, problem string, ctx ExecutionContext) bool {
	prompt := 'Does this thought contain a complete solution to the problem? Answer yes or no.
Problem: ${problem}
Thought: ${thought}

Answer (yes/no):'
	
	request := CompletionRequest{
		model: ''
		messages: [user_message(prompt)]
		temperature: 0.3
		max_tokens: 10
	}
	
	response := ctx.llm_client.complete(request) or { return false }
	content := response.content.to_lower().trim_space()
	
	return content.contains('yes')
}

// SimplePlanner 简单规划器（直接执行技能）
pub struct SimplePlanner {
	pub mut:
		skill_registry &Registry
}

// 创建简单规划器
pub fn new_simple_planner(registry &Registry) SimplePlanner {
	return SimplePlanner{
		skill_registry: registry
	}
}

// 直接执行技能
pub fn (mut p SimplePlanner) execute_skill(skill_name string, args map[string]skills.Value, ctx SkillContext) !Result {
	return p.skill_registry.execute(skill_name, args, ctx)!
}
