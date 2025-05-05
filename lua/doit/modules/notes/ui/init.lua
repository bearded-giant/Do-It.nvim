-- UI components for the notes module
local M = {}

-- Setup function for the notes UI
function M.setup()
    -- Load notes window
    M.notes_window = require("doit.modules.notes.ui.notes_window")
    
    return M
end

return M