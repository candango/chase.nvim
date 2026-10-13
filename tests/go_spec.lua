local chase = require("chase")
local test = require("chase.test")
local go = require("chase.chasers.go")
local Path = require("plenary.path")

describe("Chase Go", function()
    local path = vim.fn.getcwd()
    it(path .. " isn't a go project", function()
        assert.are.False(go.is_project_valid())
    end)
    path = vim.fn.join(
        { vim.fn.getcwd(), "tests", "fixtures", "go", "go_project"}, chase.sep)
    it(path .. " is a go project", function()
        test.setup_project(path)
        assert.are.True(go.is_project_valid())
    end)
end)

describe("Build tags", function()
    local original_config
    local original_project_root

    before_each(function()
        original_config = chase.config
        original_project_root = chase.project_root
        chase.config = vim.deepcopy(chase.config)
        chase.config.chasers.go.build_tags = {}
    end)

    after_each(function()
        chase.config = original_config
        chase.project_root = original_project_root
    end)

    it("does not add a tags argument by default", function()
        assert.are.equal("", go.get_build_tags())
        assert.are.equal("", go.get_build_tags_arg())
    end)

    it("formats configured tags for Go", function()
        chase.config.chasers.go.build_tags = { "unit", "component" }

        assert.are.equal("unit,component", go.get_build_tags())
        assert.are.equal(
            vim.fn.shellescape("-tags=unit,component"),
            go.get_build_tags_arg()
        )
    end)

    it("uses the package directory instead of the source file", function()
        local root = vim.fn.getcwd()
        local file = vim.fn.join({
            root, "tests", "fixtures", "go", "go_project",
            "toplevel_test.go",
        }, chase.sep)
        chase.project_root = Path:new(root)

        assert.are.equal(
            "./tests/fixtures/go/go_project",
            go.get_package_path(file)
        )
    end)
end)

describe("Execution environment", function()
    local benchmark_file = vim.fn.join({
        vim.fn.getcwd(), "tests", "fixtures", "go", "go_project",
        "benchmark_test.go",
    }, chase.sep)

    it("stores free-form environment input per source buffer", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local original_input = vim.ui.input
        local prompt

        vim.ui.input = function(opts, callback)
            prompt = opts
            callback("PORT=8080 DEBUG=true")
        end

        local ok, err = pcall(chase.buf_env_edit, buf)
        vim.ui.input = original_input

        assert.is_true(ok, err)
        assert.are.equal("Chase Env: ", prompt.prompt)
        assert.are.equal("PORT=8080 DEBUG=true", chase.buf_envs[buf])

        chase.buf_env_clear(buf)
        assert.is_nil(chase.buf_envs[buf])
        test.destroy_buffer(buf)
    end)

    it("places environment text before the Go command and parameters after it", function()
        local buf, win = test.create_buffer_from_file(benchmark_file)
        assert.is_true(buf > 0)

        local original_run_command = chase.run_command
        local original_params = chase.buf_params
        local original_envs = chase.buf_envs
        local original_go_bin = go.go_bin
        local original_go_version = go.go_version
        local command

        chase.buf_params = { [buf] = "--verbose" }
        chase.buf_envs = { [buf] = "PORT=8080 DEBUG=true" }
        chase.run_command = function(cmd)
            command = cmd
        end
        go.go_bin = "go"
        go.go_version = "test"

        vim.api.nvim_win_set_cursor(win, { 1, 0 })
        go.run_file(benchmark_file)

        chase.run_command = original_run_command
        chase.buf_params = original_params
        chase.buf_envs = original_envs
        go.go_bin = original_go_bin
        go.go_version = original_go_version
        chase.destroy_my_chase(buf)
        assert.is_true(test.destroy_buffer(buf))

        assert.is_not_nil(command:find("CGO_ENABLED=0 PORT=8080 DEBUG=true ", 1, true))
        assert.is_not_nil(command:find("go test", 1, true))
        assert.are.equal("-- --verbose", command:sub(-string.len("-- --verbose")))
    end)
end)

describe("Benchmarks", function()
    local benchmark_file = vim.fn.join({
        vim.fn.getcwd(), "tests", "fixtures", "go", "go_project",
        "benchmark_test.go",
    }, chase.sep)

    it("detects the benchmark under the cursor", function()
        local buf, win = test.create_buffer_from_file(benchmark_file)
        assert.is_true(buf > 0)

        vim.api.nvim_win_set_cursor(win, { 6, 0 })
        assert.are.same({ "BenchmarkTopLevel" }, go.benchmarks_in_buffer(buf))
        assert.is_true(go.benchmark_under_cursor(buf))
        assert.are.equal(
            "^BenchmarkTopLevel$",
            go.where_am_i_benchmark(buf)
        )

        vim.api.nvim_win_close(win, true)
        assert.is_true(test.destroy_buffer(buf))
    end)

    it("runs all benchmarks when the file has no tests", function()
        local buf, win = test.create_buffer_from_file(benchmark_file)
        assert.is_true(buf > 0)

        local original_run_command = chase.run_command
        local original_go_bin = go.go_bin
        local original_go_version = go.go_version
        local command
        chase.run_command = function(cmd)
            command = cmd
        end
        go.go_bin = "go"
        go.go_version = "test"

        vim.api.nvim_win_set_cursor(win, { 1, 0 })
        go.run_file(benchmark_file)

        chase.run_command = original_run_command
        go.go_bin = original_go_bin
        go.go_version = original_go_version
        chase.destroy_my_chase(buf)
        assert.is_true(test.destroy_buffer(buf))

        assert.are.equal(
            "CGO_ENABLED=0 go clean -testcache && CGO_ENABLED=0 go test -v ./... " ..
                "-run='^$' -bench='^BenchmarkTopLevel$'",
            command
        )
    end)
end)

describe("Check in", function()
    local toplevel_test = vim.fn.join({
        vim.fn.getcwd(), "tests", "fixtures",
        "go", "go_project", "toplevel_test.go"
    }, chase.sep)
    it(toplevel_test .. " where am I relative to cursor", function()
        local buf, win = test.create_buffer_from_file(toplevel_test)
        if buf ~= nil or buf ~= 0 then
            local i = 1
            local results = {
                "^TestTopLevel1$|^TestTopLevel2$",
                "^TestTopLevel1$",
                "^TestTopLevel1$",
                "^TestTopLevel1$",
                "^TestTopLevel1$|^TestTopLevel2$",
                "^TestTopLevel2$",
                "^TestTopLevel2$",
                "^TestTopLevel1$|^TestTopLevel2$",
                "^TestTopLevel1$|^TestTopLevel2$",
            }
            for j = 4, 12 do
                vim.api.nvim_win_set_cursor(win, {j, 0})
                local where_am_i = go.where_am_i(buf)
                assert.are.equal(results[i], where_am_i)
                i = i + 1
            end
        end
    end)
end)
