// vai.utils - 通用工具函数
module utils

import time
import crypto.md5

// generate_id 生成唯一ID
pub fn generate_id(prefix string) string {
	timestamp := time.now().unix_micro()
	random := time.now().nanosecond
	return '${prefix}_${timestamp}_${random}'
}

// generate_short_id 生成短ID
pub fn generate_short_id() string {
	chars := 'abcdefghijklmnopqrstuvwxyz0123456789'
	mut result := ''
	seed := time.now().unix()
	for i := 0; i < 8; i++ {
		idx := (seed + i * 31) % chars.len
		result += chars[idx].ascii_str()
	}
	return result
}

// hash_string 计算字符串 MD5
pub fn hash_string(s string) string {
	return md5.hexhash(s)
}

// truncate_string 截断字符串
pub fn truncate_string(s string, max_len int) string {
	if s.len <= max_len {
		return s
	}
	return s[..max_len] + '...'
}

// format_duration 格式化持续时间
pub fn format_duration(d time.Duration) string {
	if d < time.second {
		return '${d.milliseconds()}ms'
	} else if d < time.minute {
		return '${d.seconds()}s'
	} else if d < time.hour {
		return '${d.minutes()}m'
	} else {
		return '${d.hours()}h'
	}
}

// clamp 限制数值范围
pub fn clamp[T](val T, min T, max T) T {
	if val < min {
		return min
	}
	if val > max {
		return max
	}
	return val
}

// Result 类型 (简化版 - 使用 V 内置的结果处理)
