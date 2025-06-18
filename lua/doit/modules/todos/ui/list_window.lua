local M = {}

-- Setup function for todos list window
function M.setup(module)
    -- Forward to the core implementation
    return require("doit.ui.list_window")
end

return M