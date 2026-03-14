local chase = require("chase")

--- @class ChaseZig : ChaseRunner
local M = {}

--- @type string
--- Prefix for the output buffer name.
M.buf_name_prefix = "ChaseZig: "

--- @type string
--- The file pattern to match for Zig files.
M.pattern = "*.zig"

--- @type string|nil
--- Path to the Zig binary.
M.zig_bin = nil

--- @type string|nil
--- Current Zig version string.
M.zig_version = nil

-- Query for Zig tests
-- Zig tests are defined as `test "description" { ... }`
local ok, test_query = pcall(vim.treesitter.query.get, "zig", "test_def")
if not ok then
    -- Fallback for older or different parsers
    test_query = nil
end

--- Retrieves a table of test names from a buffer using Tree-sitter.
--- Returns empty table if buffer is invalid, unloaded, or no tests are found.
---
--- @param buf number The buffer number to analyze.
--- @return table table A table of test names (e.g., {"test description", "another test"}).
function M.tests_in_buffer(buf)
    if not test_query or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return {}
    end
    local parser = vim.treesitter.get_parser(buf, "zig")
    if not parser then
        return {}
    end
    local tree = parser:parse()[1]
    if not tree then
        return {}
    end
    local tests = {}
    for _, node, _ in test_query:iter_captures(tree:root(), buf, 0, -1) do
        local name = vim.treesitter.get_node_text(node, buf)
        -- Strip quotes from the string literal
        name = name:gsub("^[\"']", ""):gsub("[\"']$", "")
        table.insert(tests, name)
    end
    return tests
end

--- Identifies the test case under the cursor.
--- Returns the test name or an empty string if not within a test block.
---
--- @param buf number The buffer number to analyze.
--- @return string string The name of the test under the cursor.
function M.where_am_i(buf)
    if not test_query or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return ""
    end
    local parser = vim.treesitter.get_parser(buf, "zig")
    if not parser then
        return ""
    end
    local tree = parser:parse()[1]
    if not tree then
        return ""
    end
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1

    for _, match, _ in test_query:iter_matches(tree:root(), buf) do
        local name_node = match[1] -- @test.name
        local body_node = match[2] -- @test.body

        if type(name_node) == "table" then name_node = name_node[1] end
        if type(body_node) == "table" then body_node = body_node[1] end

        local start_row, _, end_row, _ = body_node:range()
        if row >= start_row and row <= end_row then
            local name = vim.treesitter.get_node_text(name_node, buf)
            -- Strip quotes from the string literal
            return name:gsub("^[\"']", ""):gsub("[\"']$", "")
        end
    end
    return ""
end

--- Checks if the current directory is a Zig project.
--- @return boolean result True if build.zig exists.
function M.is_project_valid()
    if chase.project_root:joinpath("build.zig"):exists() then
        return true
    end
    return false
end

--- Runs the given Zig file or tests within it.
--- Uses `zig test --filter` if it's a test file or if the cursor is within a test.
--- Uses `zig run` for normal files.
---
--- @param file string The absolute path to the file to run.
function M.run_file(file)
    local buf = vim.api.nvim_get_current_buf()

    local params = chase.buf_params[buf] or ""

    if chase.is_windows() then
        file = file:gsub("/", chase.sep)
    end
    local relative_file = file:gsub(
        chase.project_root.filename .. chase.sep, ""
    )
    local chase_buf = chase.buf_chase(relative_file, buf)

    -- Zig tests usually don't have a suffix like _test.go, but we can check if we are in a test
    local where_am_i = M.where_am_i(buf)
    local testing = where_am_i ~= ""

    chase.buf_clear(chase_buf)
    local action = "Running "
    if testing then
        action = "Testing "
    end
    chase.buf_append(chase_buf, {
        "Candango Chase",
        action .. relative_file,
    })

    local zig_args = "run"
    if testing then
        zig_args = "test --test-filter \"" .. where_am_i .. "\""
        chase.buf_append(chase_buf, {
            "Filter: " .. where_am_i,
        })
    end

    chase.buf_append(chase_buf, {
        "Zig: " .. (M.zig_bin or "zig"),
        "Version: " .. (M.zig_version or "unknown"),
    })

    local cmd_list = { M.zig_bin or "zig", zig_args, file }

    if params ~= "" then
       table.insert(cmd_list, "--")
       table.insert(cmd_list, params)
        chase.buf_append(chase_buf, {
            "Params: " .. params,
        })
    end

    chase.buf_append(chase_buf, { "" })

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

--- Initializes the Zig runner by detecting the binary and its version.
function M.setup_project()
    vim.fn.jobstart(
    { "which", "zig" },
    {
        stdout_buffered = true,
        on_stdout = function(_, which_data)
            local bin = vim.fn.join(which_data, "")
            if bin ~= "" then
                M.zig_bin = bin
                vim.fn.jobstart(
                { M.zig_bin, "version" },
                {
                    stdout_buffered = true,
                    on_stdout = function(_, version_data)
                        M.zig_version = vim.fn.join(version_data, "")
                    end,
                })
            end
        end,
    })
end

return M
