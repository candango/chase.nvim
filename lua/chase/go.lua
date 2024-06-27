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

function M.is_go_project()
    if chase.project_root:joinpath("go.mod"):exists() then
        return true
    end
    return false
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
