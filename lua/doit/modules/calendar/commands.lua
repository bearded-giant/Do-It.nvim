-- Commands for calendar module
local M = {}

-- Module reference
local calendar_module = nil

-- Setup commands
function M.setup(module)
    calendar_module = module
    
    -- Create commands
    M.create_commands()
    
    -- Return empty table since commands are created directly
    return {}
end

-- Create Vim commands
function M.create_commands()
    -- Main calendar command
    vim.api.nvim_create_user_command("DoItCalendar", function(opts)
        local args = vim.split(opts.args or "", " ")
        local cmd = args[1] or ""
        
        if cmd == "" or cmd == "toggle" then
            calendar_module.toggle()
        elseif cmd == "show" then
            calendar_module.show()
        elseif cmd == "hide" then
            calendar_module.hide()
        elseif cmd == "today" then
            -- Jump to today and refresh
            if calendar_module.state then
                calendar_module.state.today()
                calendar_module.refresh()
                -- vim.notify("Calendar: Jumped to today", vim.log.levels.INFO)
            else
                vim.notify("Calendar: State not initialized", vim.log.levels.ERROR)
            end
        elseif cmd == "next" then
            calendar_module.next_period()
        elseif cmd == "prev" then
            calendar_module.prev_period()
        elseif cmd == "view" then
            local view = args[2]
            if view then
                calendar_module.switch_view(view)
            end
        elseif cmd == "refresh" then
            local icalbuddy = require("doit.modules.calendar.icalbuddy")
            icalbuddy.clear_cache()
            calendar_module.refresh()
        elseif cmd == "debug" then
            -- Toggle debug mode
            local config = calendar_module.config
            config.icalbuddy.debug = not config.icalbuddy.debug
            vim.notify("Calendar debug mode: " .. tostring(config.icalbuddy.debug), vim.log.levels.INFO)
            -- Clear cache and refresh to see debug output
            local icalbuddy = require("doit.modules.calendar.icalbuddy")
            icalbuddy.clear_cache()
            calendar_module.refresh()
        elseif cmd == "test-parser-detailed" then
            -- Run detailed parser test
            local test = require("doit.modules.calendar.test_parser")
            test.test()
        elseif cmd == "test-parse" then
            -- Test the parsing with sample data
            local icalbuddy = require("doit.modules.calendar.icalbuddy")

            local test_output = [[
today - - Stay at Grand Hyatt Deer Valley - attendees: bryan.grimes@rechargeapps.com
today at 7:20 AM - 9:43 AM - Flight to Chicago (AA 3074) - attendees: bryan.grimes@rechargeapps.com
today at 11:12 AM - 2:38 PM - Flight: ORD to SLC
tomorrow - - All Day Event - attendees: test@example.com
tomorrow at 2:00 PM - 3:00 PM - Product Review
day after tomorrow at 10:00 AM - 10:30 AM - 1:1 Meeting
]]

            local events = icalbuddy.parse_output(test_output, true)

            vim.notify(string.format("Test Parse: Found %d events", #events), vim.log.levels.INFO)
            for i, event in ipairs(events) do
                vim.notify(string.format("[%d] Date: %s, Title: %s, Time: %s-%s, Tentative: %s",
                    i,
                    event.date or "NO-DATE",
                    event.title or "NO-TITLE",
                    event.start_time or "all-day",
                    event.end_time or "",
                    tostring(event.tentative)), vim.log.levels.INFO)
            end
        elseif cmd == "check-date" then
            -- Check system date and calendar dates
            local today_system = os.date("%Y-%m-%d")
            local today_time = os.time()
            local tomorrow = os.date("%Y-%m-%d", today_time + 86400)

            vim.notify("Date Check:", vim.log.levels.INFO)
            vim.notify(string.format("  System date: %s", today_system), vim.log.levels.INFO)
            vim.notify(string.format("  System time: %s", os.date("%Y-%m-%d %H:%M:%S")), vim.log.levels.INFO)
            vim.notify(string.format("  Tomorrow: %s", tomorrow), vim.log.levels.INFO)

            -- Check calendar state
            if calendar_module.state then
                local current_date = calendar_module.state.get_date()
                local start_date, end_date = calendar_module.state.get_date_range()
                vim.notify(string.format("  Calendar current: %s", current_date), vim.log.levels.INFO)
                vim.notify(string.format("  Calendar range: %s to %s", start_date, end_date), vim.log.levels.INFO)
            end

            -- Test icalbuddy command
            local cmd = 'icalbuddy -nc -b "" eventsToday'
            local handle = io.popen(cmd .. " 2>&1")
            if handle then
                local output = handle:read("*a")
                handle:close()
                vim.notify(string.format("  icalbuddy eventsToday length: %d chars", #output), vim.log.levels.INFO)
                if #output > 0 then
                    vim.notify("  First line: " .. (output:match("^[^\n]+") or ""), vim.log.levels.INFO)
                end
            end
        elseif cmd == "check-state" then
            -- Check what's in the calendar state
            local state = calendar_module.state
            if not state then
                vim.notify("Calendar: State not initialized", vim.log.levels.ERROR)
                return
            end

            local current_date = state.get_date()
            local view = state.get_view()
            local start_date, end_date = state.get_date_range()
            local events = state.get_events() or {}

            vim.notify(string.format("Calendar State:", vim.log.levels.INFO))
            vim.notify(string.format("  Current Date: %s", current_date), vim.log.levels.INFO)
            vim.notify(string.format("  Current View: %s", view), vim.log.levels.INFO)
            vim.notify(string.format("  Date Range: %s to %s", start_date, end_date), vim.log.levels.INFO)
            vim.notify(string.format("  Total Events in State: %d", #events), vim.log.levels.INFO)

            -- Show first 5 events
            for i = 1, math.min(5, #events) do
                local e = events[i]
                vim.notify(string.format("  [%d] %s on %s (%s)",
                    i,
                    e.title or "NO-TITLE",
                    e.date or "NO-DATE",
                    e.start_time or "all-day"), vim.log.levels.INFO)
            end

            if #events > 5 then
                vim.notify(string.format("  ... and %d more events", #events - 5), vim.log.levels.INFO)
            end
        elseif cmd == "diagnose" then
            -- Run diagnostic to show raw icalbuddy output
            local icalbuddy = require("doit.modules.calendar.icalbuddy")
            local state = calendar_module.state
            local start_date, end_date = state.get_date_range()

            -- Build command
            local cmd_parts = {
                "icalbuddy",
                '-nc',
                '-b ""',
                '-iep "title,datetime,attendees"',
                '-po "datetime,title,attendees"',
                '-df ""',
                '-ps "| - |"',
                "eventsFrom:" .. start_date,
                "to:" .. end_date
            }
            local cmd = table.concat(cmd_parts, " ")

            vim.notify("Running: " .. cmd, vim.log.levels.INFO)

            local handle = io.popen(cmd .. " 2>&1")
            if handle then
                local output = handle:read("*a")
                handle:close()

                -- Save to a buffer for inspection
                local buf = vim.api.nvim_create_buf(false, true)
                local lines = vim.split(output, "\n")
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                vim.api.nvim_buf_set_option(buf, 'modifiable', false)
                vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
                vim.api.nvim_buf_set_name(buf, "icalbuddy-output")

                -- Open in a new window
                vim.cmd("split")
                vim.api.nvim_set_current_buf(buf)

                vim.notify("icalbuddy output opened in new buffer. Lines: " .. #lines, vim.log.levels.INFO)
            else
                vim.notify("Failed to run icalbuddy", vim.log.levels.ERROR)
            end
        else
            vim.notify("Unknown calendar command: " .. cmd, vim.log.levels.WARN)
        end
    end, {
        nargs = "*",
        complete = function(arglead, cmdline, cursorpos)
            local args = vim.split(cmdline, " ")
            if #args == 2 then
                return vim.tbl_filter(function(val)
                    return val:find(arglead, 1, true) == 1
                end, {
                    "toggle", "show", "hide", "today", "next", "prev", "view", "refresh", "debug", "diagnose", "test-parse", "check-state"
                })
            elseif #args == 3 and args[2] == "view" then
                return vim.tbl_filter(function(val)
                    return val:find(arglead, 1, true) == 1
                end, {
                    "day", "3day", "week"
                })
            end
            return {}
        end,
        desc = "Manage DoIt Calendar"
    })
    
    -- Convenience commands
    vim.api.nvim_create_user_command("DoItCalendarDay", function()
        calendar_module.switch_view("day")
        calendar_module.show()
    end, { desc = "Show calendar in day view" })
    
    vim.api.nvim_create_user_command("DoItCalendar3Day", function()
        calendar_module.switch_view("3day")
        calendar_module.show()
    end, { desc = "Show calendar in 3-day view" })
    
    vim.api.nvim_create_user_command("DoItCalendarWeek", function()
        calendar_module.switch_view("week")
        calendar_module.show()
    end, { desc = "Show calendar in week view" })
end

return M