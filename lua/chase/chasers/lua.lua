local chase = require("chase")

--- @class ChaseLua : Chaser
local M = {}

--- @type string
--- Prefix for the output buffer name.
M.buf_name_prefix = "ChaseLua: "

--- @type string|nil
--- Current LuaJIT version string.
M.lua_version = nil

--- @type string
--- The file pattern to match for Lua files.
M.pattern = "*.lua"

--- Helper to find the root directory of a plugin in the current runtimepath.
--- @param plugin_name string The name of the plugin (e.g., "plenary").
--- @return string|nil path The absolute path to the plugin root or nil if not found.
local function find_plugin_root(plugin_name)
    local paths = vim.api.nvim_get_runtime_file("lua/" .. plugin_name, true)
    if #paths > 0 then
        -- Returns the parent of the 'lua' directory
        return vim.fn.fnamemodify(paths[1], ":h:h")
    end
    return nil
end

--- Executes the given Lua file using Neovim's embedded JIT or headless Plenary for specs.
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

    local testing = file:match("_spec%.lua$")

    chase.buf_clear(chase_buf)
    local action = testing and "Testing " or "Running "
    chase.buf_append(chase_buf, {
        "Candango Chase",
        action .. relative_file,
    })

    if testing then
        local plenary_root = find_plugin_root("plenary")
        local ts_root = find_plugin_root("nvim-treesitter")
        local chase_root = chase.project_root.filename

        local rtp = chase_root
        if plenary_root then rtp = rtp .. "," .. plenary_root end
        if ts_root then rtp = rtp .. "," .. ts_root end

        chase.buf_append(chase_buf, {
            "Lua: nvim headless (Plenary)",
            "Version: " .. jit.version,
            "",
        })

        local cmd = {
            "nvim", "--headless", "--noplugin", "-u", "NONE",
            "--cmd", string.format("set rtp+=%s", rtp),
            "-c", "runtime plugin/plenary.vim",
            "-c", string.format("PlenaryBustedFile %s", file),
            "-c", "qa!"
        }

        vim.fn.jobstart(cmd, {
            stdout_buffered = true,
            stderr_buffered = true,
            on_stdout = function(_, data)
                if data then
                    for i, line in ipairs(data) do
                        line = line:gsub("\27%[[%d;]*m", "")
                        line = line:gsub("\r", "")
                        data[i] = line
                    end
                    chase.buf_append(chase_buf, data)
                end
            end,
            on_stderr = function(_, data)
                if data then
                    for i, line in ipairs(data) do
                        line = line:gsub("\27%[[%d;]*m", "")
                        line = line:gsub("\r", "")
                        data[i] = line
                    end
                    chase.buf_append(chase_buf, data)
                end
            end,
        })
    else
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
end

--- Initializes the Lua runner by capturing the JIT version.
function M.setup_project()
    M.lua_version = jit.version
end

return M
