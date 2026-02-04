// vai.web.app - Web 应用集成
// 集成所有 Web 功能
module web

import agent { AgentHub }

// WebApp Web 应用
pub struct WebApp {
	pub mut:
		server  &Server
		hub     &AgentHub
		config  WebConfig
}

// WebConfig Web 配置
pub struct WebConfig {
	pub mut:
		host          string = '0.0.0.0'
		port          int = 8080
		static_dir    string = 'static'
		api_key       string
		auth_enabled  bool = false
}

// 创建 Web 应用
pub fn new_web_app(hub &AgentHub, config WebConfig) &WebApp {
	mut server := new_server(config.host, config.port)
	server.static_dir = config.static_dir
	
	return &WebApp{
		server: server
		hub: hub
		config: config
	}
}

// 设置路由
pub fn (mut app WebApp) setup_routes() {
	// API 配置
	api_config := APIConfig{
		hub: app.hub
		auth_enabled: app.config.auth_enabled
		api_key: app.config.api_key
	}
	
	// 注册 API 路由
	register_api_routes(mut app.server.router, api_config)
	
	// 添加中间件
	app.server.use(cors_middleware(['*']))
	app.server.use(logging_middleware())
	
	if app.config.auth_enabled {
		app.server.use(auth_middleware(app.config.api_key))
	}
	
	// 额外页面路由
	app.server.router.get('/dashboard', fn (ctx Context) Response {
		return redirect_response('/')
	})
	
	app.server.router.get('/agents', fn (ctx Context) Response {
		return html_response('<!DOCTYPE html>
<html>
<head><title>Agents - VAI</title></head>
<body>
<h1>Agent Management</h1>
<div id="app">Loading...</div>
<script>
fetch("/api/agents")
  .then(r => r.json())
  .then(data => {
    document.getElementById("app").innerHTML = 
      "<pre>" + JSON.stringify(data, null, 2) + "</pre>";
  });
</script>
</body>
</html>')
	})
	
	app.server.router.get('/tasks', fn (ctx Context) Response {
		return html_response('<!DOCTYPE html>
<html>
<head><title>Tasks - VAI</title></head>
<body>
<h1>Task Queue</h1>
<p>View and manage tasks</p>
</body>
</html>')
	})
}

// 启动 Web 应用
pub fn (mut app WebApp) start() ! {
	app.setup_routes()
	app.server.start()!
}

// 停止 Web 应用
pub fn (mut app WebApp) stop() {
	app.server.stop()
}

// 创建默认 Web 应用
pub fn create_default_web_app(hub &AgentHub, port int) &WebApp {
	config := WebConfig{
		host: '0.0.0.0'
		port: port
		static_dir: 'static'
		auth_enabled: false
	}
	
	return new_web_app(hub, config)
}
