local M = {}

-- Setup function for todos help window
function M.setup(module)
    -- Simply forward to the core implementation
    return require("doit.ui.help_window")
end

return M