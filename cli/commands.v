// vai.cli - 本地控制台/调试工具
// 提供命令行界面和调试功能
module cli

import os
import term
import readline
import json
import time

// CLI 命令行接口
pub struct CLI {
	pub mut:
		name           string
		version        string
		commands       map[string]Command
		prompt         string = 'vai> '
		history_file   string
		running        bool
}

// Command 命令接口
pub interface Command {
	name() string
	description() string
	aliases() []string
	execute(args []string, ctx Context) !
}

// Context 命令上下文
pub struct Context {
	pub mut:
		app_data map[string]any
}

// BaseCommand 基础命令实现
pub struct BaseCommand {
	pub:
		cmd_name        string
		cmd_description string
		cmd_aliases     []string
}

pub fn (c BaseCommand) name() string {
	return c.cmd_name
}

pub fn (c BaseCommand) description() string {
	return c.cmd_description
}

pub fn (c BaseCommand) aliases() []string {
	return c.cmd_aliases
}

// 创建 CLI
pub fn new_cli(name string, version string) CLI {
	return CLI{
		name: name
		version: version
		commands: map[string]Command{}
		history_file: os.join_path(os.home_dir(), '.${name}_history')
	}
}

// 注册命令
pub fn (mut c CLI) register(cmd Command) {
	c.commands[cmd.name()] = cmd
	for alias in cmd.aliases() {
		c.commands[alias] = cmd
	}
}

// 运行 CLI
pub fn (mut c CLI) run() {
	c.running = true

	c.print_banner()

	for c.running {
		input := readline.read_line(c.prompt) or { break }
		line := input.trim_space()

		if line.len == 0 {
			continue
		}

		c.execute(line) or {
			println(term.red('Error: ${err}'))
		}
	}
}

// 执行命令
pub fn (mut c CLI) execute(line string) ! {
	parts := line.split(' ')
	if parts.len == 0 {
		return
	}

	cmd_name := parts[0]
	args := if parts.len > 1 { parts[1..] } else { []string{} }

	if cmd := c.commands[cmd_name] {
		mut ctx := Context{
			app_data: map[string]any{}
		}
		cmd.execute(args, ctx)!
	} else {
		return error('unknown command: ${cmd_name}. Type "help" for available commands.')
	}
}

// 停止 CLI
pub fn (mut c CLI) stop() {
	c.running = false
}

// 打印 Banner
fn (c &CLI) print_banner() {
	println('')
	println(term.cyan('╔════════════════════════════════════════╗'))
	println(term.cyan('║') + '  ${term.bold(c.name)} v${c.version}${' '.repeat(35 - c.name.len - c.version.len)}' + term.cyan('║'))
	println(term.cyan('║') + '  V AI Infrastructure Console${' '.repeat(22)}' + term.cyan('║'))
	println(term.cyan('╚════════════════════════════════════════╝'))
	println('')
	println('Type "help" for available commands, "quit" to exit.')
	println('')
}

// HelpCommand 帮助命令
pub struct HelpCommand {
	BaseCommand
	pub mut:
		cli &CLI
}

pub fn new_help_command(cli &CLI) HelpCommand {
	return HelpCommand{
		BaseCommand: BaseCommand{
			cmd_name: 'help'
			cmd_description: 'Show help information'
			cmd_aliases: ['h', '?']
		}
		cli: cli
	}
}

pub fn (c HelpCommand) execute(args []string, ctx Context) ! {
	if args.len > 0 {
		// 显示特定命令的帮助
		cmd_name := args[0]
		if cmd := c.cli.commands[cmd_name] {
			println('')
			println(term.bold('Command: ') + cmd.name())
			println(term.bold('Description: ') + cmd.description())
			aliases := cmd.aliases()
			if aliases.len > 0 {
				println(term.bold('Aliases: ') + aliases.join(', '))
			}
			println('')
		} else {
			return error('unknown command: ${cmd_name}')
		}
	} else {
		// 显示所有命令
		println('')
		println(term.bold('Available commands:'))
		println('')

		mut unique_commands := map[string]Command{}
		for _, cmd in c.cli.commands {
			unique_commands[cmd.name()] = cmd
		}

		for _, cmd in unique_commands {
			name := term.green(cmd.name())
			padding := ' '.repeat(15 - cmd.name().len)
			println('  ${name}${padding}${cmd.description()}')
		}

		println('')
	}
}

// QuitCommand 退出命令
pub struct QuitCommand {
	BaseCommand
	pub mut:
		cli &CLI
}

pub fn new_quit_command(cli &CLI) QuitCommand {
	return QuitCommand{
		BaseCommand: BaseCommand{
			cmd_name: 'quit'
			cmd_description: 'Exit the CLI'
			cmd_aliases: ['exit', 'q']
		}
		cli: cli
	}
}

pub fn (c QuitCommand) execute(args []string, ctx Context) ! {
	println('Goodbye!')
	c.cli.stop()
}

// VersionCommand 版本命令
pub struct VersionCommand {
	BaseCommand
	pub mut:
		cli &CLI
}

pub fn new_version_command(cli &CLI) VersionCommand {
	return VersionCommand{
		BaseCommand: BaseCommand{
			cmd_name: 'version'
			cmd_description: 'Show version information'
			cmd_aliases: ['v']
		}
		cli: cli
	}
}

