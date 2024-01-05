-- Buffer creation see: https://stackoverflow.com/a/75240496
local Data = require("chase.data")
local Path = require("plenary.path")
local Log = require("plenary.log")

local M =  {}

function M.is_windows()
    return string.match(vim.loop.os_uname().sysname, "Windows") ~= nil
end

M.group = vim.api.nvim_create_augroup("CANDANGO_CHASE", { clear = true })
M.sep = Path.path.sep
M.user_home = Path:new(os.getenv("HOME"))

if M.is_windows() then
    M.user_home = os.getenv("UserProfile")
end

M.user_config_dir = Path:new(vim.fn.stdpath("data"), "chase")
M.user_config = Data.config
M.user_config_projects_file = Path:new(M.user_config_dir, "projects")
M.project_root = Path:new(vim.fn.getcwd())


M.vim_did_enter = false

M.python_buf_number = -1
M.go_buf_number = -1
M.log = Log.new({
    level = "trace",
    plugin = "chase",
    use_file = true,
    outfile = vim.fn.stdpath("data") .. M.sep .. "chase.log",
    -- use_console = false,
})

-- tbl_deep_extend does not work the way you would think
-- yonk from harpoon, not public
local function merge_table_impl(t1, t2)
    for k, v in pairs(t2) do
        if type(v) == "table" then
            if type(t1[k]) == "table" then
                merge_table_impl(t1[k], v)
            else
                t1[k] = v
            end
        else
            t1[k] = v
        end
    end
end

local function merge_tables(...)
    M.log.trace("_merge_tables()")
    local out = {}
    for i = 1, select("#", ...) do
        merge_table_impl(out, select(i, ...))
    end
    return out
end

function M.is_python_project()
    -- TODO: Finish to check other python project possibilities
    if M.project_root:joinpath("setup.py"):exists() then
        return true
    end
    return false
end

function M.chase_it(opts)
    print(vim.inspect(opts.args))
end

function M.chase_it_complete(arg_lead, cmd_line, cursor_pos)
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

function M.buf_chase(file)
    local buf = M.buf_open(file .. "_run")
    return buf
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

function M.buf_open(name, type)
    -- Get a boolean that tells us if the buffer number is visible anymore.
    --
    -- :help bufwinnr
    local buf = -1
    name = name or "MONSTER_OF_THE_LAKE"
    type = type or "txt"

    local buf_from_name = M.buf_from_name(name)
    if buf_from_name ~= -1 then
        return buf_from_name
    end

    local cur_win = vim.api.nvim_get_current_win()
    if buf == -1 or not M.buf_is_visible(buf) then
        vim.cmd("botright vsplit " .. name)
        buf = vim.api.nvim_get_current_buf()
        -- vim.opt_local.readonly = true
        vim.api.nvim_buf_set_option(buf, "readonly", true)
        vim.api.nvim_buf_set_option(buf, "buftype", "nowrite")
        vim.api.nvim_buf_set_option(buf, "filetype", type)
        vim.api.nvim_buf_set_option(buf, "buflisted", false)
        vim.api.nvim_buf_set_keymap(buf, "n", "q", ":q!<CR>", {})
        vim.api.nvim_set_current_win(cur_win)
        return buf
    end
end

-- print(M.buf_from_name("MONSTER_OF_THE_LAKE"))
-- print(vim.inspect(M.all_listed_buffers()))

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

function M.setup()
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
    local venv_root = Path:new(M.user_home, "venvs")
    local venv_path = Path:new(venv_root, venv_name)

    if not venv_path:exists() then
        M.log.warn("virtualenv for " .. venv_prefix .. " doesn't exists")
        M.log.warn("creating virtualenv for " .. venv_prefix)
        vim.fn.jobstart(
        {
            "python",  "-m", "venv", "--clear",
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
    local venv_host_prog = venv_bin:joinpath("python")
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
end

function M.install_package(venv_path, package, install)
    install = install or package
    vim.fn.jobstart(
    { "python", "-m", "pip", "show", package },
    {
        stderr_buffered = true,
        on_stderr = function(_, data)
            if #data > 1 then
                M.log.warn(
                "installing " .. package .. " at venv " .. venv_path.filename
                )
                vim.fn.jobstart(
                { "python", "-m", "pip",  "install", package },
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

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function ()
        M.vim_did_enter = true
        M.setup_virtualenv("chase_global", M.set_python_global)
    end,
    group = M.group,
})

return M
