local popup = require("plenary.popup")

-- print(vim.inspect(popup))
-- print(vim.inspect(vim.fn.std ospath("data")))

local width = 60
local height = 10

local bufnr = vim.api.nvim_create_buf(false, false)
local borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }

local win_id, win = popup.create(bufnr, {
    title = "Chase",
    highlight = "HarpoonWindow",
    line = math.floor(((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
    minwidth = width,
    minheight = height,
    borderchars = borderchars,
})

vim.api.nvim_win_set_option(
    win.border.win_id,
    "winhl",
    "ColorColumn"
)

