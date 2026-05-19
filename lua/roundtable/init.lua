local M = {}

local defaults = {
	binary = "roundtable",
	config_name = "roundtable.nvim.toml",
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
					if type(breakpoint) == "table" and type(breakpoint.line) == "number" and breakpoint.line > 0 then
						entries[#entries + 1] = source_path .. ":" .. tostring(breakpoint.line)
					end
				end
			end
		end
	end

	return entries
end

local function write_config(launch_context)
	local temp_dir = vim.fn.stdpath("cache") .. "/roundtable"
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
			"candidate_roots = []",
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
			"candidate_roots = []",
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

function M.generate_config(program)
	local launch_context = resolve_launch_context(program)
	if not launch_context then
		return nil
	end

	return write_config(launch_context)
end

function M.launch(program)
	local generated_config = M.generate_config(program)
	if not generated_config then
		return
	end

	local command = shell_quote(config.binary) .. " --config " .. shell_quote(generated_config)
	open_terminal(command)
end

return M
