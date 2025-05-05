local M = {}

-- Setup function for todos scratchpad
function M.setup(module)
    -- Forward to the core implementation
    return require("doit.ui.scratchpad")
end

return M