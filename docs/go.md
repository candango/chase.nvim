# Go Runner

The Go runner in Chase provides integrated testing and execution for Go projects.

## 🚀 Activation Triggers

Chase identifies a Go project if the following file is found in the project root:
- `go.mod`

## 🧪 Execution Logic

When you press `<leader>cc`:

- **Inside a Test**:
  - Uses **Tree-sitter** to identify `TestXxx(t *testing.T)` and subtests `t.Run("subtest", ...)`.
  - Command: `go test -v ./... -run='^TestName$/^SubtestName$'`
- **Inside a Benchmark**:
  - Uses **Tree-sitter** to identify `BenchmarkXxx(b *testing.B)`.
  - Command: `go test -v ./... -run='^$' -bench='^BenchmarkName$'`
- **Outside a Test or Benchmark**:
  - Command: `go run ./package`
- **Main Entry Point**:
  - If the file contains `func main()`, Chase runs it as the main application.

## ⚙️ Configuration

```lua
require("chase").setup({
    chasers = {
        go = {
            enabled = true,
            build_tags = {},
        },
    },
})
```

### Activating build tags

Create a local module in your Neovim configuration:

```lua
-- ~/.config/nvim/lua/chase_machine.lua
return {
    chasers = {
        go = {
            build_tags = { "unit", "component" },
        },
    },
}
```

When `build_tags` is empty or omitted, Chase does not add a `-tags` argument.
