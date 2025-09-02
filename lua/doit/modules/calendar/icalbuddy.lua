-- icalbuddy integration for calendar module
local M = {}

-- Cache for event data
local cache = {
    data = nil,
    timestamp = 0
}

-- Check if running in Docker
local function is_docker()
    local f = io.open("/.dockerenv", "r")
    if f then
        f:close()
        return true
    end
    return false
end

-- Generate mock events for demo/testing
local function generate_mock_events(start_date, end_date)
    local events = {}
    
    -- Parse dates
    local s_year, s_month, s_day = start_date:match("(%d+)-(%d+)-(%d+)")
    local e_year, e_month, e_day = end_date:match("(%d+)-(%d+)-(%d+)")
    
    if not s_year then
        return events
    end
    
    local start_time = os.time({
        year = tonumber(s_year),
        month = tonumber(s_month),
        day = tonumber(s_day)
    })
    
    local end_time = os.time({
        year = tonumber(e_year),
        month = tonumber(e_month), 
        day = tonumber(e_day)
    })
    
    -- Generate events for each day in range
    local current = start_time
    while current <= end_time do
        local date = os.date("%Y-%m-%d", current)
        local weekday = tonumber(os.date("%w", current))
        
        -- Skip weekends for work events
        if weekday > 0 and weekday < 6 then
            -- Morning standup
            table.insert(events, {
                title = "Team Standup",
                date = date,
                start_time = "09:00",
                end_time = "09:30",
                location = "Zoom",
                calendar = "Work"
            })
            
            -- Random meeting in the day
            if math.random() > 0.3 then
                local meeting_types = {
                    "Product Review",
                    "1:1 with Manager", 
                    "Engineering Sync",
                    "Design Review",
                    "Sprint Planning"
                }
                local meeting = meeting_types[math.random(#meeting_types)]
                local hour = math.random(10, 15)
                
                table.insert(events, {
                    title = meeting,
                    date = date,
                    start_time = string.format("%02d:00", hour),
                    end_time = string.format("%02d:00", hour + 1),
                    location = "Conference Room",
                    calendar = "Work"
                })
            end
            
            -- Lunch reminder
            table.insert(events, {
                title = "Lunch Break",
                date = date,
                start_time = "12:00",
                end_time = "13:00",
                calendar = "Personal"
            })
        else
            -- Weekend events
            if math.random() > 0.5 then
                table.insert(events, {
                    title = "Weekend Project Time",
                    date = date,
                    all_day = true,
                    calendar = "Personal"
                })
            end
        end
        
        current = current + 86400 -- Add one day
    end
    
    return events
end

-- Check if icalbuddy is available
function M.check_availability()
    -- Always return true if in Docker (we'll use mock data)
    if is_docker() then
        return true
    end
    
    local handle = io.popen("which icalbuddy 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        return result ~= ""
    end
    return false
end

-- Parse a single event from icalbuddy output

-- Get events for a date range
function M.get_events(start_date, end_date, config)
    config = config or {}
    
    -- Use mock data if in Docker
    if is_docker() then
        -- Set random seed based on date for consistency
        local seed = tonumber((start_date:gsub("-", ""))) or os.time()
        math.randomseed(seed)
        
        local events = generate_mock_events(start_date, end_date)
        
        -- Update cache
        cache.data = events
        cache.timestamp = os.time()
        
        return events
    end
    
    -- Check cache
    local now = os.time()
    local cache_ttl = config.cache_ttl or 60
    if cache.data and (now - cache.timestamp) < cache_ttl then
        return M.filter_events(cache.data, start_date, end_date)
    end
    
    -- Build icalbuddy command with better formatting options
    local cmd_parts = {
        config.path or "icalbuddy",
        '--includeEventProps "title,datetime"',
        '--propertyOrder "datetime,title"',
        '--noCalendarNames',
        '--bullet ""',
        "eventsFrom:" .. start_date,
        "to:" .. end_date
    }
    
    local cmd = table.concat(cmd_parts, " ")
    
    -- Execute icalbuddy
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        return {}
    end
    
    local output = handle:read("*a")
    handle:close()
    
    -- Parse output
    local events = M.parse_output(output)
    
    -- Debug: Check if times are present
    -- for _, event in ipairs(events) do
    --     if event.date_str and event.date_str:match(" at ") then
    --         print("DEBUG: Event " .. event.title .. " has date_str with times: " .. event.date_str)
    --         print("  start_time: " .. (event.start_time or "nil"))
    --     end
    -- end
    
    -- Update cache
    cache.data = events
    cache.timestamp = now
    
    return events
end

-- Parse icalbuddy output (new format with datetime first, then title)
function M.parse_output(output)
    local events = {}
    
    -- Split into lines
    local lines = vim.split(output, "\n")
    
    local i = 1
    local current_date = nil  -- Track current date context
    local current_date_str = nil  -- Track the actual date string
    
    while i <= #lines do
        local line = lines[i]
        
        -- Skip empty lines
        if line == "" then
            i = i + 1
        -- Check for date headers (can be "today", "tomorrow", "day after tomorrow", or actual dates)
        elseif not line:match("^%s") and not line:match(" at ") then
            -- This is a date header line
            current_date = line
            
            -- Convert to actual date string
            if line:match("^today") then
                current_date_str = os.date("%Y-%m-%d")
            elseif line:match("^tomorrow$") then
                current_date_str = os.date("%Y-%m-%d", os.time() + 86400)
            elseif line:match("^day after tomorrow") then
                current_date_str = os.date("%Y-%m-%d", os.time() + 2 * 86400)
            else
                -- Parse actual date like "Wednesday, September 4, 2025" or "September 4, 2025" or "Sep 4, 2025"
                -- Try with day name first
                local weekday, month_str, day, year = line:match("^(%a+), (%a+) (%d+), (%d+)")
                if not month_str then
                    -- Try without day name (full month name)
                    month_str, day, year = line:match("^(%a+) (%d+), (%d+)")
                end
                if not month_str then
                    -- Try abbreviated month format "Sep 4, 2025"
                    month_str, day, year = line:match("^(%a%a%a) (%d+), (%d+)")
                end
                
                if month_str and day and year then
                    local months = {
                        Jan = 1, January = 1,
                        Feb = 2, February = 2,
                        Mar = 3, March = 3,
                        Apr = 4, April = 4,
                        May = 5,
                        Jun = 6, June = 6,
                        Jul = 7, July = 7,
                        Aug = 8, August = 8,
                        Sep = 9, September = 9,
                        Oct = 10, October = 10,
                        Nov = 11, November = 11,
                        Dec = 12, December = 12
                    }
                    local month = months[month_str]
                    if month then
                        current_date_str = string.format("%04d-%02d-%02d", 
                            tonumber(year),
                            month, 
                            tonumber(day))
                    end
                end
            end
            i = i + 1
        -- Check for datetime line (e.g., "tomorrow at 11:30 AM - 12:00 PM" or "day after tomorrow at...")
        -- Note: icalbuddy uses non-breaking spaces (0xC2 0xA0) in times
        elseif not line:match("^%s") and line:match(" at %d+:%d+.+[AP]M %- %d+:%d+.+[AP]M") then
            local event = {}
            
            -- Parse the datetime (use .+ for spaces since icalbuddy uses non-breaking spaces)
            local date_part, start_time, start_ampm, end_time, end_ampm = 
                line:match("^(.+) at (%d+:%d+).+([AP]M) %- (%d+:%d+).+([AP]M)")
            
            -- Check if the date_part is a relative date that should update our context
            if date_part then
                if date_part:match("^today") then
                    current_date_str = os.date("%Y-%m-%d")
                elseif date_part:match("^tomorrow$") then
                    current_date_str = os.date("%Y-%m-%d", os.time() + 86400)
                elseif date_part:match("^day after tomorrow") then
                    current_date_str = os.date("%Y-%m-%d", os.time() + 2 * 86400)
                elseif date_part:match("^(%a%a%a) (%d+), (%d+)") then
                    -- Parse date like "Sep 4, 2025"
                    local month_str, day, year = date_part:match("^(%a%a%a) (%d+), (%d+)")
                    if month_str and day and year then
                        local months = {
                            Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
                            Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12
                        }
                        local month = months[month_str]
                        if month then
                            current_date_str = string.format("%04d-%02d-%02d", 
                                tonumber(year),
                                month, 
                                tonumber(day))
                        end
                    end
                end
            end
            
            if start_time and end_time then
                -- Convert to 24-hour format
                local hour, min = start_time:match("(%d+):(%d+)")
                hour = tonumber(hour)
                if start_ampm == "PM" and hour ~= 12 then
                    hour = hour + 12
                elseif start_ampm == "AM" and hour == 12 then
                    hour = 0
                end
                event.start_time = string.format("%02d:%s", hour, min)
                
                hour, min = end_time:match("(%d+):(%d+)")
                hour = tonumber(hour)
                if end_ampm == "PM" and hour ~= 12 then
                    hour = hour + 12
                elseif end_ampm == "AM" and hour == 12 then
                    hour = 0
                end
                event.end_time = string.format("%02d:%s", hour, min)
            end
            
            -- Get the title from the next line (should be indented)
            i = i + 1
            if i <= #lines and lines[i]:match("^%s+") then
                event.title = lines[i]:gsub("^%s+", "")
            end
            
            -- Use the current_date_str we tracked from the date header
            event.date = current_date_str
            
            table.insert(events, event)
            i = i + 1
        -- Check for all-day event (just indented title, no time)
        elseif line:match("^%s+%S") then
            local event = {}
            event.title = line:gsub("^%s+", "")
            event.all_day = true
            
            -- Use the current_date_str we tracked from the date header
            event.date = current_date_str
            
            table.insert(events, event)
            i = i + 1
        else
            i = i + 1
        end
    end
    
    return events
end

-- Filter events by date range
function M.filter_events(events, start_date, end_date)
    local filtered = {}
    
    for _, event in ipairs(events) do
        if event.date and event.date >= start_date and event.date <= end_date then
            table.insert(filtered, event)
        end
    end
    
    return filtered
end

-- Get events for today
function M.get_today_events(config)
    local today = os.date("%Y-%m-%d")
    return M.get_events(today, today, config)
end

-- Get events for a specific date
function M.get_date_events(date, config)
    return M.get_events(date, date, config)
end

-- Clear cache
function M.clear_cache()
    cache.data = nil
    cache.timestamp = 0
end

return M