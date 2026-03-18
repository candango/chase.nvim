local chase = require("chase")
local Log = chase.log
local Path = require("plenary.path")

--- @class PythonChaser : Chaser
local M = {}

--- @type string
--- Prefix for the output buffer name.
M.buf_name_prefix = "ChasePy: "

--- @type string|nil
--- Current Python version string.
M.python_version = nil

--- @type string
--- The file pattern to match for Python files.
M.pattern = "*.py"

-- Query tests case classes
local test_query = vim.treesitter.query.get("python", "test_case_class")

local test_method_query = vim.treesitter.query.get("python", "test_case_func")

--- Checks if the buffer contains a main entry point.
--- @param buf_number number The buffer number to check.
--- @return boolean result True if `if __name__ == "__main__":` is found.
function M.buf_is_main(buf_number)
    local lines = vim.api.nvim_buf_get_lines(buf_number, 0, -1, false)
    for _, line in ipairs(lines) do
        local pattern = "if __name__[ ]*==[ ]*[\"|']__main__[\"|'][ ]*:"
        if string.match(line, pattern) then
            return true
        end
    end
    return false
end

--- Hook triggered after saving a Python file.
function M.on_python_save()
    local data = {
        buf = tonumber(vim.fn.expand("<abuf>")),
        file = vim.fn.expand("<afile>"),
        match = vim.fn.expand("<amatch>"),
    }
    if M.buf_is_main(data.buf) then
        Log.info("Doing main stuff...")
        -- print(vim.inspect(data))
        -- chase.buf_open(data.file .. "_run")
    end
    -- print(vim.inspect(data))
    -- vim.api.nvim_create_buf(false, false)
end

--- Returns the path to the preferred Python binary (Virtualenv or Host).
--- @return string path The absolute path to the python executable.
function M.preferred_python()
    if os.getenv("VIRTUAL_ENV") ~= nil then
        local bin_path = "bin"
        local python = chase.installed_python
        if chase.is_windows() then
            bin_path = "Scripts"
            python = "python.exe"
        end
        return Path:new(
            os.getenv("VIRTUAL_ENV"), bin_path, python
        ).filename
    end
    return vim.api.nvim_get_var("python3_host_prog")
end

--- Retrieves the test class or method under the cursor.
--- @param buf number The buffer number to analyze.
--- @return string location The "Class.method" or "Class" string for unittest filtering.
function M.where_am_i(buf)
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return ""
    end
    local parser = vim.treesitter.get_parser(buf, "python")
    if not parser then
        return ""
    end
    local tree = parser:parse()[1]
    if not tree then
        return ""
    end
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1
    for _, match, _ in test_method_query:iter_matches(tree:root(), buf) do
        local class_node = match[1] -- @class.name TSNode[1]
        local method_node = match[2] -- @method.name TSNode[1]
        local body_node = match[3] -- @func.body TSNode[1]
        if type(class_node) == "table" then
            class_node = class_node[1]
        end
        if type(method_node) == "table" then
            method_node = method_node[1]
        end
        if type(body_node) == "table" then
            body_node = body_node[1]
        end
        local start_row, _, end_row, _ = body_node:range()
        if row >= start_row  and row <= end_row then
            local class_name = vim.treesitter.get_node_text(class_node, buf)
            local method_name = vim.treesitter.get_node_text(method_node, buf)
            return class_name .. "." .. method_name
        end
    end
    for _, match, _ in test_query:iter_matches(tree:root(), buf) do
        local class_node = match[1] -- @class.name TSNode[1]
        local body_node = match[2] -- @func.body TSNode[1]
        if type(class_node) == "table" then
            class_node = class_node[1]
        end
        if type(body_node) == "table" then
            body_node = body_node[1]
        end
        local start_row, _, end_row, _ = body_node:range()
        if row >= start_row  and row <= end_row then
            local class_name = vim.treesitter.get_node_text(class_node, buf)
            return class_name
        end
    end
    return ""
end

