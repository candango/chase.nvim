local chase = require("chase")
local test = require("chase.test")
local rust = require("chase.chasers.rust")

describe("Chase Rust Project", function()
    local root = vim.fn.getcwd()
    local fixtures = vim.fn.join({ root, "tests", "fixtures", "rust" }, chase.sep)

    after_each(function()
        test.reset_project()
    end)

    it("detects a Cargo project", function()
        test.setup_project(vim.fn.join({ fixtures, "default" }, chase.sep))
        assert.is_true(rust.is_project_valid())
    end)

    it("detects nested Cargo projects from a repository root", function()
        test.setup_project(fixtures)
        assert.is_true(rust.is_project_valid())
    end)

    it("resolves the default binary from src/main.rs", function()
        assert.is_nil(rust.binary_name("src/main.rs"))
    end)

    it("resolves a binary from src/bin", function()
        assert.are.equal("cli", rust.binary_name("src/bin/cli.rs"))
        assert.are.equal("server", rust.binary_name("src/bin/server/main.rs"))
    end)

    it("resolves integration test targets", function()
        assert.are.equal("smoke", rust.integration_test_name("tests/smoke.rs"))
        assert.is_nil(rust.integration_test_name("tests/support/mod.rs"))
    end)

    it("finds the member manifest inside a workspace", function()
        local workspace = vim.fn.join({ fixtures, "workspace" }, chase.sep)
        local member_file = vim.fn.join({ workspace, "app", "src", "main.rs" }, chase.sep)

        test.setup_project(workspace)

        assert.are.equal(
            vim.fn.join({ workspace, "app", "Cargo.toml" }, chase.sep),
            rust.find_manifest(member_file)
        )
    end)

    it("detects Rust test attributes", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "#[tokio::test]",
            "async fn works() {}",
        })

        assert.is_true(rust.buf_is_test(buf))
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end)
