local chase = require("chase")

--- @class ChaseZig : Chaser
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
local ok, test_query = pcall(vim.treesitter.query.get, "zig", "test_def")
if not ok then test_query = nil end

local ok_artifact, build_artifact_query = pcall(vim.treesitter.query.get, "zig", "build_artifact")
if not ok_artifact then build_artifact_query = nil end

--- Retrieves a table of test names from a buffer using Tree-sitter.
function M.tests_in_buffer(buf)
    if not test_query or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return {}
    end
    local parser = vim.treesitter.get_parser(buf, "zig")
    if not parser then return {} end
    local tree = parser:parse()[1]
    if not tree then return {} end
    local tests = {}
    for _, node, _ in test_query:iter_captures(tree:root(), buf, 0, -1) do
        local name = vim.treesitter.get_node_text(node, buf)
        name = name:gsub("^[\"']", ""):gsub("[\"']$", "")
        table.insert(tests, name)
    end
    return tests
end

--- Identifies the test case under the cursor.
--- @param buf number The buffer number to analyze.
--- @return string|boolean|nil result The test name (string), true if anonymous test, or nil if not in a test.
function M.where_am_i(buf)
    if not test_query or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return nil
    end
    local parser = vim.treesitter.get_parser(buf, "zig")
    if not parser then return nil end
    local tree = parser:parse()[1]
    if not tree then return nil end

    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1

    for _, match, _ in test_query:iter_matches(tree:root(), buf) do
        local captures = {}
        for id, node in pairs(match) do
            captures[test_query.captures[id]] = node
        end

        local body_node = captures["test.body"]
        if type(body_node) == "table" then body_node = body_node[1] end

        local start_row, _, end_row, _ = body_node:range()
        if row >= start_row and row <= end_row then
            local name_node = captures["test.name"]
            if name_node then
                if type(name_node) == "table" then name_node = name_node[1] end
                local name = vim.treesitter.get_node_text(name_node, buf)
                return name:gsub("^[\"']", ""):gsub("[\"']$", "")
            end
            -- Inside a test block but no name (anonymous test)
            return true
        end
    end
    return nil
end

--- Scans build.zig to find if the current file is a root source for an executable.
--- @param file string The relative path of the file to search for.
--- @return string|nil name The name of the artifact/bin if found in build.zig.
function M.find_artifact_name(file)
    local build_path = chase.project_root:joinpath("build.zig")
    if not build_path:exists() or not build_artifact_query then
        return nil
    end

    local content = build_path:read()
    local parser = vim.treesitter.get_string_parser(content, "zig")
    local tree = parser:parse()[1]

    local target_file = file:gsub("\\", "/")
    local mod_to_path = {}

    for _, match, _ in build_artifact_query:iter_matches(tree:root(), content, 0, -1) do
        local captures = {}
        for id, node in pairs(match) do
            local name = build_artifact_query.captures[id]
            local target_node = type(node) == "table" and node[1] or node
            captures[name] = vim.treesitter.get_node_text(target_node, content)
        end

        if captures["mod.name"] and captures["mod.path"] then
            mod_to_path[captures["mod.name"]] = captures["mod.path"]
        elseif captures["exe.name"] then
            local exe_name = captures["exe.name"]
            if captures["exe.path"] == target_file then
                return exe_name
            elseif captures["exe.mod_ref"] then
                if mod_to_path[captures["exe.mod_ref"]] == target_file then
                    return exe_name
                end
            end
        end
    end
    return nil
end

--- Checks if the current directory is a Zig project.
--- @return boolean result True if build.zig exists.
function M.is_project_valid()
    return chase.project_root:joinpath("build.zig"):exists()
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
    local relative_file = file:gsub(chase.project_root.filename .. chase.sep, "")
    local chase_buf = chase.buf_chase(relative_file, buf)

    local where_am_i = M.where_am_i(buf)
    local testing = where_am_i ~= nil
    local test_name = type(where_am_i) == "string" and where_am_i or nil

    local artifact_name = M.find_artifact_name(relative_file)

    chase.buf_clear(chase_buf)
    local action = testing and "Testing " or "Running "
    chase.buf_append(chase_buf, {
        "Candango Chase",
        action .. relative_file,
    })

    if test_name then
        chase.buf_append(chase_buf, { "Filter: " .. test_name })
    elseif testing then
        chase.buf_append(chase_buf, { "Mode: Anonymous Test" })
    end

    chase.buf_append(chase_buf, {
        "Zig: " .. (M.zig_bin or "zig"),
        "Version: " .. (M.zig_version or "unknown"),
        "Strategy: " .. (artifact_name and "zig build artifact" or "zig run/test (fallback)"),
    })

    local cmd_list = { M.zig_bin or "zig" }

    if testing then
        if artifact_name then
            table.insert(cmd_list, "build")
            table.insert(cmd_list, "test")
            table.insert(cmd_list, "--")
        else
            table.insert(cmd_list, "test")
            table.insert(cmd_list, file)
        end

        if test_name then
            table.insert(cmd_list, "--test-filter")
            table.insert(cmd_list, "\"" .. test_name .. "\"")
        end
    else
        if artifact_name then
            table.insert(cmd_list, "build")
            table.insert(cmd_list, "run")
            table.insert(cmd_list, "-Dbin=" .. artifact_name)
        else
            table.insert(cmd_list, "run")
            table.insert(cmd_list, file)
        end
    end

    if params ~= "" then
       table.insert(cmd_list, "--")
       table.insert(cmd_list, params)
        chase.buf_append(chase_buf, { "Params: " .. params })
    end

    chase.buf_append(chase_buf, { "", "" })

    chase.run_command(table.concat(cmd_list, " "), chase_buf)
end

--- Initializes the Zig runner by detecting the binary and its version.
function M.setup_project()
    vim.fn.jobstart({ "which", "zig" }, {
        stdout_buffered = true,
        on_stdout = function(_, which_data)
            local bin = vim.fn.join(which_data, "")
            if bin ~= "" then
                M.zig_bin = bin
                vim.fn.jobstart({ M.zig_bin, "version" }, {
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
