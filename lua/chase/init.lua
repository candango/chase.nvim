local Data = require("chase.data")
local async = require("plenary.async")
local Path = require("plenary.path")
local Log = require("plenary.log")

local M =  {}

function M.is_windows()
    return string.match(vim.loop.os_uname().sysname, "Windows") ~= nil
end

M.group = vim.api.nvim_create_augroup("CANDANGO_CHASE", { clear = true })
M.sep = Path.path.sep
M.user_home = Path:new(os.getenv("HOME"))
M.installed_python = "python"
M.global_env_done = false

if M.is_windows() then
    M.user_home = os.getenv("UserProfile")
end

if not M.is_windows() then
    local stream = assert(io.popen('which python3', 'r'))
    local output = stream:read('*all')
    stream:close()
    if #output > 0 then
        M.installed_python = "python3"
    end
end

M.user_config_dir = Path:new(vim.fn.stdpath("data"), "chase")
M.config = Data.config
M.user_config_projects_file = Path:new(M.user_config_dir, "projects")
M.project_root = Path:new(vim.fn.getcwd())

M.vim_did_enter = false

M.python_buf_number = -1
M.go_buf_number = -1
local log_level = os.getenv("CHASE_LOG_LEVEL") or "warn"
M.log = Log.new({
    level = log_level,
    plugin = "chase",
    use_file = true,
    outfile = vim.fn.stdpath("data") .. M.sep .. "chase.log",
    -- use_console = false,
})

M.buf_refs = {}
M.buf_win_refs = {}

function M.chase_it(opts)
    print(vim.inspect(opts.args))
end

function M.chase_it_complete(arg_lead, cmd_line, _) -- cursor_pos)
    local cmd_line_x = vim.fn.split(cmd_line, " ")
    local cmd_line_count = #cmd_line_x
    M.log.warn(arg_lead)
    if cmd_line_count == 1 then
        return { "mark" }
    end
    if cmd_line_count == 2 then
        return { "run" }
    end
end

local chase_it_opts = { nargs = "*", complete=M.chase_it_complete }
vim.api.nvim_create_user_command("Chase", M.chase_it, chase_it_opts)
vim.api.nvim_create_user_command("C", M.chase_it, chase_it_opts)

function M.buf_chase(file, buf)
    local chase_buf = M.buf_open(file .. "_run", buf)
    return chase_buf
end

function M.buf_is_visible(buf)
    -- Get a boolean that tells us if the buffer number is visible anymore.
    --
    -- :help bufwinnr
    buf = buf or "/"
    return vim.api.nvim_call_function("bufwinnr", { buf }) ~= -1
end

-- From: https://codereview.stackexchange.com/a/282183
function M.all_listed_buffers()
    local bufs = {}
    local count = 1
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            bufs[count] = buf
            count = count + 1
        end
    end

    return bufs
end

function M.buf_from_name(name)
    for _, buf in ipairs(M.all_listed_buffers()) do
        local listed_name = vim.api.nvim_buf_get_name(buf):gsub(
            M.project_root .. M.sep, ""
        )
        if listed_name == name then
            return buf
        end
    end
    return -1
end

function M.buf_open(name, buf, type)
    -- Get a boolean that tells us if the buffer number is visible anymore.
    --
    -- :help bufwinnr
    local chase_buf = -1
    name = name or "MONSTER_OF_THE_LAKE"
    type = type or "txt"

    local buf_from_name = M.buf_from_name(name)
    if buf_from_name ~= -1 then
        return buf_from_name
    end

    local cur_win = vim.api.nvim_get_current_win()
    if chase_buf == -1 or not M.buf_is_visible(chase_buf) then
        vim.cmd("botright vsplit " .. name)
        chase_buf = vim.api.nvim_get_current_buf()
        -- vim.opt_local.readonly = true
        vim.api.nvim_buf_set_option(chase_buf, "readonly", true)
        vim.api.nvim_buf_set_option(chase_buf, "buftype", "nowrite")
        vim.api.nvim_buf_set_option(chase_buf, "filetype", type)
        vim.api.nvim_buf_set_option(chase_buf, "buflisted", false)
        vim.api.nvim_buf_set_var(chase_buf, "original_buf", buf)
        vim.api.nvim_buf_set_keymap(chase_buf, "n", "<leader>q", "",
            {callback = function()
                M.chase_buf_destroy(chase_buf)
            end}
        )
        vim.api.nvim_set_current_win(cur_win)
        M.buf_refs[buf] = chase_buf
        return chase_buf
    end
end

function M.on_buf_hidden()
    local cur_buf = vim.api.nvim_get_current_buf()
    local buf = M.buf_refs[cur_buf]
    if buf then
        M.buf_hide(buf)
    end
