# Lua Runner

The Lua runner in Chase provides integrated execution for Lua files within Neovim.

## 🚀 Activation Triggers

The Lua runner is always active as it uses Neovim's embedded Lua JIT.

## 🧪 Execution Logic

When you press `<leader>cc`:

- **Execution**:
  - Uses `dofile(file)` to run the Lua file.
  - Command: Runs within the current Neovim instance.
  - **Capturing Output**: Chase overrides `print` temporarily to capture the output into the Chase buffer.

## ⚙️ Configuration

```lua
require("chase").setup({
    -- Always enabled by default
})
```
