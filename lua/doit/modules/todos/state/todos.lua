-- Todo operations for the todos module
local M = {}

-- Setup module
function M.setup(state)
    -- Add a new todo 
    function M.add_todo(text, priorities)
        local new_todo = {
            text = text,
            done = false,
            timestamp = os.time(),
            order_index = #state.todos + 1,
        }
        
        if priorities and #priorities > 0 then
            new_todo.priorities = priorities
        end
        
        table.insert(state.todos, new_todo)
        state.save_todos()
        
        return new_todo
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
            state.todos[index].text = new_text
            state.save_todos()
        end
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