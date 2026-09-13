local chase = require("chase")
local test = require("chase.test")
local Path = require("plenary.path")

local root = vim.fn.getcwd()
local go_project = vim.fn.join(
    { root, "tests", "fixtures", "go", "go_project" }, chase.sep
)

local function groups_on(buf, row)
    local result = {}
    local extmarks = vim.api.nvim_buf_get_extmarks(
        buf, chase.ns, { row, 0 }, { row, -1 }, { details = true }
    )
    for _, mark in ipairs(extmarks) do
        table.insert(result, {
            group = mark[4].hl_group, col = mark[3], end_col = mark[4].end_col,
        })
    end
    return result
end

describe("Chase parse_location", function()
    it("reads go test package-relative output", function()
        local loc = chase.parse_location("    thing_test.go:12: expected 1, got 2")
        assert.are.same(
            { file = "thing_test.go", line = 12, col_start = 4, col_end = 20 },
            { file = loc.file, line = loc.line, col_start = loc.col_start, col_end = loc.col_end }
        )
        assert.is_nil(loc.col)
    end)

    it("reads zig diagnostics with column", function()
        local loc = chase.parse_location(
            "/usr/lib/zig/std/start.zig:697:43: error: root source file struct"
        )
        assert.are.equal("/usr/lib/zig/std/start.zig", loc.file)
        assert.are.equal(697, loc.line)
        assert.are.equal(43, loc.col)
    end)

    it("reads rust arrows", function()
        local loc = chase.parse_location("  --> src/main.rs:4:5")
        assert.are.equal("src/main.rs", loc.file)
        assert.are.equal(4, loc.line)
        assert.are.equal(5, loc.col)
    end)

    it("reads python tracebacks", function()
        local loc = chase.parse_location('  File "/tmp/pkg/mod.py", line 12, in run')
        assert.are.equal("/tmp/pkg/mod.py", loc.file)
        assert.are.equal(12, loc.line)
        assert.is_nil(loc.col)
    end)

    it("reads plenary and lua stack lines", function()
        local loc = chase.parse_location("tests/x_spec.lua:12: Expected objects to be the same.")
        assert.are.equal("tests/x_spec.lua", loc.file)
        assert.are.equal(12, loc.line)
    end)

    it("reads java stack frames", function()
        local loc = chase.parse_location("\tat com.x.Foo.bar(Foo.java:12)")
        assert.are.equal("Foo.java", loc.file)
        assert.are.equal(12, loc.line)
    end)

    it("ignores header and summary lines", function()
        assert.is_nil(chase.parse_location("Version: 0.16.0"))
        assert.is_nil(chase.parse_location("Zig: /usr/bin/zig"))
        assert.is_nil(chase.parse_location("ok  \tgithub.com/x/y\t0.1s"))
        assert.is_nil(chase.parse_location("--- FAIL: TestX (0.00s)"))
        assert.is_nil(chase.parse_location(""))
    end)
end)

describe("Chase resolve_location_file", function()
    before_each(function() test.setup_project(go_project) end)
    after_each(function() test.reset_project() end)

    it("keeps readable absolute paths", function()
        local abs = go_project .. chase.sep .. "toplevel_test.go"
        assert.are.equal(abs, chase.resolve_location_file(abs, nil))
    end)

    it("resolves project-relative paths", function()
        assert.are.equal(
            go_project .. chase.sep .. "toplevel_test.go",
            chase.resolve_location_file("toplevel_test.go", nil)
        )
    end)

    it("prefers the hint directory", function()
        assert.are.equal(
            go_project .. chase.sep .. "benchmark_test.go",
            chase.resolve_location_file("benchmark_test.go", go_project)
        )
    end)

    it("falls back to a basename search under the project root", function()
        test.setup_project(root)
        assert.are.equal(
            go_project .. chase.sep .. "toplevel_test.go",
            chase.resolve_location_file("toplevel_test.go", nil)
        )
    end)

    it("returns nil for unknown files", function()
        assert.is_nil(chase.resolve_location_file("nope_definitely_missing.go", nil))
    end)
end)