pub fn (c VersionCommand) execute(args []string, ctx Context) ! {
	println('${c.cli.name} v${c.cli.version}')
}

// StatusCommand 状态命令
pub struct StatusCommand {
	BaseCommand
	pub mut:
		get_status fn () StatusInfo
}

pub struct StatusInfo {
	pub:
		uptime         time.Duration
		active_agents  int
		messages_processed int
		memory_usage   string
}

pub fn new_status_command(get_status fn () StatusInfo) StatusCommand {
	return StatusCommand{
		BaseCommand: BaseCommand{
			cmd_name: 'status'
			cmd_description: 'Show system status'
			cmd_aliases: ['st']
		}
		get_status: get_status
	}
}

pub fn (c StatusCommand) execute(args []string, ctx Context) ! {
	status := c.get_status()

	println('')
	println(term.bold('System Status'))
	println('  Uptime:         ${status.uptime}')
	println('  Active Agents:  ${status.active_agents}')
	println('  Messages:       ${status.messages_processed}')
	println('  Memory Usage:   ${status.memory_usage}')
	println('')
}

// LogCommand 日志命令
pub struct LogCommand {
	BaseCommand
	pub mut:
		log_file string
}

pub fn new_log_command(log_file string) LogCommand {
	return LogCommand{
		BaseCommand: BaseCommand{
			cmd_name: 'logs'
			cmd_description: 'Show recent logs'
			cmd_aliases: ['log']
		}
		log_file: log_file
	}
}

pub fn (c LogCommand) execute(args []string, ctx Context) ! {
	lines := args.int()
	if lines <= 0 {
		lines = 20
	}

	if !os.exists(c.log_file) {
		println('No log file found.')
		return
	}

	content := os.read_file(c.log_file) or {
		return error('failed to read log file: ${err}')
	}

	log_lines := content.split('\n')
	start := if log_lines.len > lines { log_lines.len - lines } else { 0 }

	println('')
	println(term.bold('Recent logs:'))
	println('')

	for line in log_lines[start..] {
		if line.contains('[ERROR]') {
			println(term.red(line))
		} else if line.contains('[WARN]') {
			println(term.yellow(line))
		} else if line.contains('[INFO]') {
			println(term.green(line))
		} else {
			println(line)
		}
	}

	println('')
}

// ConfigCommand 配置命令
pub struct ConfigCommand {
	BaseCommand
	pub mut:
		config_file string
}

pub fn new_config_command(config_file string) ConfigCommand {
	return ConfigCommand{
		BaseCommand: BaseCommand{
			cmd_name: 'config'
			cmd_description: 'Show or edit configuration'
			cmd_aliases: ['cfg']
		}
		config_file: config_file
	}
}

pub fn (c ConfigCommand) execute(args []string, ctx Context) ! {
	if args.len == 0 {
		// 显示配置
		if os.exists(c.config_file) {
			content := os.read_file(c.config_file)!
			println('')
			println(term.bold('Configuration:'))
			println(content)
			println('')
		} else {
			println('No configuration file found.')
		}
	} else if args[0] == 'edit' {
		// 打开编辑器编辑配置
		editor := os.getenv('EDITOR')
		if editor.len == 0 {
			editor = 'vi'
		}
		os.system('${editor} ${c.config_file}')
	}
}

// DebugCommand 调试命令
pub struct DebugCommand {
	BaseCommand
	pub mut:
		get_debug_info fn () map[string]any
}

pub fn new_debug_command(get_debug_info fn () map[string]any) DebugCommand {
	return DebugCommand{
		BaseCommand: BaseCommand{
			cmd_name: 'debug'
			cmd_description: 'Show debug information'
			cmd_aliases: ['dbg']
		}
		get_debug_info: get_debug_info
	}
}

pub fn (c DebugCommand) execute(args []string, ctx Context) ! {
	info := c.get_debug_info()

	println('')
	println(term.bold('Debug Information:'))
	println('')

	json_data := json.encode_pretty(info)
	println(json_data)
	println('')
}

// ClearCommand 清屏命令
pub struct ClearCommand {
	BaseCommand
}

pub fn new_clear_command() ClearCommand {
	return ClearCommand{
		BaseCommand: BaseCommand{
			cmd_name: 'clear'
			cmd_description: 'Clear the screen'
			cmd_aliases: ['cls']
		}
	}
}

pub fn (c ClearCommand) execute(args []string, ctx Context) ! {
	print('\x1b[2J\x1b[H')
}

// EchoCommand 回显命令（用于测试）
pub struct EchoCommand {
	BaseCommand
}

pub fn new_echo_command() EchoCommand {
	return EchoCommand{
		BaseCommand: BaseCommand{
			cmd_name: 'echo'
			cmd_description: 'Echo the input'
			cmd_aliases: []
		}
	}
}

pub fn (c EchoCommand) execute(args []string, ctx Context) ! {
	println(args.join(' '))
}

// 注册默认命令
pub fn register_default_commands(mut cli CLI, get_status fn () StatusInfo, get_debug_info fn () map[string]any) {
	cli.register(new_help_command(&cli))
	cli.register(new_quit_command(&cli))
	cli.register(new_version_command(&cli))
	cli.register(new_status_command(get_status))
	cli.register(new_debug_command(get_debug_info))
	cli.register(new_clear_command())
	cli.register(new_echo_command())
}
