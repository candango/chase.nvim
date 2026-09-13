local Config = require("chase.config")
local Async = require("chase.async")
local Path = require("plenary.path")
local Log = require("plenary.log")

local M =  {}

function M.is_windows()
    return string.match(vim.uv.os_uname().sysname, "Windows") ~= nil
end

M.group = vim.api.nvim_create_augroup("CANDANGO_CHASE", { clear = true })
M.sep = (function()
  if jit then
    local os = string.lower(jit.os)
    if os ~= "windows" then
      return "/"
    else
      return "\\"
    end
  else
    return package.config:sub(1, 1)
  end
end)()

M.user_home = Path:new(os.getenv("HOME"))
M.installed_python = "python"
M.global_env_done = false
M.installed_uv = nil
M.uv_installed = false

if M.is_windows() then
    M.user_home = os.getenv("UserProfile")
end

if not M.is_windows() then
    local stream = assert(io.popen('which python3', 'r'))
    local output = stream:read('*all')
    stream:close()
    if #output > 0 then
        M.installed_python = "python3"
    end
end

M.user_config_dir = Path:new(vim.fn.stdpath("data"), "chase")
M.config = Config.defaults
M.user_config_projects_file = Path:new(M.user_config_dir, "projects")
M.project_root = Path:new(vim.fn.getcwd())

--- Updates the project root and clears relevant state.
--- @param new_root string|nil The new absolute path for the project root.
function M.update_project_root(new_root)
    new_root = new_root or vim.fn.getcwd()
    M.project_root = Path:new(new_root)
    M.log.info("Project root updated to: " .. M.project_root.filename)
    -- Reset state that depends on the root
    M.buf_params = {}
end

--- Retrieves Git project information for isolation.
--- @return table info { root, parent, project, worktree }
function M.get_project_info()
    local root_list = vim.fn.systemlist("git rev-parse --show-toplevel")
    local root = root_list[1]
    if #root_list == 0 or not root or root == "" then
        root = vim.fn.getcwd()
        return {
            root = root,
            parent = vim.fn.fnamemodify(root, ":h:t"),
            project = vim.fn.fnamemodify(root, ":t"),
            worktree = nil,
        }
    end

    local common_dir_list = vim.fn.systemlist("git rev-parse --git-common-dir")
    local common_dir = common_dir_list[1]
    local is_worktree = false
    local worktree_name = nil

    if common_dir and common_dir ~= "" and common_dir ~= ".git" and common_dir ~= root .. "/.git" then
        -- It's a worktree if common-dir points elsewhere
        is_worktree = true
        worktree_name = vim.fn.fnamemodify(root, ":t")
    end

    local project_path = root
    if is_worktree then
        -- In a worktree, 'root' is the worktree path.
        -- We want the project name to be the parent directory of the worktree if it's nested,
        -- or we might need a better way to find the 'project' name.
        -- Common pattern: project/ (main) and project/worktree-name
        -- Or: project/.bare and project/master, project/feature-x
        project_path = vim.fn.fnamemodify(root, ":h")
    end

    return {
        root = root,
        parent = vim.fn.fnamemodify(project_path, ":h:t"),
        project = vim.fn.fnamemodify(project_path, ":t"),
        worktree = worktree_name,
    }
end

M.vim_did_enter = false

M.python_buf_number = -1
M.go_buf_number = -1
local log_level = os.getenv("CHASE_LOG_LEVEL") or "warn"
M.log = Log.new({
    level = log_level,
    plugin = "chase",
    use_file = true,
    outfile = vim.fn.stdpath("data") .. M.sep .. "chase.log",
    -- use_console = false,
})

M.buf_refs = {}
M.buf_win_refs = {}
M.ns = vim.api.nvim_create_namespace("chase")

--- @type table<number, string>
--- Map of buffer numbers to their respective execution parameters.
--- Key: buffer number (integer)
--- Value: parameter string (string)
M.buf_params = {}

function M.chase_it(opts)
    print(vim.inspect(opts.args))
end

function M.chase_it_complete(arg_lead, cmd_line, _) -- cursor_pos)
    local cmd_line_x = vim.fn.split(cmd_line, " ")
    local cmd_line_count = #cmd_line_x
    M.log.warn(arg_lead)
    if cmd_line_count == 1 then
        return { "mark" }
    end
    if cmd_line_count == 2 then
        return { "run" }
    end
end

local chase_it_opts = { nargs = "*", complete=M.chase_it_complete }
vim.api.nvim_create_user_command("Chase", M.chase_it, chase_it_opts)
vim.api.nvim_create_user_command("C", M.chase_it, chase_it_opts)

