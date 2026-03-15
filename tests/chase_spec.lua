local chase = require("chase")
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
