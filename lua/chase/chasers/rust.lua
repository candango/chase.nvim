local chase = require("chase")
local Path = require("plenary.path")

--- @class ChaseRust : Chaser
local M = {}

--- @type string
M.buf_name_prefix = "ChaseRust: "

--- @type string
M.pattern = "*.rs"

--- @type string
M.cargo_bin = "cargo"

--- @type string|nil
M.cargo_version = nil

--- Finds the nearest Cargo manifest from a Rust file up to the project root.
--- This supports workspace members with their own package manifests.
--- @param file string The absolute path to a Rust source file.
--- @return string|nil manifest The nearest Cargo.toml path.
function M.find_manifest(file)
    local directory = Path:new(file):parent()
    local project_root = Path:new(chase.project_root.filename)

    while directory do
        local manifest = directory:joinpath("Cargo.toml")
        if manifest:exists() then
            return manifest.filename
        end
        if directory.filename == project_root.filename then
            break
        end
        local parent = directory:parent()
        if not parent or parent.filename == directory.filename then
            break
        end
        directory = parent
    end

    return nil
end

--- Resolves a Cargo binary name from src/bin/<name>.rs or src/bin/<name>/main.rs.
--- @param relative_file string The file path relative to the crate root.
--- @return string|nil name The Cargo binary name.
function M.binary_name(relative_file)
    local name = relative_file:match("^src[/\\]bin[/\\]([^/\\]+)%.rs$")
    if name then
        return name
    end
    return relative_file:match("^src[/\\]bin[/\\]([^/\\]+)[/\\]main%.rs$")
end

--- Checks whether a Rust buffer contains a test attribute.
--- @param buf number The buffer number to inspect.
--- @return boolean result True when a Rust test attribute is present.
function M.buf_is_test(buf)
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
        return false
    end

    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line:match("#%s*%[%s*test%s*%]") or line:match("#%s*%[%s*[%w_:]+test%s*%]") then
            return true
        end
    end
    return false
end

--- Resolves an integration test target from tests/<name>.rs.
--- @param relative_file string The file path relative to the crate root.
--- @return string|nil name The Cargo integration test target name.
function M.integration_test_name(relative_file)
    return relative_file:match("^tests[/\\]([^/\\]+)%.rs$")
end

--- Reads the package name used by Cargo for the default src/main.rs binary.
--- @param manifest string|nil The Cargo.toml path.
--- @return string|nil name The package name.
function M.package_name(manifest)
    if not manifest then
        return nil
    end

    local file = io.open(manifest, "r")
    if not file then
        return nil
    end

    local in_package = false
    for line in file:lines() do
        if line:match("^%s*%[package%]%s*$") then
            in_package = true
        elseif in_package and line:match("^%s*%[") then
            break
        elseif in_package then
            local name = line:match('^%s*name%s*=%s*["\']([^"\']+)["\']')
            if name then
                file:close()
                return name
            end
        end
    end

    file:close()
    return nil
end

--- Checks if the current directory contains a Cargo project or workspace.
--- @return boolean result True when Cargo.toml exists at the project root.
function M.is_project_valid()
    local project_root = chase.project_root.filename
    if chase.project_root:joinpath("Cargo.toml"):exists() then
        return true
    end

    return #vim.fn.globpath(project_root, "**/Cargo.toml", false, true) > 0
end

local function relative_path(file, root)
    local prefix = root .. chase.sep
    if file:sub(1, #prefix) == prefix then
        return file:sub(#prefix + 1)
    end
    return file
end

local function is_cargo_progress(line)
    return line:match("^%s*Finished `%w+` profile")
        or line:match("^%s*Running `")
end

--- Runs a Rust binary or Cargo test target.
--- @param file string The absolute path to the Rust source file.
function M.run_file(file)
    local buf = vim.api.nvim_get_current_buf()
    local project_relative_file = relative_path(file, chase.project_root.filename)
    local manifest = M.find_manifest(file)
    local crate_root = manifest and vim.fn.fnamemodify(manifest, ":h") or chase.project_root.filename
    local relative_file = relative_path(file, crate_root)
    local integration_test = M.integration_test_name(relative_file)
    local testing = integration_test ~= nil or relative_file:match("_test%.rs$") ~= nil or M.buf_is_test(buf)
    local binary = not testing and M.binary_name(relative_file) or nil
    if not testing and relative_file == "src" .. chase.sep .. "main.rs" then
        binary = binary or M.package_name(manifest)
    end
    local args = { M.cargo_bin, testing and "test" or "run" }

    if manifest then
        table.insert(args, "--manifest-path")
        table.insert(args, vim.fn.shellescape(manifest))
    end

    if integration_test then
        table.insert(args, "--test")
        table.insert(args, vim.fn.shellescape(integration_test))
    elseif binary then
        table.insert(args, "--bin")
        table.insert(args, vim.fn.shellescape(binary))
    end

    local command = table.concat(args, " ")
    local chase_buf = chase.buf_chase(project_relative_file, buf)

    chase.buf_clear(chase_buf)
    chase.buf_append(chase_buf, {
        "Candango Chase",
        (testing and "Testing " or "Running ") .. project_relative_file,
        "Cargo: " .. M.cargo_bin,
        "Version: " .. (M.cargo_version or "unknown"),
        "Command: " .. command,
        "Target: " .. (integration_test or binary or (testing and "all tests" or "default binary")),
        "",
        "",
    })

    chase.run_command(command, chase_buf, {
        on_stderr = function(_, data)
            local output = {}
            for _, line in ipairs(data or {}) do
                if line ~= "" and not is_cargo_progress(line) then
                    table.insert(output, line)
                end
            end
            if #output > 0 then
                chase.buf_stream(chase_buf, output)
            end
        end,
        on_exit = function(_, code)
            if code ~= 0 then
                chase.buf_append(chase_buf, {
                    "",
                    "Exit: failed (code " .. code .. ")",
                })
            end
        end,
    })
end

--- Detects Cargo and captures its version.
function M.setup_project()
    vim.fn.jobstart({ M.cargo_bin, "--version" }, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            local version = vim.fn.join(data, ""):gsub("\r", ""):gsub("\n", "")
            M.cargo_version = version
        end,
    })
end

return M