function M.buf_chase(file, buf)
    local chase_buf = M.buf_open(file .. "_run", buf)
    return chase_buf
end

function M.buf_is_visible(buf)
    -- Get a boolean that tells us if the buffer number is visible anymore.
    --
    -- :help bufwinnr
    buf = buf or "/"
    return vim.api.nvim_call_function("bufwinnr", { buf }) ~= -1
end

-- From: https://codereview.stackexchange.com/a/282183
function M.all_listed_buffers()
    local bufs = {}
    local count = 1
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            bufs[count] = buf
            count = count + 1
        end
    end

    return bufs
end

function M.buf_from_name(name)
    for _, buf in ipairs(M.all_listed_buffers()) do
        local listed_name = vim.api.nvim_buf_get_name(buf):gsub(
            M.project_root .. M.sep, ""
        )
        if listed_name == name then
            return buf
        end
    end
    return -1
end

function M.buf_open(name, buf, type)
    -- Get a boolean that tells us if the buffer number is visible anymore.
    --
    -- :help bufwinnr
    local chase_buf = -1
    name = name or "MONSTER_OF_THE_LAKE"
    type = type or "txt"

    local buf_from_name = M.buf_from_name(name)
    if buf_from_name ~= -1 then
        return buf_from_name
    end

    local cur_win = vim.api.nvim_get_current_win()
    if chase_buf == -1 or not M.buf_is_visible(chase_buf) then
        vim.cmd("botright vsplit " .. name)
        chase_buf = vim.api.nvim_get_current_buf()
        vim.bo[chase_buf].modifiable = true
        vim.bo[chase_buf].buftype = "nofile"
        vim.bo[chase_buf].filetype = type
        vim.bo[chase_buf].buflisted = false
        vim.api.nvim_buf_set_var(chase_buf, "original_buf", buf)
        vim.api.nvim_buf_set_keymap(chase_buf, "n", "<leader>q", "",
            {callback = function()
                M.chase_buf_destroy(chase_buf)
            end}
        )
        for _, lhs in ipairs({ "<CR>", "gd" }) do
            vim.api.nvim_buf_set_keymap(chase_buf, "n", lhs, "",
                {callback = function()
                    M.buf_jump(chase_buf)
                end, desc = "Chase: jump to the source location under the cursor"}
            )
        end
        vim.api.nvim_set_current_win(cur_win)
        M.buf_refs[buf] = chase_buf
        return chase_buf
    end
end

function M.on_buf_hidden()
    local cur_buf = vim.api.nvim_get_current_buf()
    local buf = M.buf_refs[cur_buf]
    if buf then
        M.buf_hide(buf)
    end
end

function M.chase_buf_close(buf)

end

function M.buf_is_hidden(buf)
    local win = vim.fn.bufwinid(buf)
    if win > 0 then
        return false
    end
    return true
end

function M.buf_show(buf)
    local win = vim.fn.bufwinid(buf)
    local cur_win = vim.api.nvim_get_current_win()
    if win == -1 then
        local ok = true
        -- handle when user is closing the chase buffer directly as the the
        -- states are not correct chase will try to reopen the window
        ok = pcall(function() vim.cmd("botright vsplit") end)
        if not ok then
            -- destroying the buffer and set the state correctly
            -- return to avoid reopening the buffer
            M.chase_buf_destroy(buf)
            return
        end
        win = vim.api.nvim_get_current_win()
    end
    -- set buf to current window
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(cur_win)
end

function M.buf_hide(buf)
    local win = vim.fn.bufwinid(buf)
    if win > 0 then
        local buftype = vim.bo[buf].buftype
        vim.bo[buf].buftype = ""
        vim.api.nvim_win_hide(win)
        if buftype then
            vim.bo[buf].buftype = buftype
        end
    end
end

function M.oppened_chase_buf_hide()
    for _, chase_buf in pairs(M.buf_refs) do
        if chase_buf and vim.api.nvim_buf_is_valid(chase_buf) then
            local wins = vim.fn.win_findbuf(chase_buf)
            if #wins > 0 then
                M.buf_hide(chase_buf)
            end
        end
    end
end

function M.destroy_my_chase(buf)
    for buf_ref, buf_chase in pairs(M.buf_refs) do
        if buf_ref == buf then
            M.chase_buf_destroy(buf_chase)
            break
        end
    end
end

function M.chase_clear_buf_ref(original_buf)
    local buf_refs = {}
    for buf_ref, buf_chase in pairs(M.buf_refs) do
        if buf_ref ~= original_buf then
            buf_refs[buf_ref] = buf_chase
        end
    end
    M.buf_refs = buf_refs