end

function M.on_buf_enter(extra_keymaps)
    extra_keymaps = extra_keymaps or {}
    local cur_buf = vim.api.nvim_get_current_buf()
    local keymaps = {
        {
            mode = "n",
            lhs = "<leader>cd",
            opts = { callback = function () M.destroy_my_chase(cur_buf) end },
        },
        {
            mode = "n",
            lhs = "<leader>q",
            opts = { callback = function () M.destroy_my_chase(cur_buf) end },
        },
    }
    for _, keymap in pairs(extra_keymaps) do
        keymaps[#keymaps+1] = keymap
    end
    local found, _ = pcall(
        vim.api.nvim_buf_get_var, cur_buf, "chase_keymaps_set")
    if not found then
        vim.api.nvim_buf_set_var(cur_buf, "chase_keymaps_set", true)
        for _, keymap in pairs(keymaps) do
            local mode = keymap["mode"]
            local lhs = keymap["lhs"] or ""
            local rhs = keymap["rhs"] or ""
            local opts = keymap["opts"] or {}
            vim.api.nvim_buf_set_keymap(cur_buf, mode, lhs, rhs, opts)
        end
    end
    for buf, chase_buf in pairs(M.buf_refs) do
        if buf ~= cur_buf then
            M.buf_hide(chase_buf)
        end
        if buf == cur_buf then
            if M.buf_is_hidden(chase_buf) then
                M.buf_show(chase_buf)
            end
        end
    end
end

-- function M.on_buf_leave()
--     local cur_buf = vim.api.nvim_get_current_buf()
--     print("BufLeave" .. cur_buf)
-- end
--
-- function M.on_buf_unload()
--     local cur_buf = vim.api.nvim_get_current_buf()
--     print("BufUnload" .. cur_buf)
-- end

function M.chase_buf_close(buf)

end

function M.buf_is_hidden(buf)
    local win = vim.fn.bufwinid(buf)
    if win > 0 then
        return false
    end
    return true
end

function M.buf_show(buf)
    local win = vim.fn.bufwinid(buf)
    local cur_win = vim.api.nvim_get_current_win()
    if win == -1 then
        vim.cmd("botright vsplit")
        win = vim.api.nvim_get_current_win()
    end
    -- set buf to current window
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(cur_win)
end

function M.buf_hide(buf)
    local win = vim.fn.bufwinid(buf)
    if win > 0 then
        local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
        vim.api.nvim_buf_set_option(buf, "buftype", "")
        vim.api.nvim_win_hide(win)
        if buftype then
            vim.api.nvim_buf_set_option(buf, "buftype", buftype)
        end
    end
end

function M.destroy_my_chase(buf)
    for buf_ref, buf_chase in pairs(M.buf_refs) do
        if buf_ref == buf then
            M.chase_buf_destroy(buf_chase)
            break
        end
    end
end

function M.chase_buf_destroy(chase_buf)
    local buf = vim.api.nvim_buf_get_var(chase_buf, "original_buf")
    local buf_refs = {}
    for buf_ref, buf_chase in pairs(M.buf_refs) do
        if buf_ref ~= buf then
            buf_refs[buf_ref] = buf_chase
        end
    end
    M.buf_refs = buf_refs
    vim.cmd("bd " .. chase_buf)
end

function M.buf_clear(buf)
    vim.api.nvim_buf_set_option(buf, "buftype", "")
    vim.api.nvim_buf_set_option(buf, "readonly", false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.api.nvim_buf_set_option(buf, "readonly", true)
    vim.api.nvim_buf_set_option(buf, "buftype", "nowrite")
end

function M.buf_append(buf, lines)
    vim.api.nvim_buf_set_option(buf, "readonly", false)
    vim.api.nvim_buf_set_option(buf, "buftype", "")
    local line_count = #vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if line_count < 2 then
        local first_line = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]
        if first_line == "" then
            line_count = 0
        end
    end
    vim.api.nvim_buf_set_lines(buf, line_count, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "readonly", true)
    vim.api.nvim_buf_set_option(buf, "buftype", "nowrite")
end

function M.setup(config)
    config = config or {}
    M.config = vim.tbl_deep_extend("force", M.config, config)
    M.log.trace("Setting up chase")
    if os.getenv("CHASE_DEBUG_LEVEL") then
        M.log = Log.new({
            level = os.getenv("CHASE_DEBUG_LEVEL"),
            plugin = "chase",
            use_file = true,
            outfile = vim.fn.stdpath("data") .. M.sep .. "chase.log",
            -- use_console = false,
        })
    end

    if os.getenv("CHASE_HOME") then
        M.log.trace("changing user config home to " .. os.getenv("CHASE_HOME"))
        M.user_home = Path:new(os.getenv("CHASE_HOME"))
        M.user_config_dir = Path:new(M.user_home, "chase")
        M.user_config_projects_file = Path:new(
            M.user_config_dir,
            "projects"
        )
    end

    if not  M.user_config_dir:exists() then
        M.log.warn("creating user config dir: " .. M.user_config_dir.filename)
        M.user_config_dir:mkdir()
    end

    if not  M.user_config_projects_file:exists() then
        M.log.warn("creating user projects file: " ..
            M.user_config_projects_file.filename)
        M.user_config_projects_file:touch()
        local file = io.open(M.user_config_projects_file.filename, "w")
        if file == nil then
            return
        end
        file:write(vim.json.encode(Data.config))
        file:close()
    end

    local file = io.open(M.user_config_projects_file.filename, "r")
    if file == nil then
        return
    end
    local config = vim.json.decode(file:read())
    file:close()
end

-- M.buf_clear(32)
-- M.buf_append(32, {"buga huga"})
-- print(vim.inspect(M.all_listed_buffers()))

-- from: https://stackoverflow.com/a/9102300/2887989
function M.get_path(file_path, sep)
    sep = sep or "/"
    return file_path:match("(.*"..sep..")")
end

function M.setup_virtualenv(venv_prefix, callback)
    local cwd_x = vim.fn.split(vim.fn.getcwd(), M.sep)
    venv_prefix = venv_prefix or cwd_x[#cwd_x]
    local venv_name = venv_prefix .. "_env"
    local venv_root = Path:new(M.config.python.venvs_dir)
    local venv_path = Path:new(venv_root, venv_name)

    if not venv_path:exists() then
        M.log.warn("virtualenv for " .. venv_prefix .. " doesn't exists")
        M.log.warn("creating virtualenv for " .. venv_prefix)
        vim.fn.jobstart(
        {
            M.installed_python,  "-m", "venv", "--clear",
            "--upgrade-deps", venv_path.filename,
        },
        {
            stdout_buffered = true,
            on_stdout = function(_, _)
                M.log.warn("virtualenv " .. venv_prefix ..
                " created successfully")
                if callback ~= nil then
                    callback(venv_path)
                end
            end,
        })
        return
    end
    if callback ~= nil then
        callback(venv_path)
    end
end

function M.add_to_path(path)
    local env_path = os.getenv("PATH")
    local path_sep = ":"
    if M.is_windows() then
        path_sep = ";"
    end
    vim.cmd("let $PATH = '" .. path .. path_sep .. env_path .. "'")
end

function M.set_python_global(venv_path)
    local venv_bin = venv_path:joinpath("bin")
    local venv_host_prog = venv_bin:joinpath(M.installed_python)
    if M.is_windows() then
        venv_bin = venv_path:joinpath("Scripts")
        venv_host_prog = venv_bin:joinpath("python.exe")
    end
    -- local venv_activate = venv_bin:joinpath("activate")
    M.add_to_path(venv_bin)
    vim.cmd("let g:python3_host_prog='" .. venv_host_prog .. "'")
    M.install_package(venv_path, "build", "build[virtualenv]")
    M.install_package(venv_path, "pynvim")
    M.install_package(venv_path, "twine")
    M.install_package(venv_path, "wheel")
    M.global_env_done = true
end

function M.install_package(venv_path, package, install)
    install = install or package
    vim.fn.jobstart(
    { M.installed_python, "-m", "pip", "show", package },
    {
        stderr_buffered = true,
        on_stderr = function(_, data)
            if #data > 1 then
                M.log.warn(
                "installing " .. package .. " at venv " .. venv_path.filename
                )
                vim.fn.jobstart(
                { M.installed_python, "-m", "pip",  "install", package },
                {
                    stdout_buffered = true,
                    on_stdout = function(_,_)
                        M.log.warn(
                        package .. " installed at " .. venv_path.filename ..
                        " successfully"
                        )
                    end,
                })
            end
        end,
    })
end

function M.run_after_global_env(time, callback)
    local max_attempts = 12
    return async.void(function()
        for _ = 1, max_attempts do
            if M.global_env_done then
                callback()
                return
            end
            async.util.sleep(time)
        end
        M.log.error("unable to check if global python environment is done")
    end)
end

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function ()
        M.vim_did_enter = true
        M.setup_virtualenv("chase_global", M.set_python_global)
        if M.config.python.enabled then
            M.run_after_global_env(1000, (function()
                require("chase.python").setup()
            end))()
        end
        if M.config.go.enabled then
            require("chase.go").setup()
        end
    end,
    group = M.group,
})

return M
