if vim.g.loaded_roundtable_nvim == 1 then
	return
end

vim.g.loaded_roundtable_nvim = 1

vim.api.nvim_create_user_command("RoundtableLaunch", function(opts)
	require("roundtable").launch(opts.args ~= "" and opts.args or nil)
end, {
	nargs = "?",
	complete = "file",
	desc = "Launch Roundtable with a generated TOML config",
})

vim.api.nvim_create_user_command("RoundtableGenerateConfig", function(opts)
	local path = require("roundtable").generate_config(opts.args ~= "" and opts.args or nil)
	if path then
		vim.notify("Roundtable config generated: " .. path, vim.log.levels.INFO)
	end
end, {
	nargs = "?",
	complete = "file",
	desc = "Generate Roundtable TOML config without launching",
})

vim.api.nvim_create_user_command("RoundtableCheck", function()
	require("roundtable").check()
end, {
	desc = "Check Roundtable, nvim-dap, and CodeLLDB setup",
})

vim.api.nvim_create_user_command("RoundtableOpenConfig", function(opts)
	require("roundtable").open_config(opts.args ~= "" and opts.args or nil)
end, {
	nargs = "?",
	complete = "file",
	desc = "Open the last generated Roundtable TOML config",
})

vim.api.nvim_create_user_command("RoundtableInfo", function()
	require("roundtable").info()
end, {
	desc = "Show resolved Roundtable plugin state",
})