end

function M.chase_buf_destroy(chase_buf)
    local buf = vim.api.nvim_buf_get_var(chase_buf, "original_buf")
    M.chase_clear_buf_ref(buf)
    -- using pcall to avoid errors if buffer is already closed
    pcall(function() vim.cmd("bd " .. chase_buf) end)
end

--- Clears all lines from the specified buffer.
--- @param buf number The buffer number to clear.
function M.buf_clear(buf)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.bo[buf].modifiable = false
end

--- Appends complete lines to a buffer, ensuring they start on a new line.
--- Ideal for headers, footers, and static messages.
--- @param buf number The buffer number to append to.
--- @param lines string[] A list of strings representing complete lines.
function M.buf_append(buf, lines)
    if not lines or #lines == 0 then return end
    vim.bo[buf].modifiable = true

    local line_count = vim.api.nvim_buf_line_count(buf)
    local is_new = line_count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""

    local first_row
    if is_new then
        -- If it's a fresh buffer, don't leave an empty line at the top
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        first_row = 0
    else
        -- Append at the very end, which always creates new lines
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
        first_row = line_count
    end

    vim.bo[buf].modifiable = false
    M.buf_highlight_lines(buf, first_row, first_row + #lines)
    M.buf_scroll(buf)
end

--- Scrolls all windows displaying the specified buffer to the last line.
--- @param buf number The buffer number to scroll.
function M.buf_scroll(buf)
    local wins = vim.fn.win_findbuf(buf)
    local line_count = vim.api.nvim_buf_line_count(buf)
    for _, win in ipairs(wins) do
        pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })
    end
end

--- Applies a highlight group to a range of columns on a buffer line.
--- Uses an extmark on the chase namespace, so the highlight is stored with
--- the line and costs nothing on redraw.
--- @param buf number The buffer number.
--- @param hl_group string The highlight group name.
--- @param row number 0-indexed line number.
--- @param col_start number 0-indexed start column.
--- @param col_end number End column (-1 for end of line).
function M.buf_add_highlight(buf, hl_group, row, col_start, col_end)
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
    if not line then return end
    if col_end == -1 or col_end > #line then
        col_end = #line
    end
    if col_start >= col_end then return end
    vim.api.nvim_buf_set_extmark(buf, M.ns, row, col_start, {
        end_col = col_end,
        hl_group = hl_group,
    })
end

--- Ordered list of patterns applied to process output lines.
--- The first matching entry wins and highlights the whole line.
--- Patterns are anchored at the start of the line on purpose: they run once
--- per line at insertion time, on the main loop, so keep them cheap.
--- Chasers or users may extend this table before running.
--- @type { pattern: string, group: string }[]
M.output_patterns = {
    -- go test
    { pattern = "^%-%-%- FAIL", group = "ChaseError" },
    { pattern = "^%-%-%- PASS", group = "ChaseSuccess" },
    { pattern = "^FAIL", group = "ChaseError" },
    { pattern = "^PASS", group = "ChaseSuccess" },
    { pattern = "^ok%s", group = "ChaseSuccess" },
    { pattern = "^panic:", group = "ChaseError" },
    -- python unittest
    { pattern = "^OK", group = "ChaseSuccess" },
    { pattern = "^FAILED", group = "ChaseError" },
    { pattern = "^Traceback", group = "ChaseError" },
    -- cargo test / rustc / zig
    { pattern = "^test result: ok", group = "ChaseSuccess" },
    { pattern = "^test result: FAILED", group = "ChaseError" },
    { pattern = "^error", group = "ChaseError" },
    { pattern = "^warning", group = "ChaseWarning" },
    -- plenary
    { pattern = "^Success:", group = "ChaseSuccess" },
    { pattern = "^Failed :", group = "ChaseError" },
    { pattern = "^Errors :", group = "ChaseError" },
    -- compiler diagnostics: path:line:col: (zig, go build) and path:line: (javac)
    { pattern = "^%S+:%d+:%d+: note:", group = "ChaseInfo" },
    { pattern = "^%S+:%d+:%d+: warning:", group = "ChaseWarning" },
    { pattern = "^%S+:%d+:%d+: ", group = "ChaseError" },
    { pattern = "^%S+:%d+: error:", group = "ChaseError" },
    { pattern = "^%S+:%d+: warning:", group = "ChaseWarning" },
    -- chase itself
    { pattern = "^Exit: failed", group = "ChaseError" },
    { pattern = "^Error:", group = "ChaseError" },
}

