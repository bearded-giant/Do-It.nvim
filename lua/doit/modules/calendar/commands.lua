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
            calendar_module.today()
            calendar_module.refresh()
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
                    "toggle", "show", "hide", "today", "next", "prev", "view", "refresh"
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