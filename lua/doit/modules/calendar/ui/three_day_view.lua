-- 3-day view renderer for calendar UI (column layout)
local M = {}

-- Helper function to format time
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

-- Truncate text to fit column width
local function truncate(text, max_len)
    if #text <= max_len then
        return text
    end
    return text:sub(1, max_len - 2) .. ".."
end

-- Render 3-day view in columns
function M.render(calendar_module)
    local lines = {}
    local state = calendar_module.state
    local config = calendar_module.config

    -- Get date range
    local start_date, end_date = state.get_date_range()
    local events = state.get_events() or {}

    -- Use actual window width if available, otherwise fall back to config
    local total_width = config.window.actual_width or config.window.width

    -- Calculate column width for 3 columns with separators
    -- We have 2 separators (" │ ") between 3 columns, each taking 3 chars
    local separators_total = 6  -- 2 separators × 3 chars each
    local available_for_columns = total_width - separators_total - 2  -- -2 for side padding
    local col_width = math.floor(available_for_columns / 3)

    -- Header
    local header = string.format(" 3-Day View: %s - %s ",
        state.format_date_short(start_date),
        state.format_date_short(end_date))
    table.insert(lines, header)
    table.insert(lines, string.rep("─", total_width - 2))  -- -2 for padding

    -- Prepare events for each day
    local day_data = {}
    local max_events = 0

    for i = 0, 2 do
        local date = state.add_days(start_date, i)
        local is_today = date == os.date("%Y-%m-%d")

        -- Get day name and date
        local day_header = state.format_date_short(date)
        local dow = os.date("%a", os.time({
            year = tonumber(date:sub(1, 4)),
            month = tonumber(date:sub(6, 7)),
            day = tonumber(date:sub(9, 10))
        }))

        -- Filter and sort events for this day
        local day_events = {}
        for _, event in ipairs(events) do
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
            header = dow .. " " .. day_header,
            is_today = is_today,
            events = day_events
        }

        max_events = math.max(max_events, #day_events)
    end

    -- Day headers row
    local header_line = ""
    for i = 1, 3 do
        local day = day_data[i]
        local header_text = day.header
        if day.is_today then
            header_text = "▶ " .. header_text
        else
            header_text = "  " .. header_text
        end

        -- Center the header in the column
        local padding = math.max(0, col_width - #header_text)
        local left_pad = math.floor(padding / 2)
        local right_pad = padding - left_pad

        header_line = header_line .. string.rep(" ", left_pad) .. header_text .. string.rep(" ", right_pad)

        if i < 3 then
            header_line = header_line .. " │ "
        end
    end
    table.insert(lines, header_line)

    -- Separator under headers
    local sep_line = string.rep("─", col_width)
    for i = 2, 3 do
        sep_line = sep_line .. "─┼─" .. string.rep("─", col_width)
    end
    table.insert(lines, sep_line)

    -- Event rows
    local event_lines = {}
    for row = 1, math.max(max_events, 1) do
        local line = ""

        for col = 1, 3 do
            local day = day_data[col]
            local event = day.events[row]
            local cell_text = ""

            if event then
                -- Add tentative indicator (?) at the start if event is tentative
                local prefix = event.tentative and "? " or ""
                local title = event.title or "(No title)"

                if event.all_day then
                    cell_text = prefix .. "[All Day] " .. title
                elseif event.start_time then
                    local time_str = format_time(event.start_time)
                    cell_text = prefix .. time_str .. " " .. title
                else
                    cell_text = prefix .. title
                end
                cell_text = truncate(cell_text, col_width)
            elseif row == 1 and #day.events == 0 then
                cell_text = "No events"
            end

            -- Pad to column width
            cell_text = cell_text .. string.rep(" ", math.max(0, col_width - #cell_text))
            line = line .. cell_text

            if col < 3 then
                line = line .. " │ "
            end
        end

        table.insert(event_lines, line)
    end

    -- Add event lines
    for _, line in ipairs(event_lines) do
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