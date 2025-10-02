-- Day detail modal for displaying full event information without truncation
local M = {}

-- Module reference
local calendar_module = nil
local current_modal_win = nil
local current_modal_buf = nil

-- Helper function to format time
local function format_time(time_str)
    if not time_str or type(time_str) ~= "string" then
        return ""
    end

    local hour, min = time_str:match("(%d+):(%d+)")
    if not hour or not min then
        return time_str:sub(1, 5)  -- Fallback to first 5 chars
    end

    hour = tonumber(hour)
    if not hour then
        return time_str
    end

    local ampm = hour >= 12 and "pm" or "am"
    if hour > 12 then
        hour = hour - 12
    elseif hour == 0 then
        hour = 12
    end

    return string.format("%d:%02d%s", hour, min, ampm)
end

-- Close the current modal if it exists
function M.close_current_modal()
    if current_modal_win and vim.api.nvim_win_is_valid(current_modal_win) then
        vim.api.nvim_win_close(current_modal_win, true)
    end
    if current_modal_buf and vim.api.nvim_buf_is_valid(current_modal_buf) then
        vim.api.nvim_buf_delete(current_modal_buf, { force = true })
    end
    current_modal_win = nil
    current_modal_buf = nil
end

-- Show modal with day's events
function M.show_day(day_offset, parent_buf)
    if not calendar_module then
        vim.notify("Calendar module not initialized", vim.log.levels.ERROR)
        return
    end

    -- Close any existing modal first
    M.close_current_modal()

    local state = calendar_module.state
    local view = state.get_view()

    -- Calculate the date based on the view and offset
    local target_date
    if view == "week" then
        -- For week view, calculate from start of week (Sunday)
        local start_date = state.get_date_range()
        target_date = state.add_days(start_date, day_offset - 1)
    elseif view == "3day" then
        -- For 3-day view, calculate from today
        local start_date = os.date("%Y-%m-%d")
        target_date = state.add_days(start_date, day_offset - 1)
    else
        vim.notify("Day detail modal only works in 3-day or week view", vim.log.levels.WARN)
        return
    end

    -- Get events for the target date
    local all_events = state.get_events() or {}
    local day_events = {}

    for _, event in ipairs(all_events) do
        if event.date == target_date then
            table.insert(day_events, event)
        end
    end

    -- Sort events
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

    -- Prepare modal content
    local lines = {}
    local formatted_date = state.format_date(target_date)

    -- Header
    table.insert(lines, "")
    table.insert(lines, "  " .. formatted_date)
    table.insert(lines, "  " .. string.rep("─", #formatted_date))
    table.insert(lines, "")

    if #day_events == 0 then
        table.insert(lines, "  No events scheduled")
    else
        for _, event in ipairs(day_events) do
            -- Ensure event data is clean
            if type(event) ~= "table" then
                goto continue
            end

            local prefix = (event.tentative == true) and "[?] " or ""
            local title = tostring(event.title or "(No title)")

            -- Remove any special characters that might cause rendering issues
            title = title:gsub("[\r\n\t]", " ")

            if event.all_day then
                table.insert(lines, "  • [All Day] " .. prefix .. title)
            else
                local time_str = ""
                if event.start_time and event.end_time then
                    time_str = format_time(tostring(event.start_time)) .. " - " .. format_time(tostring(event.end_time))
                elseif event.start_time then
                    time_str = format_time(tostring(event.start_time))
                end

                if time_str ~= "" then
                    table.insert(lines, "  • " .. time_str)
                    table.insert(lines, "    " .. prefix .. title)
                else
                    table.insert(lines, "  • " .. prefix .. title)
                end
            end

            -- Add location if available (no emojis to avoid issues)
            if event.location and type(event.location) == "string" and event.location ~= "" then
                local location = tostring(event.location):gsub("[\r\n\t]", " ")
                table.insert(lines, "    Location: " .. location)
            end

            -- Add calendar name if available (no emojis to avoid issues)
            if event.calendar and type(event.calendar) == "string" and event.calendar ~= "" then
                local calendar = tostring(event.calendar):gsub("[\r\n\t]", " ")
                table.insert(lines, "    Calendar: " .. calendar)
            end

            table.insert(lines, "")

            ::continue::
        end
    end

    -- Footer
    table.insert(lines, "")
    table.insert(lines, "  Press [q] or [Esc] to close")
    table.insert(lines, "")

    -- Add extra empty lines to ensure full buffer coverage
    for _ = 1, 5 do
        table.insert(lines, "")
    end

    -- Calculate dimensions
    local max_width = 0
    for _, line in ipairs(lines) do
        max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
    end

    local width = math.min(max_width + 4, vim.o.columns - 10)
    local height = math.min(#lines + 2, vim.o.lines - 6)

    -- Pad all lines to full width to ensure complete background coverage
    for i, line in ipairs(lines) do
        local padding = width - vim.fn.strdisplaywidth(line)
        if padding > 0 then
            lines[i] = line .. string.rep(" ", padding)
        end
    end

    -- Create a fresh buffer for the modal
    local buf = vim.api.nvim_create_buf(false, true)
    current_modal_buf = buf

    -- Set buffer options BEFORE setting content
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)

    -- Set the content
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)

    -- Calculate position (centered)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    -- Create window with high z-index to ensure it appears on top
    local win_opts = {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = ' Day Details ',
        title_pos = 'center',
        zindex = 50,  -- Higher z-index to appear on top
        focusable = true,
    }

    local win = vim.api.nvim_open_win(buf, true, win_opts)
    current_modal_win = win

    -- Force focus to the new window
    vim.api.nvim_set_current_win(win)

    -- Set window options for proper isolation
    vim.api.nvim_win_set_option(win, 'winblend', 0)  -- Set to 0 for opaque background
    vim.api.nvim_win_set_option(win, 'cursorline', false)
    vim.api.nvim_win_set_option(win, 'wrap', false)
    vim.api.nvim_win_set_option(win, 'number', false)
    vim.api.nvim_win_set_option(win, 'relativenumber', false)
    vim.api.nvim_win_set_option(win, 'signcolumn', 'no')
    vim.api.nvim_win_set_option(win, 'spell', false)
    vim.api.nvim_win_set_option(win, 'fillchars', 'eob: ')  -- Hide end-of-buffer tildes

    -- Set window highlight to ensure proper background
    vim.api.nvim_win_set_option(win, 'winhighlight', 'Normal:Normal,FloatBorder:Normal')

    -- Setup keymaps to close modal
    local close_modal = function()
        M.close_current_modal()
        -- Return focus to parent buffer
        if parent_buf and vim.api.nvim_buf_is_valid(parent_buf) then
            local parent_wins = vim.fn.win_findbuf(parent_buf)
            if #parent_wins > 0 and vim.api.nvim_win_is_valid(parent_wins[1]) then
                vim.api.nvim_set_current_win(parent_wins[1])
            end
        end
    end

    vim.keymap.set('n', 'q', close_modal, { buffer = buf, silent = true })
    vim.keymap.set('n', '<Esc>', close_modal, { buffer = buf, silent = true })
end

-- Setup module
function M.setup(module)
    calendar_module = module
    return M
end

return M