local chase = require("chase")
local test = require("chase.test")
local zig = require("chase.chasers.zig")

describe("Chase Zig Project", function()
    local root = vim.fn.getcwd()
    local zig_fixture_path = vim.fn.join({ root, "tests", "fixtures", "zig" }, chase.sep)

    before_each(function()
        test.setup_project(zig_fixture_path)
    end)

    after_each(function()
        test.reset_project()
    end)

    it("detects a valid Zig project with build.zig", function()
        assert.are.True(zig.is_project_valid())
    end)

    describe("Artifact Discovery via Treesitter", function()
        it("finds artifact name for main.zig (mapped via module)", function()
            local relative_file = "src/main.zig"
            local artifact = zig.find_artifact_name(relative_file)
            assert.are.equal("zig", artifact)
        end)

        it("finds artifact name for tool.zig (mapped directly)", function()
            local relative_file = "src/tool.zig"
            local artifact = zig.find_artifact_name(relative_file)
            assert.are.equal("tool", artifact)
        end)

        it("returns nil for standalone.zig (not in build.zig)", function()
            local relative_file = "src/standalone.zig"
            local artifact = zig.find_artifact_name(relative_file)
            assert.are.equal(nil, artifact)
        end)
    end)

    describe("Test Discovery", function()
        local main_zig = vim.fn.join({ zig_fixture_path, "src", "main.zig" }, chase.sep)
        local buf, win

        before_each(function()
            buf, win = test.create_buffer_from_file(main_zig)
        end)

        after_each(function()
            if buf and buf ~= -1 then
                test.destroy_buffer(buf)
            end
        end)

        it("identifies named tests in main.zig", function()
            if buf ~= -1 then
                local test_cases = {
                    {line = 21, expected = "simple test"},
                    {line = 28, expected = "use other module"},
                    {line = 32, expected = "fuzz example"}
                }

                for _, tc in ipairs(test_cases) do
                    vim.api.nvim_win_set_cursor(win, {tc.line + 2, 0})
                    local where_am_i = zig.where_am_i(buf)
                    assert.are.equal(tc.expected, where_am_i)
                end
            end
        end)

        it("identifies anonymous tests in main.zig", function()
            if buf ~= -1 then
                local line_count = vim.api.nvim_buf_line_count(buf)
                vim.api.nvim_win_set_cursor(win, {line_count - 1, 0})
                local where_am_i = zig.where_am_i(buf)
                assert.are.equal(true, where_am_i)
            end
        end)
    end)

    describe("Test File Detection", function()
        local function with_file(name, fn)
            local path = vim.fn.join({ zig_fixture_path, "src", name }, chase.sep)
            local buf, win = test.create_buffer_from_file(path)
            assert.is_true(buf > 0)
            vim.api.nvim_win_set_cursor(win, { 1, 0 })
            fn(path, buf)
            pcall(vim.api.nvim_win_close, win, true)
            test.destroy_buffer(buf)
        end

        it("treats test_*.zig as a test file", function()
            with_file("test_standalone.zig", function(path, buf)
                assert.is_true(zig.is_test_file(path, buf))
            end)
        end)

        it("treats a file with tests and no main as a test file", function()
            with_file("math.zig", function(path, buf)
                assert.is_false(zig.has_main(buf))
                assert.is_true(zig.is_test_file(path, buf))
            end)
        end)

        it("keeps a file with main runnable even when it has tests", function()
            with_file("main.zig", function(path, buf)
                assert.is_true(zig.has_main(buf))
                assert.is_false(zig.is_test_file(path, buf))
            end)
        end)

        it("keeps a plain main file runnable", function()
            with_file("standalone.zig", function(path, buf)
                assert.is_false(zig.is_test_file(path, buf))
            end)
        end)
    end)
end)
