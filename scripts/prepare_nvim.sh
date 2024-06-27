#!/bin/bash

mkdir -p "$HOME/.config/nvim" 
mkdir -p "$HOME/.local/share/nvim" 
mkdir -p "$HOME/.local/state/nvim" 

cat <<EOF | tee "$HOME/.config/nvim/init.lua" >/dev/null 2>&1
-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
end
vim.opt.rtp:prepend(lazypath)

-- Setup lazy.nvim
require("lazy").setup({
  spec = {
    -- add your plugins here
    { "nvim-lua/plenary.nvim" }
  },
  -- automatically check for plugin updates
  checker = { enabled = true },
})
EOF
