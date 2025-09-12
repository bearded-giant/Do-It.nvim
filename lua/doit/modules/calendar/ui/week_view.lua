-- Week view renderer for calendar UI
local M = {}

-- Render week view
function M.render(calendar_module)
    local lines = {}
    local state = calendar_module.state
    local config = calendar_module.config
    
    -- Get date range (Monday to Sunday)
    local start_date, end_date = state.get_date_range()
    local events = state.get_events() or {}
    
    -- Header
    local header = string.format(" Week: %s - %s ",
        state.format_date_short(start_date),
        state.format_date_short(end_date))
    table.insert(lines, header)
    table.insert(lines, string.rep("─", config.window.width - 4))
    table.insert(lines, "")
    
    -- Days of week
    local days = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
    
    -- Render each day
    for i = 0, 6 do
        local date = state.add_days(start_date, i)
        local is_today = date == os.date("%Y-%m-%d")
        local day_marker = is_today and "▶" or " "
        
        table.insert(lines, string.format("%s %s %s", 
            day_marker,
            days[i + 1],
            state.format_date_short(date)))
        
        -- Filter events for this day
        local day_events = {}
        for _, event in ipairs(events) do
            if event.date == date then
                table.insert(day_events, event)
            end
        end
        
        -- Sort events by start time (all-day events first, then by time)
        table.sort(day_events, function(a, b)
            -- All-day events come first
            if a.all_day and not b.all_day then return true end
            if b.all_day and not a.all_day then return false end
            if a.all_day and b.all_day then 
                return (a.title or "") < (b.title or "")
            end
            
            -- Both have times, sort by start time
            if a.start_time and b.start_time then
                return a.start_time < b.start_time
            end
            
            return false
        end)
        
        if #day_events == 0 then
            table.insert(lines, "     -")
        else
            -- Show first 2 events per day in week view
            local count = 0
            for _, event in ipairs(day_events) do
                if count < 2 then
                    local event_line = "     "
                    if event.start_time then
                        event_line = event_line .. string.format("%s ", event.start_time:sub(1, 5))
                    end
                    event_line = event_line .. M.truncate_title(event.title, 30)
                    table.insert(lines, event_line)
                    count = count + 1
                end
            end
            if #day_events > 2 then
                table.insert(lines, string.format("     ... +%d more", #day_events - 2))
            end
        end
        
        if i < 6 then
            table.insert(lines, "")
        end
    end
    
    -- Footer
    table.insert(lines, "")
    table.insert(lines, string.rep("─", config.window.width - 4))
    local footer = " [d]ay [3]day [w]eek │ [h/l] prev/next │ [t]oday │ [q]uit "
    table.insert(lines, footer)
    
    return lines
end

-- Truncate title to fit width
function M.truncate_title(title, max_width)
    if #title <= max_width then
        return title
    end
    return title:sub(1, max_width - 3) .. "..."
end

return M