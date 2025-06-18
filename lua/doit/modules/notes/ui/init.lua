-- UI components for the notes module
local M = {}

-- Setup function for the notes UI
function M.setup(module)
    -- Load and initialize notes window with module reference
    local notes_window = require("doit.modules.notes.ui.notes_window")
    M.notes_window = notes_window.setup(module)
    
    return M
end

return M