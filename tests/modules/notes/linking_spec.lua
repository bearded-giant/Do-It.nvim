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
    
    describe("find_note_by_title", function()
        it("should find a note by title pattern", function()
            -- Mock the notes state
            notes_state.notes = {
                global = {
                    id = "global_id",
                    content = "# Global Note\nSome content"
                },
                project = {
                    project1 = {
                        id = "project1_id",
                        content = "# Project Note\nSome project content"
                    }
                }
            }
            
            -- Test finding global note
            local note = notes_state.find_note_by_title("Global Note")
            assert.are.equal("global_id", note.id)
            
            -- Test finding project note
            note = notes_state.find_note_by_title("Project Note")
            assert.are.equal("project1_id", note.id)
        end)
        
        it("should handle partial title matches", function()
            -- Mock the notes state
            notes_state.notes = {
                global = {
                    id = "global_id",
                    content = "# Global Test Note\nSome content"
                }
            }
            
            -- Test finding with partial title
            local note = notes_state.find_note_by_title("Test")
            assert.are.equal("global_id", note.id)
        end)
        
        it("should handle case-insensitive matching", function()
            -- Mock the notes state
            notes_state.notes = {
                global = {
                    id = "global_id",
                    content = "# Global Test Note\nSome content"
                }
            }
            
            -- Test finding with different case
            local note = notes_state.find_note_by_title("test note")
            assert.are.equal("global_id", note.id)
        end)
        
        it("should return nil for non-existent notes", function()
            -- Mock the notes state with a project property to avoid nil error
            notes_state.notes = {
                global = {
                    id = "global_id",
                    content = "# Global Note\nSome content"
                },
                project = {}  -- Ensure project property exists
            }
            
            -- Test finding non-existent note
            local note = notes_state.find_note_by_title("Non-existent")
            assert.is_nil(note)
        end)
    end)
    
    describe("get_all_notes_titles", function()
        it("should return a list of all note titles", function()
            -- Mock the notes state
            notes_state.notes = {
                global = {
                    id = "global_id",
                    content = "# Global Note\nSome content"
                },
                project = {
                    project1 = {
                        id = "project1_id",
                        content = "# Project Note\nSome project content"
                    },
                    project2 = {
                        id = "project2_id",
                        content = "# Another Project\nMore content"
                    }
                }
            }
            
            local titles = notes_state.get_all_notes_titles()
            assert.are.equal(3, #titles)
            
            -- Check for the global note
            local has_global = false
            local has_project1 = false
            local has_project2 = false
            
            for _, title_data in ipairs(titles) do
                if title_data.id == "global_id" then
                    has_global = true
                    assert.are.equal("Global Note", title_data.title)
                elseif title_data.id == "project1_id" then
                    has_project1 = true
                    assert.are.equal("Project Note", title_data.title)
                elseif title_data.id == "project2_id" then
                    has_project2 = true
                    assert.are.equal("Another Project", title_data.title)
                end
            end
            
            assert.is_true(has_global)
            assert.is_true(has_project1)
            assert.is_true(has_project2)
        end)
        
        it("should handle empty notes", function()
            -- Mock the notes state with empty content
            notes_state.notes = {
                global = {
                    id = "global_id",
                    content = ""
                },
                project = {}
            }
            
            local titles = notes_state.get_all_notes_titles()
            assert.are.equal(0, #titles)
        end)
    end)
end)