local chase = require("chase")
local Data = require("chase.data")

describe("Chase config", function()
    it("should keep default values", function()
        chase.setup()
        assert.are.equal(Data.config.python, chase.config.python)
    end)
    it("should keep custom values", function()
        local custom_python_path = "custom_python_path"
        chase.setup({ python = custom_python_path })
        assert.are.equal(custom_python_path, chase.config.python)
    end)
end)
