-- Sorting functionality for todos module
local M = {}

-- Setup module
function M.setup(state)
    -- Sort all todos
    function M.sort_todos()
        -- Generate priority scores
        for _, todo in ipairs(state.todos) do
            todo._score = state.get_priority_score(todo)
        end
        
        -- Perform sorting
        table.sort(state.todos, function(a, b)
            -- First, sort by completion status (incomplete first)
            if a.done ~= b.done then
                return not a.done
            end
            
            -- Then sort by in_progress (in_progress first)
            if a.in_progress ~= b.in_progress then
                return a.in_progress
            end
            
            -- Use order_index for reordering if present
            if a.order_index and b.order_index and a.order_index ~= b.order_index then
                return a.order_index < b.order_index
            end
            
            -- Then by priority score
            if a._score ~= b._score then
                return a._score > b._score
            end
            
            -- Then by due date (if both have due dates)
            if a.due_date and b.due_date and a.due_date ~= b.due_date then
                return a.due_date < b.due_date
            end
            
            -- If only one has a due date, it comes first
            if a.due_date and not b.due_date then
                return true
            elseif not a.due_date and b.due_date then
                return false
            end
            
            -- Finally, sort by creation time (older first)
            return (a.timestamp or 0) < (b.timestamp or 0)
        end)
    end
    
    -- Get filtered and sorted list of todos
    function M.get_filtered_todos()
        local todos = {}
        
        -- Apply tag filter if set
        if state.active_filter then
            for _, todo in ipairs(state.todos) do
                if todo.text:find("#" .. state.active_filter) then
                    table.insert(todos, todo)
                end
            end
        else
            todos = vim.deepcopy(state.todos)
        end
        
        -- Sort the filtered todos
        table.sort(todos, function(a, b)
            -- First, sort by completion status (incomplete first)
            if a.done ~= b.done then
                return not a.done
            end
            
            -- Then sort by in_progress (in_progress first)
            if a.in_progress ~= b.in_progress then
                return a.in_progress
            end
            
            -- Use order_index for reordering if present
            if a.order_index and b.order_index and a.order_index ~= b.order_index then
                return a.order_index < b.order_index
            end
            
            -- Then by priority score
            local a_score = state.get_priority_score(a)
            local b_score = state.get_priority_score(b)
            if a_score ~= b_score then
                return a_score > b_score
            end
            
            -- Finally, sort by creation time (older first)
            return (a.timestamp or 0) < (b.timestamp or 0)
        end)
        
        return todos
    end
    
    return M
end

return M