--- Ordered list of patterns that locate a source position inside an output
--- line. Each pattern must capture the file, the line and optionally the
--- column, in that order. The first match wins. Shared by the highlight
--- scanner (underline) and by the <CR> jump in the Chase buffer.
--- @type { pattern: string }[]
M.location_patterns = {
    -- python traceback: File "/x/y.py", line 12, in foo
    { pattern = 'File "([^"]+)", line (%d+)' },
    -- generic path:line[:col] (go, zig, rust, lua, php, java)
    { pattern = "([%w%._/\\~%-]+%.%w+):(%d+):?(%d*)" },
}

--- @class ChaseLocation
--- @field file string File as written in the output line.
--- @field line number 1-indexed line.
--- @field col number|nil 1-indexed column when present.
--- @field col_start number 0-indexed start of the match in the text.
--- @field col_end number Exclusive end of the match in the text.

--- Extracts a source location from an output line.
--- @param text string The line text.
--- @return ChaseLocation|nil location Nil when no pattern matches.
function M.parse_location(text)
    for _, entry in ipairs(M.location_patterns) do
        local col_start, col_end, file, line, col = text:find(entry.pattern)
        if col_start then
            if col == "" then
                -- The optional column did not match, but the pattern may
                -- have consumed a trailing separator: end after the line.
                col_end = col_start - 1 + #file + 1 + #line
            end
            return {
                file = file,
                line = tonumber(line),
                col = tonumber(col),
                col_start = col_start - 1,
                col_end = col_end,
            }
        end
    end
    return nil
end

