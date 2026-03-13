local chase = require("chase")

--- @class ChaseJava : ChaseRunner
local M = {}

--- @type string
--- Prefix for the output buffer name.
M.buf_name_prefix = "ChaseJava: "

--- @type string|nil
--- Path to the Java binary.
M.java_bin = nil

--- @type string|nil
--- Current Java version string.
M.java_version = nil

--- @type string|nil
--- Path to the Javac compiler binary.
M.javac_bin = nil

--- @type string
--- The file pattern to match for Java files.
M.pattern = "*.java"

-- Query for JUnit test methods
local test_query = vim.treesitter.query.parse("java", [[
    (class_declaration
        name: (identifier) @class.name) @class.def
    (method_declaration
        (modifiers
            (marker_annotation
                name: (identifier) @annotation
                (#eq? @annotation "Test")))
        name: (identifier) @method.name) @method.def
]])

--- Retrieves test methods from the buffer using Tree-sitter.
--- @param buf number The buffer number to analyze.
--- @return table tests A list of test method names.
function M.tests_in_buffer(buf)
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return {}
    end
    local parser = vim.treesitter.get_parser(buf, "java")
    if not parser then
        return {}
    end
    local tree = parser:parse()[1]
    if not tree then
        return {}
    end
    local tests = {}
    for _, node, metadata in test_query:iter_captures(tree:root(), buf, 0, -1) do
        local name = vim.treesitter.get_node_text(node, buf)
        if metadata and metadata[3] == "method.name" then
            table.insert(tests, name)
        end
    end
    return tests
end

--- Identifies the test class or method under the cursor.
--- @param buf number The buffer number to analyze.
--- @return string location The "Class#method" string for filtering.
function M.where_am_i(buf)
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return ""
    end
    local parser = vim.treesitter.get_parser(buf, "java")
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
            if capture_name == "class.name" then
                local start_row, _, _, _ = node:range()
                if row >= start_row then
                    current_class = vim.treesitter.get_node_text(node, buf)
                end
            elseif capture_name == "method.name" then
                local start_row, _, end_row, _ = node:range()
                if row >= start_row and row <= end_row then
                    current_method = vim.treesitter.get_node_text(node, buf)
                end
            end
        end
    end

    if current_method ~= "" then
        return current_class .. "#" .. current_method
    elseif current_class ~= "" then
        return current_class
    end
    return ""
end

--- Checks if the buffer contains a public static void main.
--- @param buf_number number The buffer number to check.
--- @return boolean result True if main is found.
function M.buf_is_main(buf_number)
    local lines = vim.api.nvim_buf_get_lines(buf_number, 0, -1, false)
    for _, line in ipairs(lines) do
        local pattern = "public%s+static%s+void%s+main%s*%("
        if string.match(line, pattern) then
            return true
        end
    end
    return false
end

--- Validates if the current directory is a Java project (Maven, Gradle, etc).
--- @return boolean result True if build files exist.
function M.is_project_valid()
    local project_files = { ".classpath", "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts" }
    for _, file in ipairs(project_files) do
        if chase.project_root:joinpath(file):exists() then
            return true
        end
    end
    return false
end

--- Detects Java and Javac binaries and captures the version.
function M.get_package_from_file(file)
    local f = io.open(file, "r")
    if not f then
        return ""
    end
    for line in f:lines() do
        local package = string.match(line, "^package%s+([%w%.]+)%s*;")
        if package then
            f:close()
            return package
        end
    end
    f:close()
    return ""
end

--- Extracts the Java class name from a file path (filename without extension).
--- @param file string The path to the Java file.
--- @return string basename The name of the class.
function M.get_class_name(file)
    local basename = vim.fn.fnamemodify(file, ":t:r")
    return basename
end

--- Retrieves source and output directories from the .classpath file.
--- Defaults to "src" and "build" if the file is missing or invalid.
--- @return string src_dir The directory containing source files.
--- @return string output_dir The directory for compiled class files.
function M.get_classpath_dirs()
    local classpath_file = chase.project_root:joinpath(".classpath")
    local src_dir = "src"
    local output_dir = "build"

    if classpath_file:exists() then
        local f = io.open(classpath_file.filename, "r")
        if f then
            local content = f:read("*all")
            f:close()

            -- Parse src path
            local src_match = content:match('kind="src"%s+path="([^"]+)"')
            if src_match then
                src_dir = src_match
            end

            -- Parse output path
            local output_match = content:match('kind="output"%s+path="([^"]+)"')
            if output_match then
                output_dir = output_match
            end
        end
    end

    return src_dir, output_dir
end

--- Runs the given Java file or tests using Maven, Gradle or plain Javac.
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
    local testing = file:match("Test%.java$")
    if not testing then
        testing = file:match("Tests%.java$")
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

    local java_execution = M.java_bin
    local java_args = ""

    if testing then
        local package = M.get_package_from_file(file)
        local class_name = M.get_class_name(file)
        local full_class = package ~= "" and (package .. "." .. class_name) or class_name
        local where_am_i = M.where_am_i(buf)

        chase.buf_append(chase_buf, {
            "Test class: " .. full_class,
        })

        if where_am_i ~= "" then
            chase.buf_append(chase_buf, {
                "Location: " .. where_am_i,
            })
        end

        -- Check if Maven or Gradle project
        if chase.project_root:joinpath("pom.xml"):exists() then
            java_execution = "mvn"
            java_args = "test"
            if where_am_i ~= "" then
                java_args = java_args .. " -Dtest=" .. where_am_i
            else
                java_args = java_args .. " -Dtest=" .. class_name
            end
        elseif chase.project_root:joinpath("build.gradle"):exists() or
               chase.project_root:joinpath("build.gradle.kts"):exists() then
            java_execution = "./gradlew"
            if chase.is_windows() then
                java_execution = "gradlew.bat"
            end
            java_args = "test"
            if where_am_i ~= "" then
                java_args = java_args .. " --tests " .. where_am_i
            else
                java_args = java_args .. " --tests " .. class_name
            end
        end
    else
        local package = M.get_package_from_file(file)
        local class_name = M.get_class_name(file)
        local full_class = package ~= "" and (package .. "." .. class_name) or class_name

        -- Check if Maven or Gradle project
        if chase.project_root:joinpath("pom.xml"):exists() then
            java_execution = "mvn"
            java_args = "exec:java -Dexec.mainClass=" .. full_class
        elseif chase.project_root:joinpath("build.gradle"):exists() or
               chase.project_root:joinpath("build.gradle.kts"):exists() then
            java_execution = "./gradlew"
            if chase.is_windows() then
                java_execution = "gradlew.bat"
            end
            java_args = "run"
        else
            -- Plain java execution - read .classpath or use defaults
            local src_name, output_name = M.get_classpath_dirs()
            local src_dir = chase.project_root:joinpath(src_name).filename
            local build_dir = chase.project_root:joinpath(output_name).filename

            local mkdir_cmd = "mkdir -p " .. build_dir
            if chase.is_windows() then
                mkdir_cmd = "if not exist " .. build_dir .. " mkdir " .. build_dir
                java_execution = mkdir_cmd .. " && " .. M.javac_bin .. " -d " .. build_dir .. " " .. src_dir .. chase.sep .. "*.java " .. src_dir .. chase.sep .. "**" .. chase.sep .. "*.java 2>NUL && " .. M.java_bin
            else
                java_execution = mkdir_cmd .. " && " .. M.javac_bin .. " -d " .. build_dir .. " $(find " .. src_dir .. " -name '*.java') && " .. M.java_bin
            end
            java_args = "-cp " .. build_dir .. " " .. full_class
        end
    end

    chase.buf_append(chase_buf, {
        "Java: " .. M.java_bin,
        "Version: " .. M.java_version,
        "",
    })

    local cmd_list = { java_execution, java_args }

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

--- Detects Java binaries.
function M.setup_project()
    vim.fn.jobstart(
    { "which", "java" },
    {
        stdout_buffered = true,
        on_stdout = function(_, which_data)
            M.java_bin = vim.fn.join(which_data, ""):gsub("\n", "")
            vim.fn.jobstart(
            { M.java_bin, "-version" },
            {
                stderr_buffered = true,
                on_stderr = function(_, version_data)
                    local version_line = version_data[1] or ""
                    M.java_version = version_line:match("version \"(.-)\"") or version_line
                end,
            })
        end,
    })
    vim.fn.jobstart(
    { "which", "javac" },
    {
        stdout_buffered = true,
        on_stdout = function(_, which_data)
            M.javac_bin = vim.fn.join(which_data, ""):gsub("\n", "")
        end,
    })
end

return M
