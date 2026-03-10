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
    php = {
        enabled = true,
        include_path = { "." },
    },
}

return M
