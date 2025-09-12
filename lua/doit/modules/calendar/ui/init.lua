-- UI manager for calendar module
local M = {}

-- Module reference
local calendar_module = nil
local window = nil
local current_renderer = nil

-- Setup UI
function M.setup(module)
    calendar_module = module
    
    -- Initialize window module
    window = require("doit.modules.calendar.ui.window").setup(module)
    
    return M
end

-- Toggle calendar window
function M.toggle()
    if calendar_module.state.is_window_open() then
        M.hide()
    else
        M.show()
    end
end

-- Show calendar window
function M.show()
    if not window then
        return
    end
    
    -- Create window
    window.create()
    
    -- Mark as open
    calendar_module.state.set_window_open(true)
    
    -- Render content
    M.refresh()
    
    -- Setup keymaps
    M.setup_keymaps()
end

-- Hide calendar window
function M.hide()
    if not window then
        return
    end
    
    window.close()
    calendar_module.state.set_window_open(false)
end

-- Refresh calendar display
function M.refresh()
    if not calendar_module.state.is_window_open() then
        return
    end
    
    -- Get current view
    local view = calendar_module.state.get_view()
    
    -- Load appropriate renderer
    if view == "day" then
        current_renderer = require("doit.modules.calendar.ui.day_view")
    elseif view == "3day" then
        current_renderer = require("doit.modules.calendar.ui.three_day_view")
    elseif view == "week" then
        current_renderer = require("doit.modules.calendar.ui.week_view")
    end
    
    -- Get date range
    local start_date, end_date = calendar_module.state.get_date_range()
    
    -- Fetch events
    local icalbuddy = require("doit.modules.calendar.icalbuddy")
    local events = icalbuddy.get_events(start_date, end_date, calendar_module.config.icalbuddy)
    calendar_module.state.set_events(events)
    
    -- Render the view
    if current_renderer then
        local lines = current_renderer.render(calendar_module)
        window.set_content(lines)
    end
end

-- Setup keymaps for the calendar window
function M.setup_keymaps()
    local buf = window.get_buffer()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    
    local keymaps = calendar_module.config.keymaps
    local opts = { buffer = buf, silent = true }
    
    -- Close window
    if keymaps.close then
        vim.keymap.set("n", keymaps.close, function()
            M.hide()
        end, opts)
    end
    
    -- Navigation
    if keymaps.next_period then
        vim.keymap.set("n", keymaps.next_period, function()
            calendar_module.next_period()
        end, opts)
    end
    
    if keymaps.prev_period then
        vim.keymap.set("n", keymaps.prev_period, function()
            calendar_module.prev_period()
        end, opts)
    end
    
    if keymaps.today then
        vim.keymap.set("n", keymaps.today, function()
            calendar_module.today()
        end, opts)
    end
    
    -- View switching
    if keymaps.switch_view_day then
        vim.keymap.set("n", keymaps.switch_view_day, function()
            calendar_module.switch_view("day")
        end, opts)
    end
    
    if keymaps.switch_view_3day then
        vim.keymap.set("n", keymaps.switch_view_3day, function()
            calendar_module.switch_view("3day")
        end, opts)
    end
    
    if keymaps.switch_view_week then
        vim.keymap.set("n", keymaps.switch_view_week, function()
            calendar_module.switch_view("week")
        end, opts)
    end
    
    -- Refresh
    if keymaps.refresh then
        vim.keymap.set("n", keymaps.refresh, function()
            local icalbuddy = require("doit.modules.calendar.icalbuddy")
            icalbuddy.clear_cache()
            M.refresh()
        end, opts)
    end
end

return M