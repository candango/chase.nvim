vim.opt.runtimepath:append "."
package.path = package.path .. ";" .. vim.fn.expand("./nvim-treesitter/lua/?.lua")
vim.opt.runtimepath:append(vim.fn.expand("./nvim-treesitter"))
vim.cmd.runtime { "plugin/plenary.vim", bang = true }
vim.cmd.runtime { "plugin/nvim-treesitter.lua", bang = true }

vim.filetype.add {
  extension = {
    conf = "hocon",
    cmm = "t32",
    hurl = "hurl",
    ncl = "nickel",
    tig = "tiger",
    usd = "usd",
    usda = "usd",
    wgsl = "wgsl",
    w = "wing",
  },
}

vim.o.swapfile = false
vim.bo.swapfile = false

vim.cmd(":TSUpdateSync go lua python")
vim.cmd(":sleep 3")
