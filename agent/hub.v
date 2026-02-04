// vai.agent.hub - Agent 协作中心
// 负责 Agent 注册、发现、消息路由和任务协调
module agent

import protocol { Message, new_event_message }
import sync
import time
import json

// AgentHub Agent 协作中心
@[heap]
pub struct AgentHub {
	pub mut:
		id            string
		name          string
		agents        map[string]&BaseAgent
		message_queue chan RoutedMessage
		task_queue    chan Task
		results       map[string]TaskResult
		// 配置
		max_agents    int = 100
		task_timeout  time.Duration = 5 * time.minute
		// 同步
		mu            sync.RwMutex
		running       bool
}

// RoutedMessage 路由消息
pub struct RoutedMessage {
	pub:
		from    string
		to      string
		msg     Message
		timestamp time.Time
}

// TaskAssignment 任务分配
pub struct TaskAssignment {
	pub:
		task       Task
		assigned_to string
		assigned_at time.Time
		deadline   ?time.Time
}

// 创建 Agent Hub
pub fn new_hub(id string, name string) &AgentHub {
	return &AgentHub{
		id: id
		name: name
		agents: map[string]&BaseAgent{}
		message_queue: chan RoutedMessage{cap: 1000}
		task_queue: chan Task{cap: 100}
		results: map[string]TaskResult{}
		max_agents: 100
		task_timeout: 5 * time.minute
		running: false
	}
}

// 启动 Hub
pub fn (mut h AgentHub) start() ! {
	h.running = true
	
	// 启动消息路由循环
	spawn h.message_router()
	
	// 启动任务调度器
	spawn h.task_scheduler()
	
	// 启动心跳检查
	spawn h.heartbeat_checker()
	
	println('Agent Hub "${h.name}" (${h.id}) started')
}

// 停止 Hub
pub fn (mut h AgentHub) stop() {
	h.running = false
}

// 注册 Agent
pub fn (mut h AgentHub) register(mut ag BaseAgent) ! {
	h.mu.lock()
	defer { h.mu.unlock() }
	
	if h.agents.len >= h.max_agents {
		return error('max agents limit reached')
	}
	
	if ag.agent_id in h.agents {
		return error('agent already registered: ${ag.agent_id}')
	}
	
	h.agents[ag.agent_id] = unsafe { ag }
	
	// 通知其他 Agent
	h.broadcast_announce(mut ag)
	
	println('Agent registered: ${ag.agent_name} (${ag.agent_id})')
}

// 注销 Agent
pub fn (mut h AgentHub) unregister(ag_id string) {
	h.mu.lock()
	defer { h.mu.unlock() }
	
	h.agents.delete(ag_id)
	println('Agent unregistered: ${ag_id}')
}

// 路由消息
pub fn (mut h AgentHub) route_message(from string, to string, msg Message) ! {
	if !h.running {
		return error('hub not running')
	}
	
	routed := RoutedMessage{
		from: from
		to: to
		msg: msg
		timestamp: time.now()
	}
	
	h.message_queue <- routed
}

// 广播消息
pub fn (mut h AgentHub) broadcast(from string, msg Message) ! {
	h.mu.rlock()
	defer { h.mu.runlock() }
	
	for id, _ in h.agents {
		if id != from {
			h.route_message(from, id, msg) or { continue }
		}
	}
}

// 消息路由循环
fn (mut h AgentHub) message_router() {
	for h.running {
		select {
			routed := <-h.message_queue {
				h.deliver_message(routed)
			}
			100 * time.millisecond {
				// 继续
			}
		}
	}
}

// 投递消息
fn (mut h AgentHub) deliver_message(routed RoutedMessage) {
	h.mu.rlock()
	defer { h.mu.runlock() }
	
	if target := h.agents[routed.to] {
		target.inbox <- routed.msg
	}
}

// 提交任务
pub fn (mut h AgentHub) submit_task(task Task) !string {
	if !h.running {
		return error('hub not running')
	}
	
	h.task_queue <- task
	return task.id
}

// 任务调度器
fn (mut h AgentHub) task_scheduler() {
	for h.running {
		select {
			task := <-h.task_queue {
				h.assign_task(task)
			}
			1 * time.second {
				// 继续
			}
		}
	}
}

// 分配任务
fn (mut h AgentHub) assign_task(task Task) {
	h.mu.rlock()
	defer { h.mu.runlock() }
	
	// 如果指定了 Agent，直接分配
	if assigned_to := task.assigned_to {
		if mut target_ag := h.agents[assigned_to] {
			if target_ag.agent_status == .idle {
				spawn h.execute_task_on_agent(task, mut target_ag)
				return
			}
		}
	}
	
	// 自动选择最合适的 Agent
	mut best_agent := ?&BaseAgent(none)
	mut best_score := -1
	
	for _, mut candidate in h.agents {
		if candidate.agent_status != .idle {
			continue
		}
		
		// 计算匹配分数
		score := h.calculate_agent_score(mut candidate, task)
		if score > best_score {
			best_score = score
			best_agent = unsafe { candidate }
		}
	}
	
	if mut best_ag := best_agent {
		spawn h.execute_task_on_agent(task, mut best_ag)
	} else {
		// 没有可用 Agent，重新入队
		time.sleep(1 * time.second)
		h.task_queue <- task
	}
}

