-- Tests for the notes module
describe("notes module", function()
    local notes_module
    
    before_each(function()
        -- Clear module cache
        package.loaded["doit.modules.notes"] = nil
        package.loaded["doit.modules.notes.config"] = nil
        package.loaded["doit.modules.notes.state"] = nil
        package.loaded["doit.modules.notes.ui"] = nil
        package.loaded["doit.modules.notes.commands"] = nil
        
        -- Create minimal core mock if not exists
        if not package.loaded["doit.core"] then
            package.loaded["doit.core"] = {
                register_module = function(_, module) return module end,
                get_module = function() return nil end,
                events = {
                    on = function() return function() end end,
                    emit = function() return end
                }
            }
        end
        
        -- Load notes module
        notes_module = require("doit.modules.notes")
    end)
    
    it("should initialize correctly", function()
        assert.are.equal("table", type(notes_module))
        assert.are.equal("function", type(notes_module.setup))
        assert.are.equal("function", type(notes_module.standalone_setup))
    end)
    
    it("should setup with default configuration", function()
        local module = notes_module.setup({})
        
        assert.are.equal("table", type(module.config))
        assert.are.equal("table", type(module.state))
        assert.are.equal("table", type(module.ui))
        assert.are.equal("table", type(module.commands))
    end)
    
    it("should work in standalone mode", function()
        local module = notes_module.standalone_setup({})
        
        assert.are.equal("table", type(module.config))
        assert.are.equal("table", type(module.state))
        assert.are.equal("table", type(module.ui))
        assert.are.equal("table", type(module.commands))
    end)
end)