-- Configuration for the notes module
local M = {}

-- Default module configuration
M.defaults = {
    enabled = true,
    icon = "📓",
    storage_path = vim.fn.stdpath("data") .. "/doit/notes",
    mode = "project", -- "global" or "project"
    window = {
        width = 0.6,
        height = 0.6,
        border = "rounded",
        title = " Notes ",
        title_pos = "center",
    },
    keymaps = {
        toggle = "<leader>dn",
        close = "q",
        switch_mode = "m",
    },
}

-- Module configuration
M.options = {}

-- Setup function
function M.setup(opts)
    -- Merge defaults with user options
    M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
    return M.options
end

return M