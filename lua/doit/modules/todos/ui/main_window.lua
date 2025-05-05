local M = {}

-- Setup function for todos main window
function M.setup(module)
    -- Forward to the core implementation
    return require("doit.ui.main_window")
end

return M