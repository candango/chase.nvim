local chase = require("chase")

--- @class ChasePHP : Chaser
local M = {}

--- @type string
--- Prefix for the output buffer name.
M.buf_name_prefix = "ChasePHP: "

--- @type string
--- Path to the PHP binary.
M.php_bin = "php"

--- @type string|nil
--- Path to the PHPUnit binary.
M.phpunit_bin = nil

--- @type string|nil
--- Current PHP version string.
M.php_version = nil

--- @type string
--- The file pattern to match for PHP files.
M.pattern = "*.php"

-- Query for PHPUnit test classes and methods
-- PHPUnit tests are classes extending TestCase with methods starting with 'test' or @test annotation
local test_query = vim.treesitter.query.get("php", "phpunit_test")

--- Retrieves the test class and method under the cursor.
--- Returns a string "ClassName::methodName" or just "ClassName".
---
--- @param buf number The buffer number to analyze.
--- @return string string The test name under the cursor for PHPUnit filtering.
function M.where_am_i(buf)
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return ""
    end
    local parser = vim.treesitter.get_parser(buf, "php")
    if not parser then
        return ""
    end
    local tree = parser:parse()[1]
    if not tree then
        return ""
    end
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1

    local current_class = ""
    local current_method = ""

    for _, match, _ in test_query:iter_matches(tree:root(), buf) do
        for id, node in pairs(match) do
            local capture_name = test_query.captures[id]
            -- Flatten node if it's a table (sometimes TS returns a list of nodes)
            local target_node = node
            if type(target_node) == "table" then target_node = target_node[1] end

            if capture_name == "class.name" then
                if target_node and type(target_node) == "userdata" and target_node.range then
                    local start_row, _, _, _ = target_node:range()
                    if row >= start_row then
                        current_class = vim.treesitter.get_node_text(target_node, buf)
                    end
                end
            elseif capture_name == "method.name" then
                -- We need the method definition node for the range check
                -- In the query, method.def is the 5th capture
                local method_def_node = match[5]
                if type(method_def_node) == "table" then method_def_node = method_def_node[1] end

                if method_def_node and type(method_def_node) == "userdata" and method_def_node.range then
                    local start_row, _, end_row, _ = method_def_node:range()
                    if row >= start_row and row <= end_row then
                        if target_node and target_node.range then
                            current_method = vim.treesitter.get_node_text(target_node, buf)
                        end
                    end
                end
            end
        end
    end

    if current_method ~= "" and current_class ~= "" then
        return current_class .. "::" .. current_method
    elseif current_class ~= "" then
        return current_class
    end
    return ""
end

--- Checks if the current directory is a PHP project.
--- @return boolean result True if it's a valid PHP project.
function M.is_project_valid()
    local prj_files = {
        "composer.json",
        "composer.lock",
        "artisan",
        "phpunit.xml",
        "phpunit.xml.dist",
        "vendor/autoload.php"
    }
    for _, file in ipairs(prj_files) do
        if chase.project_root:joinpath(file):exists() then
            return true
        end
    end
    return false
end

--- Runs the given PHP file or tests within it.
--- Uses PHPUnit if it's a test file or if within a test class.
--- Uses `php` for normal files.
---
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
    local where_am_i = M.where_am_i(buf)
    local testing = where_am_i ~= "" or file:match("Test%.php$")

    chase.buf_clear(chase_buf)
    local action = "Running "
    if testing then
        action = "Testing "
    end
    chase.buf_append(chase_buf, {
        "Candango Chase",
        action .. relative_file,
    })

    local php_cmd = M.php_bin
    local php_args = ""

    if testing then
        if M.phpunit_bin then
            php_cmd = M.phpunit_bin
            if where_am_i ~= "" then
                php_args = "--filter '" .. where_am_i .. "'"
                chase.buf_append(chase_buf, {
                    "Filter: " .. where_am_i,
                })
            end
        else
            chase.buf_append(chase_buf, {
                "Error: PHPUnit not found. Please install it locally or globally.",
            })
            return
        end
    else
        -- For normal PHP files, we build the include_path from configuration and project root
        -- Default to { "." } if not defined
        local config_path = chase.config.php.include_path or { "." }
        local sep = chase.is_windows() and ";" or ":"
        local paths = {}
        for _, p in ipairs(config_path) do
            table.insert(paths, p)
        end
        table.insert(paths, chase.project_root.filename)

        local include_path = table.concat(paths, sep)
        php_args = "-d include_path='" .. include_path .. "'"

        -- Inject the autoloader if it exists
        local autoloader = chase.project_root:joinpath("vendor", "autoload.php")
        if autoloader:exists() then
            php_args = php_args .. " -d auto_prepend_file='" .. autoloader.filename .. "'"
            chase.buf_append(chase_buf, {
                "Autoloader: " .. autoloader.filename,
            })
        end
    end

    chase.buf_append(chase_buf, {
        "PHP: " .. M.php_bin,
        "Version: " .. (M.php_version or "unknown"),
        "",
    })

    local cmd_list = { php_cmd, php_args }
    if not testing or (not M.phpunit_bin) then
        cmd_list[#cmd_list+1] = file
    elseif M.phpunit_bin then
        -- PHPUnit usually takes the file or directory as the last argument
        cmd_list[#cmd_list+1] = file
    end

    vim.fn.jobstart(
    table.concat(cmd_list, " "),
    {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data)
            if chase.is_windows() then
                for i, v in ipairs(data) do
                    data[i] = v:gsub("\r", "")
                end
            end
            chase.buf_append(chase_buf, data)
        end,
        on_stderr = function(_, data)
            chase.buf_append(chase_buf, data)
        end,
    })
end

--- Detects PHP and PHPUnit binaries.
function M.setup_project()
    -- Find PHP
    vim.fn.jobstart(
    { "which", "php" },
    {
        stdout_buffered = true,
        on_stdout = function(_, data)
            local bin = vim.fn.join(data, ""):gsub("\n", "")
            if bin ~= "" then
                M.php_bin = bin
                vim.fn.jobstart(
                { M.php_bin, "-v" },
                {
                    stdout_buffered = true,
                    on_stdout = function(_, v_data)
                        local first_line = v_data[1] or ""
                        M.php_version = first_line:match("PHP ([%d%.]+)")
                    end,
                })
            end
        end,
    })

    -- Find PHPUnit (Local first, then global)
    -- If vendor/autoload.php exists, we prioritize vendor/bin/phpunit
    local vendor_dir = chase.project_root:joinpath("vendor")
    local local_phpunit = vendor_dir:joinpath("bin", "phpunit")
    local autoloader = vendor_dir:joinpath("autoload.php")

    if autoloader:exists() and local_phpunit:exists() then
        M.phpunit_bin = local_phpunit.filename
    elseif local_phpunit:exists() then
        M.phpunit_bin = local_phpunit.filename
    else
        vim.fn.jobstart(
        { "which", "phpunit" },
        {
            stdout_buffered = true,
            on_stdout = function(_, data)
                local bin = vim.fn.join(data, ""):gsub("\n", "")
                if bin ~= "" then
                    M.phpunit_bin = bin
                end
            end,
        })
    end
end

return M
