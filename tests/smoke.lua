local root = vim.fn.getcwd()
vim.env.XDG_CACHE_HOME = vim.fn.tempname() .. "-cache"
vim.opt.runtimepath:append(root)
vim.cmd("runtime plugin/roundtable.lua")

local function assert_contains(text, needle)
	if not text:find(needle, 1, true) then
		error("expected generated TOML to contain: " .. needle .. "\n\nGenerated TOML:\n" .. text)
	end
end

local function read_file(path)
	return table.concat(vim.fn.readfile(path), "\n")
end

local function prepare_project(name)
	local project = vim.fn.tempname() .. "-" .. name
	local source_dir = project .. "/src"
	vim.fn.mkdir(source_dir, "p")
	vim.fn.writefile({ "cmake_minimum_required(VERSION 3.20)" }, project .. "/CMakeLists.txt")
	local source_path = source_dir .. "/main.cpp"
	vim.fn.writefile({ "int main() { return 0; }" }, source_path)
	vim.cmd("edit " .. vim.fn.fnameescape(source_path))
	vim.bo.filetype = "cpp"
	vim.cmd("cd " .. vim.fn.fnameescape(project))
	return project
end

local function current_buffer_breakpoints()
	return {
		{ line = 7 },
		{ line = 9, enabled = false },
		{ line = 11, enabled = true },
	}
end

local function install_fake_dap()
	package.loaded["dap"] = nil
	package.loaded["dap.breakpoints"] = nil
	package.preload["dap"] = function()
		return {
			configurations = {
				cpp = {
					{
						name = "Launch app",
						request = "launch",
						program = "${workspaceFolder}/build/app",
						args = { "--flag", "value" },
						cwd = "${workspaceFolder}",
						stopOnEntry = false,
					},
				},
			},
		}
	end
	package.preload["dap.breakpoints"] = function()
		return {
			get = function(bufnr)
				if bufnr == vim.api.nvim_get_current_buf() then
					return current_buffer_breakpoints()
				end
				return {}
			end,
		}
	end
end

local function test_profile_generation()
	local project = prepare_project("profile")
	install_fake_dap()

	local roundtable = require("roundtable")
	local config_dir = project .. "/.roundtable"
	roundtable.setup({
		config_dir = config_dir,
		config_name = "profile.toml",
		use_profile = true,
		profile_name = "nvim",
		working_directory = project,
		watches = { "argc" },
	})

	local config_path = roundtable.generate_config()
	assert(config_path, "expected profile config path")
	assert(config_path == config_dir .. "/profile.toml", "unexpected profile config path: " .. config_path)
	local toml = read_file(config_path)

	assert_contains(toml, 'profile = "nvim"')
	assert_contains(toml, "[profiles.nvim]")
	assert_contains(toml, 'program = "' .. project .. '/build/app"')
	assert_contains(toml, 'arguments = ["--flag", "value"]')
	assert_contains(toml, 'working_directory = "' .. project .. '"')
	assert_contains(toml, "stop_on_entry = false")
	assert_contains(toml, 'watches = ["argc"]')
	assert_contains(toml, 'breakpoints = ["' .. project .. '/src/main.cpp:7", "' .. project .. '/src/main.cpp:11"]')
end

local function test_direct_generation()
	local project = prepare_project("direct")
	install_fake_dap()

	local roundtable = require("roundtable")
	local config_dir = project .. "/.roundtable"
	roundtable.setup({
		config_dir = config_dir,
		config_name = "direct.toml",
		use_profile = false,
		working_directory = project,
		watches = { "argc" },
	})

	local config_path = roundtable.generate_config()
	assert(config_path, "expected direct config path")
	assert(config_path == config_dir .. "/direct.toml", "unexpected direct config path: " .. config_path)
	local toml = read_file(config_path)

	assert_contains(toml, 'mode = "dap_launch"')
	assert_contains(toml, "[dap_launch]")
	assert_contains(toml, 'program = "' .. project .. '/build/app"')
	assert_contains(toml, 'entries = ["argc"]')
	assert_contains(toml, 'entries = ["' .. project .. '/src/main.cpp:7", "' .. project .. '/src/main.cpp:11"]')
end

test_profile_generation()
test_direct_generation()

vim.print("roundtable.nvim smoke tests passed")
