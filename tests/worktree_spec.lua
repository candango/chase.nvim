local chase = require("chase")

describe("Chase Project Info", function()
    local original_systemlist = vim.fn.systemlist

    after_each(function()
        vim.fn.systemlist = original_systemlist
    end)

    it("should detect non-git environment", function()
        vim.fn.systemlist = function(cmd)
            if cmd == "git rev-parse --show-toplevel" then
                return {}
            end
            return original_systemlist(cmd)
        end

        local info = chase.get_project_info()
        assert.are.equal(vim.fn.getcwd(), info.root)
        assert.is_nil(info.worktree)
    end)

    it("should detect git root (not worktree)", function()
        local mock_root = "/home/fpiraz/source/candango/chase"
        vim.fn.systemlist = function(cmd)
            if cmd == "git rev-parse --show-toplevel" then
                return { mock_root }
            elseif cmd == "git rev-parse --git-common-dir" then
                return { ".git" }
            end
            return original_systemlist(cmd)
        end

        local info = chase.get_project_info()
        assert.are.equal(mock_root, info.root)
        assert.are.equal("chase", info.project)
        assert.is_nil(info.worktree)
    end)

    it("should detect git worktree", function()
        local mock_root = "/home/fpiraz/source/candango/chase/feature-x"
        local mock_common = "/home/fpiraz/source/candango/chase/.git"
        vim.fn.systemlist = function(cmd)
            if cmd == "git rev-parse --show-toplevel" then
                return { mock_root }
            elseif cmd == "git rev-parse --git-common-dir" then
                return { mock_common }
            end
            return original_systemlist(cmd)
        end

        local info = chase.get_project_info()
        assert.are.equal(mock_root, info.root)
        assert.are.equal("chase", info.project)
        assert.are.equal("feature-x", info.worktree)
    end)
end)

local python = require("chase.chasers.python")

describe("Python Venv Prefix", function()
    local original_get_project_info = chase.get_project_info
    local original_setup_virtualenv = chase.setup_virtualenv

    after_each(function()
        chase.get_project_info = original_get_project_info
        chase.setup_virtualenv = original_setup_virtualenv
    end)

    it("should use 2-level prefix when not in worktree", function()
        chase.get_project_info = function()
            return {
                parent = "candango",
                project = "chase",
                worktree = nil
            }
        end

        local captured_prefix = nil
        chase.setup_virtualenv = function(prefix, _)
            captured_prefix = prefix
        end

        python.setup_project()
        assert.are.equal("candango_chase", captured_prefix)
    end)

    it("should use 3-level prefix when in worktree", function()
        chase.get_project_info = function()
            return {
                parent = "candango",
                project = "chase",
                worktree = "feature-x"
            }
        end

        local captured_prefix = nil
        chase.setup_virtualenv = function(prefix, _)
            captured_prefix = prefix
        end

        python.setup_project()
        assert.are.equal("candango_chase_feature-x", captured_prefix)
    end)
end)
