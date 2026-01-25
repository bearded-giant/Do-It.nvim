-- Configuration management for doit.nvim
local M = {}

-- Default configuration
M.defaults = {
    -- Framework defaults
    project = {
        enabled = true,
        detection = {
            use_git = true,
            fallback_to_cwd = true,
        },
        storage = {
            path = vim.fn.stdpath("data") .. "/doit",
        },
    },
    
    -- Module defaults
    modules = {
        todos = {
            enabled = true,
            save_path = vim.fn.stdpath("data") .. "/doit_todos.json",
            timestamp = {
                enabled = true,
            },
            window = {
                width = 55,
                height = 20,
                border = "rounded",
                position = "center",
                padding = {
                    top = 1,
                    bottom = 1,
                    left = 2,
                    right = 2,
                },
            },
            list_window = {
                width = 40,
                height = 10,
                position = "bottom-right",
            },
            formatting = {
                pending = {
                    icon = "○",
                    format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" },
                },
                in_progress = {
                    icon = "◐",
                    format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" },
                },
                done = {
                    icon = "✓",
                    format = { "notes_icon", "icon", "text", "due_date", "ect", "relative_time" },
                },
            },
            keymaps = {
                toggle_window = "<leader>td",
                toggle_list_window = "<leader>dl",
                new_todo = "n",
                toggle_todo = "x",
                delete_todo = "d",
                delete_completed = "D",
                delete_confirmation = "<Y>",
                close_window = "q",
                undo_delete = "u",
                add_due_date = "H",
                remove_due_date = "r",
                toggle_help = "?",
                toggle_tags = "t",
                toggle_priority = "<Space>",
                clear_filter = "c",
                edit_todo = "e",
                edit_tag = "e",
                edit_priorities = "p",
                delete_tag = "d",
                search_todos = "/",
                add_time_estimation = "T",
                remove_time_estimation = "R",
                import_todos = "I",
                export_todos = "E",
                remove_duplicates = "<leader>D",
                open_todo_scratchpad = "<leader>p",
                reorder_todo = "r",
                move_todo_up = "k",
                move_todo_down = "j",
            },
            calendar = {
                language = "en",
                icon = "",
                keymaps = {
                    previous_day = "h",
                    next_day = "l",
                    previous_week = "k",
                    next_week = "j",
                    previous_month = "H",
                    next_month = "L",
                    select_day = "<CR>",
                    close_calendar = "q",
                },
            },
            scratchpad = {
                syntax_highlight = "markdown",
            },
            priorities = {
                { name = "critical", weight = 16 },
                { name = "urgent", weight = 8 },
                { name = "important", weight = 4 },
            },
            priority_groups = {
                critical = {
                    members = { "critical" },
                    color = "#FF0000",
                },
                high = {
                    members = { "urgent" },
                    color = nil,
                    hl_group = "DiagnosticWarn",
                },
                medium = {
                    members = { "important" },
                    color = nil,
                    hl_group = "DiagnosticInfo",
                },
                low = {
                    members = {},
                    color = "#FFFFFF",
                },
            },
            hour_score_value = 1 / 8,
        },
        notes = {
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
        },
    },
    
    -- Plugin system
    plugins = {
        auto_discover = true,
        load_path = "doit.modules",
    },
    
    -- Development mode
    development_mode = false,
}

-- User configuration
M.options = {}

-- Setup function
function M.setup(opts)
    -- Handle legacy configuration format
    opts = M.migrate_legacy_config(opts or {})
    
    -- Merge defaults with user options
    M.options = vim.tbl_deep_extend("force", M.defaults, opts)
    
    return M.options
end

-- Migrate from legacy config format to new modular format
function M.migrate_legacy_config(opts)
    if not opts.modules then
        opts.modules = {}
    end
    
    -- If notes configuration exists at top level, move it to modules
    if opts.notes and not opts.modules.notes then
        opts.modules.notes = vim.tbl_deep_extend("force", M.defaults.modules.notes, opts.notes)
        opts.notes = nil
    end
    
    -- Move todo-related config to todos module
    local todos_config = {}
    local todo_fields = {
        "save_path", "timestamp", "window", "list_window", "formatting", "keymaps",
        "priorities", "priority_groups", "hour_score_value", "calendar", "scratchpad",
        "quick_keys", "import_export_path"
    }
    
    for _, field in ipairs(todo_fields) do
        if opts[field] then
            todos_config[field] = opts[field]
            opts[field] = nil
        end
    end
    
    if next(todos_config) ~= nil then
        opts.modules.todos = vim.tbl_deep_extend("force", opts.modules.todos or {}, todos_config)
    end
    
    return opts
end

return M