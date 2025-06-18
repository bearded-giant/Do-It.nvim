-- Tests for the core framework
describe("core", function()
    local core
    
    before_each(function()
        -- Clear loaded modules to ensure clean state
        package.loaded["doit.core"] = nil
        package.loaded["doit.core.config"] = nil
        package.loaded["doit.core.utils"] = nil
        package.loaded["doit.core.ui"] = nil
        package.loaded["doit.core.api"] = nil
        
        -- Load core module
        core = require("doit.core")
    end)
    
    it("should initialize correctly", function()
        assert.are.equal("table", type(core))
        assert.are.equal("table", type(core.events))
        assert.are.equal("function", type(core.register_module))
        assert.are.equal("function", type(core.setup))
    end)
    
    it("should return configuration after setup", function()
        local config = core.setup({})
        assert.are.equal("table", type(config))
    end)
    
    it("should register and retrieve modules", function()
        core.setup({})
        
        local test_module = {
            name = "test_module",
            version = "1.0.0"
        }
        
        core.register_module("test", test_module)
        
        assert.are.equal(test_module, core.get_module("test"))
    end)
    
    it("should handle events", function()
        core.setup({})
        
        local test_data = nil
        
        -- Subscribe to event
        local unsubscribe = core.events.on("test_event", function(data)
            test_data = data
        end)
        
        -- Emit event
        core.events.emit("test_event", { value = 42 })
        
        -- Check that event was received
        assert.are.equal(42, test_data.value)
        
        -- Unsubscribe
        unsubscribe()
        
        -- Reset test data
        test_data = nil
        
        -- Emit event again
        core.events.emit("test_event", { value = 84 })
        
        -- Check that event was not received
        assert.is_nil(test_data)
    end)
end)