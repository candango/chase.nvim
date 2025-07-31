local chase = require("chase")

local M = {}

M.buf_name_prefix = "ChaseLua: "

M.setup_called = false
M.vim_did_enter = false

M.lua_version = nil

function M.run_file(file)
    local buf = vim.api.nvim_get_current_buf()
    if chase.is_windows() then
        file = file:gsub("/", chase.sep)
    end
    local relative_file = file:gsub(
        chase.project_root.filename .. chase.sep, ""
    )
    local chase_buf = chase.buf_chase(relative_file, buf)
    chase.buf_clear(chase_buf)
    local action = "Running "
    chase.buf_append(chase_buf, {
        "Candango Chase",
        action .. relative_file,
    })

    chase.buf_append(chase_buf, {
        "Lua: nvim embeded",
        "Version: " .. jit.version,
        "",
    })
    local original_print = print
    print = function(...)
        local args = {...}
        local str = ""
        for i = 1, #args do
            str = str .. tostring(args[i]) .. " "
        end
        local lines = vim.split(str, "\r?\n")
        chase.buf_append(chase_buf, lines)
    end
    dofile(file)
    print = original_print
end

function M.setup()
    M.setup_called = true

    M.setup_project_lua()

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
        pattern = "*.lua",
        group = chase.group,
    })

    vim.api.nvim_create_autocmd("BufHidden", {
        callback = chase.on_buf_hidden,
        pattern = "*.lua",
        group = chase.group,
    })
end

function M.setup_project_lua()
    if M.setup_called then
        M.lua_version = jit.version
    end
end
return M
