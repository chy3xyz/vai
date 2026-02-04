// vai.agent - 多 Agent 协作系统
// 支持 Agent 发现、任务分配、状态共享和协作执行
module agent

import protocol { Message, Conversation, new_text_message, new_event_message }
import skills { Registry, Skill, SkillContext, Result }
import memory { Store, MemoryStore, new_memory_store }
import llm { LLMProvider, CompletionRequest, user_message, system_message, assistant_message }
import runtime { Scheduler, new_scheduler, background, with_timeout }
import time
import sync
import json

// AgentRole Agent 角色类型
pub enum AgentRole {
	coordinator  // 协调者：负责任务分配
	worker       // 工作者：执行具体任务
	planner      // 规划者：负责策略制定
	specialist   // 专家：特定领域专家
	observer     // 观察者：监控和报告
}

// AgentStatus Agent 状态
pub enum AgentStatus {
	idle         // 空闲
	busy         // 忙碌
	offline      // 离线
	error        // 错误
}

// Agent 智能体接口
pub interface Agent {
	id() string
	name() string
	role() AgentRole
	status() AgentStatus
	capabilities() []string      // 能力列表
	handle_task(task Task) !TaskResult
	send_message(to string, msg Message) !
	receive_message() !Message
}

// BaseAgent Agent 基础实现
pub struct BaseAgent {
	pub mut:
		agent_id       string
		agent_name     string
		agent_role     AgentRole
		agent_status   AgentStatus = .idle
		skill_registry &Registry
		memory_store   &Store
		llm_provider   LLMProvider
		scheduler      &Scheduler
		// 通信
		inbox          chan Message
		outbox         chan Message
		// 协作
		hub            ?&AgentHub
		peers          map[string]AgentInfo
}

// AgentInfo Agent 信息
pub struct AgentInfo {
	pub:
		id           string
		name         string
		role         AgentRole
		capabilities []string
		status       AgentStatus
		last_seen    time.Time
}

// Task 任务定义
pub struct Task {
	pub:
		id          string
		type_       string           // 任务类型
		description string           // 任务描述
		input_data  map[string]any   // 输入数据
		priority    int              // 优先级
		deadline    ?time.Time       // 截止时间
		parent_id   ?string          // 父任务ID（用于子任务）
		required_caps []string       // 必需的能力
		assigned_to ?string          // 分配给特定Agent
}

// TaskResult 任务结果
pub struct TaskResult {
	pub:
		task_id     string
		success     bool
		output      map[string]any
		error_msg   string
		completed_by string
		started_at  time.Time
		completed_at time.Time
}

// MessageType Agent 间消息类型
pub enum MessageType {
	task_assign      // 任务分配
	task_result      // 任务结果
	query            // 查询请求
	response         // 查询响应
	broadcast        // 广播消息
	heartbeat        // 心跳
	announce         // Agent 宣布上线
}

// AgentMessage Agent 间通信消息
pub struct AgentMessage {
	pub:
		msg_type    MessageType
		from        string
		to          string  // 空表示广播
		payload     json.Any
		timestamp   time.Time
		correlation_id ?string  // 用于请求-响应关联
}

// 创建基础 Agent
pub fn new_base_agent(id string, name string, role AgentRole, llm LLMProvider, skills &Registry) &BaseAgent {
	return &BaseAgent{
		agent_id: id
		agent_name: name
		agent_role: role
		agent_status: .idle
		skill_registry: skills
		memory_store: &new_memory_store()
		llm_provider: llm
		scheduler: new_scheduler(2)
		inbox: chan Message{cap: 100}
		outbox: chan Message{cap: 100}
		hub: none
		peers: map[string]AgentInfo{}
	}
}

// 实现 Agent 接口
pub fn (a &BaseAgent) id() string { return a.agent_id }
pub fn (a &BaseAgent) name() string { return a.agent_name }
pub fn (a &BaseAgent) role() AgentRole { return a.agent_role }
pub fn (a &BaseAgent) status() AgentStatus { return a.agent_status }

pub fn (a &BaseAgent) capabilities() []string {
	mut caps := []string{}
	for skill in a.skill_registry.list() {
		caps << skill.name()
	}
	return caps
}

