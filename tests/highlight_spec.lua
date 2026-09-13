local chase = require("chase")
local test = require("chase.test")

--- Collects { row, col, end_col, group } for every chase extmark in a buffer.
--- @param buf number
--- @return table[]
local function marks(buf)
    local result = {}
    local extmarks = vim.api.nvim_buf_get_extmarks(
        buf, chase.ns, 0, -1, { details = true }
    )
    for _, mark in ipairs(extmarks) do
        table.insert(result, {
            row = mark[2],
            col = mark[3],
            end_col = mark[4].end_col,
            group = mark[4].hl_group,
        })
    end
    return result
end

--- Returns the highlight groups found on a given row.
--- @param buf number
--- @param row number
--- @return string[]
local function groups_on(buf, row)
    local result = {}
    for _, mark in ipairs(marks(buf)) do
        if mark.row == row then
            table.insert(result, mark.group)
        end
    end
    return result
end

describe("Chase highlight groups", function()
    it("are defined as defaults", function()
        for _, name in ipairs({
            "ChaseTitle", "ChaseAction", "ChaseFile", "ChaseInfo",
            "ChaseError", "ChaseWarning", "ChaseSuccess", "ChaseLocation",
            "ChaseLocationExternal",
        }) do
            local hl = vim.api.nvim_get_hl(0, { name = name })
            assert.is_not_nil(hl.link, name .. " should link to a base group")
        end
    end)
end)

