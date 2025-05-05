local M = {}

-- Setup function for todos search window
function M.setup(module)
    -- Forward to the core implementation
    return require("doit.ui.search_window")
end

return M