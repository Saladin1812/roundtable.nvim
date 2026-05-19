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
}

local config = vim.deepcopy(defaults)

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
  local ok, root = pcall(vim.fs.root, 0, { ".git", "CMakeLists.txt", "compile_commands.json" })
  if ok and root then
    return root
  end
  return cwd
end

local function normalize_path(path)
  if not path or path == "" then
    return nil
  end
  return vim.fn.fnamemodify(path, ":p")
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

local function write_config(program)
  local root = project_root()
  local temp_dir = vim.fn.stdpath("cache") .. "/roundtable"
  vim.fn.mkdir(temp_dir, "p")

  local config_path = temp_dir .. "/" .. config.config_name
  local breakpoints = collect_breakpoints()

  local lines = {
    "[session]",
    'mode = "dap_launch"',
    'startup_focus = "memory"',
    "",
    "[dap_launch]",
    'program = ' .. toml_string(program),
    "arguments = " .. toml_array(config.args),
    "working_directory = " .. toml_string(root),
    "stop_on_entry = " .. tostring(config.stop_on_entry),
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

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.launch(program)
  program = program or config.program
  if type(program) == "function" then
    program = program()
  end

  if not program or program == "" then
    program = vim.fn.input("Roundtable program: ", "", "file")
  end

  if not program or program == "" then
    vim.notify("Roundtable launch cancelled: no program provided", vim.log.levels.WARN)
    return
  end

  program = normalize_path(program)
  local generated_config = write_config(program)
  local command = shell_quote(config.binary) .. " --config " .. shell_quote(generated_config)
  open_terminal(command)
end

return M
