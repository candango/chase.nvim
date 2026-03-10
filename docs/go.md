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
- **Outside a Test**:
  - Command: `go run <file>`
- **Main Entry Point**:
  - If the file contains `func main()`, Chase runs it as the main application.

## ⚙️ Configuration

```lua
require("chase").setup({
    go = {
        enabled = true,
    },
})
```
