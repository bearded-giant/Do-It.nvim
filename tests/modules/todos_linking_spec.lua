-- Tests for the todo linking functionality in todos module
describe("todos linking", function()
    local todos_module
    local todos_state
    local notes_module
    
    local state -- Declare state at module level so it's accessible in tests
    
    before_each(function()
        -- Clear module cache
        package.loaded["doit.modules.todos"] = nil
        package.loaded["doit.modules.todos.config"] = nil
        package.loaded["doit.modules.todos.state"] = nil
        package.loaded["doit.modules.todos.ui"] = nil
        package.loaded["doit.modules.todos.commands"] = nil
        package.loaded["doit.modules.notes"] = nil
        
        -- Setup mock for notes module
        package.loaded["doit.modules.notes"] = {
            state = {
                parse_note_links = function(text)
                    if not text or text == "" then return {} end
                    local links = {}
                    for link in text:gmatch("%[%[([^%]]+)%]%]") do
                        table.insert(links, link)
                    end
                    return links
                end,
                find_note_by_title = function(title)
                    if title == "Test Note" then
                        return { id = "test_note_id", content = "# Test Note\nContent" }
                    elseif title == "Another Note" then
                        return { id = "another_note_id", content = "# Another Note\nMore content" }
                    end
                    return nil
                end,
                generate_summary = function(content)
                    if not content or content == "" then return "" end
                    local first_line = ""
                    for line in content:gmatch("[^\r\n]+") do
                        if line and line:match("%S") then
                            first_line = line:gsub("^%s*#%s*", ""):gsub("^%s*", "")
                            break
                        end
                    end
                    return first_line
                end
            }
        }
        
        -- Create minimal core mock
        package.loaded["doit.core"] = {
            register_module = function(_, module) return module end,
            get_module = function(name)
                if name == "notes" then
                    return package.loaded["doit.modules.notes"]
                end
                return nil
            end,
            events = {
                on = function() return function() end end,
                emit = function() return end
            }
        }
        
        -- Initialize with minimal state
        state = {
            todos = {},
            deleted_todos = {},
            MAX_UNDO_HISTORY = 10,
            save_todos = function() end
        }
        
        -- Load todos module
        todos_module = require("doit.modules.todos.state.todos")
        todos_state = todos_module.setup(state)
    end)
    
    describe("process_note_links", function()
        it("should extract note links from todo text", function()
            local todo = {
                id = "todo1",
                text = "Todo with a [[Test Note]] link"
            }
            
            todos_state.process_note_links(todo)
            
            assert.are.equal("test_note_id", todo.note_id)
            assert.are.equal("Test Note", todo.note_summary)
            assert.is_not_nil(todo.note_updated_at)
        end)
        
        it("should handle todos with no links", function()
            local todo = {
                id = "todo1",
                text = "Todo with no links"
            }
            
            todos_state.process_note_links(todo)
            
            assert.is_nil(todo.note_id)
            assert.is_nil(todo.note_summary)
        end)
        
        it("should handle links to non-existent notes", function()
            local todo = {
                id = "todo1",
                text = "Todo with a [[Non-existent Note]] link"
            }
            
            todos_state.process_note_links(todo)
            
            assert.is_nil(todo.note_id)
            assert.is_nil(todo.note_summary)
        end)
    end)
    
    describe("add_todo", function()
        it("should process links when adding a new todo", function()
            local new_todo = todos_state.add_todo("Todo with a [[Test Note]] link")
            
            assert.are.equal("test_note_id", new_todo.note_id)
            assert.are.equal("Test Note", new_todo.note_summary)
        end)
    end)
    
    describe("edit_todo", function()
        it("should update note links when editing a todo", function()
            -- Add an initial todo
            local todo_index = 1
            state.todos[todo_index] = {
                id = "todo1",
                text = "Original todo text"
            }
            
            -- Edit the todo to add a link
            todos_state.edit_todo(todo_index, "Todo with a [[Test Note]] link")
            
            assert.are.equal("test_note_id", state.todos[todo_index].note_id)
            assert.are.equal("Test Note", state.todos[todo_index].note_summary)
        end)
        
        it("should update to a different note when editing", function()
            -- Add an initial todo with a link
            local todo_index = 1
            state.todos[todo_index] = {
                id = "todo1",
                text = "Todo with a [[Test Note]] link",
                note_id = "test_note_id",
                note_summary = "Test Note"
            }
            
            -- Edit the todo to change the link
            todos_state.edit_todo(todo_index, "Todo with a [[Another Note]] link")
            
            assert.are.equal("another_note_id", state.todos[todo_index].note_id)
            assert.are.equal("Another Note", state.todos[todo_index].note_summary)
        end)
    end)
    
    describe("link_todo_to_note and unlink_todo_from_note", function()
        it("should directly link a todo to a note", function()
            -- Add a todo
            local todo_index = 1
            state.todos[todo_index] = {
                id = "todo1",
                text = "Original todo text"
            }
            
            -- Link the todo to a note
            local result = todos_state.link_todo_to_note(todo_index, "test_note_id", "Test Note")
            
            assert.is_true(result)
            assert.are.equal("test_note_id", state.todos[todo_index].note_id)
            assert.are.equal("Test Note", state.todos[todo_index].note_summary)
            assert.is_not_nil(state.todos[todo_index].note_updated_at)
        end)
        
        it("should unlink a todo from a note", function()
            -- Add a todo with a link
            local todo_index = 1
            state.todos[todo_index] = {
                id = "todo1",
                text = "Todo with a link",
                note_id = "test_note_id",
                note_summary = "Test Note",
                note_updated_at = os.time()
            }
            
            -- Unlink the todo
            local result = todos_state.unlink_todo_from_note(todo_index)
            
            assert.is_true(result)
            assert.is_nil(state.todos[todo_index].note_id)
            assert.is_nil(state.todos[todo_index].note_summary)
            assert.is_nil(state.todos[todo_index].note_updated_at)
        end)
    end)
end)