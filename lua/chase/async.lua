local a = require("plenary.async")

local M = {}

M.run = a.run
M.void = a.void
M.scheduler = a.util.scheduler

--- @class ChaseUntilTrueOpts
--- @field interval? number The time in ms between retries (default: 500).
--- @field max_attempts? number The total number of retries (default: 15).

--- Polls a condition until it returns true or max attempts are reached.
--- @param condition_func fun():boolean The check function
--- @param opts? ChaseUntilTrueOpts Table containing 'interval' and 'max_attempts'
--- @return boolean success, string|nil error
function M.until_true(condition_func, opts)
    opts = opts or {}
    local interval = opts.interval or 500
    local max_attempts = opts.max_attempts or 15
    for _ = 1, max_attempts do
        if condition_func() then
            return true
        end
        a.util.sleep(interval)
    end
    return false, "Maximum attempts reached"
end

return M
