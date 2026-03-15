local chase = require("chase")
local Config = require("chase.config")

describe("Chase Config Logic", function ()

    before_each(function ()
        chase.config = vim.deepcopy(Config.defaults)
    end)

    it("should keep defaults when setup is empty", function ()
        chase.setup({})
        assert.are.same(Config.defaults, chase.config)
    end)

    it("should overwrite specific global settings", function ()
        chase.setup({ global = { log_level = "error" } })
        -- Log level was set to "error"
        assert.are.equal("error", chase.config.global.log_level)
        -- Save on run keeps true
        assert.are.equal(true, chase.config.global.save_on_run)
    end)

    it("should merge runner-specific settings deeply", function ()
        chase.setup({
            chasers = {
                go = { enabled = false },
            },
        })
        -- Go was disabled
        assert.are.equal(false, chase.config.chasers.go.enabled)
        -- Python keeps enabled
        assert.are.equal(true, chase.config.chasers.python.enabled)
    end)

    it("should allow custom chasers", function ()
        chase.setup({
            chasers = {
                ["my-cool-runner"] = { enabled = true, module = "test.mock" },
            },
        })
        assert.is_not_nil(chase.config.chasers["my-cool-runner"])
        assert.are.equal("test.mock", chase.config.chasers["my-cool-runner"].module)
    end)
end)
