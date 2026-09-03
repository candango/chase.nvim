local chase = require("chase")

--- @class ChaseGo : Chaser
local M = {}

--- @type string
--- Prefix for the output buffer name.
M.buf_name_prefix = "ChaseGo: "

--- @type string|nil
--- Path to the Go binary.
M.go_bin = nil

--- @type string|nil
--- Architecture of the installed Go (e.g., amd64, arm64).
M.go_arch = nil

--- @type string|nil
--- Current Go version string.
M.go_version = nil

--- @type string
--- The file pattern to match for Go files.
M.pattern = "*.go"

-- Query for top-level tests
local test_query = vim.treesitter.query.get("go", "top_level_test")

-- Query for top-level benchmarks
local benchmark_query = vim.treesitter.query.get("go", "top_level_benchmark")

-- Query for t.Run subtests
local subtest_query = vim.treesitter.query.get("go", "subtest")

--- Returns the configured Go build tags as a comma-separated string.
--- @return string tags The configured build tags.
function M.get_build_tags()
    local tags = chase.config.chasers.go.build_tags or {}
    if type(tags) == "string" then
        return tags
    end
    if type(tags) ~= "table" then
        return ""
    end
    return table.concat(tags, ",")
end

--- Returns the shell-safe command-line argument for configured build tags.
--- @return string argument The -tags argument, or an empty string.
function M.get_build_tags_arg()
    local tags = M.get_build_tags()
    if tags == "" then
        return ""
    end
    return vim.fn.shellescape("-tags=" .. tags)
end

--- Returns the package path containing a Go source file.
--- @param file string The absolute path to the Go file.
--- @return string package_path A package path relative to the project root.
function M.get_package_path(file)
    local package_dir = vim.fn.fnamemodify(file, ":h")
    local relative_package = vim.fs.relpath(
        chase.project_root.filename,
        package_dir
    )
    if not relative_package or relative_package == "." then
        return "."
    end
    return "./" .. relative_package:gsub("\\\\", "/")
end

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

--- Retrieves a table of top-level Go benchmark function names from a buffer.
--- @param buf number The buffer number to analyze.
--- @return table benchmarks A table of benchmark function names.
function M.benchmarks_in_buffer(buf)
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
    local benchmarks = {}
    for _, node, _ in benchmark_query:iter_captures(tree:root(), buf, 0, -1) do
        local name = vim.treesitter.get_node_text(node, buf)
        if name:match("^Benchmark") then
            table.insert(benchmarks, name)
        end
    end
    return benchmarks
end

--- Checks if the cursor is inside a top-level Go benchmark.
--- @param buf number The buffer number to analyze.
--- @return boolean result True when the cursor is inside a benchmark.
function M.benchmark_under_cursor(buf)
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return false
    end
    local parser = vim.treesitter.get_parser(buf, "go")
    if not parser then
        return false
    end
    local tree = parser:parse()[1]
    if not tree then
        return false
    end
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1
    for _, match, _ in benchmark_query:iter_matches(tree:root(), buf) do
        local body_node = match[4]
        if type(body_node) == "table" then
            body_node = body_node[1]
        end
        local start_row, _, end_row, _ = body_node:range()
        if row >= start_row and row <= end_row then
            return true
        end
    end
    return false
end

--- Identifies the benchmark under the cursor.
--- @param buf number The buffer number to analyze.
--- @return string filter A string suitable for go test -bench.
function M.where_am_i_benchmark(buf)
    local all_benchmarks = M.benchmarks_in_buffer(buf)
    for i, name in ipairs(all_benchmarks) do
        all_benchmarks[i] = "^" .. name .. "$"
    end
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return ""
    end
    local parser = vim.treesitter.get_parser(buf, "go")
    if not parser then
        return ""
    end
    local tree = parser:parse()[1]
    if not tree then
        return ""
    end
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1
    local benchmarks = {}
    for _, match, _ in benchmark_query:iter_matches(tree:root(), buf) do
        local func_node = match[1]
        local body_node = match[4]
        if type(func_node) == "table" then
            func_node = func_node[1]
        end
        if type(body_node) == "table" then
            body_node = body_node[1]
        end
        local start_row, _, end_row, _ = body_node:range()
        if row >= start_row and row <= end_row then
            local name = vim.treesitter.get_node_text(func_node, buf)
            table.insert(benchmarks, name)
        end
    end
    if #benchmarks == 0 then
        return table.concat(all_benchmarks, "|")
    end
    for i, name in ipairs(benchmarks) do
        benchmarks[i] = "^" .. name .. "$"
    end
    return table.concat(benchmarks, "|")
end

