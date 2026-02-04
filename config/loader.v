// vai.config.loader - 配置文件加载器
// 从 ~/.vai/config.json 加载配置
module config

import json
import os

// 配置文件路径
pub const config_dir = '~/.vai'
pub const config_file = '~/.vai/config.json'

// 加载配置（从文件和环境变量）
pub fn load_config() !Config {
	// 先加载环境变量配置
	env_cfg := config_from_env()

	// 尝试加载文件配置
	config_path := os.expand_tilde_to_home(config_file)
	if !os.exists(config_path) {
		// 文件不存在，只返回环境变量配置
		return env_cfg
	}

	// 读取配置文件
	content := os.read_file(config_path) or {
		return error('failed to read config file: ${err}')
	}

	// 解析 JSON
	file_cfg := json.decode(Config, content) or {
		return error('failed to parse config file: ${err}')
	}

	// 合并配置（文件配置优先）
	return merge_config(file_cfg, env_cfg)
}

// 保存配置到文件
pub fn save_config(cfg Config) ! {
	config_path := os.expand_tilde_to_home(config_file)
	config_dir_path := os.expand_tilde_to_home(config_dir)

	// 确保目录存在
	if !os.is_dir(config_dir_path) {
		os.mkdir_all(config_dir_path) or {
			return error('failed to create config directory: ${err}')
		}
	}

	// 序列化为 JSON
	json_str := json.encode_pretty(cfg)

	// 写入文件
	os.write_file(config_path, json_str) or {
		return error('failed to write config file: ${err}')
	}
}

// 初始化配置文件（创建默认配置）
pub fn init_config() !Config {
	config_path := os.expand_tilde_to_home(config_file)
	_ := os.expand_tilde_to_home(config_dir)

	// 如果配置文件已存在，加载它
	if os.exists(config_path) {
		return load_config()
	}

	// 创建默认配置
	cfg := default_config()

	// 尝试从环境变量填充
	env_cfg := config_from_env()
	cfg_merged := merge_config(cfg, env_cfg)

	// 保存配置文件
	save_config(cfg_merged) or {
		return error('failed to save initial config: ${err}')
	}

	return cfg_merged
}

// 获取配置目录路径
pub fn get_config_dir() string {
	return os.expand_tilde_to_home(config_dir)
}

// 获取配置文件路径
pub fn get_config_file() string {
	return os.expand_tilde_to_home(config_file)
}
