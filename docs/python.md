# Python Runner

The Python runner in Chase provides automated virtual environment management and seamless test execution.

## 🚀 Activation Triggers

Chase identifies a Python project if any of the following files are found in the project root:
- `pyproject.toml`
- `setup.py`
- `setup.cfg`

## 🐍 Virtual Environment Management

Chase automatically manages two types of environments:

1. **Global Environment**: 
   - Path: `~/venvs/chase_global_env`
   - Purpose: Acts as the dedicated Python host for Neovim (`python3_host_prog`).
   - Setup: Initialized automatically on the first run.

2. **Project Environment**:
   - Path: `~/venvs/<parent_dir>_<current_dir>_env`
   - Purpose: Provides an isolated environment for the current project.
   - Setup: Created automatically when a Python project is detected.

### ⚡ Powered by uv
If [uv](https://github.com/astral-sh/uv) is installed on your system, Chase will use it for all venv operations (creation and package installation), providing significant performance gains. If `uv` is not found, it seamlessly falls back to standard `pip` and `venv`.

## 🧪 Execution Logic

When you press `<leader>cc`:

- **Inside a Test**:
  - Uses **Tree-sitter** to detect `unittest.TestCase` classes and methods.
  - Command: `python -m unittest -v <module>.<class>.<method>`
- **Outside a Test**:
  - Command: `python <file>`
- **Main Entry Point**:
  - If the file contains `if __name__ == "__main__":`, Chase prioritizes running the file as the main entry point.

## ⚙️ Configuration

```lua
require("chase").setup({
    python = {
        enabled = true,
        venvs_dir = vim.fs.normalize("~/venvs"),
    },
})
```
