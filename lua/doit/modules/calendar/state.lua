-- State management for calendar module
local M = {}

-- Module reference
local calendar_module = nil

-- Current state
local state = {
    current_view = "day", -- "day", "3day", "week"
    current_date = nil,   -- Current date being viewed
    events = {},          -- Current events
    window_open = false   -- Window visibility state
}

-- Setup state management
function M.setup(module)
    calendar_module = module
    
    -- Initialize with today's date
    state.current_date = os.date("%Y-%m-%d")
    state.current_view = module.config.default_view or "day"
    
    return M
end

-- Get current state
function M.get()
    return state
end

-- Get current view
function M.get_view()
    return state.current_view
end

-- Set current view
function M.set_view(view)
    local valid_views = { day = true, ["3day"] = true, week = true }
    if valid_views[view] then
        state.current_view = view
    end
end

-- Get current date
function M.get_date()
    return state.current_date
end

-- Set current date
function M.set_date(date)
    state.current_date = date
end

-- Get date range for current view
function M.get_date_range()
    local start_date = state.current_date
    local end_date = start_date

    if state.current_view == "3day" then
        -- 3-day view: always today + 2 more days
        start_date = os.date("%Y-%m-%d")
        end_date = M.add_days(start_date, 2)
    elseif state.current_view == "week" then
        -- Week view: Sunday to Saturday of current week
        local today = os.date("%Y-%m-%d")
        local weekday = M.get_weekday(today) -- 0=Sunday, 6=Saturday
        start_date = M.add_days(today, -weekday) -- Go back to Sunday
        end_date = M.add_days(start_date, 6) -- Go to Saturday
    end

    return start_date, end_date
end

-- Navigate to next period based on current view
function M.next_period()
    if state.current_view == "day" then
        state.current_date = M.add_days(state.current_date, 1)
    elseif state.current_view == "3day" then
        state.current_date = M.add_days(state.current_date, 3)
    elseif state.current_view == "week" then
        state.current_date = M.add_days(state.current_date, 7)
    end
end

-- Navigate to previous period based on current view
function M.prev_period()
    if state.current_view == "day" then
        state.current_date = M.add_days(state.current_date, -1)
    elseif state.current_view == "3day" then
        state.current_date = M.add_days(state.current_date, -3)
    elseif state.current_view == "week" then
        state.current_date = M.add_days(state.current_date, -7)
    end
end

-- Jump to today
function M.today()
    state.current_date = os.date("%Y-%m-%d")
end

-- Add days to a date string (YYYY-MM-DD)
function M.add_days(date_str, days)
    local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
    if not year then
        return date_str
    end
    
    local time = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day)
    })
    
    time = time + (days * 86400) -- 86400 seconds in a day
    
    return os.date("%Y-%m-%d", time)
end

-- Get weekday for a date (0=Sunday, 6=Saturday)
function M.get_weekday(date_str)
    local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
    if not year then
        return 0
    end

    local time = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day)
    })

    -- Return 0=Sunday, 1=Monday, ..., 6=Saturday
    return tonumber(os.date("%w", time))
end

-- Format date for display
function M.format_date(date_str)
    local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
    if not year then
        return date_str
    end
    
    local time = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day)
    })
    
    return os.date("%A, %B %d, %Y", time)
end

-- Get short date format
function M.format_date_short(date_str)
    local year, month, day = date_str:match("(%d+)-(%d+)-(%d+)")
    if not year then
        return date_str
    end
    
    local time = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day)
    })
    
    return os.date("%a %m/%d", time)
end

-- Set window open state
function M.set_window_open(is_open)
    state.window_open = is_open
end

-- Get window open state
function M.is_window_open()
    return state.window_open
end

-- Store events
function M.set_events(events)
    state.events = events or {}
end

-- Get stored events
function M.get_events()
    return state.events
end

return M