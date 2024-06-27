local chase = require("chase")
local go = require("chase.go")
local test = require("chase.test")

describe("Chase Go", function()
    local path = vim.fn.getcwd()
    it(path .. " isn't a go project", function()
        assert.are.False(go.is_go_project())
    end)
    path = vim.fn.join(
        { vim.fn.getcwd(), "tests", "fixtures", "go", "go_project"}, chase.sep)
    it(path .. " is a go project", function()
        test.setup_project(path)
        assert.are.True(go.is_go_project())
    end)
end)
