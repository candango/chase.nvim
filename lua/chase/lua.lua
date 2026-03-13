local chase = require("chase")

--- @class ChaseLua : ChaseRunner
local M = {}

--- @type string
--- Prefix for the output buffer name.
M.buf_name_prefix = "ChaseLua: "

--- @type string
--- The file pattern to match for Lua files.
M.lua_version = nil

--- @type string|nil
--- Current LuaJIT version string.
M.pattern = "*.lua"

--- Executes the given Lua file using Neovim's embedded JIT.
--- Redirects `print` output to the Chase buffer during execution.
--- @param file string The absolute path to the Lua file to run.
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

--- Initializes the Lua runner by capturing the JIT version.
function M.setup_project()
        M.lua_version = jit.version
end

return M