// 处理任务
pub fn (mut a BaseAgent) handle_task(task Task) !TaskResult {
	start_time := time.now()
	a.agent_status = .busy
	defer { a.agent_status = .idle }
	
	// 使用 LLM 理解任务
	prompt := 'You are ${a.agent_name}, a ${a.agent_role} agent. 
Your capabilities: ${a.capabilities().join(', ')}

Task: ${task.description}
Input: ${json.encode(task.input_data)}

Analyze this task and determine:
1. Can you handle it directly?
2. Do you need to delegate subtasks?
3. What skills should you use?

Respond with a JSON plan.'

	request := CompletionRequest{
		model: ''
		messages: [user_message(prompt)]
		temperature: 0.3
	}
	
	response := a.llm_provider.complete(request)!
	
	// 执行计划
	mut result := TaskResult{
		task_id: task.id
		success: false
		output: map[string]any{}
		error_msg: ''
		completed_by: a.agent_id
		started_at: start_time
		completed_at: time.now()
	}
	
	// 尝试使用技能执行
	for skill in a.skill_registry.list() {
		if task.type_.contains(skill.name()) {
			ctx := SkillContext{
				session_id: task.id
				user_id: 'system'
				working_dir: '.'
			}
			
			skill_result := a.skill_registry.execute(skill.name(), task.input_data, ctx) or {
				result = TaskResult{
					...result
					success: false
					error_msg: err.msg()
					completed_at: time.now()
				}
				return result
			}
			
			result = TaskResult{
				...result
				success: skill_result.success
				output: {'result': skill_result.data}
				completed_at: time.now()
			}
			return result
		}
	}
	
	// 如果没有匹配的技能，返回 LLM 响应
	result = TaskResult{
		...result
		success: true
		output: {'response': response.content}
		completed_at: time.now()
	}
	
	return result
}

// 发送消息给另一个 Agent
pub fn (mut a BaseAgent) send_message(to string, msg Message) ! {
	if mut hub := a.hub {
		hub.route_message(a.agent_id, to, msg)!
	}
}

// 接收消息
pub fn (mut a BaseAgent) receive_message() !Message {
	select {
		msg := <-a.inbox {
			return msg
		}
		5 * time.second {
			return error('receive timeout')
		}
	}
}

// 启动 Agent
pub fn (mut a BaseAgent) start() ! {
	a.scheduler.start()!
	
	// 向 Hub 注册
	if mut hub := a.hub {
		hub.register(a)!
	}
	
	// 启动消息处理循环
	spawn a.message_loop()
	
	println('Agent ${a.agent_name} (${a.agent_id}) started as ${a.agent_role}')
}

// 停止 Agent
pub fn (mut a BaseAgent) stop() {
	a.scheduler.stop()
	if mut hub := a.hub {
		hub.unregister(a.agent_id)
	}
}

// 消息处理循环
fn (mut a BaseAgent) message_loop() {
	for a.agent_status != .offline {
		select {
			msg := <-a.inbox {
				a.process_message(msg)
			}
			100 * time.millisecond {
				// 继续
			}
		}
	}
}

// 处理接收到的消息
fn (mut a BaseAgent) process_message(msg Message) {
	// 根据消息类型处理
	if text := msg.text() {
		if text.starts_with('/task ') {
			// 处理任务请求
			task := Task{
				id: generate_task_id()
				type_: 'generic'
				description: text[6..]
				input_data: map[string]any{}
				priority: 0
			}
			
			result := a.handle_task(task) or {
				eprintln('Task failed: ${err}')
				return
			}
			
			// 发送结果
			result_msg := new_text_message('Task ${task.id} completed: ${result.output}')
			result_msg.receiver_id = msg.sender_id
			a.send_message(msg.sender_id, result_msg) or {}
		}
	}
}

// 连接到 Hub
pub fn (mut a BaseAgent) connect_to_hub(mut hub AgentHub) {
	a.hub = &hub
}

// 更新对等 Agent 信息
pub fn (mut a BaseAgent) update_peer(info AgentInfo) {
	a.peers[info.id] = info
}

// 获取在线对等 Agent
pub fn (a &BaseAgent) get_online_peers() []AgentInfo {
	mut peers := []AgentInfo{}
	for _, info in a.peers {
		if info.status != .offline {
			peers << info
		}
	}
	return peers
}

// 委托任务给其他 Agent
pub fn (mut a BaseAgent) delegate_task(task Task, target_agent string) !TaskResult {
	// 查找目标 Agent
	target := a.peers[target_agent] or {
		return error('target agent not found: ${target_agent}')
	}
	
	if target.status == .offline {
		return error('target agent is offline')
	}
	
	// 发送任务分配消息
	task_msg := AgentMessage{
		msg_type: .task_assign
		from: a.agent_id
		to: target_agent
		payload: json.Any(json.encode(task))
		timestamp: time.now()
	}
	
	// 等待结果（简化实现）
	// 实际应该通过 Hub 的消息路由
	time.sleep(100 * time.millisecond)
	
	return TaskResult{
		task_id: task.id
		success: false
		error_msg: 'Delegation not fully implemented'
		completed_by: target_agent
		started_at: time.now()
		completed_at: time.now()
	}
}

// 生成任务 ID
fn generate_task_id() string {
	return 'task_${time.now().unix}_${rand_chars(8)}'
}

fn rand_chars(len int) string {
	chars := 'abcdefghijklmnopqrstuvwxyz0123456789'
	mut result := ''
	seed := time.now().unix
	for i := 0; i < len; i++ {
		idx := (seed + i * 31) % chars.len
		result += chars[idx].ascii_str()
	}
	return result
}