--- Resolves a file named in process output to an absolute readable path.
--- Tries, in order: the path as given when absolute, the hint directory,
--- the project root, and finally a basename search under the project root
--- preferring a hit inside the hint directory. Runners such as `go test`
--- print package-relative basenames, so the search is not optional.
--- @param file string The file as written in the output.
--- @param hint_dir string|nil Directory of the buffer that started the run.
--- @return string|nil path Absolute path or nil when nothing readable exists.
function M.resolve_location_file(file, hint_dir)
    local root = M.project_root and M.project_root.filename or vim.fn.getcwd()
    local candidates = {}
    if file:sub(1, 1) == "/" or file:match("^%a:[/\\]") then
        table.insert(candidates, file)
    else
        if hint_dir then
            table.insert(candidates, hint_dir .. M.sep .. file)
        end
        table.insert(candidates, root .. M.sep .. file)
    end
    for _, candidate in ipairs(candidates) do
        if vim.fn.filereadable(candidate) == 1 then
            return vim.fn.fnamemodify(candidate, ":p")
        end
    end

    local name = vim.fn.fnamemodify(file, ":t")
    local found = vim.fs.find(name, { path = root, type = "file", limit = 50 })
    if #found == 0 then
        return nil
    end
    if hint_dir then
        for _, path in ipairs(found) do
            if vim.fn.fnamemodify(path, ":h") == hint_dir then
                return vim.fn.fnamemodify(path, ":p")
            end
        end
    end
    table.sort(found, function(a, b) return #a < #b end)
    return vim.fn.fnamemodify(found[1], ":p")
end

--- Picks the window a jump should land in: the one showing the original
--- buffer, else any non-floating window that is not the Chase buffer, else
--- a new split to the left of the Chase window.
--- @param chase_buf number The Chase buffer.
--- @param original_buf number|nil The buffer that started the run.
--- @return number win Window handle.
function M.jump_target_window(chase_buf, original_buf)
    if original_buf and vim.api.nvim_buf_is_valid(original_buf) then
        local win = vim.fn.bufwinid(original_buf)
        if win ~= -1 then
            return win
        end
    end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local config = vim.api.nvim_win_get_config(win)
        if vim.api.nvim_win_get_buf(win) ~= chase_buf and config.relative == "" then
            return win
        end
    end
    local chase_win = vim.fn.bufwinid(chase_buf)
    if chase_win ~= -1 then
        vim.api.nvim_set_current_win(chase_win)
    end
    vim.cmd("leftabove vsplit")
    return vim.api.nvim_get_current_win()
end

--- Jumps from an output line to the source location it names.
--- @param chase_buf number The Chase buffer the line belongs to.
--- @param text string The output line text.
--- @return boolean jumped True when a window now shows the location.
function M.jump_to_location(chase_buf, text)
    local location = M.parse_location(text)
    if not location then
        vim.notify("Chase: no source location on this line", vim.log.levels.WARN)
        return false
    end

    local ok, original_buf = pcall(vim.api.nvim_buf_get_var, chase_buf, "original_buf")
    if not ok then original_buf = nil end
    local hint_dir = nil
    if original_buf and vim.api.nvim_buf_is_valid(original_buf) then
        local name = vim.api.nvim_buf_get_name(original_buf)
        if name ~= "" then
            hint_dir = vim.fn.fnamemodify(name, ":p:h")
        end
    end

    local path = M.resolve_location_file(location.file, hint_dir)
    if not path then
        vim.notify("Chase: cannot find " .. location.file, vim.log.levels.WARN)
        return false
    end

    local win = M.jump_target_window(chase_buf, original_buf)
    vim.api.nvim_set_current_win(win)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local line_count = vim.api.nvim_buf_line_count(0)
    local row = math.max(1, math.min(location.line, line_count))
    local col = math.max((location.col or 1) - 1, 0)
    pcall(vim.api.nvim_win_set_cursor, win, { row, col })
    return true
end

--- Keymap entry point: jumps from the line under the cursor in a Chase buffer.
--- @param chase_buf number The Chase buffer.
--- @return boolean jumped
function M.buf_jump(chase_buf)
    local text = vim.api.nvim_get_current_line()
    return M.jump_to_location(chase_buf, text)
end

--- Resolves the highlight group for a process output line.
--- @param line string The line text.
--- @return string|nil group The highlight group name or nil when no pattern matches.
function M.output_group(line)
    for _, entry in ipairs(M.output_patterns) do
        if line:find(entry.pattern) then
            return entry.group
        end
    end
    return nil
end

--- Re-scans a range of buffer rows and applies output highlights.
--- Existing chase highlights on those rows are dropped first, so a line that
--- was welded from two chunks ends up with a single mark.
--- @param buf number The buffer number.
--- @param first_row number 0-indexed first row, inclusive.
--- @param last_row number 0-indexed last row, exclusive.
function M.buf_highlight_lines(buf, first_row, last_row)
    local lines = vim.api.nvim_buf_get_lines(buf, first_row, last_row, false)
    for i, line in ipairs(lines) do
        local row = first_row + i - 1
        vim.api.nvim_buf_clear_namespace(buf, M.ns, row, row + 1)
        local group = M.output_group(line)
        if group then
            M.buf_add_highlight(buf, group, row, 0, -1)
        end
        local location = M.parse_location(line)
        if location then
            M.buf_add_highlight(
                buf, "ChaseLocation", row, location.col_start, location.col_end
            )
        end
    end
end

--- Appends the standard Chase header (title plus action line) and highlights
--- it. Rows are read from the buffer, never assumed.
--- @param buf number The buffer number.
--- @param action string The action verb, e.g. "Running " or "Testing ".
--- @param file string The project-relative file being chased.
function M.buf_header(buf, action, file)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local is_new = line_count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
    local row = is_new and 0 or line_count
    M.buf_append(buf, { "Candango Chase", action .. file })
    vim.api.nvim_buf_clear_namespace(buf, M.ns, row, row + 2)
    M.buf_add_highlight(buf, "ChaseTitle", row, 0, -1)
    M.buf_add_highlight(buf, "ChaseAction", row + 1, 0, #action)
    M.buf_add_highlight(buf, "ChaseFile", row + 1, #action, -1)
end

--- Appends "Key: value" information lines and highlights the key part.
--- Lines without a "Key:" prefix are appended untouched.
--- @param buf number The buffer number.
--- @param lines string[] Information lines.
function M.buf_info(buf, lines)
    if not lines or #lines == 0 then return end
    local line_count = vim.api.nvim_buf_line_count(buf)
    local is_new = line_count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
    local first_row = is_new and 0 or line_count
    M.buf_append(buf, lines)
    for i, line in ipairs(lines) do
        local row = first_row + i - 1
        local key = line:match("^([%w%s]+):")
        if key then
            vim.api.nvim_buf_clear_namespace(buf, M.ns, row, row + 1)
            M.buf_add_highlight(buf, "ChaseInfo", row, 0, #key + 1)
        end
    end
end

--- Streams chunks into a buffer, welding incomplete lines together.
--- Ideal for real-time process output where chunks might not end with a newline.
--- @param buf number The buffer number to stream into.
--- @param lines string[] The chunks to stream.
function M.buf_stream(buf, lines)
    if not lines or #lines == 0 then return end
    vim.bo[buf].modifiable = true
    local line_count = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ""

    local first_row
    if line_count == 1 and last_line == "" then
        -- First chunk in a clean buffer
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        first_row = 0
    elseif last_line ~= "" then
        -- Join the first chunk of the new data to the last line of the buffer
        local new_lines = { last_line .. lines[1] }
        for i = 2, #lines do table.insert(new_lines, lines[i]) end
        vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, new_lines)
        first_row = line_count - 1
    else
        -- Last line was empty (previous chunk ended with newline), append normally
        vim.api.nvim_buf_set_lines(buf, line_count - 1, -1, false, lines)
        first_row = line_count - 1
    end

    vim.bo[buf].modifiable = false
    M.buf_highlight_lines(buf, first_row, first_row + #lines)
    M.buf_scroll(buf)
end

--- Open a prompt to add or edit parameters for the current buffer.
--- @param buf number The buffer number to manage parameters for.
function M.buf_params_edit(buf)
    local current_params = M.buf_params[buf] or ""
    vim.ui.input({
        prompt = "Chase Params: ",
        default = current_params,
    }, function(input)
        if input then
            M.buf_params[buf] = input
            M.log.info("Params updated for buffer " .. buf .. ": " .. input)
        end
    end)
end

--- Clear all parameters for the current buffer.
--- @param buf number The buffer number to clear parameters for.
function M.buf_params_clear(buf)
    M.buf_params[buf] = nil
    print("Chase: Params cleared for buffer " .. buf)
end

function M.setup(config)
    config = config or {}
    M.config = vim.tbl_deep_extend("force", M.config, config)
    M.log.trace("Setting up chase")
    if os.getenv("CHASE_DEBUG_LEVEL") then
        M.log = Log.new({
            level = os.getenv("CHASE_DEBUG_LEVEL"),
            plugin = "chase",
            use_file = true,
            outfile = vim.fn.stdpath("data") .. M.sep .. "chase.log",
            -- use_console = false,
        })
    end

    if os.getenv("CHASE_HOME") then
        M.log.trace("changing user config home to " .. os.getenv("CHASE_HOME"))
        M.user_home = Path:new(os.getenv("CHASE_HOME"))
        M.user_config_dir = Path:new(M.user_home, "chase")
        M.user_config_projects_file = Path:new(
            M.user_config_dir,
            "projects"
        )
    end

    if not  M.user_config_dir:exists() then
        M.log.warn("creating user config dir: " .. M.user_config_dir.filename)
        M.user_config_dir:mkdir()
    end

    if not  M.user_config_projects_file:exists() then
        M.log.warn("creating user projects file: " ..
            M.user_config_projects_file.filename)
        M.user_config_projects_file:touch()
        local file = io.open(M.user_config_projects_file.filename, "w")
        if file == nil then
            return
        end
        file:write(vim.json.encode(M.config))
        file:close()
    end

    local file = io.open(M.user_config_projects_file.filename, "r")
    if file == nil then
        return
    end
    local config = vim.json.decode(file:read())
    file:close()
end

-- M.buf_clear(32)
-- M.buf_append(32, {"buga huga"})
-- print(vim.inspect(M.all_listed_buffers()))

-- from: https://stackoverflow.com/a/9102300/2887989
function M.get_path(file_path, sep)
    sep = sep or "/"
    return file_path:match("(.*"..sep..")")
end

function M.get_virtualenv_job(path)
    if M.uv_installed  then
        return { M.installed_uv, "venv", "--seed", "--clear", path }
    end
    return {
        M.installed_python,  "-m", "venv", "--clear",
        "--upgrade-deps", path,
    }
end

function M.check_uv()
    local uv_exepath = vim.fn.exepath("uv")
    if #uv_exepath > 0 then
        M.uv_installed = true
        M.installed_uv = uv_exepath
    end
end

function M.setup_virtualenv(venv_prefix, callback)
    local cwd_x = vim.fn.split(vim.fn.getcwd(), M.sep)
    venv_prefix = venv_prefix or cwd_x[#cwd_x]
    local venv_name = venv_prefix .. "_env"
    local venv_root = Path:new(M.config.chasers.python.venvs_dir)
    local venv_path = Path:new(venv_root, venv_name)

    if not venv_path:exists() then
        M.log.warn("virtualenv for " .. venv_prefix .. " doesn't exists")
        M.log.warn("creating virtualenv for " .. venv_prefix)
        vim.fn.jobstart(
        M.get_virtualenv_job(venv_path.filename),
        {
            stdout_buffered = true,
            on_stdout = function(_, _)
                M.log.warn("virtualenv " .. venv_prefix .. " created successfully")
                if callback ~= nil then
                    callback(venv_path)
                end
            end,
            on_exit = function(_, exit_code)
                if exit_code ~= 0 then
                    M.log.error("Failed to create virtualenv for " .. venv_prefix .. " with error: " .. exit_code)
                end
            end,
        })
        return
    end
    if callback ~= nil then
        callback(venv_path)
    end
end

function M.add_to_path(path)
    local env_path = os.getenv("PATH")
    local path_sep = ":"
    if M.is_windows() then
        path_sep = ";"
    end
    vim.cmd("let $PATH = '" .. path .. path_sep .. env_path .. "'")
end

function M.set_python_global(venv_path)
    local venv_bin = venv_path:joinpath("bin")
    local venv_host_prog = venv_bin:joinpath(M.installed_python)
    if M.is_windows() then
        venv_bin = venv_path:joinpath("Scripts")
        venv_host_prog = venv_bin:joinpath("python.exe")
    end
    -- local venv_activate = venv_bin:joinpath("activate")
    M.add_to_path(venv_bin)
    vim.cmd("let g:python3_host_prog='" .. venv_host_prog .. "'")
    M.install_package(venv_path, "build", "build[virtualenv]")
    M.install_package(venv_path, "pynvim")
    M.install_package(venv_path, "twine")
    M.install_package(venv_path, "wheel")
    M.global_env_done = true
end

function M.get_pip_command(cmd, package)
    if M.uv_installed then
        return { M.installed_uv, "pip", cmd, package }
    end
    return { M.installed_python, "-m", "pip", cmd, package }
end

function M.install_package(venv_path, package, install)
    install = install or package
    vim.fn.jobstart(
    M.get_pip_command("show", package),
    {
        on_exit = function(_, code)
            if code ~= 0 then
                M.log.warn(
                "installing " .. package .. " at venv " .. venv_path.filename
                )
                vim.fn.jobstart(
                M.get_pip_command("install", install),
                {
                    stdout_buffered = true,
                    on_stdout = function(_,_)
                        M.log.warn(
                        package .. " installed at " .. venv_path.filename ..
                        " successfully"
                        )
                    end,
                })
            end
        end,
    })
end

--- @class Chaser
--- @field pattern string The file pattern to match (e.g., "*.php", "*.go").
--- @field run_file fun(file: string) The function that executes the file or tests.
--- @field is_project_valid? fun(): boolean (Optional) Logic to detect if the runner should be active.
--- @field setup_project? fun() (Optional) Initialization logic for the runner.

--- Handles buffer entry for a specific chaser, setting up all keymaps and managing visibility.
--- @param chaser Chaser The language-specific runner module to set up.
function M.setup_chaser(chaser)
    local cur_buf = vim.api.nvim_get_current_buf()
    local keymaps = {
        {
            mode = "n",
            lhs = "<leader>cc",
            opts = { callback = function ()
                chaser.run_file(vim.api.nvim_buf_get_name(0))
            end },
        },{
            mode = "n",
            lhs = "<leader>ca",
            opts = { callback = function () M.buf_params_edit(cur_buf) end },
        },
        {
            mode = "n",
            lhs = "<leader>cd",
            opts = { callback = function () M.destroy_my_chase(cur_buf) end },
        },
        {
            mode = "n",
            lhs = "<leader>cx",
            opts = { callback = function () M.buf_params_clear(cur_buf) end },
        },
        {
            mode = "n",
            lhs = "<leader>q",
            opts = { callback = function () M.destroy_my_chase(cur_buf) end },
        },
    }
    local found, _ = pcall(
        vim.api.nvim_buf_get_var, cur_buf, "chase_keymaps_set")
    if not found then
        vim.api.nvim_buf_set_var(cur_buf, "chase_keymaps_set", true)
        for _, keymap in pairs(keymaps) do
            local mode = keymap["mode"]
            local lhs = keymap["lhs"] or ""
            local rhs = keymap["rhs"] or ""
            local opts = keymap["opts"] or {}
            vim.api.nvim_buf_set_keymap(cur_buf, mode, lhs, rhs, opts)
        end
    end
    for buf, chase_buf in pairs(M.buf_refs) do
        if buf ~= cur_buf then
            M.buf_hide(chase_buf)
        end
        if buf == cur_buf then
            if M.buf_is_hidden(chase_buf) then
                M.buf_show(chase_buf)
            end
        end
    end
end

--- Registers a new language runner (chaser).
--- @param chaser Chaser The chaser module to register.
function M.register_chaser(chaser)
    if not chaser.pattern then
        M.log.error("Chaser registration failed: 'pattern' is required.")
        return
    end

    if not chaser.run_file then
        M.log.error("Chaser registration failed: 'run_file' is required.")
        return
    end

    if chaser.is_project_valid and not chaser.is_project_valid() then
        M.log.debug("Chaser for " .. chaser.pattern .. " skipped: not a valid project.")
        return
    end

    if chaser.setup_project then
        chaser.setup_project()
    end

    vim.api.nvim_create_autocmd("BufEnter", {
        callback = function()
            M.setup_chaser(chaser)
        end,
        pattern = chaser.pattern,
        group = M.group,
    })

    vim.api.nvim_create_autocmd("BufHidden", {
        callback = M.on_buf_hidden,
        pattern = chaser.pattern,
        group = M.group,
    })
end

--- Runs a shell command for a chaser and streams output to a buffer.
--- @param cmd table|string The command to be executed.
--- @param buf number The buffer where output will be appened.
--- @param opts? table { on_stdout = func, on_stderr = func, on_exit = func }
function M.run_command(cmd, buf, opts)
    opts = opts or {}

    local default_on_stdout_stderr = function (_, data)
        if data and (data[1] ~= "" or #data > 1) then
            if M.is_windows() then
                for i, v in ipairs(data) do
                    data[i] = v:gsub("\r", "")
                end
            end
            M.buf_stream(buf, data)
        end
    end

    return vim.fn.jobstart(cmd, {
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = opts.on_stdout or default_on_stdout_stderr,
        on_stderr = opts.on_stderr or default_on_stdout_stderr,
        on_exit = opts.on_exit,
    })
end

--- Triggers a full refresh of the project state, including root detection and chasers.
function M.refresh()
    M.update_project_root()
    M.check_uv()
    -- Global venv might need a refresh too if HOME changed, but usually static
    -- M.setup_virtualenv("chase_global", M.set_python_global)

    for name, opts in pairs(M.config.chasers) do
        if opts.enabled then
            local module_path = opts.module or ("chase.chasers." .. name)
            -- Clear package from cache to allow re-registration if needed
            package.loaded[module_path] = nil
            local ok, chaser = pcall(require, module_path)
            if ok then
                if name == "python" then
                    Async.run(function()
                        local success, err = Async.until_true(
                            function() return M.global_env_done end)
                        Async.scheduler()
                        if success then
                            M.register_chaser(chaser)
                        end
                        return success, err
                    end, function (success, err)
                        if not success then
                            M.log.error("Python registration failed: " .. err)
                        end
                    end)
                else
                    M.register_chaser(chaser)
                end
            end
        end
    end
end

--- Defines the Chase highlight groups as defaults, so colorschemes and user
--- configuration can override them. Re-applied on ColorScheme because
--- `:colorscheme` clears every group.
function M.setup_highlights()
    vim.api.nvim_set_hl(0, "ChaseWindow",  { link = "NormalFloat",    default = true })
    vim.api.nvim_set_hl(0, "ChaseBorder",  { link = "FloatBorder",    default = true })
    vim.api.nvim_set_hl(0, "ChaseTitle",   { link = "Title",          default = true })
    vim.api.nvim_set_hl(0, "ChaseAction",  { link = "Keyword",        default = true })
    vim.api.nvim_set_hl(0, "ChaseFile",    { link = "Directory",      default = true })
    vim.api.nvim_set_hl(0, "ChaseInfo",    { link = "Comment",        default = true })
    vim.api.nvim_set_hl(0, "ChaseError",   { link = "DiagnosticError", default = true })
    vim.api.nvim_set_hl(0, "ChaseWarning", { link = "DiagnosticWarn",  default = true })
    vim.api.nvim_set_hl(0, "ChaseSuccess", { link = "DiagnosticOk",    default = true })
    vim.api.nvim_set_hl(0, "ChaseLocation", { link = "Underlined",     default = true })
end

M.setup_highlights()

vim.api.nvim_create_autocmd("ColorScheme", {
    callback = M.setup_highlights,
    group = M.group,
})

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function ()
        M.setup_highlights()
        M.vim_did_enter = true
        M.setup_virtualenv("chase_global", M.set_python_global)
        M.refresh()
    end,
    group = M.group,
})

vim.api.nvim_create_autocmd("DirChanged", {
    callback = function()
        M.log.info("Directory changed, refreshing chase...")
        M.refresh()
    end,
    group = M.group,
})

-- Hide chase buffers when netrw appears
vim.api.nvim_create_autocmd("FileType", {
    pattern = "netrw",
    callback = function()
        M.oppened_chase_buf_hide()
    end,
    group = M.group,
})

return M
