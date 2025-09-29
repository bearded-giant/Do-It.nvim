-- Configuration management for calendar module
local M = {}

-- Default configuration
local defaults = {
    enabled = true,
    default_view = "day", -- "day", "3day", "week"
    hours = {
        start = 8,  -- 8am
        ["end"] = 20    -- 8pm
    },
    window = {
        -- Relative sizing (percentage of screen)
        use_relative = true,
        relative_width = 0.8,  -- 80% of screen width
        relative_height = 0.7, -- 70% of screen height

        -- Absolute sizing (fallback if relative is disabled)
        width = 80,
        height = 30,

        position = "center",
        border = "rounded",
        title = " Calendar ",
        title_pos = "center",
        padding = {
            top = 1,
            bottom = 1,
            left = 2,
            right = 2
        }
    },
    keymaps = {
        toggle_window = "<leader>dc",
        switch_view_day = "d",
        switch_view_3day = "3",
        switch_view_week = "w",
        next_period = "l",
        prev_period = "h",
        today = "t",
        close = "q",
        refresh = "r"
    },
    icalbuddy = {
        path = "icalbuddy", -- will auto-detect
        format_options = "-nc -nrd", -- no calendar names, no relative dates
        date_format = "%Y-%m-%d",
        time_format = "%H:%M",
        cache_ttl = 60, -- cache for 60 seconds
        debug = true -- set to true to see raw icalbuddy output
    },
    colors = {
        border = "Normal",
        title = "Title",
        time_column = "Comment",
        event = "Function",
        current_time = "DiagnosticWarn",
        header = "Title",
        footer = "Comment"
    }
}

-- Setup configuration
function M.setup(opts)
    opts = opts or {}
    
    -- Deep merge with defaults
    local config = vim.tbl_deep_extend("force", defaults, opts)
    
    -- Validate configuration
    M.validate(config)
    
    -- Store configuration
    M.config = config
    
    return config
end

-- Validate configuration
function M.validate(config)
    -- Validate view
    local valid_views = { day = true, ["3day"] = true, week = true }
    if not valid_views[config.default_view] then
        vim.notify("Invalid default_view: " .. config.default_view .. ". Using 'day'", vim.log.levels.WARN)
        config.default_view = "day"
    end
    
    -- Validate hours
    if config.hours.start < 0 or config.hours.start > 23 then
        config.hours.start = 8
    end
    if config.hours["end"] < 1 or config.hours["end"] > 24 then
        config.hours["end"] = 20
    end
    if config.hours.start >= config.hours["end"] then
        config.hours.start = 8
        config.hours["end"] = 20
    end
    
    -- Validate window dimensions
    if config.window.width < 40 then
        config.window.width = 40
    end
    if config.window.height < 10 then
        config.window.height = 10
    end
end

-- Get configuration value
function M.get(key)
    if not M.config then
        return nil
    end
    
    local keys = vim.split(key, ".", { plain = true })
    local value = M.config
    
    for _, k in ipairs(keys) do
        value = value[k]
        if value == nil then
            return nil
        end
    end
    
    return value
end

return M