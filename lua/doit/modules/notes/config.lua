-- configuration for the notes module
local M = {}

M.defaults = {
    enabled = true,
    ui = {
        window = {
            width = 80,
            height = 30,
            border = "rounded",
            title = " Notes ",
            title_pos = "center",
            position = "center",
            relative_width = 0.6,
            relative_height = 0.6,
            use_relative = true,
        },
        icons = {
            note = "",
            linked = "",
        },
    },
    storage = {
        path = vim.fn.stdpath("data") .. "/doit/notes",
        mode = "project",
    },
    markdown = {
        highlight = true,
        syntax = "markdown",
        conceallevel = 2,
        concealcursor = "nc",
        extensions = true,
    },
    keymaps = {
        toggle = "<leader>dn",
        -- picker keymaps
        picker = {
            open = "<CR>",
            new = "n",
            delete = "d",
            scope_toggle = "m",
            sort = "s",
            search = "/",
            close = "q",
        },
        -- editor keymaps
        editor = {
            close = "q",
            format = "gq",
            heading1 = "<leader>1",
            heading2 = "<leader>2",
            heading3 = "<leader>3",
            bold = "<leader>b",
            italic = "<leader>i",
            link = "<leader>l",
            list_item = "<leader>-",
        },
    },

    -- legacy compat
    icon = "",
    storage_path = vim.fn.stdpath("data") .. "/doit/notes",
    mode = "project",
    window = {
        width = 0.6,
        height = 0.6,
        border = "rounded",
        title = " Notes ",
        title_pos = "center",
    },
}

M.options = {}

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
    return M.options
end

return M
