# roundtable.nvim

Minimal Neovim integration for Roundtable.

This plugin generates a temporary `roundtable.toml` from Neovim context and launches Roundtable with:

```sh
roundtable --config <generated-config>
```

It does not share or attach to an existing `nvim-dap` session. Roundtable starts and owns its own CodeLLDB session.

## Setup

```lua
require("roundtable").setup({
  binary = "roundtable",
  config_dir = nil,
  config_name = "roundtable.nvim.toml",
  codelldb_candidate_roots = {},
  terminal = "split",
  watches = {},
  use_dap_config = true,
  use_profile = true,
  profile_name = "nvim",
})
```

With `lazy.nvim`, make `nvim-dap` an optional dependency if you want Roundtable to reuse DAP launch configs and breakpoints:

```lua
{
  "Saladin1812/roundtable.nvim",
  dependencies = {
    "mfussenegger/nvim-dap",
  },
  config = true,
}
```

The plugin still works without `nvim-dap` when you pass a program explicitly.

## Usage

Launch with an explicit program:

```vim
:RoundtableLaunch ./build/my_program
```

Or call `:RoundtableLaunch` with no argument and enter the program path when prompted.

Generate and inspect TOML without launching Roundtable:

```vim
:RoundtableGenerateConfig ./build/my_program
```

Check local setup:

```vim
:RoundtableCheck
```

If `nvim-dap` is installed, buffer breakpoints are copied into the generated Roundtable config.

By default the generated TOML uses a Roundtable launch profile:

```toml
[session]
profile = "nvim"

[profiles.nvim]
program = "./build/my_program"
watches = []
breakpoints = []
```

Set `use_profile = false` if you want direct `[dap_launch]`, `[watches]`, and `[breakpoints]` sections instead.

By default generated TOML is written under Neovim's cache directory. Use `config_dir` and `config_name` if you want a stable location:

```lua
require("roundtable").setup({
  config_dir = vim.fn.getcwd() .. "/.roundtable",
  config_name = "from-nvim.toml",
})
```

Roundtable auto-detects CodeLLDB from common locations, including Mason, VS Code extensions, and `PATH`. Add extra roots if your adapter is somewhere custom:

```lua
require("roundtable").setup({
  codelldb_candidate_roots = {
    vim.fn.expand("~/.local/share/nvim/mason/packages/codelldb"),
  },
})
```

When called without an explicit program, the plugin first tries the current filetype's `nvim-dap` launch configuration:

- `program`
- `args`
- `cwd`
- `stopOnEntry`

Common `nvim-dap` variables are expanded before writing TOML:

- `${workspaceFolder}`
- `${file}`
- `${fileDirname}`
- `${fileBasename}`
- `${fileBasenameNoExtension}`
- `${fileExtname}`

You can select a specific DAP config name:

```lua
require("roundtable").setup({
  dap_configuration_name = "Launch app",
})
```

## Tests

Run the headless smoke tests:

```sh
nvim -n --headless --clean -u NONE -l tests/smoke.lua
```
