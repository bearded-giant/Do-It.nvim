-- 3-day view renderer for calendar UI
local M = {}

-- Render 3-day view
function M.render(calendar_module)
    local lines = {}
    local state = calendar_module.state
    local config = calendar_module.config
    
    -- Get date range
    local start_date, end_date = state.get_date_range()
    local events = state.get_events() or {}
    
    -- Header
    local header = string.format(" %s - %s ", 
        state.format_date_short(start_date),
        state.format_date_short(end_date))
    table.insert(lines, header)
    table.insert(lines, string.rep("─", config.window.width - 4))
    table.insert(lines, "")
    
    -- Render each day
    for i = 0, 2 do
        local date = state.add_days(start_date, i)
        local day_name = state.format_date_short(date)
        
        table.insert(lines, string.format(" ▶ %s", day_name))
        
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
            table.insert(lines, "   No events")
        else
            for _, event in ipairs(day_events) do
                local event_line = "   • "
                if event.all_day then
                    event_line = event_line .. "[All Day] "
                elseif event.start_time and event.end_time then
                    -- Convert 24-hour to 12-hour with AM/PM
                    local function format_time(time_str)
                        local hour, min = time_str:match("(%d+):(%d+)")
                        hour = tonumber(hour)
                        local ampm = hour >= 12 and "pm" or "am"
                        if hour > 12 then
                            hour = hour - 12
                        elseif hour == 0 then
                            hour = 12
                        end
                        return string.format("%d:%s%s", hour, min, ampm)
                    end
                    
                    local start_fmt = format_time(event.start_time)
                    local end_fmt = format_time(event.end_time)
                    event_line = event_line .. string.format("%s - %s ", start_fmt, end_fmt)
                elseif event.start_time then
                    event_line = event_line .. string.format("%s ", event.start_time)
                end
                event_line = event_line .. event.title
                table.insert(lines, event_line)
            end
        end
        
        table.insert(lines, "")
    end
    
    -- Footer
    table.insert(lines, string.rep("─", config.window.width - 4))
    local footer = " [d]ay [3]day [w]eek │ [h/l] prev/next │ [t]oday │ [q]uit "
    table.insert(lines, footer)
    
    return lines
end

return M