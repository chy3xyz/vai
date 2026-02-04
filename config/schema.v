// vai.config.schema - 配置结构定义
// 定义 VAI 的配置结构，类似 nanobot 的 config/schema.py
module config

import os

// Config 主配置结构
pub struct Config {
pub mut:
	providers ProviderConfig
	agents    AgentConfig
	tools     ToolsConfig
	workspace WorkspaceConfig
	cron      CronConfig
}

// ProviderConfig LLM 提供商配置
pub struct ProviderConfig {
pub mut:
	openai     ?OpenAIConfig
	openrouter ?OpenRouterConfig
	ollama     ?OllamaConfig
	anthropic  ?AnthropicConfig
	groq       ?GroqConfig
	zhipu      ?ZhipuConfig
	gemini     ?GeminiConfig
}

// OpenAI 配置
pub struct OpenAIConfig {
pub:
	api_key string
}

// OpenRouter 配置
pub struct OpenRouterConfig {
pub:
	api_key string
}

// Ollama 配置
pub struct OllamaConfig {
pub:
	base_url string = 'http://localhost:11434'
}

// Anthropic 配置
pub struct AnthropicConfig {
pub:
	api_key string
}

// Groq 配置
pub struct GroqConfig {
pub:
	api_key string
}

// Zhipu 配置
pub struct ZhipuConfig {
pub:
	api_key string
}

// Gemini 配置
pub struct GeminiConfig {
pub:
	api_key string
}

// AgentConfig Agent 配置
pub struct AgentConfig {
pub mut:
	defaults DefaultAgentConfig
}

// DefaultAgentConfig 默认 Agent 配置
pub struct DefaultAgentConfig {
pub mut:
	model       string = 'gpt-4o-mini'
	temperature f64    = 0.7
	max_tokens  int    = 2000
	system_prompt string = 'You are a helpful AI assistant.'
}

// ToolsConfig 工具配置
pub struct ToolsConfig {
pub mut:
	web WebToolsConfig
}

// WebToolsConfig Web 工具配置
pub struct WebToolsConfig {
pub mut:
	search ?WebSearchConfig
}

// WebSearchConfig Web 搜索配置
pub struct WebSearchConfig {
pub:
	api_key string
	provider string = 'brave' // brave, serper, etc.
}

// WorkspaceConfig 工作区配置
pub struct WorkspaceConfig {
pub mut:
	path string = '~/.vai/workspace'
}

// CronConfig Cron 配置
pub struct CronConfig {
pub:
	enabled bool = true
}

// 默认配置
pub fn default_config() Config {
	return Config{
		providers: ProviderConfig{}
		agents: AgentConfig{
			defaults: DefaultAgentConfig{}
		}
		tools: ToolsConfig{
			web: WebToolsConfig{}
		}
		workspace: WorkspaceConfig{}
		cron: CronConfig{
			enabled: true
		}
	}
}

// 从环境变量加载配置
pub fn config_from_env() Config {
	mut cfg := default_config()

	// OpenAI
	if api_key := os.getenv_opt('OPENAI_API_KEY') {
		cfg.providers.openai = OpenAIConfig{ api_key: api_key }
	}

	// OpenRouter
	if api_key := os.getenv_opt('OPENROUTER_API_KEY') {
		cfg.providers.openrouter = OpenRouterConfig{ api_key: api_key }
		if model := os.getenv_opt('VAI_DEFAULT_MODEL') {
			cfg.agents.defaults.model = model
		}
	}

	// Ollama
	if base_url := os.getenv_opt('OLLAMA_BASE_URL') {
		cfg.providers.ollama = OllamaConfig{ base_url: base_url }
	} else {
		cfg.providers.ollama = OllamaConfig{}
	}

	// Anthropic
	if api_key := os.getenv_opt('ANTHROPIC_API_KEY') {
		cfg.providers.anthropic = AnthropicConfig{ api_key: api_key }
	}

	// Groq
	if api_key := os.getenv_opt('GROQ_API_KEY') {
		cfg.providers.groq = GroqConfig{ api_key: api_key }
	}

	// Zhipu
	if api_key := os.getenv_opt('ZHIPU_API_KEY') {
		cfg.providers.zhipu = ZhipuConfig{ api_key: api_key }
	}

	// Gemini
	if api_key := os.getenv_opt('GEMINI_API_KEY') {
		cfg.providers.gemini = GeminiConfig{ api_key: api_key }
	}

	// Web Search
	if api_key := os.getenv_opt('BRAVE_API_KEY') {
		cfg.tools.web.search = WebSearchConfig{
			api_key: api_key
			provider: 'brave'
		}
	}

	// Workspace
	if workspace_path := os.getenv_opt('VAI_WORKSPACE') {
		cfg.workspace.path = workspace_path
	}

	return cfg
}

// 合并配置（文件配置优先，环境变量作为补充）
pub fn merge_config(file_cfg Config, env_cfg Config) Config {
	mut merged := file_cfg

	// 如果文件配置中没有某个提供商，使用环境变量中的
	if merged.providers.openai == none && env_cfg.providers.openai != none {
		merged.providers.openai = env_cfg.providers.openai
	}
	if merged.providers.openrouter == none && env_cfg.providers.openrouter != none {
		merged.providers.openrouter = env_cfg.providers.openrouter
	}
	if merged.providers.ollama == none && env_cfg.providers.ollama != none {
		merged.providers.ollama = env_cfg.providers.ollama
	}
	if merged.providers.anthropic == none && env_cfg.providers.anthropic != none {
		merged.providers.anthropic = env_cfg.providers.anthropic
	}
	if merged.providers.groq == none && env_cfg.providers.groq != none {
		merged.providers.groq = env_cfg.providers.groq
	}
	if merged.providers.zhipu == none && env_cfg.providers.zhipu != none {
		merged.providers.zhipu = env_cfg.providers.zhipu
	}
	if merged.providers.gemini == none && env_cfg.providers.gemini != none {
		merged.providers.gemini = env_cfg.providers.gemini
	}

	// Web Search
	if merged.tools.web.search == none && env_cfg.tools.web.search != none {
		merged.tools.web.search = env_cfg.tools.web.search
	}

	// 如果文件配置使用默认值，使用环境变量的值
	if merged.agents.defaults.model == 'gpt-4o-mini' && env_cfg.agents.defaults.model != 'gpt-4o-mini' {
		merged.agents.defaults.model = env_cfg.agents.defaults.model
	}

	return merged
}
