local M =  {
}

M.config = {
    go = {
        enabled = true,
    },
    python = {
        enabled = true,
        venvs_dir = vim.fs.normalize("~/venvs"),
    },
}

return M