describe("Chase jump_to_location", function()
    local src_buf, src_win, chase_buf

    before_each(function()
        test.setup_project(go_project)
        local file = go_project .. chase.sep .. "benchmark_test.go"
        src_buf, src_win = test.create_buffer_from_file(file)
        chase_buf = chase.buf_chase("benchmark_test.go", src_buf)
    end)

    after_each(function()
        chase.chase_buf_destroy(chase_buf)
        pcall(vim.api.nvim_win_close, src_win, true)
        test.destroy_buffer(src_buf)
        test.reset_project()
    end)

    it("opens the file in the original window at the line", function()
        assert.is_true(chase.jump_to_location(chase_buf, "    toplevel_test.go:3: boom"))

        local buf = vim.api.nvim_win_get_buf(src_win)
        assert.are.equal(
            go_project .. chase.sep .. "toplevel_test.go",
            vim.api.nvim_buf_get_name(buf)
        )
        assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(src_win))
        test.destroy_buffer(buf)
    end)

    it("positions the cursor on the column when present", function()
        assert.is_true(chase.jump_to_location(chase_buf, "./toplevel_test.go:5:6: undefined"))
        assert.are.same({ 5, 5 }, vim.api.nvim_win_get_cursor(src_win))
        test.destroy_buffer(vim.api.nvim_win_get_buf(src_win))
    end)

    it("refuses lines without a location", function()
        assert.is_false(chase.jump_to_location(chase_buf, "--- FAIL: TestX (0.00s)"))
        assert.are.equal(src_buf, vim.api.nvim_win_get_buf(src_win))
    end)

    it("refuses locations it cannot resolve", function()
        assert.is_false(chase.jump_to_location(chase_buf, "ghost_file.go:1: nope"))
        assert.are.equal(src_buf, vim.api.nvim_win_get_buf(src_win))
    end)

    it("binds <CR> and gd in the chase buffer", function()
        local maps = vim.api.nvim_buf_get_keymap(chase_buf, "n")
        local found = {}
        for _, map in ipairs(maps) do
            found[map.lhs] = true
        end
        assert.is_true(found["<CR>"])
        assert.is_true(found["gd"])
    end)
end)

describe("Chase location highlighting", function()
    local buf

    before_each(function() buf = vim.api.nvim_create_buf(false, true) end)
    after_each(function() test.destroy_buffer(buf) end)

    it("underlines the file:line span on streamed output", function()
        chase.buf_stream(buf, { "    thing_test.go:12: expected 1, got 2", "" })
        assert.are.same(
            { { group = "ChaseLocation", col = 4, end_col = 20 } },
            groups_on(buf, 0)
        )
    end)

    it("colors compiler diagnostics and underlines their location", function()
        chase.buf_stream(buf, {
            "/usr/lib/zig/std/start.zig:697:43: error: no member named 'main'",
            "test_chase.zig:1:1: note: struct declared here",
            "src/x.zig:3:9: warning: unused",
            "Foo.java:12: error: cannot find symbol",
            "",
        })
        assert.are.equal("ChaseError", groups_on(buf, 0)[1].group)
        assert.are.equal("ChaseLocationExternal", groups_on(buf, 0)[2].group)
        assert.are.equal("ChaseInfo", groups_on(buf, 1)[1].group)
        assert.are.equal("ChaseWarning", groups_on(buf, 2)[1].group)
        assert.are.equal("ChaseError", groups_on(buf, 3)[1].group)
    end)

    it("does not underline the header file", function()
        chase.buf_header(buf, "Running ", "src/main.zig")
        chase.buf_info(buf, { "Version: 0.16.0" })
        for row = 0, 2 do
            for _, mark in ipairs(groups_on(buf, row)) do
                assert.are_not.equal("ChaseLocation", mark.group)
            end
        end
    end)
end)

