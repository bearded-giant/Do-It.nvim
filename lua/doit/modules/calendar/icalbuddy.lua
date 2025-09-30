-- icalbuddy integration for calendar module (parser for actual output format)
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

                local event = {
                    title = meeting,
                    date = date,
                    start_time = string.format("%02d:00", hour),
                    end_time = string.format("%02d:00", hour + 1),
                    location = "Conference Room",
                    calendar = "Work"
                }

                -- Make some meetings tentative (30% chance)
                if math.random() < 0.3 then
                    event.tentative = true
                end

                table.insert(events, event)
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

-- Parse actual icalbuddy output format (no "" prefix, just plain text)
function M.parse_output(output, debug)
    local events = {}

    if debug and output and #output > 0 then
        local preview = output:sub(1, 500)
        -- vim.notify("Parsing icalbuddy output (first 500 chars):\n" .. preview, vim.log.levels.DEBUG)
    end

    -- Split into lines
    local lines = vim.split(output, "\n")

    if debug then
        -- vim.notify(string.format("Processing %d lines", #lines), vim.log.levels.DEBUG)
    end

    local i = 1
    while i <= #lines do
        local line = lines[i]

        -- Check if it's an event title line (starts with "" or non-indented, non-empty)
        if line:match('^""') or (line ~= "" and not line:match("^%s")) then
            local title = line
            -- Remove the "" prefix if present
            if title:match('^""') then
                title = title:match('^""(.+)')
            end
            local event = {
                title = title and title:gsub("^%s+", ""):gsub("%s+$", "") or line -- trim
            }

            if debug then
                -- vim.notify(string.format("New event at line %d: %s", i, event.title or "NO-TITLE"), vim.log.levels.DEBUG)
            end

            -- Collect all property lines for this event
            local properties = {}
            local j = i + 1
            while j <= #lines and (lines[j] == "" or lines[j]:match("^%s")) do
                local prop_line = lines[j]

                -- Only process lines with 4-space indent (property lines)
                if prop_line:match("^    ") and not prop_line:match("^        ") then
                    local content = prop_line:gsub("^    ", "") -- Remove exactly 4 spaces
                    table.insert(properties, content)
                end
                j = j + 1
            end

            -- Process properties in flexible order
            -- Process datetime first if it exists (since it sets the date)
            for _, content in ipairs(properties) do
                -- Check if it's a datetime line (no prefix like location: or attendees:)
                if not content:match("^%w+:") then
                    local parsed = M.parse_datetime_line(content, debug)
                    if parsed then
                        event.date = parsed.date
                        event.start_time = parsed.start_time
                        event.end_time = parsed.end_time
                        event.all_day = parsed.all_day
                        if debug then
                            -- vim.notify(string.format("    Applied datetime to event: date=%s, start=%s, end=%s",
                            --     event.date, event.start_time or "nil", event.end_time or "nil"), vim.log.levels.DEBUG)
                        end
                    end
                end
            end

            -- Then process other properties
            for _, content in ipairs(properties) do
                -- Check for location
                if content:match("^location:") then
                    event.location = content:match("^location:%s*(.+)")

                -- Check for attendees (mark as tentative)
                elseif content:match("^attendees:") then
                    event.tentative = true

                -- Check for notes (skip but don't process)
                elseif content:match("^notes:") then
                    -- Notes field, ignore content
                end
            end

            -- Only add event if it has a date
            if event and event.title and event.date then
                -- Handle multi-day events by duplicating for each day
                if event.multi_day and event.end_date then
                    -- Calculate days between start and end
                    local current = event.date
                    while current <= event.end_date do
                        local day_event = vim.tbl_deep_extend("force", {}, event)
                        day_event.date = current
                        day_event.multi_day_indicator = true
                        table.insert(events, day_event)

                        -- Move to next day
                        local y, m, d = current:match("(%d+)-(%d+)-(%d+)")
                        local time = os.time({year = tonumber(y), month = tonumber(m), day = tonumber(d)})
                        current = os.date("%Y-%m-%d", time + 86400)
                    end
                else
                    -- Single day event
                    table.insert(events, event)
                end
                if debug then
                    -- vim.notify(string.format("  Saved event: %s on %s (%s)",
                    --     event.title, event.date,
                    --     event.start_time or "all-day"), vim.log.levels.DEBUG)
                end
            elseif event and event.title then
                if debug then
                    -- vim.notify(string.format("  SKIPPED event without date: '%s'", event.title), vim.log.levels.WARN)
                    -- Debug: show properties we collected
                    -- vim.notify(string.format("    Properties collected: %d", #properties), vim.log.levels.WARN)
                    for idx, prop in ipairs(properties) do
                        -- vim.notify(string.format("      [%d] %s", idx, prop:sub(1, 50)), vim.log.levels.WARN)
                    end
                end
            end

            -- Skip to the line after all properties have been processed
            i = j - 1  -- j is already at the next event or end, -1 because we'll increment below
        end

        i = i + 1
    end

    if debug then
        -- vim.notify(string.format("Total events parsed: %d", #events), vim.log.levels.DEBUG)
        -- for _, event in ipairs(events) do
        --     vim.notify(string.format("  - %s: %s (%s)",
        --         event.date or "no-date",
        --         event.title or "no-title",
        --         event.start_time or "all-day"), vim.log.levels.DEBUG)
        -- end
    end

    return events
end

-- Parse a datetime line from icalbuddy output
function M.parse_datetime_line(line, debug)
    local result = {}

    -- Normalize whitespace: replace narrow no-break space (U+202F) with regular space
    -- This is used by icalbuddy between time and AM/PM
    local nbsp = string.char(226, 128, 175)  -- UTF-8 for U+202F
    line = line:gsub(nbsp, " ")

    -- Always use actual current time for relative dates
    -- icalbuddy always returns relative dates based on TODAY, not the query date
    local base_time = os.time()

    -- Pattern for multi-day events like "yesterday - tomorrow" or "day before yesterday - tomorrow"
    -- Must NOT match "today at" patterns - check for absence of "at"
    if line:match(" %- ") and not line:match(" at ") then
        -- Parse the start and end of the range
        local start_part, end_part = line:match("^(.+) %- (.+)$")
        if start_part and end_part then
            -- Parse start date
            local start_date = nil
            if start_part:match("day before yesterday") then
                start_date = os.date("%Y-%m-%d", base_time - 2 * 86400)
            elseif start_part == "yesterday" then
                start_date = os.date("%Y-%m-%d", base_time - 86400)
            elseif start_part == "today" then
                start_date = os.date("%Y-%m-%d", base_time)
            elseif start_part == "tomorrow" then
                start_date = os.date("%Y-%m-%d", base_time + 86400)
            elseif start_part:match("day after tomorrow") then
                start_date = os.date("%Y-%m-%d", base_time + 2 * 86400)
            end

            -- Parse end date
            local end_date = nil
            if end_part:match("day before yesterday") then
                end_date = os.date("%Y-%m-%d", base_time - 2 * 86400)
            elseif end_part == "yesterday" then
                end_date = os.date("%Y-%m-%d", base_time - 86400)
            elseif end_part == "today" then
                end_date = os.date("%Y-%m-%d", base_time)
            elseif end_part == "tomorrow" then
                end_date = os.date("%Y-%m-%d", base_time + 86400)
            elseif end_part:match("day after tomorrow") then
                end_date = os.date("%Y-%m-%d", base_time + 2 * 86400)
            end

            if start_date and end_date then
                result.date = start_date
                result.end_date = end_date  -- Store the end date for multi-day events
                result.all_day = true
                result.multi_day = true
                return result
            end
        end
    end

    -- Pattern 1: "today at 5:20 AM - 7:43 AM"
    if line:match("today at %d+:%d+ [AP]M %- %d+:%d+ [AP]M") then
        result.date = os.date("%Y-%m-%d", base_time)
        local start_str, end_str = line:match("today at (%d+:%d+ [AP]M) %- (%d+:%d+ [AP]M)")
        result.start_time = M.parse_time(start_str)
        result.end_time = M.parse_time(end_str)

    -- Pattern 2: "tomorrow at 8:00 AM - 10:00 AM" (but NOT "day after tomorrow")
    elseif line:match("tomorrow at %d+:%d+ [AP]M %- %d+:%d+ [AP]M") and not line:match("day after tomorrow") then
        result.date = os.date("%Y-%m-%d", base_time + 86400)
        local start_str, end_str = line:match("tomorrow at (%d+:%d+ [AP]M) %- (%d+:%d+ [AP]M)")
        result.start_time = M.parse_time(start_str)
        result.end_time = M.parse_time(end_str)

    -- Pattern 3: "day after tomorrow at 7:30 AM - 9:00 AM"
    elseif line:match("day after tomorrow at %d+:%d+ [AP]M %- %d+:%d+ [AP]M") then
        result.date = os.date("%Y-%m-%d", base_time + 2 * 86400)
        local start_str, end_str = line:match("day after tomorrow at (%d+:%d+ [AP]M) %- (%d+:%d+ [AP]M)")
        result.start_time = M.parse_time(start_str)
        result.end_time = M.parse_time(end_str)

    -- Pattern 4: "yesterday at ..."
    elseif line:match("yesterday at %d+:%d+ [AP]M %- %d+:%d+ [AP]M") then
        result.date = os.date("%Y-%m-%d", base_time - 86400)
        local start_str, end_str = line:match("yesterday at (%d+:%d+ [AP]M) %- (%d+:%d+ [AP]M)")
        result.start_time = M.parse_time(start_str)
        result.end_time = M.parse_time(end_str)

    -- Pattern 5: "Oct 1, 2025 at 9:00 AM - 12:00 PM"
    elseif line:match("%a+ %d+, %d+ at %d+:%d+ [AP]M %- %d+:%d+ [AP]M") then
        local date_str, start_str, end_str = line:match("(.+) at (%d+:%d+ [AP]M) %- (%d+:%d+ [AP]M)")
        result.date = M.parse_absolute_date(date_str)
        result.start_time = M.parse_time(start_str)
        result.end_time = M.parse_time(end_str)

    -- Pattern 6: All-day "today"
    elseif line == "today" then
        result.date = os.date("%Y-%m-%d", base_time)
        result.all_day = true

    -- Pattern 7: All-day "tomorrow"
    elseif line == "tomorrow" then
        result.date = os.date("%Y-%m-%d", base_time + 86400)
        result.all_day = true

    -- Pattern 8: All-day "yesterday"
    elseif line == "yesterday" then
        result.date = os.date("%Y-%m-%d", base_time - 86400)
        result.all_day = true

    -- Pattern 9: All-day "day after tomorrow"
    elseif line == "day after tomorrow" then
        result.date = os.date("%Y-%m-%d", base_time + 2 * 86400)
        result.all_day = true

    -- Pattern 10: Single day all-day "Oct 3, 2025"
    elseif line:match("%a+ %d+, %d+$") then
        result.date = M.parse_absolute_date(line)
        result.all_day = true

    -- Pattern 11: Multi-day with times "day after tomorrow at 8:30 PM - Oct 1, 2025 at 12:00 AM"
    elseif line:match("day after tomorrow at %d+:%d+.[AP]M %- %a+ %d+, %d+ at %d+:%d+.[AP]M") then
        result.date = os.date("%Y-%m-%d", base_time + 2 * 86400)
        local start_str = line:match("day after tomorrow at (%d+:%d+.[AP]M)")
        result.start_time = M.parse_time(start_str)
        -- For multi-day events, we'll just show on the start day for now
        result.end_time = "23:59"

    -- Pattern 12: Multi-day with times "tomorrow at 8:30 PM - day after tomorrow at 12:00 AM"
    elseif line:match("tomorrow at %d+:%d+.[AP]M %- day after tomorrow at %d+:%d+.[AP]M") then
        result.date = os.date("%Y-%m-%d", base_time + 86400)
        local start_str = line:match("tomorrow at (%d+:%d+.[AP]M)")
        result.start_time = M.parse_time(start_str)
        -- For multi-day events ending next day, extend to end of current day
        result.end_time = "23:59"

    -- Pattern 13: "payday" or other special keywords
    elseif line == "payday" then
        -- Try to extract from context, for now use a future date
        result.date = os.date("%Y-%m-%d", base_time + 5 * 86400)
        result.all_day = true

    else
        if debug then
            -- vim.notify(string.format("Could not parse datetime: %s", line), vim.log.levels.WARN)
        end
        return nil
    end

    return result
end

-- Parse a time string like "5:20 AM" to "05:20"
function M.parse_time(time_str)
    if not time_str then return nil end

    local hour, min, ampm = time_str:match("(%d+):(%d+) ([AP]M)")
    if not hour then return nil end

    hour = tonumber(hour)
    if ampm == "PM" and hour ~= 12 then
        hour = hour + 12
    elseif ampm == "AM" and hour == 12 then
        hour = 0
    end

    return string.format("%02d:%s", hour, min)
end

-- Parse an absolute date like "Oct 1, 2025" to "2025-10-01"
function M.parse_absolute_date(date_str)
    local month_names = {
        Jan = 1, January = 1,
        Feb = 2, February = 2,
        Mar = 3, March = 3,
        Apr = 4, April = 4,
        May = 5,
        Jun = 6, June = 6,
        Jul = 7, July = 7,
        Aug = 8, August = 8,
        Sep = 9, September = 9, Sept = 9,
        Oct = 10, October = 10,
        Nov = 11, November = 11,
        Dec = 12, December = 12
    }

    local month_str, day, year = date_str:match("(%a+) (%d+), (%d+)")
    if month_str and day and year then
        local month = month_names[month_str]
        if month then
            return string.format("%04d-%02d-%02d", tonumber(year), month, tonumber(day))
        end
    end

    -- Fallback to today
    return os.date("%Y-%m-%d")
end

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

    -- Build icalbuddy command
    -- For io.popen, we need proper shell syntax
    local cmd = string.format(
        "icalbuddy -nc -b '\"\"' eventsFrom:%s to:%s",
        start_date,
        end_date
    )

    -- Debug: Log the command and date range
    if config.debug then
        -- vim.notify(string.format("Fetching events from %s to %s", start_date, end_date), vim.log.levels.DEBUG)
        -- vim.notify("icalbuddy command: " .. cmd, vim.log.levels.DEBUG)
    end

    -- Execute icalbuddy
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        vim.notify("Failed to execute icalbuddy command", vim.log.levels.ERROR)
        return {}
    end

    local output = handle:read("*a")
    handle:close()

    -- Debug: Log the raw output
    if config.debug then
        -- vim.notify("icalbuddy raw output length: " .. #output, vim.log.levels.DEBUG)
        if #output > 0 then
            -- Count events in raw output for debugging
            local event_count = 0
            for line in output:gmatch("[^\n]+") do
                if line:match('^""') then
                    event_count = event_count + 1
                end
            end
            -- vim.notify(string.format("Raw output contains %d events (lines starting with \"\")", event_count), vim.log.levels.DEBUG)
            -- vim.notify("icalbuddy raw output (first 1000 chars):\n" .. output:sub(1, 1000), vim.log.levels.DEBUG)
        else
            -- vim.notify("icalbuddy returned empty output", vim.log.levels.WARN)
        end
    end

    -- Parse output
    local events = M.parse_output(output, config.debug)

    -- Deduplicate events before caching
    local seen = {}
    local unique_events = {}
    for _, event in ipairs(events) do
        local key = string.format("%s|%s|%s",
            event.date or "",
            event.title or "",
            event.start_time or "all-day")
        if not seen[key] then
            seen[key] = true
            table.insert(unique_events, event)
        end
    end

    -- Update cache with deduplicated events
    cache.data = unique_events
    cache.timestamp = now

    return unique_events
end

-- Filter events by date range
function M.filter_events(events, start_date, end_date)
    local filtered = {}
    local seen = {}  -- Track unique events to prevent duplicates

    for _, event in ipairs(events) do
        if event.date and event.date >= start_date and event.date <= end_date then
            -- Create a unique key for the event (date + title + time)
            local key = string.format("%s|%s|%s",
                event.date or "",
                event.title or "",
                event.start_time or "all-day")

            -- Only add if we haven't seen this exact event
            if not seen[key] then
                seen[key] = true
                table.insert(filtered, event)
            end
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

-- Get cache info for debugging
function M.get_cache_info()
    if cache.data then
        return {
            events = cache.data,
            timestamp = cache.timestamp
        }
    end
    return nil
end

return M