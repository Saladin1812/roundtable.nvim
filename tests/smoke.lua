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

local function install_fake_dap()
	package.loaded["dap"] = nil
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
end

local function test_profile_generation()
	local project = prepare_project("profile")
	install_fake_dap()

	local roundtable = require("roundtable")
	roundtable.setup({
		use_profile = true,
		profile_name = "nvim",
		working_directory = project,
		watches = { "argc" },
	})

	local config_path = roundtable.generate_config()
	assert(config_path, "expected profile config path")
	local toml = read_file(config_path)

	assert_contains(toml, 'profile = "nvim"')
	assert_contains(toml, "[profiles.nvim]")
	assert_contains(toml, 'program = "' .. project .. '/build/app"')
	assert_contains(toml, 'arguments = ["--flag", "value"]')
	assert_contains(toml, 'working_directory = "' .. project .. '"')
	assert_contains(toml, "stop_on_entry = false")
	assert_contains(toml, 'watches = ["argc"]')
end

local function test_direct_generation()
	local project = prepare_project("direct")
	install_fake_dap()

	local roundtable = require("roundtable")
	roundtable.setup({
		use_profile = false,
		working_directory = project,
		watches = { "argc" },
	})

	local config_path = roundtable.generate_config()
	assert(config_path, "expected direct config path")
	local toml = read_file(config_path)

	assert_contains(toml, 'mode = "dap_launch"')
	assert_contains(toml, "[dap_launch]")
	assert_contains(toml, 'program = "' .. project .. '/build/app"')
	assert_contains(toml, 'entries = ["argc"]')
end

test_profile_generation()
test_direct_generation()

vim.print("roundtable.nvim smoke tests passed")
