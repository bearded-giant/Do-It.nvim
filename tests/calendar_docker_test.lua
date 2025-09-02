-- Test calendar module in Docker
describe("Calendar Docker Test", function()
    it("should register calendar module", function()
        local doit = require("doit")
        
        doit.setup({
            modules = {
                calendar = {
                    enabled = true
                }
            }
        })
        
        assert.is_not_nil(doit.calendar, "Calendar module should be loaded")
        
        -- Check registry
        if doit.core and doit.core.registry then
            local modules = doit.core.registry.list()
            local found = false
            for _, mod in ipairs(modules) do
                if mod.name == "calendar" then
                    found = true
                    break
                end
            end
            assert.is_true(found, "Calendar should be in registry")
        end
    end)
    
    it("should work with mock data in Docker", function()
        local icalbuddy = require("doit.modules.calendar.icalbuddy")
        
        -- Should detect as available (mocked in Docker)
        assert.is_true(icalbuddy.check_availability())
        
        -- Should generate events
        local events = icalbuddy.get_events("2025-01-01", "2025-01-07", {})
        assert.is_table(events)
        assert.is_true(#events > 0, "Should generate mock events")
    end)
end)