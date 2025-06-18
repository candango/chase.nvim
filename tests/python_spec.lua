local chase = require("chase")
local test = require("chase.test")
local python = require("chase.python")

describe("Chase Python", function()
    local path = vim.fn.getcwd()
    it(path .. " isn't a python project", function()
        assert.are.False(python.is_python_project())
    end)
    local projects = { "pyproject_toml", "setup_cfg", "setup_py"}
    for _, project in ipairs(projects) do
        test.reset_project()
        path = vim.fn.join(
            { vim.fn.getcwd(), "tests", "fixtures", "python", project},
            chase.sep
        )
        it(path .. " is a python project", function()
            test.setup_project(path)
            assert.are.True(python.is_python_project())
        end)
    end
end)

describe("Check in", function()
    local python_test = vim.fn.join({
        vim.fn.getcwd(), "tests", "fixtures",
        "python", "python_test.py"
    }, chase.sep)
    it(python_test .. " where am I relative to cursor", function()
        local buf, win = test.create_buffer_from_file(python_test)
        if buf ~= nil or buf ~= 0 then
            local i = 1
            local results = {
                "FirstTestCase",
                "FirstTestCase.test_1",
                "FirstTestCase.test_1",
                "FirstTestCase",
                "FirstTestCase.test_2",
                "FirstTestCase.test_2",
                "",
                "",
                "SecondTestCase",
                "SecondTestCase",
                "SecondTestCase.test_1",
                "SecondTestCase.test_1",
                "SecondTestCase",
                "SecondTestCase.test_2",
                "SecondTestCase.test_2",
                "",
            }
            for j = 7, 22 do
                vim.api.nvim_win_set_cursor(win, {j, 0})
                local where_am_i = python.where_am_i(buf)
                assert.are.equal(results[i], where_am_i)
                i = i + 1
            end
        end
    end)
end)