describe("Chase buf_header", function()
    local buf

    before_each(function()
        buf = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
        test.destroy_buffer(buf)
    end)

    it("highlights title, action and file", function()
        chase.buf_header(buf, "Testing ", "pkg/thing_test.go")

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.are.same({ "Candango Chase", "Testing pkg/thing_test.go" }, lines)

        local found = marks(buf)
        assert.are.equal(3, #found)
        assert.are.same(
            { row = 0, col = 0, end_col = #"Candango Chase", group = "ChaseTitle" },
            found[1]
        )
        assert.are.same(
            { row = 1, col = 0, end_col = #"Testing ", group = "ChaseAction" },
            found[2]
        )
        assert.are.same(
            { row = 1, col = #"Testing ", end_col = #"Testing pkg/thing_test.go", group = "ChaseFile" },
            found[3]
        )
    end)

    it("computes rows from the buffer when appended later", function()
        chase.buf_append(buf, { "previous", "run" })
        chase.buf_header(buf, "Running ", "main.go")

        assert.are.same({ "ChaseTitle" }, groups_on(buf, 2))
        assert.are.same({ "ChaseAction", "ChaseFile" }, groups_on(buf, 3))
    end)
end)

describe("Chase buf_info", function()
    local buf

    before_each(function()
        buf = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
        test.destroy_buffer(buf)
    end)

    it("highlights only the key of Key: value lines", function()
        chase.buf_info(buf, {
            "Go: /usr/bin/go",
            "Build tags: unit,component",
            "",
            "plain text",
        })

        local found = marks(buf)
        assert.are.equal(2, #found)
        assert.are.same(
            { row = 0, col = 0, end_col = #"Go:", group = "ChaseInfo" },
            found[1]
        )
        assert.are.same(
            { row = 1, col = 0, end_col = #"Build tags:", group = "ChaseInfo" },
            found[2]
        )
    end)
end)

describe("Chase output_group", function()
    it("maps well-known lines to highlight groups", function()
        assert.are.equal("ChaseError", chase.output_group("--- FAIL: TestX (0.00s)"))
        assert.are.equal("ChaseSuccess", chase.output_group("--- PASS: TestX (0.00s)"))
        assert.are.equal("ChaseError", chase.output_group("FAIL\tgithub.com/x/y\t0.1s"))
        assert.are.equal("ChaseSuccess", chase.output_group("ok  \tgithub.com/x/y\t0.1s"))
        assert.are.equal("ChaseError", chase.output_group("panic: boom"))
        assert.are.equal("ChaseSuccess", chase.output_group("OK"))
        assert.are.equal("ChaseError", chase.output_group("FAILED (failures=1)"))
        assert.are.equal("ChaseError", chase.output_group("Traceback (most recent call last):"))
        assert.are.equal("ChaseSuccess", chase.output_group("test result: ok. 3 passed"))
        assert.are.equal("ChaseError", chase.output_group("test result: FAILED. 1 failed"))
        assert.are.equal("ChaseError", chase.output_group("error[E0308]: mismatched types"))
        assert.are.equal("ChaseWarning", chase.output_group("warning: unused variable"))
        assert.are.equal("ChaseError", chase.output_group("Exit: failed (code 1)"))
        assert.are.equal("ChaseError", chase.output_group("Error: PHPUnit not found."))
    end)

    it("leaves ordinary lines alone", function()
        assert.is_nil(chase.output_group("=== RUN   TestX"))
        assert.is_nil(chase.output_group("hello from chase"))
        assert.is_nil(chase.output_group(""))
        assert.is_nil(chase.output_group("    ok is not at line start"))
    end)

    it("is extensible through output_patterns", function()
        table.insert(chase.output_patterns, {
            pattern = "^CUSTOM", group = "ChaseWarning",
        })
        assert.are.equal("ChaseWarning", chase.output_group("CUSTOM line"))
        table.remove(chase.output_patterns)
        assert.is_nil(chase.output_group("CUSTOM line"))
    end)
end)

describe("Chase buf_stream highlighting", function()
    local buf

    before_each(function()
        buf = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
        test.destroy_buffer(buf)
    end)

    it("highlights matching lines once at insertion", function()
        chase.buf_stream(buf, { "=== RUN   TestX", "--- FAIL: TestX (0.00s)", "" })
        chase.buf_stream(buf, { "ok  \tpkg\t0.1s", "" })

        assert.are.same({}, groups_on(buf, 0))
        assert.are.same({ "ChaseError" }, groups_on(buf, 1))
        assert.are.same({ "ChaseSuccess" }, groups_on(buf, 2))
    end)

    it("re-applies a single mark on a welded partial line", function()
        chase.buf_stream(buf, { "--- FA" })
        assert.are.same({}, groups_on(buf, 0))

        chase.buf_stream(buf, { "IL: TestX (0.00s)", "" })
        assert.are.equal(
            "--- FAIL: TestX (0.00s)",
            vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
        )
        assert.are.same({ "ChaseError" }, groups_on(buf, 0))
        assert.are.equal(1, #marks(buf))
    end)

    it("does not weld into a header line", function()
        chase.buf_header(buf, "Running ", "main.go")
        chase.buf_append(buf, { "" })
        chase.buf_stream(buf, { "panic: boom", "" })

        assert.are.same({ "ChaseTitle" }, groups_on(buf, 0))
        assert.are.same({ "ChaseError" }, groups_on(buf, 2))
    end)
end)

describe("Chase buf_append highlighting", function()
    it("colors chase status lines", function()
        local buf = vim.api.nvim_create_buf(false, true)
        chase.buf_append(buf, { "", "Exit: failed (code 101)" })
        assert.are.same({ "ChaseError" }, groups_on(buf, 1))
        test.destroy_buffer(buf)
    end)
end)

describe("Chase Lua chaser header", function()
    local lua = require("chase.chasers.lua")
    local root = vim.fn.getcwd()

    it("colors the header on the embedded run branch", function()
        local file = vim.fn.join(
            { root, "tests", "fixtures", "lua", "hello.lua" }, chase.sep
        )
        local src_buf, win = test.create_buffer_from_file(file)
        assert.is_true(src_buf > 0)

        lua.run_file(file)

        local chase_buf = chase.buf_refs[src_buf]
        assert.is_not_nil(chase_buf)
        local lines = vim.api.nvim_buf_get_lines(chase_buf, 0, -1, false)
        assert.are.equal("Candango Chase", lines[1])
        assert.are.equal("Running tests/fixtures/lua/hello.lua", lines[2])
        assert.are.equal("Lua: nvim embedded", lines[3])
        assert.are.equal("hello from chase ", lines[6])

        assert.are.same({ "ChaseTitle" }, groups_on(chase_buf, 0))
        assert.are.same({ "ChaseAction", "ChaseFile" }, groups_on(chase_buf, 1))
        assert.are.same({ "ChaseInfo" }, groups_on(chase_buf, 2))
        assert.are.same({ "ChaseInfo" }, groups_on(chase_buf, 3))

        chase.chase_buf_destroy(chase_buf)
        pcall(vim.api.nvim_win_close, win, true)
        test.destroy_buffer(src_buf)
    end)
end)
