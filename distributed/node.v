// vai.distributed - 分布式部署支持
// 实现多节点 Agent 通信和集群管理
module distributed

import agent { Agent, AgentInfo, Task, TaskResult }
import protocol { Message }
import net.http
import net.websocket
import json
import time
import sync
import rand

// NodeRole 节点角色
pub enum NodeRole {
	master   // 主节点：协调集群
	worker   // 工作节点：执行任务
	gateway  // 网关节点：处理外部请求
}

// NodeStatus 节点状态
pub enum NodeStatus {
	online
	offline
	busy
	degraded
}

// Node 分布式节点
pub struct Node {
	pub mut:
		id            string
		role          NodeRole
		status        NodeStatus
		address       string           // 节点地址
		api_port      int = 8080
		ws_port       int = 8081
		peers         map[string]PeerNode
		known_masters []string         // 已知主节点地址
		task_queue    chan Task
		results       chan TaskResult
		mu            sync.RwMutex
		running       bool
}

// PeerNode 对等节点
pub struct PeerNode {
	pub:
		id        string
		role      NodeRole
		address   string
		last_seen time.Time
		load      f32  // 负载 0-1
}

// ClusterConfig 集群配置
pub struct ClusterConfig {
	pub:
		node_id        string
		role           NodeRole
		bind_address   string = '0.0.0.0'
		api_port       int = 8080
		ws_port        int = 8081
		master_nodes   []string  // 初始主节点列表
		heartbeat_interval int = 30  // 秒
}

// 创建新节点
pub fn new_node(config ClusterConfig) Node {
	node_id := if config.node_id.len > 0 { config.node_id } else { generate_node_id() }
	
	return Node{
		id: node_id
		role: config.role
		status: .online
		address: config.bind_address
		api_port: config.api_port
		ws_port: config.ws_port
		peers: map[string]PeerNode{}
		known_masters: config.master_nodes
		task_queue: chan Task{cap: 100}
		results: chan TaskResult{cap: 100}
		running: false
	}
}

// 生成节点 ID
fn generate_node_id() string {
	return 'node_${time.now().unix}_${rand.string(8)}'
}

// 启动节点
pub fn (mut n Node) start() ! {
	n.running = true
	
	// 启动 HTTP API 服务器
	spawn n.start_api_server()
	
	// 启动 WebSocket 服务器
	spawn n.start_ws_server()
	
	// 如果是工作节点，连接到主节点
	if n.role == .worker {
		spawn n.connect_to_masters()
	}
	
	// 启动心跳
	spawn n.heartbeat_loop()
	
	println('Node ${n.id} started as ${n.role} on ${n.address}:${n.api_port}')
}

// 停止节点
pub fn (mut n Node) stop() {
	n.running = false
}

// 启动 API 服务器
fn (mut n Node) start_api_server() {
	// 使用标准 HTTP 服务器
	// 实际实现需要集成 web 模块
	for n.running {
		time.sleep(1 * time.second)
	}
}

// 启动 WebSocket 服务器
fn (mut n Node) start_ws_server() {
	// 监听 WebSocket 连接
	for n.running {
		time.sleep(1 * time.second)
	}
}

// 连接到主节点
fn (mut n Node) connect_to_masters() {
	for master_addr in n.known_masters {
		n.join_cluster(master_addr) or {
			eprintln('Failed to connect to master ${master_addr}: ${err}')
			continue
		}
	}
}

// JoinResponse 加入集群响应
pub struct JoinResponse {
	pub:
		success bool
		peers   []PeerNode
}

// 加入集群
pub fn (mut n Node) join_cluster(master_address string) ! {
	// 向主节点注册
	reg_data := json.encode({
		'node_id': n.id
		'role': int(n.role)
		'address': n.address
		'api_port': n.api_port
		'ws_port': n.ws_port
	})
	
	mut req := http.new_request(.post, 'http://${master_address}/cluster/join', reg_data)
	req.header.add(.content_type, 'application/json')
	
	resp := http.fetch(req)!
	
	if resp.status_code != 200 {
		return error('failed to join cluster: ${resp.status_code}')
	}
	
	// 解析对等节点列表
	join_resp := json.decode(JoinResponse, resp.body)!
	
	// 添加对等节点
	for peer in join_resp.peers {
		n.add_peer(peer)
	}
}

