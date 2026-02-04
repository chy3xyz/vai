// vai.cron.types - 定时任务类型定义
module cron

import time

// CronJob 定时任务
pub struct CronJob {
pub:
	id          string
	schedule    string  // Cron 表达式，如 "0 0 * * *" (每天午夜)
	description string
	handler     fn () ! @[required]  // 任务处理函数
pub mut:
	enabled     bool
	last_run    ?time.Time
	next_run    ?time.Time
	run_count   int
	error_count int
}

// CronExpression Cron 表达式解析结果
pub struct CronExpression {
pub:
	minute     []int  // 0-59
	hour       []int  // 0-23
	day        []int  // 1-31
	month      []int  // 1-12
	day_of_week []int // 0-6 (0=Sunday)
}

// 创建 Cron 任务
pub fn new_cron_job(id string, schedule string, description string, handler fn () !) CronJob {
	return CronJob{
		id: id
		schedule: schedule
		description: description
		enabled: true
		handler: handler
		run_count: 0
		error_count: 0
	}
}

// 解析 Cron 表达式（简化实现）
pub fn parse_cron_expression(expr string) !CronExpression {
	parts := expr.split(' ')
	if parts.len != 5 {
		return error('invalid cron expression: expected 5 fields')
	}
	
	return CronExpression{
		minute: parse_field(parts[0], 0, 59)!
		hour: parse_field(parts[1], 0, 23)!
		day: parse_field(parts[2], 1, 31)!
		month: parse_field(parts[3], 1, 12)!
		day_of_week: parse_field(parts[4], 0, 6)!
	}
}

// 解析字段（支持 * 和数字）
fn parse_field(field string, min int, max int) ![]int {
	if field == '*' {
		mut result := []int{}
		for i := min; i <= max; i++ {
			result << i
		}
		return result
	}
	
	// 简单数字
	val := field.int()
	if val >= min && val <= max {
		return [val]
	}
	return error('value ${val} out of range [${min}, ${max}] or invalid field: ${field}')
}

// 检查 Cron 表达式是否匹配当前时间
pub fn (expr CronExpression) matches(now time.Time) bool {
	minute := now.minute
	hour := now.hour
	day := now.day
	month := now.month
	// V 语言中 weekday 需要计算：0=Sunday, 1=Monday, ..., 6=Saturday
	// 使用 weekday_str 然后转换
	weekday_str := now.weekday_str()
	weekday_map := {
		'Sunday': 0
		'Monday': 1
		'Tuesday': 2
		'Wednesday': 3
		'Thursday': 4
		'Friday': 5
		'Saturday': 6
	}
	weekday := weekday_map[weekday_str] or { 0 }
	
	return minute in expr.minute &&
		hour in expr.hour &&
		day in expr.day &&
		month in expr.month &&
		weekday in expr.day_of_week
}

// 计算下次运行时间
pub fn (expr CronExpression) next_run_time(now time.Time) time.Time {
	// 简化实现：返回下一分钟
	return now.add(1 * time.minute)
}
