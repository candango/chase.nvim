local popup = require("plenary.popup")

local M =  {}

local borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }

local window_keymap = function(buf, mode, key, callback)
    vim.keymap.set(mode, key, callback, {
        buffer = buf,
    })
end

local DEFAULT_WIDTH = 60
local DEFAULT_HEIGHT = 10

local function create_floating_window(title, config, enter)
    config.width = config.width or DEFAULT_WIDTH
    config.height = config.height or DEFAULT_HEIGHT

    local border_lines = {}

    local left = borderchars[5]
    local right = borderchars[6]
    local mid_line = borderchars[1]:rep(config.width - #title - 2)
    local title_render = left .. title .. mid_line .. right
    table.insert(border_lines, title_render)

    for _=1, config.height-2 do
        table.insert(border_lines, borderchars[2] .. (" "):rep(config.width -2) .. borderchars[4])
    end

    local bottom = borderchars[8] .. borderchars[1]:rep(config.width -2) .. borderchars[7]
    table.insert(border_lines, bottom)

    if enter == nil then
        enter = false  -- Default to entering the window
    end
    -- Create a buffer
    -- false for no scratch buffer, true for no file
    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, border_lines)

    -- Create the floating window
    local win = vim.api.nvim_open_win(buf, enter, config)

    window_keymap(buf, "n", "q", function ()
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, {unload = true})
    end)

    vim.wo[win].winhl = "FloatBorder:ChaseWindowBorder"
    return { buf = buf, win = win }
end


local bufnr = vim.api.nvim_create_buf(false, false)

vim.api.nvim_set_hl(0, "ChaseWindowBorder", { bg = "NONE", ctermbg = "NONE" })

local state = {
    buf = nil,
    floats = {},
}

function M.create_popup(width, height)
    width = width or DEFAULT_WIDTH
    height = height or DEFAULT_HEIGHT

    if not state.buf then
        state.buf = vim.api.nvim_create_buf(false, false)
    end

    local win_id, win = popup.create(state.buf, {
        title = "Chase",
        highlight = "ChaseWindow",
        line = math.floor(((vim.o.lines - height) / 2) - 1),
        col = math.floor((vim.o.columns - width) / 2),
        minwidth = width,
        minheight = height,
        borderchars = borderchars,
    })

    window_keymap("n", "q", function ()
        vim.api.nvim_win_close(win_id, true)
        vim.api.nvim_buf_delete(state.buf, {unload = true})
    end)

    vim.api.nvim_set_hl(0, "ChaseWindow", {bg = "NONE"})
    vim.api.nvim_set_hl(0, "ChaseWindowBorder", {bg = "NONE"})
    vim.wo[win.border.win_id].winhl = "Normal:ChaseWindow,FloatBorder:ChaseWindowBorder"
end

local function create_window_config(width, height)
    width = width or DEFAULT_WIDTH
    height = height or DEFAULT_HEIGHT
    return {
        relative = "editor",
        width = width,
        height = height,
        style = "minimal",
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor(((vim.o.lines - height) / 2) - 1),
        zindex = 1,
    }
end

vim.api.nvim_create_user_command("ShowWindow", function()
    local _, win = create_floating_window("Tmux Sessions", create_window_config(60, 20), true)
    if win then
        window_keymap("n", "<leader> q", function ()
            vim.api.nvim_win_close(win, true)
            vim.api.nvim_buf_delete(state.buf, {unload = true})
        end)
    end

end, {})
