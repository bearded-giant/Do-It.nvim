-- Tests for core plugins module
describe("core plugins", function()
    local plugins

    before_each(function()
        package.loaded["doit.core.plugins"] = nil
        package.loaded["doit.core.config"] = nil

        -- Mock config
        package.loaded["doit.core.config"] = {
            options = {
                plugins = {
                    auto_discover = true,
                    load_path = "doit.modules",
                }
            }
        }

        plugins = require("doit.core.plugins")
    end)

    describe("get_standalone_path", function()
        it("should prefix with doit_", function()
            assert.are.equal("doit_calendar", plugins.get_standalone_path("calendar"))
        end)

        it("should handle hyphenated names", function()
            assert.are.equal("doit_obsidian-sync", plugins.get_standalone_path("obsidian-sync"))
        end)
    end)

    describe("load_module", function()
        it("should load an existing module", function()
            local module = plugins.load_module("todos")
            assert.is_not_nil(module)
        end)

        it("should return nil for non-existent module", function()
            local module = plugins.load_module("nonexistent_module_xyz")
            assert.is_nil(module)
        end)
    end)

    describe("load_standalone", function()
        it("should return nil for non-existent standalone module", function()
            local module = plugins.load_standalone("nonexistent_standalone_xyz")
            assert.is_nil(module)
        end)
    end)

    describe("discover_modules", function()
        it("should return a table", function()
            local modules = plugins.discover_modules()
            assert.is_table(modules)
        end)

        it("should not discover when disabled", function()
            package.loaded["doit.core.config"].options.plugins.auto_discover = false
            local modules = plugins.discover_modules()
            assert.are.equal(0, #modules)
        end)
    end)
end)
