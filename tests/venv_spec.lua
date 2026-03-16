local chase = require("chase")
local Path = require("plenary.path")

describe("Chase Venv Management", function()
    local sandbox_root = Path:new(vim.fn.getcwd(), "tests", "sandbox")
    local venvs_root = sandbox_root:joinpath("venvs")
    local test_pip_venv_name = "test_uv"
    local test_pip_venv_path = venvs_root:joinpath(test_pip_venv_name .. "_env")
    local test_uv_venv_name = "test_uv"
    local test_uv_venv_path = venvs_root:joinpath(test_uv_venv_name .. "_env")

    it("should create a venv using pip and install cartola and run it", function()
        if test_pip_venv_path:exists() then
            vim.fn.system("rm -rf " .. test_uv_venv_path.filename)
        end

        chase.setup({
            chasers = {
                python = {
                    venvs_dir = venvs_root.filename
                }
            }
        })

        local venv_done = false
        local install_done = false
        local run_done = false
        local created_path = nil
        local output_lines = {}

        chase.setup_virtualenv(test_pip_venv_name, function(path)
            created_path = path

            local pip_bin = created_path:joinpath("bin", "pip").filename
            if chase.is_windows() then
                pip_bin = created_path:joinpath("Scripts", "pip.exe").filename
            end

            vim.fn.jobstart({pip_bin, "install", "cartola"}, {
                on_exit = function(_, exit_code)
                    if exit_code == 0 then
                        install_done = true

                        local py_bin = created_path:joinpath("bin", "python").filename
                        if chase.is_windows() then
                            py_bin = created_path:joinpath("Scripts", "python.exe").filename
                        end

                        local test_script = sandbox_root:joinpath("cartola_test.py").filename


                        vim.fn.jobstart({py_bin, test_script}, {
                            stdout_buffered = true,
                            on_stdout = function(_, data)
                                for _, line in ipairs(data) do
                                    if line ~= "" then table.insert(output_lines, line) end
                                end
                            end,
                            on_exit = function()
                                run_done = true
                                venv_done = true
                            end
                        })
                    end
                end
            })
        end)
        vim.wait(16000, function() return venv_done end, 500)

        assert.are.True(install_done, "Cartola installation failed")
        assert.are.True(run_done, "Execution of cartola script failed")
        assert.are.equal("CARTOLA_OK: 03", output_lines[1], "Output from cartola script is wrong")
    end)

    it("should create a venv using uv and install cartola and run it", function()
        if test_uv_venv_path:exists() then
            vim.fn.system("rm -rf " .. test_uv_venv_path.filename)
        end

        chase.setup({
            chasers = {
                python = {
                    venvs_dir = venvs_root.filename
                }
            }
        })
        chase.check_uv()

        local venv_done = false
        local install_done = false
        local run_done = false
        local created_path = nil
        local output_lines = {}

        chase.setup_virtualenv(test_uv_venv_name, function(path)
            created_path = path

            local pip_bin = created_path:joinpath("bin", "pip").filename
            if chase.is_windows() then
                pip_bin = created_path:joinpath("Scripts", "pip.exe").filename
            end

            vim.fn.jobstart({pip_bin, "install", "cartola"}, {
                on_exit = function(_, exit_code)
                    if exit_code == 0 then
                        install_done = true

                        local py_bin = created_path:joinpath("bin", "python").filename
                        if chase.is_windows() then
                            py_bin = created_path:joinpath("Scripts", "python.exe").filename
                        end

                        local test_script = sandbox_root:joinpath("cartola_test.py").filename


                        vim.fn.jobstart({py_bin, test_script}, {
                            stdout_buffered = true,
                            on_stdout = function(_, data)
                                for _, line in ipairs(data) do
                                    if line ~= "" then table.insert(output_lines, line) end
                                end
                            end,
                            on_exit = function()
                                run_done = true
                                venv_done = true
                            end
                        })
                    end
                end
            })
        end)
        vim.wait(16000, function() return venv_done end, 500)

        assert.are.True(install_done, "Cartola installation failed")
        assert.are.True(run_done, "Execution of cartola script failed")
        assert.are.equal("CARTOLA_OK: 03", output_lines[1], "Output from cartola script is wrong")
    end)
end)
