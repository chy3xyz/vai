// vai.cron.service - Cron 服务实现
module cron

import time
import sync

// CronService Cron 服务
@[heap]
pub struct CronService {
pub mut:
	jobs    map[string]CronJob
	running bool
	mu      sync.RwMutex
}

// 创建 Cron 服务
pub fn new_cron_service() &CronService {
	return &CronService{
		jobs: map[string]CronJob{}
		running: false
	}
}

// 启动 Cron 服务
pub fn (mut cs CronService) start() {
	cs.running = true
	spawn cs.run_loop()
}

// 停止 Cron 服务
pub fn (mut cs CronService) stop() {
	cs.running = false
}

// 主循环
fn (mut cs CronService) run_loop() {
	for cs.running {
		now := time.now()
		cs.check_and_run_jobs(now)
		time.sleep(60 * time.second) // 每分钟检查一次
	}
}

// 检查并运行任务
fn (mut cs CronService) check_and_run_jobs(now time.Time) {
	cs.mu.rlock()
	defer { cs.mu.runlock() }
	
	for _, mut job in cs.jobs {
		if !job.enabled {
			continue
		}
		
		// 解析 Cron 表达式
		expr := parse_cron_expression(job.schedule) or { continue }
		
		// 检查是否应该运行
		if expr.matches(now) {
			// 检查是否已经运行过（避免重复运行）
			if last_run := job.last_run {
				if now - last_run < 60 * time.second {
					continue
				}
			}
			
			// 运行任务
			spawn cs.execute_job(mut job)
		}
	}
}

// 执行任务
fn (mut cs CronService) execute_job(mut job CronJob) {
	cs.mu.lock()
	job.last_run = time.now()
	job.run_count++
	cs.mu.unlock()
	
	// 执行处理函数
	job.handler() or {
		cs.mu.lock()
		job.error_count++
		cs.mu.unlock()
		eprintln('Cron job ${job.id} failed: ${err}')
	}
}

// 添加任务
pub fn (mut cs CronService) add_job(job CronJob) ! {
	cs.mu.lock()
	defer { cs.mu.unlock() }
	
	if job.id in cs.jobs {
		return error('job already exists: ${job.id}')
	}
	
	// 解析并计算下次运行时间
	expr := parse_cron_expression(job.schedule) or {
		return error('invalid cron expression: ${err}')
	}
	
	mut job_with_next := job
	job_with_next.next_run = expr.next_run_time(time.now())
	cs.jobs[job.id] = job_with_next
}

// 删除任务
pub fn (mut cs CronService) remove_job(id string) {
	cs.mu.lock()
	defer { cs.mu.unlock() }
	cs.jobs.delete(id)
}

// 启用任务
pub fn (mut cs CronService) enable_job(id string) ! {
	cs.mu.lock()
	defer { cs.mu.unlock() }
	
	if mut job := cs.jobs[id] {
		job.enabled = true
	} else {
		return error('job not found: ${id}')
	}
}

// 禁用任务
pub fn (mut cs CronService) disable_job(id string) ! {
	cs.mu.lock()
	defer { cs.mu.unlock() }
	
	if mut job := cs.jobs[id] {
		job.enabled = false
	} else {
		return error('job not found: ${id}')
	}
}

// 列出所有任务
pub fn (mut cs CronService) list_jobs() []CronJob {
	cs.mu.rlock()
	defer { cs.mu.runlock() }
	
	mut jobs := []CronJob{}
	for _, job in cs.jobs {
		jobs << job
	}
	return jobs
}

// 获取任务
pub fn (mut cs CronService) get_job(id string) ?CronJob {
	cs.mu.rlock()
	defer { cs.mu.runlock() }
	return cs.jobs[id] or { return none }
}
