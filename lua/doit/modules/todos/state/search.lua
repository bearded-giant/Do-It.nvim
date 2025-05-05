-- Search functionality for todos module
local M = {}

-- Setup module
function M.setup(state)
    -- Search todos by text
    function M.search_todos(query)
        if not query or query == "" then
            return state.todos
        end
        
        local results = {}
        query = query:lower()
        
        for _, todo in ipairs(state.todos) do
            if todo.text:lower():find(query, 1, true) then
                table.insert(results, todo)
            end
        end
        
        return results
    end
    
    -- Fuzzy search todos
    function M.fuzzy_search(query)
        if not query or query == "" then
            return state.todos
        end
        
        local results = {}
        query = query:lower()
        
        -- Make an array of query characters for matching
        local query_chars = {}
        for i = 1, #query do
            query_chars[i] = query:sub(i, i)
        end
        
        for _, todo in ipairs(state.todos) do
            local text = todo.text:lower()
            local match = true
            local start_pos = 1
            
            -- Try to find each query character in sequence
            for _, char in ipairs(query_chars) do
                local found_pos = text:find(char, start_pos, true)
                if not found_pos then
                    match = false
                    break
                end
                start_pos = found_pos + 1
            end
            
            if match then
                table.insert(results, todo)
            end
        end
        
        return results
    end
    
    -- Filter todos by status
    function M.filter_by_status(status)
        local results = {}
        
        for _, todo in ipairs(state.todos) do
            if status == "done" and todo.done then
                table.insert(results, todo)
            elseif status == "pending" and not todo.done then
                table.insert(results, todo)
            elseif status == "in_progress" and todo.in_progress then
                table.insert(results, todo)
            end
        end
        
        return results
    end
    
    return M
end

return M