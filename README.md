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
})
```

## Usage

Launch with an explicit program:

```vim
:RoundtableLaunch ./build/my_program
```

Or call `:RoundtableLaunch` with no argument and enter the program path when prompted.

If `nvim-dap` is installed, buffer breakpoints are copied into the generated Roundtable config.
