local M = {}

function M.setup(state)
    local function generate_todo_id()
        return require("doit.core.utils.id").generate(state.todos)
    end
    
    function M.add_todo(text, priorities)
        local new_todo = {
            id = generate_todo_id(),
            text = text,
            done = false,
            created_at = os.time(),
            order_index = #state.todos + 1,
            description = require("doit.core.utils.footer").stamp(""),
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
        
        local notes_state = notes_module and notes_module.state
        -- the notes module can be present but only partly wired (disabled, or a
        -- todos-only setup), so every entry point is checked before it is called
        if not notes_state or not notes_state.parse_note_links or not notes_state.find_note_by_title then
            return
        end

        local links = notes_state.parse_note_links(todo.text)

        if #links > 0 then
            local note = notes_state.find_note_by_title(links[1])
            if note and note.id then
                todo.note_id = note.id
                if notes_state.generate_summary then
                    todo.note_summary = notes_state.generate_summary(note.content)
                end
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
                todo.completed_at = nil
            elseif todo.in_progress and not todo.done then
                -- In Progress -> Done
                todo.in_progress = false
                todo.done = true
                todo.completed_at = os.time()
            else
                -- Done -> Pending (reset both)
                todo.in_progress = false
                todo.done = false
                todo.completed_at = nil
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
            state.todos[index].completed_at = nil
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
    
    -- Indices of todos that repeat an earlier todo's normalized text. The first
    -- occurrence is always the keeper, so this is stable under re-runs.
    local function duplicate_indices()
        local normalize = require("doit.modules.todos.state.normalize")
        local footer = require("doit.core.utils.footer")
        -- every todo carries a footer stamp, so "has a description" is always
        -- true — the keeper test has to look past the footer at real notes
        local function has_notes(todo)
            return footer.strip(todo.description or ""):gsub("%s", "") ~= ""
        end

        local groups = {}
        local order = {}
        for i, todo in ipairs(state.todos) do
            local key = normalize.normalize(todo.text)
            -- an empty body carries no identity; never collapse those together
            if key ~= "" then
                if not groups[key] then
                    groups[key] = {}
                    table.insert(order, key)
                end
                table.insert(groups[key], i)
            end
        end

        local dupes = {}
        for _, key in ipairs(order) do
            local idxs = groups[key]
            if #idxs > 1 then
                -- keep the copy carrying real notes, else the first occurrence,
                -- so nvim and MCP agree on which one survives
                local keep = idxs[1]
                for _, i in ipairs(idxs) do
                    if has_notes(state.todos[i]) then
                        keep = i
                        break
                    end
                end
                for _, i in ipairs(idxs) do
                    if i ~= keep then
                        table.insert(dupes, i)
                    end
                end
            end
        end

        table.sort(dupes)
        return dupes
    end

    -- Non-destructive: lets the UI show a count and preview before confirming.
    function M.find_duplicates()
        local dupes = duplicate_indices()
        local previews = {}
        for _, idx in ipairs(dupes) do
            table.insert(previews, state.todos[idx].text)
        end
        return #dupes, previews
    end

    function M.remove_duplicates()
        local dupes = duplicate_indices()

        -- descending so earlier indices stay valid, and routed through the same
        -- bookkeeping as delete_todo so `u` can restore a mistaken dedupe
        table.sort(dupes, function(a, b) return a > b end)

        for _, idx in ipairs(dupes) do
            local todo = state.todos[idx]
            todo.delete_time = os.time()
            table.insert(state.deleted_todos, 1, todo)
            table.remove(state.todos, idx)
        end

        while #state.deleted_todos > state.MAX_UNDO_HISTORY do
            table.remove(state.deleted_todos)
        end

        if #dupes > 0 then
            state.save_todos()
        end

        return #dupes
    end
    
    return M
end

return M