--- Identifies the test or subtest under the cursor.
--- @param buf number The buffer number to analyze.
--- @return string filter A string suitable for `go test -run` (e.g., "^TestFoo$" or "^TestFoo$/^SubTest$").
function M.where_am_i(buf)
    local all_tests = M.tests_in_buffer(buf)
    for i, nome in ipairs(all_tests) do
        all_tests[i] = "^" .. nome ..  "$"
    end
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return ""
    end
    local parser = vim.treesitter.get_parser(buf, "go")
    if not parser then
        return ""
    end
    local tree = parser:parse()[1]
    if not tree then
        return ""
    end
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1
    local tests = {}
    for _, match, _ in test_query:iter_matches(tree:root(), buf) do
        local func_node = match[1] -- @func_node TSNode[1]
        local body_node = match[4] -- @body_node TSNode[4]
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

--- Checks if the buffer contains a main function.
--- @param buf_number number The buffer number to check.
--- @return boolean result True if `func main()` is found.
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

--- Validates if the current directory is a Go project.
--- @return boolean result True if go.mod exists.
function M.is_project_valid()
    if chase.project_root:joinpath("go.mod"):exists() then
        return true
    end
    return false
end

--- Runs the package containing the given Go file or its tests.
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
    local testing = file:match("_test.go$")
    if not testing then
        testing = file:match("test_.*.go$")
    end
    local benchmark = testing and M.benchmark_under_cursor(buf)
    chase.buf_clear(chase_buf)
    local action = "Running "
    if benchmark then
        action = "Benchmarking "
    elseif testing then
        action = "Testing "
    end
    chase.buf_append(chase_buf, {
        "Candango Chase",
        action .. relative_file,
    })

    local build_tags_arg = M.get_build_tags_arg()
    local package_path = M.get_package_path(file)
    local go_args = "run"
    if build_tags_arg ~= "" then
        go_args = go_args .. " " .. build_tags_arg
    end
    local go_execution = M.go_bin
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
        local where_am_i
        if benchmark then
            where_am_i = M.where_am_i_benchmark(buf)
        else
            where_am_i = M.where_am_i(buf)
        end
        if where_am_i ~= "" then
            chase.buf_append(chase_buf, {
                "Location: " .. where_am_i,
            })
        end
        go_args = "test"
        if build_tags_arg ~= "" then
            go_args = go_args .. " " .. build_tags_arg
        end
        if benchmark then
            go_args = go_args .. " -v ./... -run='^$' -bench='" .. where_am_i .. "'"
        else
            go_args = go_args .. " -v ./... -run='" .. where_am_i .. "'"
        end
        go_execution = "CGO_ENABLED=0 " .. M.go_bin ..  " clean -testcache && " .. go_execution
    end

    chase.buf_append(chase_buf, {
        "Go: " .. M.go_bin,
        "Version: " .. M.go_version,
    })

    if M.get_build_tags() ~= "" then
        chase.buf_append(chase_buf, {
            "Build tags: " .. M.get_build_tags(),
        })
    end

    if params ~= "" then
        chase.buf_append(chase_buf, { "Params: " .. params })
    end

    chase.buf_append(chase_buf, {
        "",
        "",
    })

    local cmd_list = { go_execution, go_args }
    if not testing then
        cmd_list[#cmd_list+1] = package_path
        if params ~= "" then
            cmd_list[#cmd_list+1] = params
        end
    elseif params ~= "" then
        cmd_list[#cmd_list+1] = "--"
        cmd_list[#cmd_list+1] = params
    end

    chase.run_command( table.concat(cmd_list, " "), chase_buf,
    {
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
            chase.buf_stream(chase_buf, filtered_data)
        end,
    })
end

--- Initializes the Go runner by detecting the binary and its version.
function M.setup_project()
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
            M.tidy_and_restart()
        end,
    })
end

--- Runs `go mod tidy` and restarts LSPs.
function M.tidy_and_restart()
    chase.log.info("Running go mod tidy...")
    vim.fn.jobstart({ M.go_bin or "go", "mod", "tidy" }, {
        on_exit = function(_, code)
            if code == 0 then
                chase.log.info("go mod tidy complete. Restarting LSP...")
                local clients = vim.lsp.get_clients({ bufnr = 0 })
                if #clients == 0 then
                    chase.log.info("No LSP clients attached to current buffer")
                    return
                end
                if vim.fn.has("nvim-0.12") == 1 then
                    vim.cmd("lsp restart")
                    return
                end
                vim.cmd("LspRestart")
            else
                chase.log.error("go mod tidy failed with code " .. code)
            end
        end
    })
end

return M
