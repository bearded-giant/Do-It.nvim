-- Commands for the notes module
local M = {}

-- Setup function for commands
function M.setup(module)
    local commands = {}
    
    -- Notes command
    commands.DoitNotes = {
        callback = function()
            module.ui.notes_window.toggle_notes_window()
        end,
        opts = {
            desc = "Toggle notes window",
        }
    }
    
    return commands
end

return M