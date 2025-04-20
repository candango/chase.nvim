local chase = require("chase")

local M = {}

M.buf_name_prefix = "ChaseGo: "

M.setup_called = false
M.vim_did_enter = false

M.go_bin = nil
M.go_arch = nil
M.go_version = nil

-- Query for top-level tests
local test_query = vim.treesitter.query.parse("go", [[
    (function_declaration
        name: (identifier) @func.name
        parameters: (parameter_list
            (parameter_declaration
                type: (pointer_type
                    (qualified_type
                        package: (package_identifier) @pkg
                        name: (type_identifier) @type))))
        (#match? @func.name "^Test")
        (#eq? @pkg "testing")
        (#eq? @type "T")) @func.def
]])

-- Query for t.Run subtests
local subtest_query = vim.treesitter.query.parse("go", [[
    (call_expression
        function: (selector_expression
            operand: (identifier) @t
            field: (field_identifier) @method
            (#eq? @t "t")
            (#eq? @method "Run"))
        arguments: (argument_list
            (interpreted_string_literal
               (interpreted_string_literal_content) @subtest.name) 
            (func_literal
                parameters: (parameter_list
                    (parameter_declaration
                        type: (pointer_type
                            (qualified_type
                                package: (package_identifier) @pkg
                                name: (type_identifier) @type))))
                )) @call_exp
        (#eq? @pkg "testing")
        (#eq? @type "T"))
]])

--- Retrieves a table of top-level Go test function names from a buffer using
--- Tree-sitter. Only includes functions matching the pattern
--- `TestXxx(t *testing.T)` defined at the top level of the file. Subtests
--- within `t.Run` calls are excluded. The buffer must contain valid Go code
--- and have the Go Tree-sitter parser available.
--- Returns empty table if buffer is invalid, unloaded, or no tests are found.
---
--- @param buf number The buffer number to analyze.
--- @return table table A table of top-level test function names (e.g., {"TestFoo", "TestBar"}). 
function M.tests_in_buffer(buf)
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return {}
    end
    local parser = vim.treesitter.get_parser(buf, "go")
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
        if name:match("^Test") then
           table.insert(tests, name)
        end
    end
    return tests
end

function M.where_am_i(buf)
    local all_tests = M.tests_in_buffer(buf)
    for i, nome in ipairs(all_tests) do
        all_tests[i] = "^" .. nome ..  "$"
    end
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return {}
    end
    local parser = vim.treesitter.get_parser(buf, "go")
    if not parser then
        return {}
    end
    local tree = parser:parse()[1]
    if not tree then
        return {}
    end
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1
    local tests = {}
    for _, match, _ in test_query:iter_matches(tree:root(), buf) do
        local func_node = match[1] -- @func.name TSNode[1]
        local body_node = match[4] -- @func.body TSNode[4]
        if type(func_node) == "table" then
            func_node = func_node[1]
        end
        if type(body_node) == "table" then
            body_node = body_node[1]
        end
        local start_row, _, end_row, _ = body_node:range()
        if row >= start_row  and row <= end_row then
            local name = vim.treesitter.get_node_text(func_node, buf)
            table.insert(tests, name)
        end
    end
    if #tests == 0 then
        return table.concat(all_tests, "|")
    end
    for _, match, _ in subtest_query:iter_matches(tree:root(), buf) do
        local func_node = match[3] -- @func.name TSNode
        local body_node = match[6] -- @func.body TSNode
        if type(func_node) == "table" then
            func_node = func_node[1]
        end
        if type(body_node) == "table" then
            body_node = body_node[1]
        end
        local start_row, _, end_row, _ = body_node:range()
        if row >= start_row  and row <= end_row then
            local name = vim.treesitter.get_node_text(func_node, buf)
            name = string.gsub(name, " ", "_")
            table.insert(tests, name)
        end
    end
    for i, nome in ipairs(tests) do
        tests[i] = "^" .. nome ..  "$"
    end
    return table.concat(tests, "/")
end

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
        local where_am_i  = M.where_am_i(buf)
        if where_am_i ~= "" then
            chase.buf_append(chase_buf, {
                "Location: " .. where_am_i,
            })
        end
        go_args = "test -v ./... -run='" .. where_am_i .. "'"
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
            local filtered_data = {}
            local no_tests_to_run = false
            for _, line in ipairs(data) do
                if string.match(line, "no tests to run") then
                    no_tests_to_run = true
                end
                if not string.match(line, "no test") and not string.match(line, "%(cached%)") then
                    if no_tests_to_run and line == "PASS" then
                        no_tests_to_run = false
                        goto continue
                    end
                    no_tests_to_run = false
                    table.insert(filtered_data, line)
                end
                ::continue::
            end
            chase.buf_append(chase_buf, filtered_data)
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