// 添加对等节点
pub fn (mut n Node) add_peer(peer PeerNode) {
	n.mu.lock()
	defer { n.mu.unlock() }
	
	n.peers[peer.id] = peer
}

// 心跳循环
fn (mut n Node) heartbeat_loop() {
	for n.running {
		time.sleep(30 * time.second)
		
		n.send_heartbeats()
	}
}

// 发送心跳
fn (mut n Node) send_heartbeats() {
	n.mu.rlock()
	peers := n.peers.clone()
	n.mu.runlock()
	
	for _, peer in peers {
		// 向对等节点发送心跳
		go n.send_heartbeat_to(peer)
	}
}

// 向单个节点发送心跳
fn (mut n Node) send_heartbeat_to(peer PeerNode) {
	heartbeat := json.encode({
		'node_id': n.id
		'status': int(n.status)
		'timestamp': time.now().unix
		'load': n.get_load()
	})
	
	mut req := http.new_request(.post, 'http://${peer.address}:${peer.api_port}/cluster/heartbeat', heartbeat)
	req.header.add(.content_type, 'application/json')
	
	http.fetch(req) or {
		// 心跳失败，标记节点可能离线
		return
	}
}

// 获取节点负载
fn (n &Node) get_load() f32 {
	// 简化实现：基于任务队列长度
	return 0.5
}

// 分发任务
pub fn (mut n Node) distribute_task(task Task) !string {
	if n.role != .master {
		return error('only master can distribute tasks')
	}
	
	// 选择负载最低的节点
	mut best_node := ?PeerNode(none)
	mut min_load := f32(1.0)
	
	n.mu.rlock()
	for _, peer in n.peers {
		if peer.role == .worker && peer.load < min_load {
			min_load = peer.load
			best_node = peer
		}
	}
	n.mu.runlock()
	
	if node := best_node {
		return n.send_task_to_node(node, task)
	}
	
	return error('no available worker node')
}

// 发送任务到节点
fn (mut n Node) send_task_to_node(node PeerNode, task Task) !string {
	task_data := json.encode(task)
	
	mut req := http.new_request(.post, 'http://${node.address}:${node.api_port}/tasks', task_data)
	req.header.add(.content_type, 'application/json')
	
	resp := http.fetch(req)!
	
	if resp.status_code != 200 {
		return error('failed to send task: ${resp.status_code}')
	}
	
	return task.id
}

// 处理接收到的任务
pub fn (mut n Node) handle_task(task Task) TaskResult {
	// 将任务放入队列
	n.task_queue <- task
	
	// 等待结果（简化实现）
	select {
		result := <-n.results {
			return result
		}
		10 * time.second {
			return TaskResult{
				task_id: task.id
				success: false
				error_msg: 'timeout'
			}
		}
	}
}

// 广播消息
pub fn (mut n Node) broadcast(msg Message) ! {
	n.mu.rlock()
	peers := n.peers.clone()
	n.mu.runlock()
	
	for _, peer in peers {
		go n.send_message_to(peer, msg)
	}
}

// 发送消息到节点
fn (mut n Node) send_message_to(peer PeerNode, msg Message) {
	msg_data := json.encode(msg)
	
	mut req := http.new_request(.post, 'http://${peer.address}:${peer.api_port}/messages', msg_data)
	req.header.add(.content_type, 'application/json')
	
	http.fetch(req) or { return }
}

// ClusterStatus 集群状态
pub struct ClusterStatus {
	pub:
		total_nodes   int
		online_nodes  int
		worker_nodes  int
		gateway_nodes int
		master_nodes  int
}

// 获取集群状态
pub fn (n &Node) get_cluster_status() ClusterStatus {
	n.mu.rlock()
	defer { n.mu.runlock() }
	
	mut workers := 0
	mut gateways := 0
	mut online := 0
	
	for _, peer in n.peers {
		match peer.role {
			.worker { workers++ }
			.gateway { gateways++ }
			else {}
		}
		
		if time.now() - peer.last_seen < 2 * time.minute {
			online++
		}
	}
	
	return ClusterStatus{
		total_nodes: n.peers.len + 1
		online_nodes: online + 1
		worker_nodes: workers
		gateway_nodes: gateways
		master_nodes: if n.role == .master { 1 } else { 0 }
	}
}
