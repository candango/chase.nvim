# Zig Runner

The Zig runner in Chase provides integrated testing and execution for Zig projects.

## 🚀 Activation Triggers

Chase identifies a Zig project if the following file is found in the project root:
- `build.zig`

## 🧪 Execution Logic

When you press `<leader>cc`:

- **Inside a Test**:
  - Uses **Tree-sitter** to identify `test "description" { ... }` blocks.
  - Command: `zig test --test-filter "description" <file>`
- **Outside a Test**:
  - Command: `zig run <file>`

## ⚙️ Configuration

```lua
require("chase").setup({
    zig = {
        enabled = true,
    },
})
```
