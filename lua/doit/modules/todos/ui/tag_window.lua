local M = {}

-- Setup function for todos tag window
function M.setup(module)
    -- Forward to the core implementation
    return require("doit.ui.tag_window")
end

return M