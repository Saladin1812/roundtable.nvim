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
