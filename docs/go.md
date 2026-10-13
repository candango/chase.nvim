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

## ⌨️ Execution controls

The Go chaser exposes buffer-local execution controls:

- `<leader>cc` runs the current file or test.
- `<leader>caa` opens a free-form input for command parameters.
- `<leader>cax` clears the stored command parameters.
- `<leader>cee` opens a free-form input for environment variables.
- `<leader>cex` clears the stored environment variables.
- `<leader>q` deletes the Chase output buffer.

The parameter and environment inputs are raw shell text. Chase does not parse
or validate either value; the text is placed around the Go command as:

```text
ENVVARS go run ./package PARAMETERS
```

For example, entering `PORT=8080 DEBUG=true` as the environment and
`--verbose` as the parameters runs:

```text
PORT=8080 DEBUG=true go run ./package --verbose
```

The values are isolated per source buffer. Do not enter secrets if the command
or shell output would expose them.

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
