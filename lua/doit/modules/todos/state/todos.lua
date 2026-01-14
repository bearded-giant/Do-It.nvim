local M = {}

function M.setup(state)
    local function generate_todo_id()
        return os.time() .. "_" .. math.random(1000000, 9999999)
    end
    
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
        
        M.process_note_links(new_todo)
        
        table.insert(state.todos, new_todo)
        state.save_todos()
        
        return new_todo
    end
    
    -- Process note links in todo text and sync with notes module
    function M.process_note_links(todo)
        if not todo or not todo.text then return end
        
        local core = package.loaded["doit.core"]
        local notes_module = core and core.get_module and core.get_module("notes")
        
        if not notes_module or not notes_module.state then
            return
        end
        
        local links = notes_module.state.parse_note_links(todo.text)
        
        if #links > 0 then
            local note = notes_module.state.find_note_by_title(links[1])
            if note and note.id then
                todo.note_id = note.id
                todo.note_summary = notes_module.state.generate_summary(note.content)
                todo.note_updated_at = os.time()
            end
        end
    end
    
    function M.get_todo_by_id(id)
        if not id then return nil end
        
        for _, todo in ipairs(state.todos) do
            if todo.id == id then
                return todo
            end
        end
        return nil
    end
    
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

    -- Move a todo from current list to another list
    function M.move_todo_to_list(todo_index, target_list_name)
        if not state.todos[todo_index] then
            return false, "Todo not found at index " .. todo_index
        end

        local current_list = state.todo_lists.active
        if current_list == target_list_name then
            return false, "Todo is already in list '" .. target_list_name .. "'"
        end

        -- Get the todo and create a deep copy
        local todo = vim.deepcopy(state.todos[todo_index])

        -- Remove from current list
        table.remove(state.todos, todo_index)
        state.save_todos()

        -- Switch to target list
        local success, msg = state.load_list(target_list_name)
        if not success then
            -- If target list doesn't exist, create it
            state.create_list(target_list_name, {})
            state.load_list(target_list_name)
        end

        -- Add to target list
        todo.order_index = #state.todos + 1
        table.insert(state.todos, todo)
        state.save_todos()

        -- Fire event for move operation
        local core = require("doit.core")
        if core and core.emit then
            core.emit("todo:moved", {
                todo = todo,
                from_list = current_list,
                to_list = target_list_name
            })
        end

        -- Switch back to original list
        state.load_list(current_list)

        return true, "Moved todo to '" .. target_list_name .. "'"
    end
    
    function M.toggle_todo(index)
        if state.todos[index] then
            local todo = state.todos[index]
            
            -- Cycle through states: pending -> in_progress -> done -> pending
            if not todo.in_progress and not todo.done then
                -- Pending -> In Progress
                todo.in_progress = true
                todo.done = false
            elseif todo.in_progress and not todo.done then
                -- In Progress -> Done
                todo.in_progress = false
                todo.done = true
            else
                -- Done -> Pending (reset both)
                todo.in_progress = false
                todo.done = false
            end
            
            state.save_todos()
        end
    end
    
    function M.set_in_progress(index, value)
        if state.todos[index] then
            state.todos[index].in_progress = value
            state.save_todos()
        end
    end

    function M.revert_to_pending(index)
        if state.todos[index] then
            state.todos[index].in_progress = false
            state.todos[index].done = false
            state.save_todos()
        end
    end
    
    function M.delete_todo(index)
        if state.todos[index] then
            local todo = state.todos[index]
            todo.delete_time = os.time()
            
            table.insert(state.deleted_todos, 1, todo)
            table.remove(state.todos, index)
            
            if #state.deleted_todos > state.MAX_UNDO_HISTORY then
                state.deleted_todos[state.MAX_UNDO_HISTORY + 1] = nil
            end
            
            state.save_todos()
        end
    end
    
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
        
        while #state.deleted_todos > state.MAX_UNDO_HISTORY do
            table.remove(state.deleted_todos)
        end
        
        if deleted_count > 0 then
            state.save_todos()
        end
        
        return deleted_count
    end
    
    function M.undo_delete()
        if #state.deleted_todos > 0 then
            local todo = table.remove(state.deleted_todos, 1)

            todo.delete_time = nil

            todo.order_index = #state.todos + 1

            table.insert(state.todos, todo)
            state.save_todos()

            return true
        end

        return false
    end
    
    function M.parse_categories(text)
        local categories = {}
        for tag in text:gmatch("#(%w+)") do
            table.insert(categories, tag)
        end
        return categories
    end
    
    function M.edit_todo(index, new_text)
        if state.todos[index] then
            local todo = state.todos[index]
            todo.text = new_text
            
            M.process_note_links(todo)
            
            state.save_todos()
        end
    end
    
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
    
    function M.remove_duplicates()
        local text_map = {}
        local duplicates = {}
        
        for i, todo in ipairs(state.todos) do
            if text_map[todo.text] then
                table.insert(duplicates, i)
            else
                text_map[todo.text] = true
            end
        end
        
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