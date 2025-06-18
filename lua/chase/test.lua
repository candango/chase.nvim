local chase = require("chase")
local Path = require("plenary.path")

-- Add ci treesitter to runtimepath
vim.opt.runtimepath:append(vim.fn.expand("./nvim-treesitter"))

-- Add lazy treesitter to runtimepath
vim.opt.runtimepath:append(vim.fn.expand("~/.local/share/nvim/lazy/nvim-treesitter"))

local M =  {
}

M.original_path = ""

--- Creates a hidden buffer and loads the contents of a file into it.
--- The buffer is created as unlisted and scratch, meaning it won’t appear
--- in buffer lists and is temporary. Useful for processing file contents
--- without displaying them.
---
--- @param filepath string The path to the file to load. Can be absolute or
--- relative.
--- @return number, number buf The buffer number if successful, or nil if the
--- filepath is invalid, unreadable, or buffer creation fails.
function M.create_buffer_from_file(filepath)
    if not filepath or filepath == "" then
        return -1, -1
    end
    if not vim.fn.filereadable(filepath) then
        return -1, -1
    end

    local buf = vim.api.nvim_create_buf(true, true)
    if buf == 0 then
        return -1, -1
    end
    vim.api.nvim_buf_set_name(buf, filepath)

    local lines = vim.fn.readfile(filepath)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = 50,
        height = 10,
        col = 1,
        row = 1,
    })
    return buf, win
end

--- Destroys a buffer by its buffer number, if it exists and is valid.
--- Silently succeeds if the buffer is already deleted or invalid, ensuring
--- safe cleanup.
--- Intended for use in testing or temporary buffer management.
---
--- @param buf number The buffer number to destroy. Must be a valid buffer ID.
--- @return boolean result True if the buffer was successfully destroyed or
--- didn’t exist, false if deletion failed.
function M.destroy_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return true -- Treat invalid or non-existent as "already handled"
    end

    local success, _ = pcall(function()
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    if not success then
        return false
    end

    return true
end

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
