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
  terminal = "split",
  watches = {},
  use_dap_config = true,
})
```

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

If `nvim-dap` is installed, buffer breakpoints are copied into the generated Roundtable config.

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
