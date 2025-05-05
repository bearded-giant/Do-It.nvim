-- Notes module for doit.nvim
local M = {}

-- Module version
M.version = "1.0.0"

-- Setup function for the notes module
function M.setup(opts)
    -- Initialize module with core framework
    local core = require("doit.core")
    
    -- Setup module configuration
    local config = require("doit.modules.notes.config")
    M.config = config.setup(opts)
    
    -- Initialize state
    local state_module = require("doit.modules.notes.state")
    M.state = state_module.setup(M)
    
    -- Initialize UI with module reference
    local ui_module = require("doit.modules.notes.ui")
    M.ui = ui_module.setup(M)
    
    -- Initialize commands
    M.commands = require("doit.modules.notes.commands").setup(M)
    
    -- Register module with core
    core.register_module("notes", M)
    
    -- Set up keymaps from config
    M.setup_keymaps()
    
    -- Emit events for other modules
    M.on_note_updated = function(note)
        core.events.emit("note_updated", note)
    end
    
    return M
end

-- Set up module keymaps
function M.setup_keymaps()
    local config = M.config
    
    -- Notes window toggle
    if config.keymaps.toggle then
        vim.keymap.set("n", config.keymaps.toggle, function()
            M.ui.notes_window.toggle_notes_window()
        end, { desc = "Toggle Notes Window" })
    end
end

-- Standalone entry point (when used without the framework)
function M.standalone_setup(opts)
    -- Create minimal core if it doesn't exist
    if not package.loaded["doit.core"] then
        -- Minimal core implementation
        local minimal_core = {
            register_module = function() return end,
            get_module = function() return nil end,
            events = {
                on = function() return function() end end,
                emit = function() return end
            }
        }
        package.loaded["doit.core"] = minimal_core
    end
    
    return M.setup(opts)
end

return M