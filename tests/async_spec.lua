local Async = require("chase.async")

describe("Chase Async Core", function ()

    it("until_true should return true when condition is met", function ()
        Async.run(function ()
            local done = false

            vim.defer_fn(function() done = true  end, 200)

            return Async.until_true(function() return done end, {
                interval= 10,
                max_attempts= 50,
            })
        end, function(success, err)
            assert.are.equal(true, success)
            assert.is_nil(err)
        end)
    end)

    it("until_true should return false on timeout", function ()
        Async.run(function ()
            local never_done = false

            return Async.until_true(function() return never_done end, {
                interval= 10,
                max_attempts= 3,
            })
        end, function(success, err)
            assert.are.equal(false, success)
            assert.are.equal(err, "Max attempts reached")
        end)
    end)
end)
