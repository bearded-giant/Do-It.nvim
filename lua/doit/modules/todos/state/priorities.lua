-- Priority handling for todos module
local M = {}

-- Setup module
function M.setup(state)
    -- Update priority weights for todos
    function M.update_priority_weights()
        local config = require("doit.modules.todos.config").options
        
        for _, todo in ipairs(state.todos) do
            -- Skip if no priorities
            if not todo.priorities or type(todo.priorities) ~= "string" then
                goto continue
            end
            
            -- Find priority configuration
            for _, priority in ipairs(config.priorities or {}) do
                if priority.name == todo.priorities then
                    todo._priority_weight = priority.weight or 0
                    break
                end
            end
            
            ::continue::
        end
    end
    
    -- Get priority score for a todo
    function M.get_priority_score(todo)
        local score = 0
        
        -- Base score from priority weight
        if todo._priority_weight then
            score = score + todo._priority_weight
        end
        
        -- In-progress items get highest priority
        if todo.in_progress then
            score = score + 100
        end
        
        -- Higher score for incomplete items
        if not todo.done then
            score = score + 10
        end
        
        -- Due date boosts priority
        if todo.due_date then
            -- Parse due date as timestamp
            local due_timestamp = 0
            if type(todo.due_date) == "number" then
                due_timestamp = todo.due_date
            else
                -- Try to parse as YYYY-MM-DD
                local year, month, day = todo.due_date:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
                if year and month and day then
                    due_timestamp = os.time({
                        year = tonumber(year),
                        month = tonumber(month),
                        day = tonumber(day),
                    })
                end
            end
            
            if due_timestamp > 0 then
                local now = os.time()
                local days_until_due = math.floor((due_timestamp - now) / (24 * 60 * 60))
                
                -- Exponentially increase priority as due date approaches
                if days_until_due <= 7 then
                    score = score + (7 - days_until_due) * 2
                end
                
                -- Past due items get highest priority
                if days_until_due < 0 then
                    score = score + 20
                end
            end
        end
        
        return score
    end
    
    return M
end

return M