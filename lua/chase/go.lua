local chase = require("chase")
local Log = chase.log
local Path = require("plenary.path")

local M = {}

M.buf_name_prefix = "ChaseGo: "

M.setup_called = false
M.vim_did_enter = false

M.go_bin = nil
M.go_arch = nil
M.go_version = nil

function M.buf_is_main(buf_number)
    local lines = vim.api.nvim_buf_get_lines(buf_number, 0, -1, false)
    for _, line in ipairs(lines) do
        local pattern = "func main()"
        if string.match(line, pattern) then
            return true
        end
    end
    return false
end

function M.is_go_project()
    if chase.project_root:joinpath("go.mod"):exists() then
        return true
    end
    return false
end

function M.run_file(file)
    local buf = vim.api.nvim_get_current_buf()
    if chase.is_windows() then
        file = file:gsub("/", chase.sep)
    end
    local relative_file = file:gsub(
        chase.project_root.filename .. chase.sep, ""
    )
    local chase_buf = chase.buf_chase(relative_file, buf)
    local testing = file:match("_test.go$")
    if not testing then
        testing = file:match("test_.*.go$")
    end
    chase.buf_clear(chase_buf)
    local action = "Running "
    if testing then
        action = "Testing "
    end
    chase.buf_append(chase_buf, {
        "Candango Chase",
        action .. relative_file,
    })

    local go_args = "run"
    if testing then
        -- local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
        -- local lines = vim.api.nvim_buf_get_lines(0, 0, row, false)
        -- local current_module = M.get_current_module(file)
        -- local current_testing = current_module
        -- local where_am_i = M.where_am_i(lines, row)
        -- chase.buf_append(chase_buf, {
        --     "Current module: " .. current_module,
        -- })
        -- if where_am_i ~= "" then
        --     current_testing = current_testing .. "." .. where_am_i
        --     chase.buf_append(chase_buf, {
        --         "Location: " .. where_am_i,
        --     })
        -- end
	    -- CGO_ENABLED=0 go clean -testcache && go test -v  ./...
        go_args = "test -v ./ -run=./" .. relative_file
    end

    chase.buf_append(chase_buf, {
        "Go: " .. M.go_bin,
        "Version: " .. M.go_version,
        "",
    })

    local cmd_list = { M.go_bin, go_args }
    if not testing then
        cmd_list[#cmd_list+1] = file
    end

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
            chase.buf_append(chase_buf, data)
        end,
        on_stderr = function(_, data)
            chase.buf_append(chase_buf, data)
        end,
    })
end

function M.setup()
    M.setup_called = true

    M.setup_project_go()

    if M.is_go_project() then
        vim.api.nvim_create_autocmd("BufEnter", {
            callback = function()
                local keymaps = {
                    {
                        mode = "n",
                        lhs = "<leader>cc",
                        opts = { callback = function ()
                            M.run_file(vim.api.nvim_buf_get_name(0))
                        end },
                    },
                }
                chase.on_buf_enter(keymaps)
            end,
            pattern = "*.go",
            group = chase.group,
        })

        vim.api.nvim_create_autocmd("BufHidden", {
            callback = chase.on_buf_hidden,
            pattern = "*.go",
            group = chase.group,
        })
    end
end

function M.setup_project_go()

    if M.setup_called then
        if M.is_go_project() then
            -- local cwd_x = vim.fn.split(vim.fn.getcwd(), chase.sep)
            vim.fn.jobstart(
            { "which", "go" },
            {
                stdout_buffered = true,
                on_stdout = function(_, which_data)
                    M.go_bin = vim.fn.join(which_data, "")
                    vim.fn.jobstart(
                    { M.go_bin, "version" },
                    {
                        stdout_buffered = true,
                        on_stdout = function(_, version_data)
                            local go_version = vim.fn.split(
                                vim.fn.join(version_data, ""), "")
                            M.go_arch = go_version[4]
                            M.go_version = go_version[3]
                        end,
                    })
                end,
            })
        end
    end
end
-- M.setup_called = true
-- M.setup_project_go()
return M
