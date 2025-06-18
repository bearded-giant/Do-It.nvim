-- Todo operations for the todos module
local M = {}

-- Setup module
function M.setup(state)
    -- Generate a unique ID for a todo
    local function generate_todo_id()
        return os.time() .. "_" .. math.random(1000000, 9999999)
    end
    
    -- Add a new todo 
    function M.add_todo(text, priorities)
        local new_todo = {
            id = generate_todo_id(),
            text = text,
            done = false,
            timestamp = os.time(),
            order_index = #state.todos + 1,
        }
        
        if priorities and #priorities > 0 then
            new_todo.priorities = priorities
        end
        
        -- Process any note links in the todo text
        M.process_note_links(new_todo)
        
        table.insert(state.todos, new_todo)
        state.save_todos()
        
        return new_todo
    end
    
    -- Parse note links from todo text and update todo.note_id if found
    function M.process_note_links(todo)
        if not todo or not todo.text then return end
        
        -- Try to get a reference to the notes module
        local core = package.loaded["doit.core"]
        local notes_module = core and core.get_module and core.get_module("notes")
        
        if not notes_module or not notes_module.state then
            return -- Cannot process links without notes module
        end
        
        -- Extract note links from text
        local links = notes_module.state.parse_note_links(todo.text)
        
        -- If links found, try to match with the first one
        if #links > 0 then
            local note = notes_module.state.find_note_by_title(links[1])
            if note and note.id then
                todo.note_id = note.id
                todo.note_summary = notes_module.state.generate_summary(note.content)
                todo.note_updated_at = os.time()
            end
        end
    end
    
    -- Get a todo by its ID
    function M.get_todo_by_id(id)
        if not id then return nil end
        
        for _, todo in ipairs(state.todos) do
            if todo.id == id then
                return todo
            end
        end
        return nil
    end
    
    -- Get all todos linked to a specific note ID
    function M.get_todos_by_note_id(note_id)
        if not note_id then return {} end
        
        local linked_todos = {}
        for _, todo in ipairs(state.todos) do
            if todo.note_id == note_id then
                table.insert(linked_todos, todo)
            end
        end
        return linked_todos
    end
    
    -- Toggle a todo status
    function M.toggle_todo(index)
        if state.todos[index] then
            state.todos[index].done = not state.todos[index].done
            state.save_todos()
        end
    end
    
    -- Set todo status (in_progress)
    function M.set_in_progress(index, value)
        if state.todos[index] then
            state.todos[index].in_progress = value
            state.save_todos()
        end
    end
    
    -- Delete a todo
    function M.delete_todo(index)
        if state.todos[index] then
            local todo = state.todos[index]
            todo.delete_time = os.time()  -- Add deletion timestamp
            
            table.insert(state.deleted_todos, 1, todo)
            table.remove(state.todos, index)
            
            -- Limit undo history
            if #state.deleted_todos > state.MAX_UNDO_HISTORY then
                state.deleted_todos[state.MAX_UNDO_HISTORY + 1] = nil
            end
            
            state.save_todos()
        end
    end
    
    -- Delete completed todos
    function M.delete_completed()
        local deleted_count = 0
        
        for i = #state.todos, 1, -1 do
            if state.todos[i].done then
                local todo = state.todos[i]
                todo.delete_time = os.time()
                
                table.insert(state.deleted_todos, 1, todo)
                table.remove(state.todos, i)
                
                deleted_count = deleted_count + 1
            end
        end
        
        -- Limit undo history
        while #state.deleted_todos > state.MAX_UNDO_HISTORY do
            table.remove(state.deleted_todos)
        end
        
        if deleted_count > 0 then
            state.save_todos()
        end
        
        return deleted_count
    end
    
    -- Undo last deleted todo
    function M.undo_delete()
        if #state.deleted_todos > 0 then
            local todo = table.remove(state.deleted_todos, 1)
            
            -- Remove the deletion timestamp
            todo.delete_time = nil
            
            -- Set order_index to be at the end
            todo.order_index = #state.todos + 1
            
            table.insert(state.todos, todo)
            state.save_todos()
            
            return todo
        end
        
        return nil
    end
    
    -- Parse categories from todo text (starts with #)
    function M.parse_categories(text)
        local categories = {}
        for tag in text:gmatch("#(%w+)") do
            table.insert(categories, tag)
        end
        return categories
    end
    
    -- Edit a todo
    function M.edit_todo(index, new_text)
        if state.todos[index] then
            local todo = state.todos[index]
            todo.text = new_text
            
            -- Re-process note links when text is edited
            M.process_note_links(todo)
            
            state.save_todos()
        end
    end
    
    -- Link a todo to a note directly
    function M.link_todo_to_note(todo_index, note_id, note_summary)
        if not state.todos[todo_index] then
            return false
        end
        
        state.todos[todo_index].note_id = note_id
        state.todos[todo_index].note_summary = note_summary
        state.todos[todo_index].note_updated_at = os.time()
        state.save_todos()
        
        return true
    end
    
    -- Unlink a todo from its note
    function M.unlink_todo_from_note(todo_index)
        if not state.todos[todo_index] then
            return false
        end
        
        state.todos[todo_index].note_id = nil
        state.todos[todo_index].note_summary = nil
        state.todos[todo_index].note_updated_at = nil
        state.save_todos()
        
        return true
    end
    
    -- Remove duplicate todos
    function M.remove_duplicates()
        local text_map = {}
        local duplicates = {}
        
        -- Find duplicates
        for i, todo in ipairs(state.todos) do
            if text_map[todo.text] then
                table.insert(duplicates, i)
            else
                text_map[todo.text] = true
            end
        end
        
        -- Remove duplicates from end to beginning to maintain indices
        table.sort(duplicates, function(a, b) return a > b end)
        
        for _, idx in ipairs(duplicates) do
            table.remove(state.todos, idx)
        end
        
        if #duplicates > 0 then
            state.save_todos()
        end
        
        return #duplicates
    end
    
    return M
end

return M