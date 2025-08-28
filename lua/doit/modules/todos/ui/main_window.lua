-- Module wrapper for main window
-- This ensures the main_window from doit.ui is properly loaded and accessible

local M = {}

-- Cache the main window module once loaded
local cached_main_window = nil

-- Setup function for todos main window
function M.setup(module)
    -- Only load once
    if not cached_main_window then
        cached_main_window = require("doit.ui.main_window")
    end
    
    -- Return the cached main window
    return cached_main_window
end

-- If someone requires this module directly, also provide the setup
setmetatable(M, {
    __index = function(t, k)
        if not cached_main_window then
            cached_main_window = require("doit.ui.main_window")
        end
        return cached_main_window[k]
    end
})

return M