--- Converts a file path to a Python module path.
--- @param file string The absolute file path.
--- @return string module The dot-separated module path.
function M.get_current_module(file)
    local relative_path = file:gsub(chase.project_root.filename, "")
    if relative_path:sub(1,1) == chase.sep then
        relative_path = relative_path:sub(2, -1)
    end
    local current_module = relative_path:gsub(".py", ""):gsub(chase.sep, ".")
    return current_module
end

--- Runs the given Python file or tests within it using `unittest`.
--- @param file string The absolute path to the file to run.
function M.run_file(file)
    local buf = vim.api.nvim_get_current_buf()
    if chase.is_windows() then
        file = file:gsub("/", chase.sep)
    end
    local relative_file = file:gsub(
        chase.project_root.filename .. chase.sep, ""
    )
    local chase_buf = chase.buf_chase(relative_file, buf)
    local testing = file:match("_test.py$")
    if not testing then
        testing = file:match("test_.*.py$")
    end
    chase.buf_clear(chase_buf)
    local action = "Running "
    if testing then
        action = "Testing "
    end
    chase.buf_append(chase_buf, {
        "Candango Chase",
        action .. relative_file,
    })

    local py_cmd = M.preferred_python()
    local py_args = ""
    if testing then
        local current_module = M.get_current_module(file)
        local current_testing = current_module
        local where_am_i = M.where_am_i(buf)
        chase.buf_append(chase_buf, {
            "Current module: " .. current_module,
        })
        if where_am_i ~= "" then
            current_testing = current_testing .. "." .. where_am_i
            chase.buf_append(chase_buf, {
                "Location: " .. where_am_i,
            })
        end
        py_args = "-m unittest -v " .. current_testing
    end

    chase.buf_append(chase_buf, {
        "Python: " .. M.preferred_python(),
        "Version: " .. M.python_version,
        "",
        "",
    })

    local cmd_list = { py_cmd, py_args }
    if not testing then
        cmd_list[#cmd_list+1] = file
    end

    chase.run_command(table.concat(cmd_list, " "), chase_buf)
end

--- Initializes the Python runner by setting up the virtualenv and capturing
--- the version.
function M.setup_project()
    local cwd_x = vim.fn.split(vim.fn.getcwd(), chase.sep)
    local venv_prefix = table.concat(cwd_x, "_", #cwd_x-1, #cwd_x)
    chase.setup_virtualenv(venv_prefix, M.set_python)

    vim.fn.jobstart(
    { M.preferred_python(), "--version" },
    {
        stdout_buffered = true,
        on_stdout = function(_, data)
            local result = vim.fn.join(data, "")
            M.python_version = vim.fn.split(result, " ")[2]
            if chase.is_windows then
                M.python_version = M.python_version:gsub("\r", "")
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufWritePost", {
        callback = M.on_python_save,
        pattern = M.pattern,
        group = chase.group,
    })
end

--- Validates if the current directory is a Python project.
--- @return boolean result True if pyproject.toml, setup.cfg or setup.py exists.
function M.is_project_valid()
    local prj_files = { "pyproject.toml", "setup.cfg", "setup.py" }
    for _, file in ipairs(prj_files) do
        if chase.project_root:joinpath(file):exists() then
            return true
        end
    end
    return false
end

--- Configures the environment to use the detected virtualenv.
--- @param venv_path any The plenary.path object pointing to the venv root.
function M.set_python(venv_path)
    local venv_bin = venv_path:joinpath("bin")
    if chase.is_windows() then
        venv_bin = venv_path:joinpath("Scripts")
    end
    -- local venv_activate = venv_bin:joinpath("activate")
    chase.add_to_path(venv_bin)
    -- let $VIRTUAL_ENV=<project_virtualenv>
    vim.cmd("let $VIRTUAL_ENV='" .. venv_path.filename .. "'")
    if chase.is_windows() then
        vim.cmd("let $PYTHONPATH='.;" .. chase.project_root.filename .. "'")
        return
    end
    vim.cmd("let $PYTHONPATH='.:" .. chase.project_root.filename .. "'")
end

return M
