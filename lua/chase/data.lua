local M =  {
}

M.config = {
    go = {
        enabled = false,
    },
    python = {
        enabled = true,
        venvs_dir = vim.fs.normalize("~/venvs"),
    },
}

return M
