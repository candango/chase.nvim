local chase = require("chase")
local test = require("chase.test")
local go = require("chase.go")

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

describe("Check where am I on a test relative to the buffer cursor", function()
    local toplevel_test = vim.fn.join({
        vim.fn.getcwd(), "tests", "fixtures",
        "go", "go_project", "toplevel_test.go"
    }, chase.sep)
    it(toplevel_test .. " is a go project", function()
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
