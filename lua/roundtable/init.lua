local M = {}

local defaults = {
	binary = "roundtable",
	config_dir = nil,
	config_name = "roundtable.nvim.toml",
	codelldb_candidate_roots = {},
	terminal = "split",
	program = nil,
	args = {},
	watches = {},
	stop_on_entry = true,
	continue_once = false,
	include_breakpoints = true,
	use_dap_config = true,
	dap_configuration_name = nil,
	use_profile = true,
	profile_name = "nvim",
}

local config = vim.deepcopy(defaults)
local root_markers = { ".git", "CMakeLists.txt", "compile_commands.json" }

local function shell_quote(value)
	return vim.fn.shellescape(value)
end

local function path_exists(path)
	return type(path) == "string" and path ~= "" and vim.loop.fs_stat(path) ~= nil
end

local function command_available(command)
	if type(command) ~= "string" or command == "" then
		return false
	end
	if command:find("/", 1, true) or command:find("\\", 1, true) then
		return path_exists(command)
	end
	return vim.fn.executable(command) == 1
end

local function toml_string(value)
	value = tostring(value or "")
	value = value:gsub("\\", "\\\\")
	value = value:gsub('"', '\\"')
	return '"' .. value .. '"'
end

local function toml_array(values)
	local encoded = {}
	for _, value in ipairs(values or {}) do
		encoded[#encoded + 1] = toml_string(value)
	end
	return "[" .. table.concat(encoded, ", ") .. "]"
end

local function project_root()
	local cwd = vim.loop.cwd()
	local ok, root = pcall(vim.fs.root, 0, root_markers)
	if ok and root then
		return root
	end

	local current_file = vim.api.nvim_buf_get_name(0)
	local search_dir = current_file ~= "" and vim.fn.fnamemodify(current_file, ":p:h") or cwd
	while search_dir and search_dir ~= "" do
		for _, marker in ipairs(root_markers) do
			if vim.loop.fs_stat(search_dir .. "/" .. marker) then
				return search_dir
			end
		end

		local parent = vim.fn.fnamemodify(search_dir, ":h")
		if parent == search_dir then
			break
		end
		search_dir = parent
	end

	return cwd
end

local function normalize_path(path)
	if not path or path == "" then
		return nil
	end
	return vim.fn.fnamemodify(path, ":p")
end

local function evaluate_value(value)
	if type(value) == "function" then
		local ok, result = pcall(value)
		if ok then
			return result
		end
		vim.notify("Roundtable ignored failing nvim-dap function value: " .. tostring(result), vim.log.levels.WARN)
		return nil
	end

	return value
end

local function normalize_args(args)
	args = evaluate_value(args)
	if type(args) == "table" then
		return args
	end
	if type(args) == "string" and args ~= "" then
		return { args }
	end
	return {}
end

local function dap_variables()
	local current_file = normalize_path(vim.api.nvim_buf_get_name(0)) or ""
	return {
		workspaceFolder = config.working_directory or project_root(),
		file = current_file,
		fileDirname = current_file ~= "" and vim.fn.fnamemodify(current_file, ":h") or "",
		fileBasename = current_file ~= "" and vim.fn.fnamemodify(current_file, ":t") or "",
		fileBasenameNoExtension = current_file ~= "" and vim.fn.fnamemodify(current_file, ":t:r") or "",
		fileExtname = current_file ~= "" and vim.fn.fnamemodify(current_file, ":e") or "",
	}
end

local function expand_dap_string(value)
	if type(value) ~= "string" then
		return value
	end

	local variables = dap_variables()
	return (value:gsub("%${([%w_]+)}", function(name)
		return variables[name] or ("${" .. name .. "}")
	end))
end

local function expand_dap_value(value)
	if type(value) == "table" then
		local expanded = {}
		for index, item in ipairs(value) do
			expanded[index] = expand_dap_value(item)
		end
		return expanded
	end

	return expand_dap_string(value)
end

local function current_dap_configuration()
	if not config.use_dap_config then
		return nil
	end

	local ok, dap = pcall(require, "dap")
	if not ok or type(dap.configurations) ~= "table" then
		return nil
	end

	local filetype = vim.bo.filetype
	local configurations = dap.configurations[filetype]
	if type(configurations) ~= "table" then
		return nil
	end

	for _, candidate in ipairs(configurations) do
		if type(candidate) == "table" and candidate.request == "launch" and candidate.program ~= nil then
			if config.dap_configuration_name == nil or candidate.name == config.dap_configuration_name then
				return candidate
			end
		end
	end

	return nil
end

local function dap_status()
	if not config.use_dap_config then
		return {
			ok = true,
			message = "nvim-dap config lookup disabled",
		}
	end

	local ok, dap = pcall(require, "dap")
	if not ok or type(dap.configurations) ~= "table" then
		return {
			ok = false,
			message = "nvim-dap is not available; install mfussenegger/nvim-dap or pass a program explicitly",
		}
	end

	local filetype = vim.bo.filetype
	local configurations = dap.configurations[filetype]
	if type(configurations) ~= "table" or #configurations == 0 then
		return {
			ok = false,
			message = "no nvim-dap launch configuration for filetype '" .. filetype .. "'",
		}
	end

	if current_dap_configuration() then
		return {
			ok = true,
			message = "nvim-dap launch configuration found",
		}
	end

	return {
		ok = false,
		message = "no matching nvim-dap launch configuration with request='launch' and program",
	}
end

local function codelldb_roots()
	local roots = vim.deepcopy(config.codelldb_candidate_roots or {})
	local data = vim.fn.stdpath("data")
	local home = vim.loop.os_homedir() or ""

	roots[#roots + 1] = data .. "/mason/packages/codelldb"
	roots[#roots + 1] = data .. "/mason/packages/codelldb/extension"
	roots[#roots + 1] = home .. "/.local/share/nvim/mason/packages/codelldb"
	roots[#roots + 1] = home .. "/.vscode/extensions"
	roots[#roots + 1] = home .. "/.vscode-insiders/extensions"

	return roots
end

local function codelldb_status()
	if command_available("codelldb") then
		return {
			ok = true,
			message = "codelldb found on PATH",
		}
	end

	for _, root in ipairs(codelldb_roots()) do
		if path_exists(root) then
			return {
				ok = true,
				message = "CodeLLDB candidate root found: " .. root,
			}
		end
	end

	return {
		ok = false,
		message = "CodeLLDB was not found on PATH, Mason, or common VS Code extension roots",
	}
end

local function build_launch_context(program)
	local dap_configuration = nil
	if not program or program == "" then
		dap_configuration = current_dap_configuration()
		if dap_configuration then
			program = expand_dap_value(evaluate_value(dap_configuration.program))
		end
	end

	local cwd = expand_dap_value(config.working_directory or project_root())
	local args = expand_dap_value(config.args)
	local stop_on_entry = config.stop_on_entry

	if dap_configuration then
		cwd = expand_dap_value(evaluate_value(dap_configuration.cwd)) or cwd
		args = expand_dap_value(normalize_args(dap_configuration.args))
		if type(dap_configuration.stopOnEntry) == "boolean" then
			stop_on_entry = dap_configuration.stopOnEntry
		end
	end

	return {
		program = program,
		working_directory = cwd,
		args = normalize_args(args),
		stop_on_entry = stop_on_entry,
	}
end

local function collect_breakpoints()
	if not config.include_breakpoints then
		return {}
	end

	local ok, dap_breakpoints = pcall(require, "dap.breakpoints")
	if not ok or type(dap_breakpoints.get) ~= "function" then
		return {}
	end

	local entries = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local source_path = normalize_path(vim.api.nvim_buf_get_name(bufnr))
		if source_path then
			local buffer_breakpoints = dap_breakpoints.get(bufnr)
			if type(buffer_breakpoints) == "table" then
				for _, breakpoint in ipairs(buffer_breakpoints) do
					if
						type(breakpoint) == "table"
						and breakpoint.enabled ~= false
						and type(breakpoint.line) == "number"
						and breakpoint.line > 0
					then
						entries[#entries + 1] = source_path .. ":" .. tostring(breakpoint.line)
					end
				end
			end
		end
	end

	return entries
end

local function write_config(launch_context)
	local temp_dir = config.config_dir or (vim.fn.stdpath("cache") .. "/roundtable")
	vim.fn.mkdir(temp_dir, "p")

	local config_path = temp_dir .. "/" .. config.config_name
	local breakpoints = collect_breakpoints()

	local lines
	if config.use_profile then
		lines = {
			"[session]",
			"profile = " .. toml_string(config.profile_name),
			'startup_focus = "memory"',
			"",
			"[profiles." .. config.profile_name .. "]",
			"program = " .. toml_string(launch_context.program),
			"arguments = " .. toml_array(launch_context.args),
			"working_directory = " .. toml_string(launch_context.working_directory),
			"stop_on_entry = " .. tostring(launch_context.stop_on_entry),
			"continue_once = " .. tostring(config.continue_once),
			"watches = " .. toml_array(config.watches),
			"breakpoints = " .. toml_array(breakpoints),
			"",
			"[codelldb.auto_detect]",
			"enabled = true",
			"candidate_roots = " .. toml_array(config.codelldb_candidate_roots),
			"",
		}
	else
		lines = {
			"[session]",
			'mode = "dap_launch"',
			'startup_focus = "memory"',
			"",
			"[dap_launch]",
			"program = " .. toml_string(launch_context.program),
			"arguments = " .. toml_array(launch_context.args),
			"working_directory = " .. toml_string(launch_context.working_directory),
			"stop_on_entry = " .. tostring(launch_context.stop_on_entry),
			"continue_once = " .. tostring(config.continue_once),
			"",
			"[watches]",
			"entries = " .. toml_array(config.watches),
			"",
			"[breakpoints]",
			"entries = " .. toml_array(breakpoints),
			"",
			"[codelldb.auto_detect]",
			"enabled = true",
			"candidate_roots = " .. toml_array(config.codelldb_candidate_roots),
			"",
		}
	end

	vim.fn.writefile(lines, config_path)
	return config_path
end

local function open_terminal(command)
	if config.terminal == "tab" then
		vim.cmd.tabnew()
	elseif config.terminal == "vsplit" then
		vim.cmd.vsplit()
	elseif config.terminal == "current" then
	-- Reuse current window.
	else
		vim.cmd.split()
	end

	vim.cmd.terminal(command)
	vim.cmd.startinsert()
end

local function resolve_launch_context(program)
	program = program or config.program
	if type(program) == "function" then
		program = program()
	end

	local launch_context = build_launch_context(program)
	program = launch_context.program

	if not program or program == "" then
		program = vim.fn.input("Roundtable program: ", "", "file")
		launch_context.program = program
	end

	if not program or program == "" then
		vim.notify("Roundtable cancelled: no program provided", vim.log.levels.WARN)
		return nil
	end

	launch_context.program = normalize_path(program)
	if not launch_context.program then
		vim.notify("Roundtable cancelled: invalid program path", vim.log.levels.WARN)
		return nil
	end

	return launch_context
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.check()
	local binary_found = command_available(config.binary)
	local dap = dap_status()
	local code_lldb = codelldb_status()

	local checks = {
		{
			name = "roundtable binary",
			ok = binary_found,
			message = binary_found and ("found: " .. config.binary)
				or ("not found: " .. config.binary .. "; set setup({ binary = '/path/to/roundtable' })"),
		},
		{
			name = "nvim-dap",
			ok = dap.ok,
			message = dap.message,
		},
		{
			name = "CodeLLDB",
			ok = code_lldb.ok,
			message = code_lldb.message,
		},
	}

	for _, check in ipairs(checks) do
		local level = check.ok and vim.log.levels.INFO or vim.log.levels.WARN
		vim.notify("Roundtable check: " .. check.name .. ": " .. check.message, level)
	end

	return checks
end

function M.generate_config(program)
	local launch_context = resolve_launch_context(program)
	if not launch_context then
		return nil
	end

	return write_config(launch_context)
end

function M.launch(program)
	if not command_available(config.binary) then
		vim.notify(
			"Roundtable binary not found: " .. config.binary .. ". Set setup({ binary = '/path/to/roundtable' }).",
			vim.log.levels.ERROR
		)
		return
	end

	local code_lldb = codelldb_status()
	if not code_lldb.ok then
		vim.notify(
			"CodeLLDB was not detected. Roundtable may fail to start; install CodeLLDB with Mason/VS Code or set codelldb_candidate_roots.",
			vim.log.levels.WARN
		)
	end

	local generated_config = M.generate_config(program)
	if not generated_config then
		return
	end

	local command = shell_quote(config.binary) .. " --config " .. shell_quote(generated_config)
	open_terminal(command)
end

return M
