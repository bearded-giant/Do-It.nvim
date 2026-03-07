-- Tests for the note linking functionality in notes module
describe("notes linking", function()
    local notes_module
    local notes_state
    
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
        
        -- Initialize with minimal configuration
        local module = notes_module.setup({})
        notes_state = module.state
    end)
    
    describe("parse_note_links", function()
        it("should extract links from text with [[]] format", function()
            local text = "This is a note with a [[Test Note]] link in it"
            local links = notes_state.parse_note_links(text)
            
            assert.are.equal(1, #links)
            assert.are.equal("Test Note", links[1])
        end)
        
        it("should extract multiple links", function()
            local text = "Links to [[First Note]] and [[Second Note]] in the same text"
            local links = notes_state.parse_note_links(text)
            
            assert.are.equal(2, #links)
            assert.are.equal("First Note", links[1])
            assert.are.equal("Second Note", links[2])
        end)
        
        it("should handle empty text", function()
            local links = notes_state.parse_note_links("")
            assert.are.equal(0, #links)
            
            links = notes_state.parse_note_links(nil)
            assert.are.equal(0, #links)
        end)
        
        it("should handle text with no links", function()
            local text = "This text has no links in it"
            local links = notes_state.parse_note_links(text)
            
            assert.are.equal(0, #links)
        end)
    end)
end)