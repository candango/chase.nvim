local M =  {
}

--- @class ChaseConfig
--- @field global table Global plugin settings.
--- @field ui table UI and buffer settings.
--- @field chasers table language-specific runner settings.
M.defaults = {
    global = {
        log_level = os.getenv("CHASE_LOG_LEVEL") or "warn",
        save_on_run = true, -- Auto-save buffer before execution
    },
    ui = {
        split_direction = "botright vsplit",
        width = nil, -- Uses default if nil
        auto_focus = false, -- Move cursor to Chase buffer on run
    },
    chasers = {
        go = {
            enabled = true,
            test_args = { "-v", "./..." },
        },
        python = {
            enabled = true,
            venvs_dir = vim.fs.normalize("~/venvs"),
            runner = "uv", -- prefer 'uv' if available
        },
        php = {
            enabled = true,
            include_path = { "." },
        },
        lua = {
            enabled = true,
        },
        zig = {
            enabled = true,
        },
        java = {
            enabled = true,
        },
    }
}

return M
