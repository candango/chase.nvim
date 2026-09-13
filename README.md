# Candango Chase

Chase is a Neovim plugin designed to streamline your development workflow by
automatically configuring runtime environments and executing code with
contextual awareness.

With Chase, you can focus on writing high-quality code while we handle the
tedious task of environment configuration. Say goodbye to manual setup and
hello to a more efficient development workflow.

## 🚀 Key Features

- **Auto-Configuration**: Chase intelligently detects and configures runtime
environments for multiple languages.
- **Python Magic**: Automatic management of virtual environments.
  - **Global Environment**: Automatically creates and manages `~/venvs/chase_global_env` to power Neovim's `python3_host_prog`.
  - **Project Environments**: Creates per-project environments in `~/venvs/` (e.g., `~/venvs/parent_project_env`) and sets them up automatically.
  - **Smart Tools**: Uses `uv` if available for lightning-fast venv management, with a seamless fallback to `pip`.
- **Intelligent Runners**: Language-specific runners that understand your project structure and tests.
- **Asynchronous Execution**: Runs code and tests in a dedicated, non-blocking Chase buffer using Neovim's `jobstart`.
- **Focused Testing**: Integrated with **Tree-sitter** to detect the specific test under your cursor and run it in isolation.

## 🛠 Supported Runners

| Runner | Project Trigger | Test Framework |
| :--- | :--- | :--- |
| **Python** | `pyproject.toml`, `setup.py` | `unittest` |
| **Go** | `go.mod` | `go test` |
| **Zig** | `build.zig` | `zig test` |
| **PHP** | `composer.json`, `phpunit.xml` | `phpunit` |
| **Java** | `pom.xml`, `build.gradle` | `junit` (Maven/Gradle) |
| **Lua** | Always Active | Embedded Nvim Lua |

Detailed documentation for each runner can be found in the [docs/](docs/) directory.

## 📦 Installation

Use your favorite plugin manager. For example, with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "candango/chase.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-treesitter/nvim-treesitter",
    },
    config = function()
        require("chase").setup({
            -- Optional configuration
            python = {
                enabled = true,
                venvs_dir = vim.fs.normalize("~/venvs"),
            },
            go = {
                enabled = true,
            },
            -- etc.
        })
    end,
}
```

## ⌨️ Usage

The universal command for Chase is `<leader>cc`. 

- **Inside a test**: Chase will detect the test case under the cursor and run only that test.
- **Outside a test**: Chase will run the entire file or the project main entry point.
- **Toggle Buffer**: Use `<leader>q` to close the Chase output buffer.

## 🎨 Highlighting

Every runner writes the same header to the Chase buffer and colors it with
the groups below. Process output is scanned once per line as it streams in,
so well-known lines such as `--- FAIL`, `ok`, `panic:`, `Traceback`,
`test result: ok` or `error[E0308]` are colored without any redraw cost.

| Group | Default link | Applied to |
| :--- | :--- | :--- |
| `ChaseTitle` | `Title` | The `Candango Chase` title line |
| `ChaseAction` | `Keyword` | The action verb (`Running`, `Testing`, `Benchmarking`) |
| `ChaseFile` | `Directory` | The file being chased |
| `ChaseInfo` | `Comment` | Keys of header lines such as `Version:` or `Location:` |
| `ChaseSuccess` | `DiagnosticOk` | Passing test summaries |
| `ChaseWarning` | `DiagnosticWarn` | Compiler warnings |
| `ChaseError` | `DiagnosticError` | Failures, panics, tracebacks and non-zero exits |

All groups are defined with `default = true`, so a colorscheme or your own
configuration can override them:

```lua
vim.api.nvim_set_hl(0, "ChaseError", { fg = "#ff5555", bold = true })
```

The output scanner is driven by `require("chase").output_patterns`, an
ordered list of `{ pattern = <lua pattern>, group = <highlight group> }`
entries where the first match wins. Append your own entries to color
runner-specific lines:

```lua
table.insert(require("chase").output_patterns, {
    pattern = "^SKIP", group = "ChaseWarning",
})
```

## 📜 License

**Apache License V2.0**

Copyright © 2023-2024 Flavio Garcia
