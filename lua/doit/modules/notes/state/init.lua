-- State management for notes module
local M = {}

-- Initialize notes state
function M.setup()
    -- Load storage module
    local storage = require("doit.modules.notes.state.storage")
    
    -- Initialize with storage
    storage.setup(M)
    
    -- Forward storage functions
    for name, func in pairs(storage) do
        if type(func) == "function" and not M[name] then
            M[name] = func
        end
    end
    
    -- Initialize notes state
    M.notes = {
        global = { content = "" },
        project = {},
        current_mode = "project",
    }
    
    return M
end

return M