describe("Chase project-first jump", function()
    local src_buf, src_win, chase_buf

    before_each(function()
        test.setup_project(go_project)
        local file = go_project .. chase.sep .. "benchmark_test.go"
        src_buf, src_win = test.create_buffer_from_file(file)
        chase_buf = chase.buf_chase("benchmark_test.go", src_buf)
    end)

    after_each(function()
        chase.chase_buf_destroy(chase_buf)
        pcall(vim.api.nvim_win_close, src_win, true)
        test.destroy_buffer(src_buf)
        test.reset_project()
    end)

    it("classifies locations without touching the filesystem", function()
        assert.is_true(chase.is_project_location(chase.parse_location("thing_test.go:3: x")))
        assert.is_true(chase.is_project_location(
            chase.parse_location(go_project .. "/toplevel_test.go:3: x")))
        assert.is_false(chase.is_project_location(
            chase.parse_location("/usr/lib/zig/std/start.zig:697:43: error: x")))
        assert.is_false(chase.is_project_location(
            chase.parse_location('  File "/usr/lib/python3.12/unittest/case.py", line 58, in x')))
    end)

    it("prefers the project note below a zig stdlib error", function()
        chase.buf_stream(chase_buf, {
            "/usr/lib/zig/std/start.zig:697:43: error: root source file struct has no member named 'main'",
            "    const fn_info = @typeInfo(@TypeOf(root.main)).@\"fn\";",
            "toplevel_test.go:5:1: note: struct declared here",
            "",
        })
        assert.is_true(chase.jump_to_location(
            chase_buf, vim.api.nvim_buf_get_lines(chase_buf, 0, 1, false)[1], 0))
        assert.are.equal(
            go_project .. chase.sep .. "toplevel_test.go",
            vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(src_win))
        )
        assert.are.same({ 5, 0 }, vim.api.nvim_win_get_cursor(src_win))
        test.destroy_buffer(vim.api.nvim_win_get_buf(src_win))
    end)

    it("prefers the project frame below go runtime frames", function()
        chase.buf_stream(chase_buf, {
            "panic: boom",
            "",
            "goroutine 1 [running]:",
            "runtime/debug.Stack()",
            "\t/usr/lib/go/src/runtime/debug/stack.go:24 +0x5e",
            "goproject.TestTopLevel1(0xc000001)",
            "\t" .. go_project .. "/toplevel_test.go:6 +0x1d",
            "",
        })
        assert.is_true(chase.jump_to_location(
            chase_buf, vim.api.nvim_buf_get_lines(chase_buf, 4, 5, false)[1], 4))
        assert.are.same({ 6, 0 }, vim.api.nvim_win_get_cursor(src_win))
        test.destroy_buffer(vim.api.nvim_win_get_buf(src_win))
    end)

    it("looks above when the project frame precedes a library frame", function()
        chase.buf_stream(chase_buf, {
            "Traceback (most recent call last):",
            '  File "' .. go_project .. '/toplevel_test.go", line 3, in run',
            '  File "/usr/lib/python3.12/unittest/case.py", line 58, in testPartExecutor',
            "AssertionError: boom",
            "",
        })
        assert.is_true(chase.jump_to_location(
            chase_buf, vim.api.nvim_buf_get_lines(chase_buf, 2, 3, false)[1], 2))
        assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(src_win))
        test.destroy_buffer(vim.api.nvim_win_get_buf(src_win))
    end)

    it("does not cross a blank line looking for project lines", function()
        local external = vim.env.VIMRUNTIME .. "/filetype.lua"
        chase.buf_stream(chase_buf, {
            external .. ":1:1: error: x",
            "",
            "toplevel_test.go:5:1: note: unrelated",
            "",
        })
        assert.is_true(chase.jump_to_location(
            chase_buf, vim.api.nvim_buf_get_lines(chase_buf, 0, 1, false)[1], 0))
        assert.are.equal(
            vim.fn.fnamemodify(external, ":p"),
            vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(src_win))
        )
        test.destroy_buffer(vim.api.nvim_win_get_buf(src_win))
    end)

    it("underlines project and external locations differently", function()
        local buf = vim.api.nvim_create_buf(false, true)
        chase.buf_stream(buf, {
            "/usr/lib/zig/std/start.zig:697:43: error: x",
            "toplevel_test.go:5:1: note: here",
            "",
        })
        assert.are.equal("ChaseLocationExternal", groups_on(buf, 0)[2].group)
        assert.are.equal("ChaseLocation", groups_on(buf, 1)[2].group)
        test.destroy_buffer(buf)
    end)
end)
