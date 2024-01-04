-- see:help events
-- au BufWritePost  <=== To display the autocmds
-- au! BufWritePost <=== To clear
-- SEE: https://youtu.be/HR1dKKrOmDs?t=324
-- SEE: https://youtu.be/9gUatBHuXE0?t=453 <== Jobstart
-- SEE: https://stackoverflow.com/a/75240496

local chase = require("chase")
local Log = chase.log
local Path = require("plenary.path")

local M = {}

M.buf_name_prefix = "ChasePy: "

M.buf_name_suffix = " P)"

M.setup_called = false
M.vim_did_enter = false

M.python_version = nil

-- Output buffers table
M.bufs_out = {}
-- print(M.bufs_out)

function M.buf_is_main(buf_number)
    local lines = vim.api.nvim_buf_get_lines(buf_number, 0, -1, false)
    for _, line in ipairs(lines) do
        local pattern = "if __name__[ ]*==[ ]*[\"|']__main__[\"|'][ ]*:"
        if string.match(line, pattern) then
            return true
        end
    end
    return false
end

-- M.buf_out_register(file, name, python

function M.on_python_save()
    local data = {
        buf = tonumber(vim.fn.expand("<abuf>")),
        file = vim.fn.expand("<afile>"),
        match = vim.fn.expand("<amatch>"),
    }
    if M.buf_is_main(data.buf) then
        Log.info("Doing main stuff...")
        -- print(vim.inspect(data))
        chase.buf_open(data.file .. "_run")
    end
    -- print(vim.inspect(data))
    -- vim.api.nvim_create_buf(false, false)
end

function M.setup_project_virtualenv()
    if M.setup_called then
        if chase.is_python_project() then
            local cwd_x = vim.fn.split(vim.fn.getcwd(), chase.sep)
            chase.setup_virtualenv(cwd_x[#cwd_x], M.set_python)
            vim.fn.jobstart(
            { M.preferred_python(), "--version" },
            {
                stdout_buffered = true,
                on_stdout = function(_, data)
                    local result = vim.fn.join(data, "")
                    M.python_version = vim.fn.split(result, " ")[2]
                    if chase.is_windows then
                        M.python_version = M.python_version:gsub("\r", "")
                    end
                end,
            })
        end
    end
end

function M.preferred_python()
    if os.getenv("VIRTUAL_ENV") ~= nil then
        local bin_path = "bin"
        local python = "python"
        if chase.is_windows() then
            bin_path = "Scripts"
            python = "python.exe"
        end
        return Path:new(
            os.getenv("VIRTUAL_ENV"), bin_path, python
        ).filename
    end
    return vim.api.nvim_get_var("python3_host_prog")
end

function M.run_file(file)
    if chase.is_windows() then
        file = file:gsub("/", chase.sep)
    end
    local relative_file = file:gsub(
        chase.project_root.filename .. chase.sep, ""
    )
    local buf = chase.buf_chase(relative_file)
    local testing = file:match("_test.py$")
    if not testing then
        testing = file:match("test_.*.py$")
    end
    chase.buf_clear(buf)
    local action = "Running "
    if testing then
        action = "Testing "
    end
    chase.buf_append(buf, {
        "Candango Chase",
        action .. relative_file,
        "Python: " .. M.preferred_python(),
        "Version: " .. M.python_version,
        "",
        ""
    })

    local py_cmd = M.preferred_python()
    local py_args = ""
    if testing then
        py_args = "-m unittest -v"
    end
    local cmd_list = { py_cmd, py_args, file }
    vim.fn.jobstart(
    table.concat(cmd_list, " "),
    {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data)
            if chase.is_windows() then
                for i, v in ipairs(data) do
                    data[i] = v:gsub("\r", "")
                end
            end
            chase.buf_append(buf, data)
        end,
        on_stderr = function(_, data)
            chase.buf_append(buf, data)
        end,
    })
end

function M.on_vim_start()
    M.setup_project_virtualenv()
end

vim.api.nvim_create_autocmd("VimEnter", {
    callback = M.on_vim_start,
    group = chase.group,
})

function M.setup()
    M.setup_called = true

    if chase.vim_did_enter then
        M.setup_project_virtualenv()
    end

    vim.api.nvim_create_autocmd("BufWritePost", {
        callback = M.on_python_save,
        pattern = "*.py",
        group = chase.group,
    })
end

function M.set_python(venv_path)
    local venv_bin = venv_path:joinpath("bin")
    if chase.is_windows() then
        venv_bin = venv_path:joinpath("Scripts")
    end
    -- local venv_activate = venv_bin:joinpath("activate")
    chase.add_to_path(venv_bin)
    -- let $VIRTUAL_ENV=<project_virtualenv>
    vim.cmd("let $VIRTUAL_ENV='" .. venv_path.filename .. "'")
    if chase.is_windows then
        vim.cmd("let $PYTHONPATH='.;" .. chase.project_root.filename .. "'")
        return
    end
    vim.cmd("let $PYTHONPATH='.:" .. chase.project_root.filename .. "'")
end

return M
