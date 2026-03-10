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

## 📜 License

**Apache License V2.0**

Copyright © 2023-2024 Flavio Garcia
