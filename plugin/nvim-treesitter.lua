if vim.g.loaded_nvim_treesitter then
  return
end
vim.g.loaded_nvim_treesitter = true

-- setup modules
require("nvim-treesitter").setup({
    ensure_installed = {
        "go",
        "lua",
        "python",
    },
})
