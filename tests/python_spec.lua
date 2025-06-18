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
