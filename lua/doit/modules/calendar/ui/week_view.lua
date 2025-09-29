-- Week view renderer for calendar UI (column layout)
local M = {}

-- Helper function to format time
local function format_time(time_str)
    local hour, min = time_str:match("(%d+):(%d+)")
    if not hour then return time_str:sub(1, 5) end
    hour = tonumber(hour)
    local ampm = hour >= 12 and "p" or "a"
    if hour > 12 then
        hour = hour - 12
    elseif hour == 0 then
        hour = 12
    end
    return string.format("%d:%s%s", hour, min, ampm)
end

-- Truncate text to fit column width
local function truncate(text, max_len)
    if #text <= max_len then
        return text
    end
    return text:sub(1, max_len - 2) .. ".."
end

-- Render week view in columns
function M.render(calendar_module)
    local lines = {}
    local state = calendar_module.state
    local config = calendar_module.config

    -- Get date range (Monday to Sunday)
    local start_date, end_date = state.get_date_range()
    local events = state.get_events() or {}

    -- Debug: Log events and dates
    if config.icalbuddy and config.icalbuddy.debug then
        -- vim.notify(string.format("Week view: %s to %s", start_date, end_date), vim.log.levels.DEBUG)
        -- vim.notify(string.format("Total events in state: %d", #events), vim.log.levels.DEBUG)
        for _, event in ipairs(events) do
            -- vim.notify(string.format("  Event: %s on %s", event.title or "no-title", event.date or "no-date"), vim.log.levels.DEBUG)
        end
    end

    -- Use actual window width if available, otherwise fall back to config
    local total_width = config.window.actual_width or config.window.width

    -- Calculate column width (divide available width by 7 columns)
    local separators_total = 6  -- 6 separators × 1 char each
    local available_for_columns = total_width - separators_total - 2  -- -2 for side padding
    local col_width = math.floor(available_for_columns / 7)

    -- Header
    local header = string.format(" Week View: %s - %s ",
        state.format_date_short(start_date),
        state.format_date_short(end_date))
    table.insert(lines, header)
    table.insert(lines, string.rep("─", total_width - 2))  -- -2 for padding

    -- Days of week labels (Sunday first)
    local days = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

    -- Prepare events for each day
    local day_data = {}
    local max_events = 0

    for i = 0, 6 do
        local date = state.add_days(start_date, i)
        local is_today = date == os.date("%Y-%m-%d")

        -- Get day number
        local day_num = tonumber(date:sub(9, 10))

        -- Filter and sort events for this day
        local day_events = {}
        for _, event in ipairs(events) do
            if config.icalbuddy and config.icalbuddy.debug and i == 0 then
                -- Debug first day only to avoid spam
                -- vim.notify(string.format("    Comparing event.date='%s' with date='%s': %s",
                --     event.date or "nil",
                --     date,
                --     tostring(event.date == date)), vim.log.levels.DEBUG)
            end
            if event.date == date then
                table.insert(day_events, event)
            end
        end

        table.sort(day_events, function(a, b)
            if a.all_day and not b.all_day then return true end
            if b.all_day and not a.all_day then return false end
            if a.all_day and b.all_day then
                return (a.title or "") < (b.title or "")
            end
            if a.start_time and b.start_time then
                return a.start_time < b.start_time
            end
            return false
        end)

        day_data[i + 1] = {
            label = days[i + 1],
            day_num = day_num,
            is_today = is_today,
            events = day_events
        }

        -- Limit events shown per day in week view
        local max_shown = 3
        if #day_events > max_shown then
            local temp = {}
            for j = 1, max_shown - 1 do
                temp[j] = day_events[j]
            end
            temp[max_shown] = {
                title = string.format("+%d more", #day_events - max_shown + 1),
                is_more = true
            }
            day_data[i + 1].events = temp
        end

        max_events = math.max(max_events, #day_data[i + 1].events)
    end

    -- Day headers row (day names)
    local header_line = ""
    for i = 1, 7 do
        local day = day_data[i]
        local header_text = day.label .. " " .. day.day_num
        if day.is_today then
            header_text = "▶" .. header_text:sub(2)
        end

        -- Pad/truncate to column width
        header_text = truncate(header_text, col_width)
        header_text = header_text .. string.rep(" ", math.max(0, col_width - #header_text))
        header_line = header_line .. header_text

        if i < 7 then
            header_line = header_line .. "│"
        end
    end
    table.insert(lines, header_line)

    -- Separator under headers
    local sep_line = string.rep("─", col_width)
    for i = 2, 7 do
        sep_line = sep_line .. "┼" .. string.rep("─", col_width)
    end
    table.insert(lines, sep_line)

    -- Event rows
    for row = 1, math.max(max_events, 1) do
        local line = ""

        for col = 1, 7 do
            local day = day_data[col]
            local event = day.events[row]
            local cell_text = ""

            if event then
                if event.is_more then
                    cell_text = event.title or ""
                else
                    -- Add tentative indicator (?) at the start if event is tentative
                    local prefix = event.tentative and "?" or ""
                    local title = event.title or "(No title)"

                    if event.all_day then
                        cell_text = prefix .. "• " .. title
                    elseif event.start_time then
                        local time_str = format_time(event.start_time)
                        cell_text = prefix .. time_str .. " " .. title
                    else
                        cell_text = prefix .. title
                    end
                end
                cell_text = truncate(cell_text, col_width)
            elseif row == 1 and #day.events == 0 then
                cell_text = "-"
            end

            -- Pad to column width
            cell_text = cell_text .. string.rep(" ", math.max(0, col_width - #cell_text))
            line = line .. cell_text

            if col < 7 then
                line = line .. "│"
            end
        end

        table.insert(lines, line)
    end

    -- Footer
    table.insert(lines, "")
    table.insert(lines, string.rep("─", total_width - 2))  -- -2 for padding
    local footer = " [d]ay [3]day [w]eek │ [h/l] prev/next │ [t]oday │ [q]uit "
    table.insert(lines, footer)

    return lines
end

return M