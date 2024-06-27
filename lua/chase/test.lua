local chase = require("chase")
local Path = require("plenary.path")

local M =  {
}

M.original_path = ""

function M.setup_project(path)
    M.original_path = chase.project_root
    chase.project_root = Path:new(path)
end

function M.reset_project()
    if M.original_path ~= "" then
        chase.project_root = M.original_path
        M.original_path = ""
    end
end

return M