// 计算 Agent 匹配分数
fn (h &AgentHub) calculate_agent_score(mut ag BaseAgent, task Task) int {
	mut score := 0
	
	// 角色匹配
	match ag.agent_role {
		.coordinator { if task.type_ == 'coordination' { score += 10 } }
		.planner { if task.type_ == 'planning' { score += 10 } }
		.worker { score += 5 }
		.specialist { 
			// 检查专业能力
			for cap in task.required_caps {
				if cap in ag.capabilities() {
					score += 15
				}
			}
		}
		else {}
	}
	
	return score
}

// 在指定 Agent 上执行任务
fn (mut h AgentHub) execute_task_on_agent(task Task, mut ag BaseAgent) {
	mut task_copy := task
	result := ag.handle_task(mut task_copy) or {
		TaskResult{
			task_id: task.id
			success: false
			error_msg: err.msg()
			completed_by: ag.agent_id
			started_at: time.now()
			completed_at: time.now()
		}
	}
	
	h.mu.lock()
	h.results[task.id] = result
	h.mu.unlock()
	
	// 通知请求者
	println('Task ${task.id} completed by ${ag.agent_name}')
}

// 获取任务结果
pub fn (mut h AgentHub) get_task_result(task_id string) ?TaskResult {
	h.mu.rlock()
	defer { h.mu.runlock() }
	return h.results[task_id] or { return none }
}

// 心跳检查
fn (mut h AgentHub) heartbeat_checker() {
	for h.running {
		time.sleep(30 * time.second)
		
		h.mu.lock()
		now := time.now()
		
		for ag_id, mut ag_info in h.agents {
			_ := ag_id
			// 检查 Agent 是否还在线
			// 简化实现：假设有 last_seen 字段
		}
		
		h.mu.unlock()
	}
}

// 广播 Agent 上线通知
fn (mut h AgentHub) broadcast_announce(mut ag BaseAgent) {
	info := AgentInfo{
		id: ag.agent_id
		name: ag.agent_name
		role: ag.agent_role
		capabilities: ag.capabilities()
		status: ag.agent_status
		last_seen: time.now()
	}
	
	msg := new_event_message('agent_announce', {
		'agent': json.encode(info)
	})
	
	h.broadcast(ag.agent_id, msg) or {}
}

// 获取所有 Agent 信息
pub fn (mut h AgentHub) list_agents() []AgentInfo {
	h.mu.rlock()
	defer { h.mu.runlock() }
	
	mut infos := []AgentInfo{}
	for _, mut ag in h.agents {
		infos << AgentInfo{
			id: ag.agent_id
			name: ag.agent_name
			role: ag.agent_role
			capabilities: ag.capabilities()
			status: ag.agent_status
			last_seen: time.now()
		}
	}
	return infos
}

// 获取特定角色的 Agent
pub fn (mut h AgentHub) get_agents_by_role(role AgentRole) []&BaseAgent {
	h.mu.rlock()
	defer { h.mu.runlock() }
	
	mut agents := []&BaseAgent{}
	for _, mut ag in h.agents {
		if ag.agent_role == role {
			agents << ag
		}
	}
	return agents
}

// 创建协作组
pub struct AgentTeam {
	pub mut:
		id      string
		name    string
		members []string  // Agent IDs
		hub     &AgentHub
}

// 创建团队
pub fn (mut h AgentHub) create_team(name string, member_ids []string) !AgentTeam {
	// 验证所有成员都存在
	for id in member_ids {
		if id !in h.agents {
			return error('agent not found: ${id}')
		}
	}
	
	return AgentTeam{
		id: generate_task_id()
		name: name
		members: member_ids
		hub: unsafe { &h }
	}
}

// 向团队广播消息
pub fn (mut t AgentTeam) broadcast(from string, msg Message) ! {
	for member_id in t.members {
		if member_id != from {
			t.hub.route_message(from, member_id, msg)!
		}
	}
}

// 分配团队任务
pub fn (mut t AgentTeam) distribute_task(task Task, strategy DistributionStrategy) ! {
	match strategy {
		.broadcast {
			// 广播给所有成员
			for member_id in t.members {
				t.hub.route_message('hub', member_id, new_event_message('team_task', {
					'task': json.encode(task)
					'team': t.id
				}))!
			}
		}
		.round_robin {
			// 轮询分配
			idx := time.now().second % t.members.len
			target := t.members[idx]
			_ = t.hub.agents[target] or { return error('agent not found') }
			t.hub.task_queue <- task
		}
		.least_loaded {
			// 分配给负载最低的成员
			mut min_load := 999999
			mut target := ''
			
			for member_id in t.members {
				if ag_info := t.hub.agents[member_id] {
					// 简化：使用状态作为负载指标
					load := if ag_info.agent_status == .busy { 1 } else { 0 }
					if load < min_load {
						min_load = load
						target = member_id
					}
				}
			}
			
			if target.len > 0 {
				t.hub.task_queue <- task
			}
		}
		else {}
	}
}

// 任务分配策略
pub enum DistributionStrategy {
	broadcast      // 广播给所有成员
	round_robin    // 轮询
	least_loaded   // 最少负载
	specialized    // 按专业能力
}
