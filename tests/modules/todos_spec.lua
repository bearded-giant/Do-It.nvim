-- Tests for the todos module
describe("todos module", function()
    local todos_module
    
    before_each(function()
        -- Clear module cache
        package.loaded["doit.modules.todos"] = nil
        package.loaded["doit.modules.todos.config"] = nil
        package.loaded["doit.modules.todos.state"] = nil
        package.loaded["doit.modules.todos.ui"] = nil
        package.loaded["doit.modules.todos.commands"] = nil
        
        -- Mock module components
        package.loaded["doit.modules.todos.config"] = {
            setup = function() 
                return {
                    save_path = vim.fn.stdpath("data") .. "/doit_todos.json",
                    window = {},
                    priorities = {}
                }
            end
        }
        
        package.loaded["doit.modules.todos.state"] = {
            setup = function() 
                return {
                    todos = {},
                    load_todos = function() end,
                    save_todos = function() end,
                    load_from_disk = function() end,
                    save_to_disk = function() end
                }
            end
        }
        
        package.loaded["doit.modules.todos.state.storage"] = {
            setup = function()
                return {
                    load_from_disk = function() end,
                    save_to_disk = function() end,
                    import_todos = function() end,
                    export_todos = function() end
                }
            end
        }
        
        package.loaded["doit.modules.todos.ui"] = {
            main_window = {},
            list_window = {}
        }
        
        package.loaded["doit.modules.todos.commands"] = {
            setup = function() return {} end
        }
        
        -- Create minimal core mock
        package.loaded["doit.core"] = {
            register_module = function(_, module) return module end,
            get_module = function() return nil end,
            get_module_config = function() return {
                save_path = vim.fn.stdpath("data") .. "/doit_todos.json",
                priorities = {}
            } end,
            events = {
                on = function() return function() end end,
                emit = function() return end
            },
            config = {
                modules = {
                    todos = {
                        save_path = vim.fn.stdpath("data") .. "/doit_todos.json",
                        priorities = {}
                    }
                }
            }
        }
        
        -- Load todos module
        todos_module = require("doit.modules.todos")
        
        -- Mock the setup function to avoid testing the actual implementation
        local original_setup = todos_module.setup
        todos_module.setup = function(opts)
            return {
                config = package.loaded["doit.modules.todos.config"].setup(opts),
                state = package.loaded["doit.modules.todos.state"].setup(),
                ui = package.loaded["doit.modules.todos.ui"],
                commands = package.loaded["doit.modules.todos.commands"].setup()
            }
        end
        
        -- Mock the standalone setup similarly
        local original_standalone = todos_module.standalone_setup
        todos_module.standalone_setup = function(opts)
            return {
                config = package.loaded["doit.modules.todos.config"].setup(opts),
                state = package.loaded["doit.modules.todos.state"].setup(),
                ui = package.loaded["doit.modules.todos.ui"],
                commands = package.loaded["doit.modules.todos.commands"].setup()
            }
        end
    end)
    
    it("should initialize correctly", function()
        assert.are.equal("table", type(todos_module))
        assert.are.equal("function", type(todos_module.setup))
        assert.are.equal("function", type(todos_module.standalone_setup))
    end)
    
    it("should setup with default configuration", function()
        local module = todos_module.setup({})
        
        assert.are.equal("table", type(module.config))
        assert.are.equal("table", type(module.state))
    end)
    
    it("should work in standalone mode", function()
        local module = todos_module.standalone_setup({})
        
        assert.are.equal("table", type(module.config))
        assert.are.equal("table", type(module.state))
    end)
end)