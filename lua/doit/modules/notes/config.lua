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
    markdown = {
        highlight = true,   -- Enable or disable markdown highlighting
        syntax = "markdown", -- Syntax to use for the notes buffer
        conceallevel = 2,   -- Enable concealing of formatting markers
        concealcursor = "nc", -- Modes in which concealing is active when cursor is on line
        extensions = true,  -- Enable markdown extensions like tables, etc.
    },
    keymaps = {
        toggle = "<leader>dn",
        close = "q",
        switch_mode = "m",
        -- Markdown editing keymaps
        format = "gq",         -- Format paragraph
        heading1 = "<leader>1", -- Insert/convert to H1
        heading2 = "<leader>2", -- Insert/convert to H2
        heading3 = "<leader>3", -- Insert/convert to H3
        bold = "<leader>b",    -- Make text bold
        italic = "<leader>i",  -- Make text italic
        link = "<leader>l",    -- Insert link
        list_item = "<leader>-", -- Insert list item
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