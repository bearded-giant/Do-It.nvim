-- Day view renderer for calendar UI
local M = {}

-- Render day view
function M.render(calendar_module)
    local lines = {}
    local state = calendar_module.state
    local config = calendar_module.config
    
    -- Get current date and events
    local current_date = state.get_date()
    local events = state.get_events() or {}
    
    -- Use actual window width if available
    local total_width = config.window.actual_width or config.window.width

    -- Format header
    local date_display = state.format_date(current_date)
    local header = string.format(" %s ", date_display)
    table.insert(lines, header)
    table.insert(lines, string.rep("─", total_width - 2))
    table.insert(lines, "")
    
    -- Get hour range
    local start_hour = config.hours.start
    local end_hour = config.hours["end"]
    
    -- Create event map by hour
    local events_by_hour = {}
    for _, event in ipairs(events) do
        if event.date == current_date and event.start_time then
            local hour = tonumber(event.start_time:match("^(%d+):"))
            if hour then
                if not events_by_hour[hour] then
                    events_by_hour[hour] = {}
                end
                table.insert(events_by_hour[hour], event)
            end
        end
    end
    
    -- Sort events within each hour by exact start time
    for hour, hour_events in pairs(events_by_hour) do
        table.sort(hour_events, function(a, b)
            return (a.start_time or "") < (b.start_time or "")
        end)
    end
    
    -- Add all-day events at the top
    local all_day_events = {}
    for _, event in ipairs(events) do
        if event.date == current_date and event.all_day then
            table.insert(all_day_events, event)
        end
    end
    
    if #all_day_events > 0 then
        table.insert(lines, " All Day Events:")
        for _, event in ipairs(all_day_events) do
            -- Add tentative indicator (?) if event is tentative
            local prefix = event.tentative and "?" or "•"
            local event_line = string.format("   %s %s", prefix, event.title)
            if event.location then
                event_line = event_line .. string.format(" (%s)", event.location)
            end
            table.insert(lines, event_line)
        end
        table.insert(lines, "")
    end
    
    -- Get current hour for highlighting
    local current_hour = tonumber(os.date("%H"))
    local is_today = current_date == os.date("%Y-%m-%d")
    
    -- Adjust start hour for today - show from current hour or one hour before
    local display_start_hour = start_hour
    if is_today then
        display_start_hour = math.max(start_hour, current_hour - 1)
    end
    
    -- Render hours
    for hour = display_start_hour, end_hour - 1 do
        local hour_str = string.format("%2d:00", hour)
        local separator = "┃"
        
        -- Check if current hour (highlight differently if today)
        if is_today and hour == current_hour then
            separator = "▶"
        end
        
        local line = string.format(" %s %s ", hour_str, separator)
        
        -- Add events for this hour
        if events_by_hour[hour] then
            local event_strs = {}
            for _, event in ipairs(events_by_hour[hour]) do
                -- Add tentative indicator (?) at start if event is tentative
                local prefix = event.tentative and "? " or ""
                local event_str = prefix .. event.title
                if event.end_time then
                    local duration = M.calculate_duration(event.start_time, event.end_time)
                    if duration then
                        event_str = event_str .. string.format(" (%s)", duration)
                    end
                end
                table.insert(event_strs, event_str)
            end
            line = line .. table.concat(event_strs, ", ")
        end
        
        table.insert(lines, line)
    end
    
    -- Add footer with controls
    table.insert(lines, "")
    table.insert(lines, string.rep("─", total_width - 2))
    
    local footer_parts = {}
    table.insert(footer_parts, "[d]ay [3]day [w]eek")
    table.insert(footer_parts, "[h/l] prev/next")
    table.insert(footer_parts, "[t]oday")
    table.insert(footer_parts, "[r]efresh")
    table.insert(footer_parts, "[q]uit")
    
    local footer = " " .. table.concat(footer_parts, " │ ") .. " "
    table.insert(lines, footer)
    
    return lines
end

-- Calculate duration between two time strings
function M.calculate_duration(start_time, end_time)
    local start_h, start_m = start_time:match("(%d+):(%d+)")
    local end_h, end_m = end_time:match("(%d+):(%d+)")
    
    if not (start_h and start_m and end_h and end_m) then
        return nil
    end
    
    local start_minutes = tonumber(start_h) * 60 + tonumber(start_m)
    local end_minutes = tonumber(end_h) * 60 + tonumber(end_m)
    local duration_minutes = end_minutes - start_minutes
    
    if duration_minutes <= 0 then
        return nil
    end
    
    local hours = math.floor(duration_minutes / 60)
    local minutes = duration_minutes % 60
    
    if hours > 0 and minutes > 0 then
        return string.format("%dh %dm", hours, minutes)
    elseif hours > 0 then
        return string.format("%dh", hours)
    else
        return string.format("%dm", minutes)
    end
end

return M