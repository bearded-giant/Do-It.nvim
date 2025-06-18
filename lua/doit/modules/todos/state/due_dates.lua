-- Due date management for todos module
local M = {}

-- Setup module
function M.setup(state)
    -- Set due date for a todo
    function M.set_due_date(index, date_string)
        if not state.todos[index] then
            return false, "Todo index out of range"
        end
        
        -- Validate date format (YYYY-MM-DD)
        if not date_string:match("^%d%d%d%d%-%d%d%-%d%d$") then
            return false, "Invalid date format. Use YYYY-MM-DD"
        end
        
        local year, month, day = date_string:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
        year, month, day = tonumber(year), tonumber(month), tonumber(day)
        
        -- Basic validation
        if month < 1 or month > 12 or day < 1 or day > 31 then
            return false, "Invalid date values"
        end
        
        -- Set due date
        state.todos[index].due_date = date_string
        state.save_todos()
        
        return true, "Due date set to " .. date_string
    end
    
    -- Remove due date from a todo
    function M.remove_due_date(index)
        if not state.todos[index] then
            return false, "Todo index out of range"
        end
        
        if state.todos[index].due_date then
            state.todos[index].due_date = nil
            state.save_todos()
            return true, "Due date removed"
        else
            return false, "No due date set"
        end
    end
    
    -- Format a due date for display
    function M.format_due_date(due_date)
        if not due_date then
            return ""
        end
        
        -- Parse date components
        local year, month, day = due_date:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
        if not year then
            return due_date
        end
        
        -- Calculate days remaining
        local due_time = os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = 23,
            min = 59,
            sec = 59
        })
        
        local now = os.time()
        local days_until = math.floor((due_time - now) / (24 * 60 * 60))
        
        -- Format the display
        local date_display = due_date
        
        -- Add relative time
        if days_until < 0 then
            return date_display .. " (overdue by " .. math.abs(days_until) .. "d)"
        elseif days_until == 0 then
            return date_display .. " (today)"
        elseif days_until == 1 then
            return date_display .. " (tomorrow)"
        else
            return date_display .. " (" .. days_until .. "d)"
        end
    end
    
    return M
end

return M