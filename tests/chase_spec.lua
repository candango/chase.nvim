local chase = require("chase")
local test = require("chase.test")
local Async = require("chase.async")

describe("Chase Streamin Output", function()
    it("should append lines to buffer in realtime", function()
        local buf = vim.api.nvim_create_buf(false, true)

        local cmd = { "sh", "-c", "echo 'L1'; sleep 0.2; echo 'L2'" }

        chase.run_command(cmd, buf)

        Async.run(function ()
            Async.until_true(function ()
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                return #lines >= 1 and lines[1] == "L1"
            end, { interval = 50 })

            local lines_after_l1 = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
            assert.are.equal("L1", lines_after_l1[1])

            Async.until_true(function ()
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                return #lines >= 2 and lines[2] == "L2"
            end, { interval = 50 })

            return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        end, function (final_lines)
            assert.are.equal("L2", final_lines[2])
        end)
    end)
end)

describe("Chase raw environment execution", function()
    it("passes the environment prefix to the subprocess", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local cmd = "CHASE_E2E=present sh -c 'printf \"%s\\n\" \"$CHASE_E2E\"'"

        chase.run_command(cmd, buf)

        Async.run(function()
            Async.until_true(function()
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                return lines[1] == "present"
            end, { interval = 50 })

            return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        end, function(lines)
            assert.are.equal("present", lines[1])
            assert.is_true(test.destroy_buffer(buf))
        end)
    end)
end)

describe("Chase execution keymaps", function()
    it("exposes the execution controls with descriptions", function()
        local original_buf = vim.api.nvim_get_current_buf()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buf)

        chase.setup_chaser({
            pattern = "*.go",
            run_file = function() end,
        })

        local descriptions = {}
        for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
            descriptions[map.lhs] = map.desc
        end

        local leader = vim.g.mapleader or "\\"
        assert.are.equal("Chase: run current file or test", descriptions[leader .. "cc"])
        assert.are.equal("Chase: edit run arguments", descriptions[leader .. "caa"])
        assert.are.equal("Chase: clear run arguments", descriptions[leader .. "cax"])
        assert.are.equal("Chase: edit environment variables", descriptions[leader .. "cee"])
        assert.are.equal("Chase: clear environment variables", descriptions[leader .. "cex"])
        assert.are.equal("Chase: delete output buffer", descriptions[leader .. "q"])
        assert.is_nil(descriptions[leader .. "cd"])

        vim.api.nvim_set_current_buf(original_buf)
        assert.is_true(test.destroy_buffer(buf))
    end)
end)
