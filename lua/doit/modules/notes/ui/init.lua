-- ui components for the notes module
local M = {}

function M.setup(module)
    local notes_window = require("doit.modules.notes.ui.notes_window")
    M.notes_window = notes_window.setup(module)

    local notes_picker = require("doit.modules.notes.ui.notes_picker")
    M.notes_picker = notes_picker.setup(module)

    return M
end

return M
