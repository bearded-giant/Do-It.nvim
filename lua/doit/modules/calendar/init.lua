-- Calendar module for doit.nvim
local M = {}

-- Module version
M.version = "1.0.0"

-- Module metadata for registry
M.metadata = {
    name = "calendar",
    version = M.version,
    description = "Calendar view with icalbuddy integration for viewing events",
    author = "bearded-giant",
    path = "doit.modules.calendar",
    dependencies = {},
    config_schema = {
        enabled = { type = "boolean", default = true },
        default_view = { type = "string", default = "day" },
        hours = { type = "table" },
        window = { type = "table" },
        keymaps = { type = "table" },
        icalbuddy = { type = "table" }
    }
}

-- Setup function for the calendar module
function M.setup(opts)
    -- Initialize module with core framework
    local core = require("doit.core")
    
    -- Setup module configuration
    local config = require("doit.modules.calendar.config")
    M.config = config.setup(opts)
    
    -- Check if icalbuddy is available
    local icalbuddy = require("doit.modules.calendar.icalbuddy")
    if not icalbuddy.check_availability() then
        vim.notify("DoIt Calendar: icalbuddy not found. Please install icalbuddy to use calendar features.", vim.log.levels.WARN)
        return M
    end
    
    -- Initialize state with module reference
    local state_module = require("doit.modules.calendar.state")
    M.state = state_module.setup(M)
    
    -- Initialize UI with module reference
    local ui_module = require("doit.modules.calendar.ui")
    M.ui = ui_module.setup(M)
    
    -- Initialize commands
    M.commands = require("doit.modules.calendar.commands").setup(M)
    
    -- Register module with core
    core.register_module("calendar", M)
    
    -- Set up keymaps from config
    M.setup_keymaps()
    
    return M
end

-- Setup keymaps for the calendar module
function M.setup_keymaps()
    local keymaps = M.config.keymaps
    
    if keymaps.toggle_window and keymaps.toggle_window ~= "" then
        vim.keymap.set("n", keymaps.toggle_window, function()
            M.toggle()
        end, { desc = "Toggle DoIt Calendar" })
    end
end

-- Toggle calendar window
function M.toggle()
    if M.ui then
        M.ui.toggle()
    end
end

-- Show calendar window
function M.show()
    if M.ui then
        M.ui.show()
    end
end

-- Hide calendar window
function M.hide()
    if M.ui then
        M.ui.hide()
    end
end

-- Switch view mode
function M.switch_view(view)
    if M.state and M.ui then
        M.state.set_view(view)
        M.ui.refresh()
    end
end

-- Navigate to next period
function M.next_period()
    if M.state and M.ui then
        M.state.next_period()
        M.ui.refresh()
    end
end

-- Navigate to previous period
function M.prev_period()
    if M.state and M.ui then
        M.state.prev_period()
        M.ui.refresh()
    end
end

-- Jump to today
function M.today()
    if M.state and M.ui then
        M.state.today()
        M.ui.refresh()
    end
end

-- Refresh calendar data
function M.refresh()
    if M.ui then
        M.ui.refresh()
    end
end

return M