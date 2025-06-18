-- Standalone entry point for notes module
local M = {}

-- Setup function for standalone use
function M.setup(opts)
    -- Use the module's standalone setup function
    return require("doit.modules.notes").standalone_setup(opts)
end

-- Return the setup function directly
return M.setup